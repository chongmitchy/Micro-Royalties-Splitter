;; Micro-Royalties-Splitter
;; A smart contract for automatically splitting and distributing royalties among multiple recipients

(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-PERCENTAGE (err u102))
(define-constant ERR-TOTAL-PERCENTAGE-EXCEEDS-100 (err u103))
(define-constant ERR-INSUFFICIENT-BALANCE (err u104))
(define-constant ERR-TRANSFER-FAILED (err u105))
(define-constant ERR-ALREADY-EXISTS (err u106))
(define-constant ERR-INVALID-AMOUNT (err u107))
(define-constant ERR-NO-RECIPIENTS (err u108))

(define-data-var contract-owner principal tx-sender)
(define-data-var total-percentage uint u0)
(define-data-var total-distributed uint u0)
(define-data-var total-received uint u0)
(define-data-var recipient-count uint u0)

(define-map recipients 
    principal 
    {
        percentage: uint,
        total-earned: uint,
        withdrawn: uint,
        active: bool,
        added-at-block: uint
    }
)

(define-map recipient-index uint principal)
(define-map balances principal uint)

(define-public (add-recipient (recipient principal) (percentage uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-OWNER-ONLY)
        (asserts! (> percentage u0) ERR-INVALID-PERCENTAGE)
        (asserts! (<= percentage u100) ERR-INVALID-PERCENTAGE)
        (asserts! (is-none (map-get? recipients recipient)) ERR-ALREADY-EXISTS)
        
        (let ((new-total (+ (var-get total-percentage) percentage)))
            (asserts! (<= new-total u100) ERR-TOTAL-PERCENTAGE-EXCEEDS-100)
            
            (map-set recipients recipient {
                percentage: percentage,
                total-earned: u0,
                withdrawn: u0,
                active: true,
                added-at-block: stacks-block-height
            })
            
            (map-set recipient-index (var-get recipient-count) recipient)
            (var-set recipient-count (+ (var-get recipient-count) u1))
            (var-set total-percentage new-total)
            (ok true)
        )
    )
)

(define-public (remove-recipient (recipient principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-OWNER-ONLY)
        
        (match (map-get? recipients recipient)
            recipient-data (let ((percentage (get percentage recipient-data)))
                (map-set recipients recipient (merge recipient-data { active: false }))
                (var-set total-percentage (- (var-get total-percentage) percentage))
                (ok true)
            )
            ERR-NOT-FOUND
        )
    )
)

(define-public (update-recipient-percentage (recipient principal) (new-percentage uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-OWNER-ONLY)
        (asserts! (> new-percentage u0) ERR-INVALID-PERCENTAGE)
        (asserts! (<= new-percentage u100) ERR-INVALID-PERCENTAGE)
        
        (match (map-get? recipients recipient)
            recipient-data (let ((old-percentage (get percentage recipient-data))
                                (new-total (+ (- (var-get total-percentage) old-percentage) new-percentage)))
                (asserts! (<= new-total u100) ERR-TOTAL-PERCENTAGE-EXCEEDS-100)
                (asserts! (get active recipient-data) ERR-NOT-FOUND)
                
                (map-set recipients recipient (merge recipient-data { percentage: new-percentage }))
                (var-set total-percentage new-total)
                (ok true)
            )
            ERR-NOT-FOUND
        )
    )
)

(define-public (deposit)
    (let ((amount (stx-get-balance tx-sender)))
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (> (var-get total-percentage) u0) ERR-NO-RECIPIENTS)
        
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (unwrap-panic (distribute-payment amount))
        (var-set total-received (+ (var-get total-received) amount))
        (ok amount)
    )
)

(define-public (deposit-amount (amount uint))
    (begin
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (> (var-get total-percentage) u0) ERR-NO-RECIPIENTS)
        
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (unwrap-panic (distribute-payment amount))
        (var-set total-received (+ (var-get total-received) amount))
        (ok amount)
    )
)

(define-private (distribute-payment (amount uint))
    (begin
        (unwrap-panic (distribute-to-index amount u0))
        (unwrap-panic (distribute-to-index amount u1))
        (unwrap-panic (distribute-to-index amount u2))
        (unwrap-panic (distribute-to-index amount u3))
        (unwrap-panic (distribute-to-index amount u4))
        (ok true)
    )
)

(define-private (distribute-to-index (amount uint) (index uint))
    (match (map-get? recipient-index index)
        recipient (distribute-single-recipient recipient amount)
        (ok true)
    )
)

(define-private (distribute-single-recipient (recipient principal) (amount uint))
    (match (map-get? recipients recipient)
        recipient-data (if (get active recipient-data)
            (let ((percentage (get percentage recipient-data))
                  (share (/ (* amount percentage) u100))
                  (current-balance (default-to u0 (map-get? balances recipient))))
                
                (map-set balances recipient (+ current-balance share))
                (map-set recipients recipient 
                    (merge recipient-data { 
                        total-earned: (+ (get total-earned recipient-data) share) 
                    }))
                (var-set total-distributed (+ (var-get total-distributed) share))
                (ok true)
            )
            (ok true)
        )
        (ok true)
    )
)



(define-public (withdraw)
    (let ((balance (default-to u0 (map-get? balances tx-sender))))
        (asserts! (> balance u0) ERR-INSUFFICIENT-BALANCE)
        
        (map-delete balances tx-sender)
        (match (map-get? recipients tx-sender)
            recipient-data (map-set recipients tx-sender 
                (merge recipient-data { 
                    withdrawn: (+ (get withdrawn recipient-data) balance) 
                }))
            true
        )
        
        (as-contract (stx-transfer? balance tx-sender tx-sender))
    )
)

(define-public (withdraw-as-owner (recipient principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-OWNER-ONLY)
        
        (let ((balance (default-to u0 (map-get? balances recipient))))
            (asserts! (> balance u0) ERR-INSUFFICIENT-BALANCE)
            
            (map-delete balances recipient)
            (match (map-get? recipients recipient)
                recipient-data (map-set recipients recipient 
                    (merge recipient-data { 
                        withdrawn: (+ (get withdrawn recipient-data) balance) 
                    }))
                true
            )
            
            (as-contract (stx-transfer? balance tx-sender recipient))
        )
    )
)

(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-OWNER-ONLY)
        (var-set contract-owner new-owner)
        (ok true)
    )
)

(define-read-only (get-recipient-info (recipient principal))
    (map-get? recipients recipient)
)

(define-read-only (get-recipient-balance (recipient principal))
    (default-to u0 (map-get? balances recipient))
)

(define-read-only (get-contract-owner)
    (var-get contract-owner)
)

(define-read-only (get-total-percentage)
    (var-get total-percentage)
)

(define-read-only (get-total-distributed)
    (var-get total-distributed)
)

(define-read-only (get-total-received)
    (var-get total-received)
)

(define-read-only (get-recipient-count)
    (var-get recipient-count)
)

(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-recipient-by-index (index uint))
    (map-get? recipient-index index)
)

(define-private (get-all-active-recipients)
    (list)
)

(define-read-only (get-distribution-preview (amount uint))
    (ok { amount: amount, total-percentage: (var-get total-percentage) })
)

(define-read-only (calculate-share (amount uint) (percentage uint))
    (/ (* amount percentage) u100)
)
