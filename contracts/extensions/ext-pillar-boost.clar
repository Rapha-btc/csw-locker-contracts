;; title: ext-pillar-boost
;; version: 1.0
;; summary: One-click sBTC leverage via Zest + Bitflow
;; description: Supply sBTC → Borrow aeUSDC → Swap to more sBTC

(impl-trait .extension-trait.extension-trait)

(define-constant err-invalid-payload (err u500))
(define-constant err-invalid-action (err u501))

;; Mainnet contract references
(define-constant SBTC 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token)
(define-constant AEUSDC 'SP3Y2ZSH8P7D50B0VBTSX11S7XSG24M1VB9YFQA4K.token-aeusdc)

;; Bitflow pool references for aeUSDC → STX → sBTC route
(define-constant TOKEN-STX 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.token-stx-v-1-2)
(define-constant POOL-STX-AEUSDC 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.xyk-pool-stx-aeusdc-v-1-2)
(define-constant POOL-SBTC-STX 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.xyk-pool-sbtc-stx-v-1-1)

;; ============================================================================
;; ENTRY POINT
;; ============================================================================

(define-public (call (payload (buff 2048)))
  (let ((details (unwrap! (from-consensus-buff? {
      action: (string-ascii 10),
      sbtc-amount: uint,
      aeusdc-amount: uint,
      min-received: uint
    } payload) err-invalid-payload)))
    
    (if (is-eq (get action details) "boost")
      (boost 
        (get sbtc-amount details) 
        (get aeusdc-amount details) 
        (get min-received details))
      (if (is-eq (get action details) "unwind")
        (unwind 
          (get sbtc-amount details) 
          (get aeusdc-amount details) 
          (get min-received details))
        err-invalid-action
      )
    )
  )
)

;; ============================================================================
;; BOOST: Supply sBTC → Borrow aeUSDC → Swap to sBTC → Supply more
;; ============================================================================

(define-private (boost 
    (sbtc-amount uint) 
    (aeusdc-to-borrow uint) 
    (min-sbtc-from-swap uint))
  (begin
    ;; Step 1: Supply sBTC as collateral to Zest
    (try! (contract-call? 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.borrow-helper-v2-1-7 supply
      SBTC
      sbtc-amount
      tx-sender  ;; owner = the CSW wallet
      tx-sender  ;; on-behalf-of
    ))
    
    ;; Step 2: Borrow aeUSDC against collateral
    (try! (contract-call? 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.borrow-helper-v2-1-7 borrow
      AEUSDC
      aeusdc-to-borrow
      tx-sender  ;; on-behalf-of
      tx-sender  ;; owner
    ))
    
    ;; Step 3: Swap aeUSDC → STX → sBTC via Bitflow
    (let ((sbtc-received (try! (contract-call? 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.xyk-swap-helper-v-1-3 swap-helper-b
        aeusdc-to-borrow
        min-sbtc-from-swap
        none  ;; no aggregator provider
        {
          a: AEUSDC,
          b: TOKEN-STX,
          c: TOKEN-STX,
          d: SBTC
        }
        {
          a: POOL-STX-AEUSDC,
          b: POOL-SBTC-STX
        }
      ))))
      
      ;; Step 4: Supply swapped sBTC as additional collateral
      (try! (contract-call? 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.borrow-helper-v2-1-7 supply
        SBTC
        sbtc-received
        tx-sender
        tx-sender
      ))
      
      (print {
        action: "boost",
        sbtc-deposited: sbtc-amount,
        aeusdc-borrowed: aeusdc-to-borrow,
        sbtc-from-swap: sbtc-received,
        total-collateral: (+ sbtc-amount sbtc-received)
      })
      
      (ok {
        sbtc-deposited: sbtc-amount,
        aeusdc-borrowed: aeusdc-to-borrow,
        sbtc-from-swap: sbtc-received
      })
    )
  )
)

;; ============================================================================
;; UNWIND: Withdraw sBTC → Swap to aeUSDC → Repay debt
;; ============================================================================

(define-private (unwind 
    (sbtc-to-withdraw uint) 
    (aeusdc-to-repay uint) 
    (min-aeusdc-from-swap uint))
  (begin
    ;; Step 1: Withdraw sBTC collateral from Zest
    (try! (contract-call? 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.borrow-helper-v2-1-7 withdraw
      SBTC
      sbtc-to-withdraw
      tx-sender  ;; owner
      tx-sender  ;; on-behalf-of
    ))
    
    ;; Step 2: Swap sBTC → STX → aeUSDC via Bitflow (reverse route)
    (let ((aeusdc-received (try! (contract-call? 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.xyk-swap-helper-v-1-3 swap-helper-b
        sbtc-to-withdraw
        min-aeusdc-from-swap
        none
        {
          a: SBTC,
          b: TOKEN-STX,
          c: TOKEN-STX,
          d: AEUSDC
        }
        {
          a: POOL-SBTC-STX,
          b: POOL-STX-AEUSDC
        }
      ))))
      
      ;; Step 3: Repay aeUSDC debt
      (try! (contract-call? 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.borrow-helper-v2-1-7 repay
        AEUSDC
        aeusdc-to-repay
        tx-sender  ;; on-behalf-of
        tx-sender  ;; owner
      ))
      
      ;; Step 4: If excess aeUSDC, it stays in wallet (user can withdraw separately)
      
      (print {
        action: "unwind",
        sbtc-withdrawn: sbtc-to-withdraw,
        aeusdc-from-swap: aeusdc-received,
        aeusdc-repaid: aeusdc-to-repay
      })
      
      (ok {
        sbtc-withdrawn: sbtc-to-withdraw,
        aeusdc-received: aeusdc-received,
        aeusdc-repaid: aeusdc-to-repay
      })
    )
  )
)