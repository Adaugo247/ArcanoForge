;; Fantasy Card Game Marketplace - Stage 2: Trading Features
;; Added marketplace functionality and safe transfer mechanisms

;; Error Codes
(define-constant ERR-UNAUTHORIZED (err u1000))
(define-constant ERR-SYSTEM-LOCKED (err u1001))
(define-constant ERR-BAD-INPUT (err u1002))
(define-constant ERR-MISSING (err u1003))
(define-constant ERR-LOW-BALANCE (err u1005))
(define-constant ERR-INVALID-CARD (err u1011))

;; Constants
(define-constant CONTRACT-ADMIN tx-sender)
(define-constant MAX-CARD-ID u1000000)
(define-constant MIN-CARD-ID u1)
(define-constant MIN-CARD-PRICE u1000000)
(define-constant PLATFORM-FEE u20)

;; Data Variables
(define-data-var total-cards uint u0)
(define-data-var system-locked bool false)
(define-data-var treasury-wallet principal CONTRACT-ADMIN)
(define-data-var total-platform-revenue uint u0)

;; Data Maps
(define-map cards
    {id: uint}
    {owner: principal,
     creator: principal,
     card-data: (string-utf8 256),
     total-prints: uint,
     tradeable: bool,
     total-trades: uint,
     verified: bool})

(define-map card-balances
    {card-id: uint, owner: principal}
    {quantity: uint,
     locked-until: uint})

(define-map trade-listings
    {card-id: uint}
    {price: uint,
     seller: principal,
     valid-until: uint,
     quantity: uint})

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
    (total-prints uint))
    (begin
        (try! (check-system-status))
        (asserts! (>= (len card-data) u10) ERR-BAD-INPUT)
        (asserts! (> total-prints u0) ERR-BAD-INPUT)
        
        (let ((card-id (+ (var-get total-cards) u1)))
            (try! (validate-card-id card-id))
            
            (map-set cards
                {id: card-id}
                {owner: tx-sender,
                 creator: tx-sender,
                 card-data: card-data,
                 total-prints: total-prints,
                 tradeable: false,
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
            
            (asserts! (>= price MIN-CARD-PRICE) ERR-BAD-INPUT)
            
            (let ((balance (unwrap! (map-get? card-balances 
                    {card-id: validated-card-id, owner: tx-sender})
                    ERR-MISSING)))
                
                (asserts! (>= (get quantity balance) quantity) ERR-BAD-INPUT)
                (asserts! (> quantity u0) ERR-BAD-INPUT)
                
                (map-set trade-listings
                    {card-id: validated-card-id}
                    {price: price,
                     seller: tx-sender,
                     valid-until: (+ block-height u1440),
                     quantity: quantity})
                (ok true)))))

(define-public (purchase-card (card-id uint))
    (begin
        (try! (check-system-status))
        (try! (validate-card-id card-id))
        
        (match (map-get? trade-listings {card-id: card-id})
            listing
                (let ((price (get price listing))
                      (seller (get seller listing))
                      (quantity (get quantity listing)))
                    
                    (asserts! (>= block-height (get valid-until listing)) ERR-BAD-INPUT)
                    (asserts! (not (is-eq tx-sender seller)) ERR-BAD-INPUT)
                    
                    (let ((platform-fee (/ (* price PLATFORM-FEE) u1000))
                          (seller-payment (- price platform-fee)))
                        
                        (try! (stx-transfer? platform-fee tx-sender (var-get treasury-wallet)))
                        (try! (stx-transfer? seller-payment tx-sender seller))
                        
                        (try! (safe-transfer-card card-id seller tx-sender quantity))
                        (map-delete trade-listings {card-id: card-id})
                        (ok true)))
            ERR-MISSING)))

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