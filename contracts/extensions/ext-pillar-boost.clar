;; title: ext-pillar-boost
;; version: 1.0
;; summary: One-click sBTC leverage via Zest + Bitflow

(impl-trait .extension-trait.extension-trait)

(define-constant err-invalid-payload (err u500))
(define-constant err-invalid-action (err u501))

;; ============================================================================
;; ENTRY POINT
;; ============================================================================

(define-public (call (payload (buff 2048)))
  (let ((details (unwrap! (from-consensus-buff? {
      action: (string-ascii 10),
      sbtc-amount: uint,
      aeusdc-amount: uint,
      min-received: uint,
      price-feed-bytes: (optional (buff 8192))
    } payload) err-invalid-payload)))
    
    (if (is-eq (get action details) "boost")
      (boost 
        (get sbtc-amount details) 
        (get aeusdc-amount details) 
        (get min-received details)
        (get price-feed-bytes details))
      (if (is-eq (get action details) "unwind")
        (unwind 
          (get sbtc-amount details) 
          (get aeusdc-amount details) 
          (get min-received details)
          (get price-feed-bytes details))
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
    (min-sbtc-from-swap uint)
    (price-feed-bytes (optional (buff 8192))))
  (begin
    ;; Step 1: Supply sBTC as collateral to Zest
    (try! (contract-call? 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.borrow-helper-v2-1-7 supply
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zsbtc-v2-0          ;; lp token
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.pool-0-reserve-v2-0 ;; pool-reserve
      'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token         ;; asset
      sbtc-amount
      tx-sender                                                      ;; owner
      none                                                           ;; referral
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.incentives-v2-1-2   ;; incentives
    ))
    
    ;; Step 2: Borrow aeUSDC against collateral
    (try! (contract-call? 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.borrow-helper-v2-1-7 borrow
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.pool-0-reserve-v2-0 ;; pool-reserve
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.oracle-v2-0         ;; oracle
      'SP3Y2ZSH8P7D50B0VBTSX11S7XSG24M1VB9YFQA4K.token-aeusdc       ;; asset-to-borrow
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zaeusdc-v2-0        ;; lp
      (list)                                                         ;; assets list - needs proper config
      aeusdc-to-borrow
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.fees-calculator-v2-0 ;; fee-calculator
      u2                                                             ;; interest-rate-mode (variable)
      tx-sender                                                      ;; owner
      price-feed-bytes
    ))
    
    ;; Step 3: Swap aeUSDC → STX → sBTC via Bitflow
    (let ((sbtc-received (try! (contract-call? 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.xyk-swap-helper-v-1-3 swap-helper-b
        aeusdc-to-borrow
        min-sbtc-from-swap
        none
        {
          a: 'SP3Y2ZSH8P7D50B0VBTSX11S7XSG24M1VB9YFQA4K.token-aeusdc,
          b: 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.token-stx-v-1-2,
          c: 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.token-stx-v-1-2,
          d: 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token
        }
        {
          a: 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.xyk-pool-stx-aeusdc-v-1-2,
          b: 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.xyk-pool-sbtc-stx-v-1-1
        }
      ))))
      
      ;; Step 4: Supply swapped sBTC as additional collateral
      (try! (contract-call? 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.borrow-helper-v2-1-7 supply
        'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zsbtc-v2-0
        'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.pool-0-reserve-v2-0
        'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token
        sbtc-received
        tx-sender
        none
        'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.incentives-v2-1-2
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
    (min-aeusdc-from-swap uint)
    (price-feed-bytes (optional (buff 8192))))
  (begin
    ;; Step 1: Withdraw sBTC collateral from Zest
    (try! (contract-call? 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.borrow-helper-v2-1-7 withdraw
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zsbtc-v2-0
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.pool-0-reserve-v2-0
      'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.oracle-v2-0
      sbtc-to-withdraw
      tx-sender
      (list)  ;; assets list - needs proper config
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.incentives-v2-1-2
      price-feed-bytes
    ))
    
    ;; Step 2: Swap sBTC → STX → aeUSDC via Bitflow (reverse route)
    (let ((aeusdc-received (try! (contract-call? 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.xyk-swap-helper-v-1-3 swap-helper-b
        sbtc-to-withdraw
        min-aeusdc-from-swap
        none
        {
          a: 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token,
          b: 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.token-stx-v-1-2,
          c: 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.token-stx-v-1-2,
          d: 'SP3Y2ZSH8P7D50B0VBTSX11S7XSG24M1VB9YFQA4K.token-aeusdc
        }
        {
          a: 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.xyk-pool-sbtc-stx-v-1-1,
          b: 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.xyk-pool-stx-aeusdc-v-1-2
        }
      ))))
      
      ;; Step 3: Repay aeUSDC debt
      (try! (contract-call? 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.borrow-helper-v2-1-7 repay
        'SP3Y2ZSH8P7D50B0VBTSX11S7XSG24M1VB9YFQA4K.token-aeusdc
        aeusdc-to-repay
        tx-sender  ;; on-behalf-of
        tx-sender  ;; payer
      ))
      
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