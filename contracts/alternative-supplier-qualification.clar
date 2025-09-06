;; title: alternative-supplier-qualification
;; Alternative Supplier Development and Qualification Smart Contract
;; Manages supplier registration, qualification levels, and performance tracking for defense supply chains

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-QUALIFICATION (err u103))
(define-constant ERR-INVALID-PERFORMANCE (err u104))
(define-constant ERR-SUPPLIER-INACTIVE (err u105))
(define-constant ERR-UNAUTHORIZED (err u106))

;; Qualification levels
(define-constant QUALIFICATION-UNQUALIFIED u0)
(define-constant QUALIFICATION-PROVISIONAL u1)
(define-constant QUALIFICATION-BASIC u2)
(define-constant QUALIFICATION-STANDARD u3)
(define-constant QUALIFICATION-ADVANCED u4)
(define-constant QUALIFICATION-CRITICAL u5)

;; Data Variables
(define-data-var total-suppliers uint u0)
(define-data-var emergency-mode bool false)
(define-data-var next-supplier-id uint u1)

;; Data Maps
(define-map suppliers
  { supplier-id: uint }
  {
    name: (string-ascii 100),
    contact-email: (string-ascii 100),
    category: (string-ascii 50),
    qualification-level: uint,
    performance-score: uint,
    registration-date: uint,
    last-updated: uint,
    active: bool,
    emergency-qualified: bool,
    certifications: (list 10 (string-ascii 50))
  }
)

(define-map supplier-performance-history
  { supplier-id: uint, performance-id: uint }
  {
    delivery-score: uint,
    quality-score: uint,
    cost-effectiveness: uint,
    compliance-score: uint,
    evaluation-date: uint,
    evaluator: principal,
    notes: (string-ascii 200)
  }
)

(define-map qualification-history
  { supplier-id: uint, history-id: uint }
  {
    previous-level: uint,
    new-level: uint,
    change-date: uint,
    reason: (string-ascii 200),
    approved-by: principal
  }
)

(define-map authorized-evaluators
  { evaluator: principal }
  {
    department: (string-ascii 50),
    authorization-level: uint,
    authorized-date: uint,
    active: bool
  }
)

;; Public Functions

;; Register a new supplier
(define-public (register-supplier
    (name (string-ascii 100))
    (contact-email (string-ascii 100))
    (category (string-ascii 50))
    (initial-qualification uint)
    (certifications (list 10 (string-ascii 50)))
  )
  (let (
    (supplier-id (var-get next-supplier-id))
  )
    ;; Validate qualification level
    (asserts! (<= initial-qualification QUALIFICATION-CRITICAL) ERR-INVALID-QUALIFICATION)
    
    ;; Register the supplier
    (map-set suppliers
      { supplier-id: supplier-id }
      {
        name: name,
        contact-email: contact-email,
        category: category,
        qualification-level: initial-qualification,
        performance-score: u75, ;; Starting score
        registration-date: block-height,
        last-updated: block-height,
        active: true,
        emergency-qualified: false,
        certifications: certifications
      }
    )
    
    ;; Update counters
    (var-set total-suppliers (+ (var-get total-suppliers) u1))
    (var-set next-supplier-id (+ supplier-id u1))
    
    ;; Record initial qualification
    (map-set qualification-history
      { supplier-id: supplier-id, history-id: u1 }
      {
        previous-level: u0,
        new-level: initial-qualification,
        change-date: block-height,
        reason: "Initial supplier registration",
        approved-by: tx-sender
      }
    )
    
    (ok supplier-id)
  )
)

;; Update supplier qualification level
(define-public (update-qualification
    (supplier-id uint)
    (new-level uint)
    (reason (string-ascii 200))
  )
  (let (
    (supplier (unwrap! (map-get? suppliers { supplier-id: supplier-id }) ERR-NOT-FOUND))
    (current-level (get qualification-level supplier))
    (history-id u1)
  )
    ;; Validate new qualification level
    (asserts! (<= new-level QUALIFICATION-CRITICAL) ERR-INVALID-QUALIFICATION)
    
    ;; Update supplier record
    (map-set suppliers
      { supplier-id: supplier-id }
      (merge supplier {
        qualification-level: new-level,
        last-updated: block-height
      })
    )
    
    ;; Record qualification change
    (map-set qualification-history
      { supplier-id: supplier-id, history-id: history-id }
      {
        previous-level: current-level,
        new-level: new-level,
        change-date: block-height,
        reason: reason,
        approved-by: tx-sender
      }
    )
    
    (ok new-level)
  )
)

;; Record supplier performance evaluation
(define-public (record-performance
    (supplier-id uint)
    (delivery-score uint)
    (quality-score uint)
    (cost-effectiveness uint)
    (compliance-score uint)
    (notes (string-ascii 200))
  )
  (let (
    (supplier (unwrap! (map-get? suppliers { supplier-id: supplier-id }) ERR-NOT-FOUND))
    (performance-id u1)
    (overall-score (/ (+ delivery-score quality-score cost-effectiveness compliance-score) u4))
  )
    ;; Validate scores (0-100 range)
    (asserts! (and (<= delivery-score u100) (<= quality-score u100) 
                   (<= cost-effectiveness u100) (<= compliance-score u100)) ERR-INVALID-PERFORMANCE)
    
    ;; Record performance evaluation
    (map-set supplier-performance-history
      { supplier-id: supplier-id, performance-id: performance-id }
      {
        delivery-score: delivery-score,
        quality-score: quality-score,
        cost-effectiveness: cost-effectiveness,
        compliance-score: compliance-score,
        evaluation-date: block-height,
        evaluator: tx-sender,
        notes: notes
      }
    )
    
    ;; Update overall performance score
    (map-set suppliers
      { supplier-id: supplier-id }
      (merge supplier {
        performance-score: overall-score,
        last-updated: block-height
      })
    )
    
    (ok overall-score)
  )
)

;; Activate emergency supplier status
(define-public (activate-emergency-supplier
    (supplier-id uint)
    (justification (string-ascii 200))
  )
  (let (
    (supplier (unwrap! (map-get? suppliers { supplier-id: supplier-id }) ERR-NOT-FOUND))
  )
    ;; Only contract owner or during emergency mode
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (var-get emergency-mode)) ERR-UNAUTHORIZED)
    
    ;; Activate emergency status
    (map-set suppliers
      { supplier-id: supplier-id }
      (merge supplier {
        emergency-qualified: true,
        last-updated: block-height
      })
    )
    
    (ok true)
  )
)

;; Deactivate supplier
(define-public (deactivate-supplier
    (supplier-id uint)
    (reason (string-ascii 200))
  )
  (let (
    (supplier (unwrap! (map-get? suppliers { supplier-id: supplier-id }) ERR-NOT-FOUND))
  )
    ;; Only contract owner can deactivate
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    
    ;; Deactivate supplier
    (map-set suppliers
      { supplier-id: supplier-id }
      (merge supplier {
        active: false,
        emergency-qualified: false,
        last-updated: block-height
      })
    )
    
    (ok true)
  )
)

;; Authorize evaluator
(define-public (authorize-evaluator
    (evaluator principal)
    (department (string-ascii 50))
    (authorization-level uint)
  )
  (begin
    ;; Only contract owner can authorize evaluators
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    
    (map-set authorized-evaluators
      { evaluator: evaluator }
      {
        department: department,
        authorization-level: authorization-level,
        authorized-date: block-height,
        active: true
      }
    )
    
    (ok evaluator)
  )
)

;; Set emergency mode
(define-public (set-emergency-mode (enabled bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set emergency-mode enabled)
    (ok enabled)
  )
)

;; Read-Only Functions

;; Get supplier information
(define-read-only (get-supplier-info (supplier-id uint))
  (map-get? suppliers { supplier-id: supplier-id })
)

;; Get supplier performance record
(define-read-only (get-performance-record
    (supplier-id uint)
    (performance-id uint)
  )
  (map-get? supplier-performance-history { supplier-id: supplier-id, performance-id: performance-id })
)

;; Get qualification history
(define-read-only (get-qualification-history
    (supplier-id uint)
    (history-id uint)
  )
  (map-get? qualification-history { supplier-id: supplier-id, history-id: history-id })
)

;; Check if supplier meets minimum qualification
(define-read-only (is-qualified-supplier
    (supplier-id uint)
    (minimum-level uint)
  )
  (match (map-get? suppliers { supplier-id: supplier-id })
    supplier (
      and
        (get active supplier)
        (>= (get qualification-level supplier) minimum-level)
    )
    false
  )
)

;; Get total suppliers count
(define-read-only (get-total-suppliers)
  (var-get total-suppliers)
)

;; Check emergency mode status
(define-read-only (is-emergency-mode)
  (var-get emergency-mode)
)

;; Get contract owner
(define-read-only (get-contract-owner)
  CONTRACT-OWNER
)

;; Private Functions

;; Get last history ID for a supplier (helper function)
(define-private (get-last-history-id (supplier-id uint))
  ;; This is a simplified version - in production, you might want to track this more efficiently
  u0
)

;; Get last performance ID for a supplier (helper function)
(define-private (get-last-performance-id (supplier-id uint))
  ;; This is a simplified version - in production, you might want to track this more efficiently
  u0
)

