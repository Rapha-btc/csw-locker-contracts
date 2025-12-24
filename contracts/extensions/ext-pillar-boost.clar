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
      sbtc-amount-2: uint,
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
          (get sbtc-amount-2 details)
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
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zsbtc-v2-0
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.pool-0-reserve-v2-0
      'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token
      sbtc-amount
      tx-sender
      none
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.incentives-v2-2
    ))
    
    ;; Step 2: Borrow aeUSDC against collateral
    (try! (contract-call? 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.borrow-helper-v2-1-7 borrow
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.pool-0-reserve-v2-0
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.aeusdc-oracle-v1-0
      'SP3Y2ZSH8P7D50B0VBTSX11S7XSG24M1VB9YFQA4K.token-aeusdc
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zaeusdc-v2-0
      (list
        { asset: 'SP4SZE494VC2YC5JYG7AYFQ44F5Q4PYV7DVMDPBG.ststx-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zststx-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.stx-btc-oracle-v1-4 }
        { asset: 'SP3Y2ZSH8P7D50B0VBTSX11S7XSG24M1VB9YFQA4K.token-aeusdc, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zaeusdc-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.aeusdc-oracle-v1-0 }
        { asset: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.wstx, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zwstx-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.stx-btc-oracle-v1-4 }
        { asset: 'SP2C2YFP12AJZB4MABJBAJ55XECVS7E4PMMZ89YZR.arkadiko-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zdiko-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.diko-oracle-v1-1 }
        { asset: 'SPN5AKG35QZSK2M8GAMR4AFX45659RJHDW353HSG.usdh-token-v1, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zusdh-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.usdh-oracle-v1-0 }
        { asset: 'SP2XD7417HGPRTREMKF748VNEQPDRR0RMANB7X1NK.token-susdt, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zsusdt-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.susdt-oracle-v1-0 }
        { asset: 'SP2C2YFP12AJZB4MABJBAJ55XECVS7E4PMMZ89YZR.usda-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zusda-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.usda-oracle-v1-1 }
        { asset: 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zsbtc-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.stx-btc-oracle-v1-4 }
        { asset: 'SP102V8P0F7JX67ARQ77WEA3D3CFB5XW39REDT0AM.token-alex, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zalex-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.alex-oracle-v1-1 }
        { asset: 'SP4SZE494VC2YC5JYG7AYFQ44F5Q4PYV7DVMDPBG.ststxbtc-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zststxbtc-v2_v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.stx-btc-oracle-v1-4 }
      )
      aeusdc-to-borrow
      'SP3Y2ZSH8P7D50B0VBTSX11S7XSG24M1VB9YFQA4K.fees-calculator
      u0
      tx-sender
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
        'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.incentives-v2-2
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
;; UNWIND: Withdraw sBTC → Swap to aeUSDC → Repay → Withdraw remaining
;; ============================================================================

(define-private (unwind 
    (sbtc-to-withdraw-for-swap uint)
    (sbtc-to-withdraw-final uint)
    (aeusdc-to-repay uint) 
    (min-aeusdc-from-swap uint)
    (price-feed-bytes (optional (buff 8192))))
  (begin
    ;; Step 1: Withdraw some sBTC from Zest (to swap for repayment)
    (try! (contract-call? 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.borrow-helper-v2-1-7 withdraw
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zsbtc-v2-0
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.pool-0-reserve-v2-0
      'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.stx-btc-oracle-v1-4
      sbtc-to-withdraw-for-swap
      tx-sender
      (list
        { asset: 'SP4SZE494VC2YC5JYG7AYFQ44F5Q4PYV7DVMDPBG.ststx-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zststx-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.stx-btc-oracle-v1-4 }
        { asset: 'SP3Y2ZSH8P7D50B0VBTSX11S7XSG24M1VB9YFQA4K.token-aeusdc, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zaeusdc-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.aeusdc-oracle-v1-0 }
        { asset: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.wstx, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zwstx-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.stx-btc-oracle-v1-4 }
        { asset: 'SP2C2YFP12AJZB4MABJBAJ55XECVS7E4PMMZ89YZR.arkadiko-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zdiko-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.diko-oracle-v1-1 }
        { asset: 'SPN5AKG35QZSK2M8GAMR4AFX45659RJHDW353HSG.usdh-token-v1, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zusdh-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.usdh-oracle-v1-0 }
        { asset: 'SP2XD7417HGPRTREMKF748VNEQPDRR0RMANB7X1NK.token-susdt, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zsusdt-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.susdt-oracle-v1-0 }
        { asset: 'SP2C2YFP12AJZB4MABJBAJ55XECVS7E4PMMZ89YZR.usda-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zusda-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.usda-oracle-v1-1 }
        { asset: 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zsbtc-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.stx-btc-oracle-v1-4 }
        { asset: 'SP102V8P0F7JX67ARQ77WEA3D3CFB5XW39REDT0AM.token-alex, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zalex-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.alex-oracle-v1-1 }
        { asset: 'SP4SZE494VC2YC5JYG7AYFQ44F5Q4PYV7DVMDPBG.ststxbtc-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zststxbtc-v2_v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.stx-btc-oracle-v1-4 }
      )
      'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.incentives-v2-2
      price-feed-bytes
    ))
    
    ;; Step 2: Swap sBTC → STX → aeUSDC via Bitflow
    (let ((aeusdc-received (try! (contract-call? 'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.xyk-swap-helper-v-1-3 swap-helper-b
        sbtc-to-withdraw-for-swap
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
        tx-sender
        tx-sender
      ))
      
      ;; Step 4: Withdraw remaining sBTC (debt is now repaid)
      (try! (contract-call? 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.borrow-helper-v2-1-7 withdraw
        'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zsbtc-v2-0
        'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.pool-0-reserve-v2-0
        'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token
        'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.stx-btc-oracle-v1-4
        sbtc-to-withdraw-final
        tx-sender
        (list
          { asset: 'SP4SZE494VC2YC5JYG7AYFQ44F5Q4PYV7DVMDPBG.ststx-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zststx-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.stx-btc-oracle-v1-4 }
          { asset: 'SP3Y2ZSH8P7D50B0VBTSX11S7XSG24M1VB9YFQA4K.token-aeusdc, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zaeusdc-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.aeusdc-oracle-v1-0 }
          { asset: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.wstx, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zwstx-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.stx-btc-oracle-v1-4 }
          { asset: 'SP2C2YFP12AJZB4MABJBAJ55XECVS7E4PMMZ89YZR.arkadiko-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zdiko-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.diko-oracle-v1-1 }
          { asset: 'SPN5AKG35QZSK2M8GAMR4AFX45659RJHDW353HSG.usdh-token-v1, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zusdh-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.usdh-oracle-v1-0 }
          { asset: 'SP2XD7417HGPRTREMKF748VNEQPDRR0RMANB7X1NK.token-susdt, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zsusdt-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.susdt-oracle-v1-0 }
          { asset: 'SP2C2YFP12AJZB4MABJBAJ55XECVS7E4PMMZ89YZR.usda-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zusda-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.usda-oracle-v1-1 }
          { asset: 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zsbtc-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.stx-btc-oracle-v1-4 }
          { asset: 'SP102V8P0F7JX67ARQ77WEA3D3CFB5XW39REDT0AM.token-alex, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zalex-v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.alex-oracle-v1-1 }
          { asset: 'SP4SZE494VC2YC5JYG7AYFQ44F5Q4PYV7DVMDPBG.ststxbtc-token, lp-token: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.zststxbtc-v2_v2-0, oracle: 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.stx-btc-oracle-v1-4 }
        )
        'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.incentives-v2-2
        price-feed-bytes
      ))
      
      (print {
        action: "unwind",
        sbtc-withdrawn-for-swap: sbtc-to-withdraw-for-swap,
        aeusdc-from-swap: aeusdc-received,
        aeusdc-repaid: aeusdc-to-repay,
        sbtc-withdrawn-final: sbtc-to-withdraw-final
      })
      
      (ok {
        sbtc-withdrawn-for-swap: sbtc-to-withdraw-for-swap,
        aeusdc-received: aeusdc-received,
        aeusdc-repaid: aeusdc-to-repay,
        sbtc-withdrawn-final: sbtc-to-withdraw-final
      })
    )
  )
)