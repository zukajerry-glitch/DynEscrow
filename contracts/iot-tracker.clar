;; IoT Tracker Contract
;; Handles IoT device data verification and shipment milestone tracking

;; Constants
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_INVALID_DEVICE (err u102))
(define-constant ERR_INVALID_DATA (err u103))
(define-constant ERR_INVALID_MILESTONE (err u104))
(define-constant ERR_DEVICE_EXISTS (err u105))
(define-constant ERR_SHIPMENT_EXISTS (err u106))
(define-constant ERR_MILESTONE_EXISTS (err u107))
(define-constant ERR_INVALID_STATUS (err u108))

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var next-device-id uint u1)
(define-data-var next-shipment-id uint u1)

;; Device Status Constants
(define-constant DEVICE_STATUS_ACTIVE u1)
(define-constant DEVICE_STATUS_INACTIVE u2)
(define-constant DEVICE_STATUS_MAINTENANCE u3)

;; Milestone Types
(define-constant MILESTONE_PICKUP u1)
(define-constant MILESTONE_TRANSIT u2)
(define-constant MILESTONE_CUSTOMS u3)
(define-constant MILESTONE_DELIVERY u4)
(define-constant MILESTONE_EXCEPTION u5)

;; Data Maps
(define-map devices
  { device-id: uint }
  {
    device-address: (buff 33),
    owner: principal,
    device-type: (string-ascii 64),
    status: uint,
    last-update: uint,
    total-shipments: uint
  }
)

(define-map shipments
  { shipment-id: uint }
  {
    device-id: uint,
    shipper: principal,
    recipient: principal,
    origin: (string-ascii 128),
    destination: (string-ascii 128),
    current-location: (string-ascii 128),
    status: uint,
    created-at: uint,
    estimated-delivery: uint,
    temperature-min: int,
    temperature-max: int,
    current-temperature: int,
    milestone-count: uint
  }
)

(define-map shipment-milestones
  { shipment-id: uint, milestone-type: uint }
  {
    timestamp: uint,
    location: (string-ascii 128),
    temperature: int,
    humidity: uint,
    verified: bool,
    verifier: principal,
    notes: (string-ascii 256)
  }
)

(define-map device-owners
  { owner: principal }
  { device-ids: (list 100 uint) }
)

;; Authorization Functions
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

(define-private (is-device-owner (device-id uint))
  (match (map-get? devices { device-id: device-id })
    device (is-eq tx-sender (get owner device))
    false
  )
)

(define-private (is-shipment-participant (shipment-id uint))
  (match (map-get? shipments { shipment-id: shipment-id })
    shipment (or 
      (is-eq tx-sender (get shipper shipment))
      (is-eq tx-sender (get recipient shipment))
      (is-device-owner (get device-id shipment))
    )
    false
  )
)

;; Device Management Functions
(define-public (register-device (device-address (buff 33)) (device-type (string-ascii 64)))
  (let (
    (device-id (var-get next-device-id))
  )
    (asserts! (is-none (index-of? (get-device-list tx-sender) device-id)) ERR_DEVICE_EXISTS)
    (map-set devices
      { device-id: device-id }
      {
        device-address: device-address,
        owner: tx-sender,
        device-type: device-type,
        status: DEVICE_STATUS_ACTIVE,
        last-update: stacks-block-height,
        total-shipments: u0
      }
    )
    (map-set device-owners
      { owner: tx-sender }
      { device-ids: (unwrap! (as-max-len? (append (get-device-list tx-sender) device-id) u100) ERR_INVALID_DATA) }
    )
    (var-set next-device-id (+ device-id u1))
    (ok device-id)
  )
)

(define-public (update-device-status (device-id uint) (new-status uint))
  (let (
    (device (unwrap! (map-get? devices { device-id: device-id }) ERR_NOT_FOUND))
  )
    (asserts! (is-device-owner device-id) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq new-status DEVICE_STATUS_ACTIVE) 
                  (is-eq new-status DEVICE_STATUS_INACTIVE) 
                  (is-eq new-status DEVICE_STATUS_MAINTENANCE)) ERR_INVALID_STATUS)
    (map-set devices
      { device-id: device-id }
      (merge device { status: new-status, last-update: stacks-block-height })
    )
    (ok true)
  )
)

;; Shipment Tracking Functions
(define-public (create-shipment 
  (device-id uint) 
  (recipient principal) 
  (origin (string-ascii 128)) 
  (destination (string-ascii 128))
  (estimated-delivery uint)
  (temp-min int)
  (temp-max int)
)
  (let (
    (shipment-id (var-get next-shipment-id))
    (device (unwrap! (map-get? devices { device-id: device-id }) ERR_NOT_FOUND))
  )
    (asserts! (is-device-owner device-id) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status device) DEVICE_STATUS_ACTIVE) ERR_INVALID_DEVICE)
    (map-set shipments
      { shipment-id: shipment-id }
      {
        device-id: device-id,
        shipper: tx-sender,
        recipient: recipient,
        origin: origin,
        destination: destination,
        current-location: origin,
        status: MILESTONE_PICKUP,
        created-at: stacks-block-height,
        estimated-delivery: estimated-delivery,
        temperature-min: temp-min,
        temperature-max: temp-max,
        current-temperature: temp-min,
        milestone-count: u0
      }
    )
    (map-set devices
      { device-id: device-id }
      (merge device { total-shipments: (+ (get total-shipments device) u1) })
    )
    (var-set next-shipment-id (+ shipment-id u1))
    (ok shipment-id)
  )
)

(define-public (add-milestone
  (shipment-id uint)
  (milestone-type uint)
  (location (string-ascii 128))
  (temperature int)
  (humidity uint)
  (notes (string-ascii 256))
)
  (let (
    (shipment (unwrap! (map-get? shipments { shipment-id: shipment-id }) ERR_NOT_FOUND))
  )
    (asserts! (is-shipment-participant shipment-id) ERR_UNAUTHORIZED)
    (asserts! (<= milestone-type MILESTONE_EXCEPTION) ERR_INVALID_MILESTONE)
    (asserts! (is-none (map-get? shipment-milestones { shipment-id: shipment-id, milestone-type: milestone-type })) ERR_MILESTONE_EXISTS)
    
    (map-set shipment-milestones
      { shipment-id: shipment-id, milestone-type: milestone-type }
      {
        timestamp: stacks-block-height,
        location: location,
        temperature: temperature,
        humidity: humidity,
        verified: true,
        verifier: tx-sender,
        notes: notes
      }
    )
    
    (map-set shipments
      { shipment-id: shipment-id }
      (merge shipment {
        current-location: location,
        status: milestone-type,
        current-temperature: temperature,
        milestone-count: (+ (get milestone-count shipment) u1)
      })
    )
    
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-device (device-id uint))
  (map-get? devices { device-id: device-id })
)

(define-read-only (get-shipment (shipment-id uint))
  (map-get? shipments { shipment-id: shipment-id })
)

(define-read-only (get-milestone (shipment-id uint) (milestone-type uint))
  (map-get? shipment-milestones { shipment-id: shipment-id, milestone-type: milestone-type })
)

(define-read-only (get-device-list (owner principal))
  (default-to (list) (get device-ids (map-get? device-owners { owner: owner })))
)

(define-read-only (is-temperature-compliant (shipment-id uint))
  (match (map-get? shipments { shipment-id: shipment-id })
    shipment
    (let (
      (current-temp (get current-temperature shipment))
      (min-temp (get temperature-min shipment))
      (max-temp (get temperature-max shipment))
    )
      (and (>= current-temp min-temp) (<= current-temp max-temp))
    )
    false
  )
)

(define-read-only (get-shipment-status (shipment-id uint))
  (match (map-get? shipments { shipment-id: shipment-id })
    shipment (ok (get status shipment))
    ERR_NOT_FOUND
  )
)

(define-read-only (is-milestone-reached (shipment-id uint) (milestone-type uint))
  (is-some (map-get? shipment-milestones { shipment-id: shipment-id, milestone-type: milestone-type }))
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

;; Admin Functions
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

