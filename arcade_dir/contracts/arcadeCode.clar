;; Fantasy Card Game Marketplace - Stage 1: Basic Card Management
;; Core functionality for card creation and ownership tracking

;; Error Codes
(define-constant ERR-UNAUTHORIZED (err u1000))
(define-constant ERR-BAD-INPUT (err u1002))
(define-constant ERR-MISSING (err u1003))
(define-constant ERR-INVALID-CARD (err u1011))

;; Constants
(define-constant CONTRACT-ADMIN tx-sender)
(define-constant MAX-CARD-ID u1000000)
(define-constant MIN-CARD-ID u1)

;; Data Variables
(define-data-var total-cards uint u0)
(define-data-var system-locked bool false)

;; Data Maps
(define-map cards
    {id: uint}
    {owner: principal,
     creator: principal,
     card-data: (string-utf8 256),
     total-prints: uint,
     verified: bool})

(define-map card-balances
    {card-id: uint, owner: principal}
    {quantity: uint})

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

;; Core Card Functions
(define-public (mint-card
    (card-data (string-utf8 256))
    (total-prints uint))
    (begin
        (asserts! (not (var-get system-locked)) ERR-UNAUTHORIZED)
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
                 verified: false})
            
            (map-set card-balances
                {card-id: card-id, owner: tx-sender}
                {quantity: total-prints})
            
            (var-set total-cards card-id)
            (ok card-id))))

;; Admin Functions
(define-public (set-system-lock (new-state bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        (var-set system-locked new-state)
        (ok true)))