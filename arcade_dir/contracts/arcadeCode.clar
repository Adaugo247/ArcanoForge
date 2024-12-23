spectator-count: uint,
     prize-pool: (string-utf8 256),
     min-players: uint})

(define-map season-rewards
    {cycle: uint}
    {reward-pool: uint,
     distributed: bool})

;; Input Validation Functions
(define-private (validate-card-id (card-id uint))
    (begin
        (asserts! (> card-id u0) ERR-INVALID-CARD)
        (asserts! (and 
            (>= card-id MIN-CARD-ID)
            (<= card-id MAX-CARD-ID)) 
            ERR-INVALID-CARD)
        (asserts! (<= card-id (var-get total-cards)) 
            ERR-INVALID-CARD)
        (ok card-id)))

(define-private (verify-card-owner (card-id uint) (owner principal))
    (match (map-get? cards {id: card-id})
        card (ok (is-eq (get owner card) owner))
        ERR-MISSING))

;; Helper Functions
(define-private (check-system-status)
    (if (var-get system-locked)
        ERR-SYSTEM-LOCKED
        (ok true)))

;; Safe Transfer Implementation
(define-private (safe-transfer-card (card-id uint) (from principal) (to principal) (amount uint))
    (let ((validated-card-id (try! (validate-card-id card-id))))
        (asserts! (is-some (map-get? cards {id: validated-card-id})) ERR-INVALID-CARD)
        (let ((sender-balance (unwrap! (map-get? card-balances 
                {card-id: validated-card-id, owner: from})
                ERR-MISSING))
              (receiver-balance (default-to 
                {quantity: u0, locked-until: u0}
                (map-get? card-balances {card-id: validated-card-id, owner: to}))))
            
            (asserts! (>= (get quantity sender-balance) amount) ERR-LOW-BALANCE)
            
            (map-set card-balances
                {card-id: validated-card-id, owner: from}
                {quantity: (- (get quantity sender-balance) amount),
                 locked-until: (get locked-until sender-balance)})
            
            (map-set card-balances
                {card-id: validated-card-id, owner: to}
                {quantity: (+ (get quantity receiver-balance) amount),
                 locked-until: (get locked-until receiver-balance)})
            
            (ok true))))

;; Core Card Functions
(define-public (mint-card
    (card-data (string-utf8 256))
    (rarity-bonus uint)
    (total-prints uint))
    (begin
        (try! (check-system-status))
        (asserts! (>= (len card-data) u10) ERR-BAD-INPUT)
        (asserts! (<= rarity-bonus MAX-RARITY-BONUS) ERR-BAD-INPUT)
        (asserts! (> total-prints u0) ERR-BAD-INPUT)
        
        (let ((card-id (+ (var-get total-cards) u1)))
            (try! (validate-card-id card-id))
            (try! (ft-mint? card-fragments total-prints tx-sender))
            
            (map-set cards
                {id: card-id}
                {owner: tx-sender,
                 creator: tx-sender,
                 card-data: card-data,
                 rarity-bonus: rarity-bonus,
                 total-prints: total-prints,
                 tradeable: false,
                 mint-block: block-height,
                 total-trades: u0,
                 verified: false})
            
            (map-set card-balances
                {card-id: card-id, owner: tx-sender}
                {quantity: total-prints,
                 locked-until: u0})
            
            (var-set total-cards card-id)
            (ok card-id))))

;; Tournament Functions
(define-public (create-tournament 
    (name (string-utf8 256))
    (rules (string-utf8 1024))
    (start-block uint)
    (duration uint)
    (min-players uint)
    (entry-fee uint))
    (begin
        (try! (check-system-status))
        (asserts! (>= (len name) u5) ERR-BAD-INPUT)
        (asserts! (>= (len rules) u10) ERR-BAD-INPUT)
        (asserts! (>= start-block block-height) ERR-BAD-INPUT)
        (asserts! (>= duration TOURNAMENT-LOCK) ERR-BAD-INPUT)
        (asserts! (>= entry-fee MIN-TOURNAMENT-ENTRY) ERR-BAD-INPUT)
        
        (let ((tournament-id (+ (var-get total-tournaments) u1)))
            (map-set tournaments
                {id: tournament-id}
                {organizer: tx-sender,
                 name: name,
                 rules: rules,
                 start-block: start-block,
                 end-block: (+ start-block duration),
                 finished: false,
                 participant-count: u0,
                 spectator-count: u0,
                 prize-pool: "",
                 min-players: min-players})
            
            (var-set total-tournaments tournament-id)
            (ok tournament-id))))

(define-public (join-tournament 
    (tournament-id uint)
    (stake-amount uint))
    (begin
        (try! (check-system-status))
        
        (match (map-get? tournaments {id: tournament-id})
            tournament
                (begin
                    (asserts! (>= stake-amount MIN-TOURNAMENT-ENTRY) ERR-BAD-INPUT)
                    (asserts! (not (get finished tournament)) ERR-INVALID-STATE)
                    (asserts! (>= (get start-block tournament) block-height) ERR-TIMEOUT)
                    
                    (try! (stx-transfer? stake-amount tx-sender (var-get treasury-wallet)))
                    
                    (map-set tournament-stakes
                        {player: tx-sender}
                        {amount: stake-amount,
                         locked-until: (get end-block tournament),
                         pending-rewards: u0,
                         last-claim: block-height})
                    
                    (var-set total-staked-power (+ (var-get total-staked-power) stake-amount))
                    (ok true))
            ERR-MISSING)))

;; Reward Functions
(define-public (claim-rewards)
    (begin
        (try! (check-system-status))
        
        (match (map-get? tournament-stakes {player: tx-sender})
            stake
                (let ((pending (get pending-rewards stake))
                      (locked-until (get locked-until stake)))
                    
                    (asserts! (> pending u0) ERR-LOW-BALANCE)
                    (asserts! (>= block-height locked-until) ERR-TIMEOUT)
                    
                    (try! (ft-mint? battle-points pending tx-sender))
                    
                    (map-set tournament-stakes
                        {player: tx-sender}
                        {amount: (get amount stake),
                         locked-until: locked-until,
                         pending-rewards: u0,
                         last-claim: block-height})
                    (ok true))
            ERR-MISSING)))

;; Season Management
(define-public (start-new-season)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        (let ((current-cycle (+ (var-get last-season-cycle) u1)))
            (map-set season-rewards
                {cycle: current-cycle}
                {reward-pool: u0,
                 distributed: false})
            (var-set last-season-cycle current-cycle)
            (ok current-cycle))))

;; Admin Functions
(define-public (set-system-lock (new-state bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        (var-set system-locked new-state)
        (ok true)))

(define-public (set-treasury-wallet (new-wallet principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        (ok (var-set treasury-wallet new-wallet))))

(define-public (activate-maintenance-mode)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        (var-set maintenance-mode true)
        (var-set system-locked true)
        (ok true)))

(define-public (distribute-season-rewards (cycle uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        (match (map-get? season-rewards {cycle: cycle})
            season
                (begin
                    (asserts! (not (get distributed season)) ERR-DUPLICATE)
                    (try! (ft-mint? arena-token (get reward-pool season) (var-get treasury-wallet)))
                    (map-set season-rewards
                        {cycle: cycle}
                        {reward-pool: (get reward-pool season),
                         distributed: true})
                    (ok true))
            ERR-MISSING)))