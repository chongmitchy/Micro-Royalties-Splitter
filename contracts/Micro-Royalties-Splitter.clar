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
(define-constant ERR-VESTING-NOT-STARTED (err u109))
(define-constant ERR-VESTING-ALREADY-EXISTS (err u110))
(define-constant ERR-INVALID-VESTING-PERIOD (err u111))
(define-constant ERR-NO-VESTED-AMOUNT (err u112))
(define-constant ERR-INVALID-SNAPSHOT-ID (err u113))
(define-constant ERR-NO-DISTRIBUTIONS (err u114))

(define-data-var contract-owner principal tx-sender)
(define-data-var total-percentage uint u0)
(define-data-var total-distributed uint u0)
(define-data-var total-received uint u0)
(define-data-var recipient-count uint u0)
(define-data-var next-vesting-id uint u1)
(define-data-var next-distribution-id uint u1)

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

(define-map vesting-schedules
    uint
    {
        recipient: principal,
        total-amount: uint,
        vested-amount: uint,
        start-block: uint,
        cliff-period: uint,
        vesting-period: uint,
        last-claim-block: uint,
        active: bool
    }
)

(define-map recipient-vesting
    principal
    { vesting-id: uint }
)

(define-map distribution-history
    uint
    {
        total-amount: uint,
        timestamp: uint,
        block-height: uint,
        recipient-count: uint,
        distributed-by: principal
    }
)

(define-map distribution-recipients
    { distribution-id: uint, recipient: principal }
    {
        amount: uint,
        percentage: uint
    }
)

(define-map recipient-distributions
    principal
    { distribution-ids: (list 100 uint) }
)

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
    (let ((distribution-id (var-get next-distribution-id)))
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (> (var-get total-percentage) u0) ERR-NO-RECIPIENTS)
        
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (unwrap-panic (distribute-payment amount))
        (unwrap-panic (record-distribution distribution-id amount))
        
        (var-set total-received (+ (var-get total-received) amount))
        (var-set next-distribution-id (+ distribution-id u1))
        (ok distribution-id)
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
                (unwrap-panic (record-recipient-share recipient (var-get next-distribution-id) share percentage))
                (ok true)
            )
            (ok true)
        )
        (ok true)
    )
)



(define-public (withdraw)
    (let ((immediate-balance (default-to u0 (map-get? balances tx-sender)))
          (vested-amount (calculate-vested-amount tx-sender)))
        (asserts! (or (> immediate-balance u0) (> vested-amount u0)) ERR-INSUFFICIENT-BALANCE)
        
        (let ((total-withdrawal (+ immediate-balance vested-amount)))
            (begin
                (if (> immediate-balance u0)
                    (map-delete balances tx-sender)
                    true)
                
                (if (> vested-amount u0)
                    (begin
                        (unwrap-panic (claim-vested-tokens tx-sender))
                        true)
                    true)
                
                (match (map-get? recipients tx-sender)
                    recipient-data (map-set recipients tx-sender 
                        (merge recipient-data { 
                            withdrawn: (+ (get withdrawn recipient-data) total-withdrawal) 
                        }))
                    true
                )
                
                (as-contract (stx-transfer? total-withdrawal tx-sender tx-sender))
            )
        )
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

(define-public (create-vesting-schedule 
    (recipient principal)
    (total-amount uint)
    (cliff-period uint)
    (vesting-period uint))
    (let ((vesting-id (var-get next-vesting-id)))
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-OWNER-ONLY)
        (asserts! (> total-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (> vesting-period u0) ERR-INVALID-VESTING-PERIOD)
        (asserts! (>= vesting-period cliff-period) ERR-INVALID-VESTING-PERIOD)
        (asserts! (is-none (map-get? recipient-vesting recipient)) ERR-VESTING-ALREADY-EXISTS)
        
        (map-set vesting-schedules vesting-id {
            recipient: recipient,
            total-amount: total-amount,
            vested-amount: u0,
            start-block: stacks-block-height,
            cliff-period: cliff-period,
            vesting-period: vesting-period,
            last-claim-block: stacks-block-height,
            active: true
        })
        
        (map-set recipient-vesting recipient { vesting-id: vesting-id })
        
        (var-set next-vesting-id (+ vesting-id u1))
        (ok vesting-id)
    )
)

(define-public (claim-vested-tokens (recipient principal))
    (let ((vesting-info (unwrap! (map-get? recipient-vesting recipient) ERR-NOT-FOUND))
          (vesting-id (get vesting-id vesting-info)))
        (match (map-get? vesting-schedules vesting-id)
            schedule
                (let ((available-amount (calculate-vested-amount recipient)))
                    (asserts! (> available-amount u0) ERR-NO-VESTED-AMOUNT)
                    (asserts! (get active schedule) ERR-VESTING-NOT-STARTED)
                    
                    (map-set vesting-schedules vesting-id
                        (merge schedule {
                            vested-amount: (+ (get vested-amount schedule) available-amount),
                            last-claim-block: stacks-block-height
                        })
                    )
                    
                    (ok available-amount)
                )
            ERR-NOT-FOUND
        )
    )
)

(define-private (calculate-vested-amount (recipient principal))
    (match (map-get? recipient-vesting recipient)
        vesting-info
            (let ((vesting-id (get vesting-id vesting-info)))
                (match (map-get? vesting-schedules vesting-id)
                    schedule
                        (if (get active schedule)
                            (let ((current-block stacks-block-height)
                                  (start-block (get start-block schedule))
                                  (cliff-period (get cliff-period schedule))
                                  (vesting-period (get vesting-period schedule))
                                  (total-amount (get total-amount schedule))
                                  (already-vested (get vested-amount schedule))
                                  (elapsed-blocks (- current-block start-block)))
                                
                                (if (< elapsed-blocks cliff-period)
                                    u0
                                    (if (>= elapsed-blocks vesting-period)
                                        (- total-amount already-vested)
                                        (let ((vested-total (/ (* total-amount elapsed-blocks) vesting-period)))
                                            (if (> vested-total already-vested)
                                                (- vested-total already-vested)
                                                u0
                                            )
                                        )
                                    )
                                )
                            )
                            u0
                        )
                    u0
                )
            )
        u0
    )
)

(define-public (deposit-to-vesting (recipient principal) (amount uint))
    (let ((vesting-info (unwrap! (map-get? recipient-vesting recipient) ERR-NOT-FOUND))
          (vesting-id (get vesting-id vesting-info)))
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-OWNER-ONLY)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (match (map-get? vesting-schedules vesting-id)
            schedule
                (begin
                    (map-set vesting-schedules vesting-id
                        (merge schedule {
                            total-amount: (+ (get total-amount schedule) amount)
                        })
                    )
                    (var-set total-received (+ (var-get total-received) amount))
                    (ok amount)
                )
            ERR-NOT-FOUND
        )
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

(define-read-only (get-vesting-schedule (vesting-id uint))
    (map-get? vesting-schedules vesting-id)
)

(define-read-only (get-recipient-vesting (recipient principal))
    (map-get? recipient-vesting recipient)
)

(define-private (record-distribution (distribution-id uint) (amount uint))
    (begin
        (map-set distribution-history distribution-id {
            total-amount: amount,
            timestamp: stacks-block-height,
            block-height: stacks-block-height,
            recipient-count: (var-get recipient-count),
            distributed-by: tx-sender
        })
        (ok true)
    )
)

(define-private (record-recipient-share (recipient principal) (distribution-id uint) (amount uint) (percentage uint))
    (let ((current-distributions (default-to { distribution-ids: (list) } 
                                              (map-get? recipient-distributions recipient)))
          (current-ids (get distribution-ids current-distributions)))
        
        (map-set distribution-recipients 
            { distribution-id: distribution-id, recipient: recipient }
            { amount: amount, percentage: percentage }
        )
        
        (map-set recipient-distributions recipient {
            distribution-ids: (unwrap-panic (as-max-len? (append current-ids distribution-id) u100))
        })
        
        (ok true)
    )
)

(define-read-only (get-distribution-info (distribution-id uint))
    (map-get? distribution-history distribution-id)
)

(define-read-only (get-recipient-share (distribution-id uint) (recipient principal))
    (map-get? distribution-recipients { distribution-id: distribution-id, recipient: recipient })
)

(define-read-only (get-recipient-distribution-history (recipient principal))
    (map-get? recipient-distributions recipient)
)

(define-read-only (get-total-distributions)
    (- (var-get next-distribution-id) u1)
)

(define-read-only (get-recipient-distribution-summary (recipient principal))
    (match (map-get? recipients recipient)
        recipient-data
            (ok {
                total-earned: (get total-earned recipient-data),
                withdrawn: (get withdrawn recipient-data),
                pending: (default-to u0 (map-get? balances recipient)),
                active: (get active recipient-data),
                percentage: (get percentage recipient-data),
                distribution-count: (len (get distribution-ids 
                    (default-to { distribution-ids: (list) } 
                                (map-get? recipient-distributions recipient))))
            })
        ERR-NOT-FOUND
    )
)

(define-read-only (get-distribution-snapshot (distribution-id uint) (recipients-list (list 5 principal)))
    (let ((dist-info (unwrap! (map-get? distribution-history distribution-id) ERR-INVALID-SNAPSHOT-ID)))
        (ok {
            distribution-info: dist-info,
            recipient-shares: (map get-recipient-share-for-snapshot recipients-list)
        })
    )
)

(define-private (get-recipient-share-for-snapshot (recipient principal))
    (default-to 
        { amount: u0, percentage: u0 }
        (map-get? distribution-recipients { distribution-id: (var-get next-distribution-id), recipient: recipient })
    )
)
