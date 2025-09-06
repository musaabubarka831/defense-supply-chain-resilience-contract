;; title: critical-component-tracking
;; Critical Component Identification and Tracking Smart Contract
;; Manages identification, tracking, and monitoring of critical defense components

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u200))
(define-constant ERR-NOT-FOUND (err u201))
(define-constant ERR-ALREADY-EXISTS (err u202))
(define-constant ERR-INVALID-CRITICALITY (err u203))
(define-constant ERR-INVALID-STATUS (err u204))
(define-constant ERR-UNAUTHORIZED-ACCESS (err u205))
(define-constant ERR-INVALID-LOCATION (err u206))

;; Criticality levels
(define-constant CRITICALITY-LOW u1)
(define-constant CRITICALITY-MEDIUM u2)
(define-constant CRITICALITY-HIGH u3)
(define-constant CRITICALITY-CRITICAL u4)
(define-constant CRITICALITY-TOP-SECRET u5)

;; Component status codes
(define-constant STATUS-REGISTERED u0)
(define-constant STATUS-IN-TRANSIT u1)
(define-constant STATUS-DELIVERED u2)
(define-constant STATUS-INSTALLED u3)
(define-constant STATUS-OPERATIONAL u4)
(define-constant STATUS-COMPROMISED u5)

;; Data Variables
(define-data-var total-components uint u0)
(define-data-var next-component-id uint u1)
(define-data-var security-alert-level uint u0)
(define-data-var tracking-enabled bool true)

;; Data Maps
(define-map components
  { component-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 200),
    criticality-level: uint,
    current-status: uint,
    supplier-id: uint,
    manufacturer: (string-ascii 100),
    serial-number: (string-ascii 50),
    registration-date: uint,
    last-updated: uint,
    current-location: (string-ascii 100),
    destination: (string-ascii 100),
    authenticity-verified: bool
  }
)

(define-map component-location-history
  { component-id: uint, history-id: uint }
  {
    previous-location: (string-ascii 100),
    new-location: (string-ascii 100),
    timestamp: uint,
    recorded-by: principal,
    transport-method: (string-ascii 50),
    notes: (string-ascii 200)
  }
)

(define-map security-incidents
  { component-id: uint, incident-id: uint }
  {
    incident-type: (string-ascii 50),
    severity: uint,
    description: (string-ascii 300),
    reported-date: uint,
    reported-by: principal,
    resolved: bool,
    resolution-date: (optional uint)
  }
)

(define-map authorized-trackers
  { tracker: principal }
  {
    department: (string-ascii 50),
    clearance-level: uint,
    authorized-date: uint,
    active: bool
  }
)

(define-map authenticity-records
  { component-id: uint, verification-id: uint }
  {
    verification-hash: (string-ascii 64),
    verification-method: (string-ascii 50),
    verified-by: principal,
    verification-date: uint,
    valid: bool
  }
)

;; Public Functions

;; Register a new critical component
(define-public (register-component
    (name (string-ascii 100))
    (description (string-ascii 200))
    (criticality-level uint)
    (supplier-id uint)
    (manufacturer (string-ascii 100))
    (serial-number (string-ascii 50))
    (initial-location (string-ascii 100))
  )
  (let (
    (component-id (var-get next-component-id))
  )
    ;; Validate criticality level
    (asserts! (and (>= criticality-level CRITICALITY-LOW) 
                   (<= criticality-level CRITICALITY-TOP-SECRET)) ERR-INVALID-CRITICALITY)
    
    ;; Register the component
    (map-set components
      { component-id: component-id }
      {
        name: name,
        description: description,
        criticality-level: criticality-level,
        current-status: STATUS-REGISTERED,
        supplier-id: supplier-id,
        manufacturer: manufacturer,
        serial-number: serial-number,
        registration-date: block-height,
        last-updated: block-height,
        current-location: initial-location,
        destination: "",
        authenticity-verified: false
      }
    )
    
    ;; Update counters
    (var-set total-components (+ (var-get total-components) u1))
    (var-set next-component-id (+ component-id u1))
    
    ;; Record initial location
    (map-set component-location-history
      { component-id: component-id, history-id: u1 }
      {
        previous-location: "",
        new-location: initial-location,
        timestamp: block-height,
        recorded-by: tx-sender,
        transport-method: "Initial Registration",
        notes: "Component registered in tracking system"
      }
    )
    
    (ok component-id)
  )
)

;; Update component location
(define-public (update-location
    (component-id uint)
    (new-location (string-ascii 100))
    (transport-method (string-ascii 50))
    (notes (string-ascii 200))
  )
  (let (
    (component (unwrap! (map-get? components { component-id: component-id }) ERR-NOT-FOUND))
    (current-location (get current-location component))
    (history-id u1)
  )
    ;; Update component location
    (map-set components
      { component-id: component-id }
      (merge component {
        current-location: new-location,
        last-updated: block-height
      })
    )
    
    ;; Record location history
    (map-set component-location-history
      { component-id: component-id, history-id: history-id }
      {
        previous-location: current-location,
        new-location: new-location,
        timestamp: block-height,
        recorded-by: tx-sender,
        transport-method: transport-method,
        notes: notes
      }
    )
    
    (ok new-location)
  )
)

;; Update component status
(define-public (update-status
    (component-id uint)
    (new-status uint)
    (notes (string-ascii 200))
  )
  (let (
    (component (unwrap! (map-get? components { component-id: component-id }) ERR-NOT-FOUND))
  )
    ;; Validate status
    (asserts! (<= new-status STATUS-COMPROMISED) ERR-INVALID-STATUS)
    
    ;; Update component status
    (map-set components
      { component-id: component-id }
      (merge component {
        current-status: new-status,
        last-updated: block-height
      })
    )
    
    ;; If compromised, raise security alert
    (if (is-eq new-status STATUS-COMPROMISED)
      (var-set security-alert-level u5)
      true
    )
    
    (ok new-status)
  )
)

;; Verify component authenticity
(define-public (verify-authenticity
    (component-id uint)
    (verification-hash (string-ascii 64))
    (verification-method (string-ascii 50))
  )
  (let (
    (component (unwrap! (map-get? components { component-id: component-id }) ERR-NOT-FOUND))
    (verification-id u1)
  )
    ;; Record authenticity verification
    (map-set authenticity-records
      { component-id: component-id, verification-id: verification-id }
      {
        verification-hash: verification-hash,
        verification-method: verification-method,
        verified-by: tx-sender,
        verification-date: block-height,
        valid: true
      }
    )
    
    ;; Update component verification status
    (map-set components
      { component-id: component-id }
      (merge component {
        authenticity-verified: true,
        last-updated: block-height
      })
    )
    
    (ok true)
  )
)

;; Report security incident
(define-public (flag-security-risk
    (component-id uint)
    (incident-type (string-ascii 50))
    (severity uint)
    (description (string-ascii 300))
  )
  (let (
    (component (unwrap! (map-get? components { component-id: component-id }) ERR-NOT-FOUND))
    (incident-id u1)
  )
    ;; Validate severity level
    (asserts! (and (>= severity u1) (<= severity u5)) ERR-INVALID-CRITICALITY)
    
    ;; Record security incident
    (map-set security-incidents
      { component-id: component-id, incident-id: incident-id }
      {
        incident-type: incident-type,
        severity: severity,
        description: description,
        reported-date: block-height,
        reported-by: tx-sender,
        resolved: false,
        resolution-date: none
      }
    )
    
    ;; Update security alert level if high severity
    (if (>= severity u4)
      (if (> severity (var-get security-alert-level))
        (var-set security-alert-level severity)
        true
      )
      true
    )
    
    (ok incident-id)
  )
)

;; Authorize tracker
(define-public (authorize-tracker
    (tracker principal)
    (department (string-ascii 50))
    (clearance-level uint)
  )
  (begin
    ;; Only contract owner can authorize trackers
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    
    (map-set authorized-trackers
      { tracker: tracker }
      {
        department: department,
        clearance-level: clearance-level,
        authorized-date: block-height,
        active: true
      }
    )
    
    (ok tracker)
  )
)

;; Set security alert level
(define-public (set-security-alert (level uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (<= level u5) ERR-INVALID-STATUS)
    (var-set security-alert-level level)
    (ok level)
  )
)

;; Read-Only Functions

;; Get component information
(define-read-only (get-component-info (component-id uint))
  (map-get? components { component-id: component-id })
)

;; Get component location history
(define-read-only (get-location-history
    (component-id uint)
    (history-id uint)
  )
  (map-get? component-location-history { component-id: component-id, history-id: history-id })
)

;; Get security incident
(define-read-only (get-security-incident
    (component-id uint)
    (incident-id uint)
  )
  (map-get? security-incidents { component-id: component-id, incident-id: incident-id })
)

;; Check if component is compromised
(define-read-only (is-component-compromised (component-id uint))
  (match (map-get? components { component-id: component-id })
    component (is-eq (get current-status component) STATUS-COMPROMISED)
    false
  )
)

;; Get total components count
(define-read-only (get-total-components)
  (var-get total-components)
)

;; Get security alert level
(define-read-only (get-security-alert-level)
  (var-get security-alert-level)
)

;; Check if tracking is enabled
(define-read-only (is-tracking-enabled)
  (var-get tracking-enabled)
)

;; Get contract owner
(define-read-only (get-contract-owner)
  CONTRACT-OWNER
)

;; Private Functions

;; Get last location history ID (helper function)
(define-private (get-last-location-history-id (component-id uint))
  ;; Simplified - in production, track this more efficiently
  u0
)

;; Get last verification ID (helper function)
(define-private (get-last-verification-id (component-id uint))
  ;; Simplified - in production, track this more efficiently
  u0
)

;; Get last incident ID (helper function)
(define-private (get-last-incident-id (component-id uint))
  ;; Simplified - in production, track this more efficiently
  u0
)

