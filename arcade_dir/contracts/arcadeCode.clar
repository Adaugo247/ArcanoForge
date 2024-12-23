;; Fantasy Card Game Marketplace and Tournament Platform Contract

;; Error Codes
(define-constant ERR-UNAUTHORIZED (err u1000))
(define-constant ERR-SYSTEM-LOCKED (err u1001))
(define-constant ERR-BAD-INPUT (err u1002))
(define-constant ERR-MISSING (err u1003))
(define-constant ERR-ACCESS-DENIED (err u1004))
(define-constant ERR-LOW-BALANCE (err u1005))
(define-constant ERR-DUPLICATE (err u1006))
(define-constant ERR-INVALID-STATE (err u1007))
(define-constant ERR-OPERATION-FAILED (err u1008))
(define-constant ERR-TIMEOUT (err u1009))
(define-constant ERR-INVALID-CARD (err u1011))

;; Constants
(define-constant CONTRACT-ADMIN tx-sender)
(define-constant MAX-RARITY-BONUS u250) ;; 25.0%
(define-constant PLATFORM-FEE u20) ;; 2.0%
(define-constant MIN-CARD-PRICE u1000000) ;; in micro-STX
(define-constant TOURNAMENT-LOCK u144) ;; ~24 hours in blocks
(define-constant SEASON-DURATION u1008) ;; ~7 days in blocks
(define-constant MIN-TOURNAMENT-ENTRY u100000000) ;; Minimum entry requirement
(define-constant DAILY-REWARDS-PERIOD u144) ;; ~24 hours in blocks
(define-constant MAX-CARD-ID u1000000) ;; Maximum valid card ID
(define-constant MIN-CARD-ID u1) ;; Minimum valid card ID

;; Data Variables
(define-data-var total-cards uint u0)
(define-data-var total-tournaments uint u0)
(define-data-var system-locked bool false)
(define-data-var treasury-wallet principal CONTRACT-ADMIN)
(define-data-var total-staked-power uint u0)
(define-data-var last-season-cycle uint u0)
(define-data-var total-platform-revenue uint u0)
(define-data-var maintenance-mode bool false)

;; Fungible Tokens
(define-fungible-token card-fragments)
(define-fungible-token arena-token)
(define-fungible-token battle-points)

;; Data Maps
(define-map cards
    {id: uint}
    {owner: principal,
     creator: principal,
     card-data: (string-utf8 256),
     rarity-bonus: uint,
     total-prints: uint,
     tradeable: bool,
     mint-block: uint,
     total-trades: uint,
     verified: bool})

(define-map trade-listings
    {card-id: uint}
    {price: uint,
     seller: principal,
     valid-until: uint,
     quantity: uint,
     auction-info: (optional {
         starting-bid: uint,
         min-price: uint,
         highest-bidder: (optional principal),
         min-increment: uint
     })})

(define-map card-balances
    {card-id: uint, owner: principal}
    {quantity: uint,
     locked-until: uint})

(define-map tournament-stakes
    {player: principal}
    {amount: uint,
     locked-until: uint,
     pending-rewards: uint,
     last-claim: uint})

(define-map tournaments
    {id: uint}
    {organizer: principal,
     name: (string-utf8 256),
     rules: (string-utf8 1024),
     start-block: uint,
     end-block: uint,
     finished: bool,
     participant-count: uint,
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
        ;; Additional check for zero value
        (asserts! (> card-id u0) ERR-INVALID-CARD)
        
        (asserts! (and 
            (>= card-id MIN-CARD-ID)
            (<= card-id MAX-CARD-ID)) 
            ERR-INVALID-CARD)
        
        (asserts! (<= card-id (var-get total-cards)) 
            ERR-INVALID-CARD)
        
        (let ((card-info (map-get? cards {id: card-id})))
            (asserts! (is-some card-info) ERR-MISSING)
            (ok card-id))))

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
            (asserts! (< (+ (get quantity receiver-balance) amount) (pow u2 u64)) ERR-BAD-INPUT)
            
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
        (asserts! (and 
            (> total-prints u0)
            (< total-prints (pow u2 u64))) ERR-BAD-INPUT)
        
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
                 mint-block: u0,
                 total-trades: u0,
                 verified: false})
            
            (map-set card-balances
                {card-id: card-id, owner: tx-sender}
                {quantity: total-prints,
                 locked-until: u0})
            
            (var-set total-cards card-id)
            (ok card-id))))

;; Marketplace Functions
(define-public (list-for-trade
    (card-id uint)
    (quantity uint)
    (price uint))
    (let 
        ((validated-card-id (try! (validate-card-id card-id))))
        (begin
            (try! (check-system-status))
            
            (asserts! (unwrap! (verify-card-owner validated-card-id tx-sender) ERR-MISSING)
                ERR-UNAUTHORIZED)
            
            (asserts! (and 
                (>= price MIN-CARD-PRICE)
                (< price (pow u2 u64)))
                ERR-BAD-INPUT)
            
            (let ((balance (unwrap! (map-get? card-balances 
                    {card-id: validated-card-id, owner: tx-sender})
                    ERR-MISSING)))
                
                (asserts! (and
                    (>= (get quantity balance) quantity)
                    (> quantity u0)
                    (< quantity (pow u2 u64)))
                    ERR-BAD-INPUT)
                
                (asserts! (>= u0 (get locked-until balance)) 
                    ERR-INVALID-STATE)
                
                (map-set trade-listings
                    {card-id: validated-card-id}
                    {price: price,
                     seller: tx-sender,
                     valid-until: (+ u0 u1440),
                     quantity: quantity,
                     auction-info: none})
                (ok true)))))

;; Purchase Function
(define-public (purchase-card (card-id uint))
    (begin
        (try! (check-system-status))
        
        ;; Direct validation checks
        (asserts! (> card-id u0) ERR-INVALID-CARD)
        (asserts! (and (>= card-id MIN-CARD-ID) 
                      (<= card-id MAX-CARD-ID)) 
                 ERR-INVALID-CARD)
        (asserts! (<= card-id (var-get total-cards)) 
                 ERR-INVALID-CARD)
        
        ;; Check if card exists
        (match (map-get? cards {id: card-id})
            card-data
                (let ((listing (unwrap! (map-get? trade-listings {card-id: card-id}) 
                        ERR-MISSING))
                      (price (get price listing))
                      (seller (get seller listing))
                      (quantity (get quantity listing)))
                    
                    (asserts! (<= u0 (get valid-until listing)) ERR-TIMEOUT) 
                    (asserts! (not (is-eq tx-sender seller)) ERR-BAD-INPUT)
                    
                    (let ((balance (stx-get-balance tx-sender)))
                        (asserts! (and 
                            (>= balance price)
                            (>= price MIN-CARD-PRICE)
                            (< price (pow u2 u64)))
                            ERR-LOW-BALANCE))
                    
                    (let ((platform-fee (/ (* price PLATFORM-FEE) u1000))
                          (seller-payment (- price platform-fee)))
                        
                        (try! (stx-transfer? platform-fee tx-sender (var-get treasury-wallet)))
                        (try! (stx-transfer? seller-payment tx-sender seller))
                        
                        (match (map-get? card-balances 
                                {card-id: card-id, owner: seller})
                            seller-balance 
                                (begin
                                    (asserts! (>= (get quantity seller-balance) quantity) 
                                        ERR-LOW-BALANCE)
                                    (try! (safe-transfer-card card-id seller tx-sender quantity))
                                    (map-delete trade-listings {card-id: card-id})
                                    (ok true))
                            ERR-MISSING)))
            ERR-MISSING)))

;; Admin Functions
(define-public (set-system-lock (new-state bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        (asserts! (not (is-eq new-state (var-get system-locked))) ERR-BAD-INPUT)
        (var-set system-locked new-state)
        (ok true)))

(define-public (set-treasury-wallet (new-wallet principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        (asserts! (not (is-eq new-wallet (var-get treasury-wallet))) ERR-BAD-INPUT)
        (ok (var-set treasury-wallet new-wallet))))

(define-public (activate-maintenance-mode)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        (var-set maintenance-mode true)
        (var-set system-locked true)
        (ok true)))