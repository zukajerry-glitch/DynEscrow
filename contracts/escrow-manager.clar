;; Escrow Manager Contract
;; Manages escrow lifecycle from creation to completion with IoT integration

;; Constants
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_NOT_FOUND (err u201))
(define-constant ERR_INVALID_AMOUNT (err u202))
(define-constant ERR_INSUFFICIENT_FUNDS (err u203))
(define-constant ERR_ESCROW_EXISTS (err u204))
(define-constant ERR_ESCROW_CLOSED (err u205))
(define-constant ERR_INVALID_STATUS (err u206))
(define-constant ERR_CONDITIONS_NOT_MET (err u207))
(define-constant ERR_TIMEOUT_NOT_REACHED (err u208))
(define-constant ERR_INVALID_MILESTONE (err u209))
(define-constant ERR_TEMPERATURE_VIOLATION (err u210))

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var next-escrow-id uint u1)
(define-data-var platform-fee-basis-points uint u250) ;; 2.5%
(define-data-var min-escrow-amount uint u1000000) ;; 1 STX in microSTX

;; Escrow Status Constants
(define-constant ESCROW_STATUS_PENDING u1)
(define-constant ESCROW_STATUS_ACTIVE u2)
(define-constant ESCROW_STATUS_RELEASED u3)
(define-constant ESCROW_STATUS_REFUNDED u4)
(define-constant ESCROW_STATUS_DISPUTED u5)
(define-constant ESCROW_STATUS_EXPIRED u6)

;; Release Condition Types
(define-constant CONDITION_DELIVERY u1)
(define-constant CONDITION_TEMPERATURE u2)
(define-constant CONDITION_TIME u3)
(define-constant CONDITION_CUSTOM_MILESTONE u4)

;; Data Maps
(define-map escrows
  { escrow-id: uint }
  {
    buyer: principal,
    seller: principal,
    amount: uint,
    shipment-id: uint,
    status: uint,
    created-at: uint,
    timeout-block: uint,
    required-milestones: (list 10 uint),
    completed-milestones: (list 10 uint),
    release-conditions: (list 5 uint),
    temperature-required: bool,
    dispute-resolver: (optional principal),
    platform-fee: uint,
    notes: (string-ascii 512)
  }
)

(define-map escrow-balances
  { escrow-id: uint }
  { deposited-amount: uint, released-amount: uint }
)

(define-map user-escrows
  { user: principal }
  { escrow-ids: (list 100 uint) }
)

(define-map dispute-votes
  { escrow-id: uint, voter: principal }
  { vote: bool, timestamp: uint }
)

;; Authorization Functions
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

(define-private (is-escrow-participant (escrow-id uint))
  (match (map-get? escrows { escrow-id: escrow-id })
    escrow (or
      (is-eq tx-sender (get buyer escrow))
      (is-eq tx-sender (get seller escrow))
      (match (get dispute-resolver escrow)
        resolver (is-eq tx-sender resolver)
        false
      )
    )
    false
  )
)

(define-private (is-buyer (escrow-id uint))
  (match (map-get? escrows { escrow-id: escrow-id })
    escrow (is-eq tx-sender (get buyer escrow))
    false
  )
)

(define-private (is-seller (escrow-id uint))
  (match (map-get? escrows { escrow-id: escrow-id })
    escrow (is-eq tx-sender (get seller escrow))
    false
  )
)

;; Helper Functions
(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-basis-points)) u10000)
)

(define-private (get-user-escrow-list (user principal))
  (default-to (list) (get escrow-ids (map-get? user-escrows { user: user })))
)

(define-private (add-to-user-escrows (user principal) (escrow-id uint))
  (let (
    (current-list (get-user-escrow-list user))
  )
    (map-set user-escrows
      { user: user }
      { escrow-ids: (unwrap! (as-max-len? (append current-list escrow-id) u100) (err u999)) }
    )
    (ok true)
  )
)

(define-private (check-milestone-completion (escrow-id uint) (required-milestones (list 10 uint)))
  (fold check-single-milestone required-milestones true)
)

(define-private (check-single-milestone (milestone-type uint) (prev-result bool))
  (and prev-result true) ;; Simplified for this implementation
)

;; Escrow Management Functions
(define-public (create-escrow
  (seller principal)
  (amount uint)
  (shipment-id uint)
  (timeout-blocks uint)
  (required-milestones (list 10 uint))
  (release-conditions (list 5 uint))
  (temperature-required bool)
  (dispute-resolver (optional principal))
  (notes (string-ascii 512))
)
  (let (
    (escrow-id (var-get next-escrow-id))
    (platform-fee (calculate-platform-fee amount))
    (total-amount (+ amount platform-fee))
  )
    (asserts! (>= amount (var-get min-escrow-amount)) ERR_INVALID_AMOUNT)
    (asserts! (>= (stx-get-balance tx-sender) total-amount) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer funds to contract
    (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))
    
    ;; Create escrow record
    (map-set escrows
      { escrow-id: escrow-id }
      {
        buyer: tx-sender,
        seller: seller,
        amount: amount,
        shipment-id: shipment-id,
        status: ESCROW_STATUS_PENDING,
        created-at: stacks-block-height,
        timeout-block: (+ stacks-block-height timeout-blocks),
        required-milestones: required-milestones,
        completed-milestones: (list),
        release-conditions: release-conditions,
        temperature-required: temperature-required,
        dispute-resolver: dispute-resolver,
        platform-fee: platform-fee,
        notes: notes
      }
    )
    
    ;; Set balance tracking
    (map-set escrow-balances
      { escrow-id: escrow-id }
      { deposited-amount: total-amount, released-amount: u0 }
    )
    
    ;; Add to user lists
    (try! (add-to-user-escrows tx-sender escrow-id))
    (try! (add-to-user-escrows seller escrow-id))
    
    ;; Update next ID
    (var-set next-escrow-id (+ escrow-id u1))
    
    (ok escrow-id)
  )
)

(define-public (activate-escrow (escrow-id uint))
  (let (
    (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR_NOT_FOUND))
  )
    (asserts! (is-seller escrow-id) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status escrow) ESCROW_STATUS_PENDING) ERR_INVALID_STATUS)
    
    (map-set escrows
      { escrow-id: escrow-id }
      (merge escrow { status: ESCROW_STATUS_ACTIVE })
    )
    
    (ok true)
  )
)

(define-public (release-escrow (escrow-id uint))
  (let (
    (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR_NOT_FOUND))
    (balance (unwrap! (map-get? escrow-balances { escrow-id: escrow-id }) ERR_NOT_FOUND))
  )
    (asserts! (is-escrow-participant escrow-id) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status escrow) ESCROW_STATUS_ACTIVE) ERR_INVALID_STATUS)
    
    ;; Check if release conditions are met
    (try! (check-release-conditions escrow-id))
    
    ;; Transfer funds to seller
    (try! (as-contract (stx-transfer? (get amount escrow) tx-sender (get seller escrow))))
    
    ;; Transfer platform fee to contract owner
    (try! (as-contract (stx-transfer? (get platform-fee escrow) tx-sender (var-get contract-owner))))
    
    ;; Update escrow status
    (map-set escrows
      { escrow-id: escrow-id }
      (merge escrow { status: ESCROW_STATUS_RELEASED })
    )
    
    ;; Update balance tracking
    (map-set escrow-balances
      { escrow-id: escrow-id }
      (merge balance { released-amount: (get deposited-amount balance) })
    )
    
    (ok true)
  )
)

(define-public (refund-escrow (escrow-id uint))
  (let (
    (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR_NOT_FOUND))
    (balance (unwrap! (map-get? escrow-balances { escrow-id: escrow-id }) ERR_NOT_FOUND))
  )
    (asserts! (is-buyer escrow-id) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq (get status escrow) ESCROW_STATUS_PENDING) 
                  (>= stacks-block-height (get timeout-block escrow))) ERR_CONDITIONS_NOT_MET)
    
    ;; Transfer full amount back to buyer (including platform fee if conditions are met)
    (try! (as-contract (stx-transfer? (get deposited-amount balance) tx-sender (get buyer escrow))))
    
    ;; Update escrow status
    (map-set escrows
      { escrow-id: escrow-id }
      (merge escrow { status: ESCROW_STATUS_REFUNDED })
    )
    
    ;; Update balance tracking
    (map-set escrow-balances
      { escrow-id: escrow-id }
      (merge balance { released-amount: (get deposited-amount balance) })
    )
    
    (ok true)
  )
)

(define-public (dispute-escrow (escrow-id uint))
  (let (
    (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR_NOT_FOUND))
  )
    (asserts! (is-escrow-participant escrow-id) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status escrow) ESCROW_STATUS_ACTIVE) ERR_INVALID_STATUS)
    
    (map-set escrows
      { escrow-id: escrow-id }
      (merge escrow { status: ESCROW_STATUS_DISPUTED })
    )
    
    (ok true)
  )
)

;; Release Condition Checking
(define-private (check-release-conditions (escrow-id uint))
  (let (
    (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR_NOT_FOUND))
    (conditions (get release-conditions escrow))
    (shipment-id (get shipment-id escrow))
  )
    ;; Check delivery milestone (simplified implementation)
    (asserts! (check-delivery-condition shipment-id) ERR_CONDITIONS_NOT_MET)
    
    ;; Check temperature compliance if required
    (if (get temperature-required escrow)
      (asserts! (check-temperature-condition shipment-id) ERR_TEMPERATURE_VIOLATION)
      true
    )
    
    (ok true)
  )
)

(define-private (check-delivery-condition (shipment-id uint))
  ;; This would integrate with IoT tracker contract
  ;; For now, simplified to always return true
  true
)

(define-private (check-temperature-condition (shipment-id uint))
  ;; This would check temperature compliance via IoT tracker
  ;; For now, simplified to always return true
  true
)

;; Read-only Functions
(define-read-only (get-escrow (escrow-id uint))
  (map-get? escrows { escrow-id: escrow-id })
)

(define-read-only (get-escrow-balance (escrow-id uint))
  (map-get? escrow-balances { escrow-id: escrow-id })
)

(define-read-only (get-user-escrows (user principal))
  (get-user-escrow-list user)
)

(define-read-only (get-escrow-status (escrow-id uint))
  (match (map-get? escrows { escrow-id: escrow-id })
    escrow (ok (get status escrow))
    ERR_NOT_FOUND
  )
)

(define-read-only (is-escrow-ready-for-release (escrow-id uint))
  (match (map-get? escrows { escrow-id: escrow-id })
    escrow
    (and 
      (is-eq (get status escrow) ESCROW_STATUS_ACTIVE)
      (check-delivery-condition (get shipment-id escrow))
      (if (get temperature-required escrow)
        (check-temperature-condition (get shipment-id escrow))
        true
      )
    )
    false
  )
)

(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-basis-points)
)

(define-read-only (get-min-escrow-amount)
  (var-get min-escrow-amount)
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

;; Admin Functions
(define-public (set-platform-fee (new-fee-basis-points uint))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (asserts! (<= new-fee-basis-points u1000) ERR_INVALID_AMOUNT) ;; Max 10%
    (var-set platform-fee-basis-points new-fee-basis-points)
    (ok true)
  )
)

(define-public (set-min-escrow-amount (new-amount uint))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (var-set min-escrow-amount new-amount)
    (ok true)
  )
)

(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)
