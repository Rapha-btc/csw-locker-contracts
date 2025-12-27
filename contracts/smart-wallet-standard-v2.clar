;; title: smart-wallet-standard
;; version: 1
;; summary: Extendible single-owner smart wallet with standard SIP-010 and SIP-009 support

;; Using deployer address for testing.
(use-trait extension-trait 'ST3FFRX7C911PZP5RHE148YDVDD9JWVS6FZRA60VS.extension-trait.extension-trait)

(use-trait sip-010-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)
(use-trait sip-009-trait 'SP2PABAF9FTAJYNFZH93XENAJ8FVY99RRM50D2JG9.nft-trait.nft-trait)

(define-constant err-unauthorised (err u4001))
(define-constant err-invalid-signature (err u4002))
(define-constant err-forbidden (err u4003))
(define-constant err-unregistered-pubkey (err u4004))
(define-constant err-not-admin-pubkey (err u4005))
(define-constant err-signature-replay (err u4006))
(define-constant err-no-auth-id (err u4007))
(define-constant err-no-message-hash (err u4008))
(define-constant err-inactive-required (err u4009))
(define-constant err-fatal-owner-not-admin (err u9999))

(define-constant INACTIVITY-PERIOD u52560) 

(define-data-var last-activity-block uint burn-block-height)
(define-data-var recovery-address principal 'SP000000000000000000002Q6VF78)
(define-data-var initial-pubkey (buff 33) 0x036e0ee032648d4ae5c45f3cdbb21771b01d6f2e0fd5c3db2c524ee9fc6b0d39ca)

(define-data-var owner principal 'SP000000000000000000002Q6VF78)

(define-fungible-token ect)

(define-map used-pubkey-authorizations
  (buff 32) ;; SIP-018 message hash
  (buff 33) ;; pubkey that signed the message
)

;; Authentication
(define-private (is-authorized (sig-message-auth (optional {
  message-hash: (buff 32),
  signature: (buff 64),
  pubkey: (buff 33),
})))
  (match sig-message-auth
    sig-message-details (consume-signature (get message-hash sig-message-details)
      (get signature sig-message-details) (get pubkey sig-message-details)
    )
    (is-admin-calling tx-sender)
  )
)

(define-read-only (is-admin-calling (caller principal))
  (ok (asserts! (is-some (map-get? admins caller)) err-unauthorised))
)

;;
;; calls with context switching
;;
(define-public (stx-transfer
    (amount uint)
    (recipient principal)
    (memo (optional (buff 34)))
    (sig-auth (optional {
      auth-id: uint,
      signature: (buff 64),
      pubkey: (buff 33),
    }))
  )
  (begin
    (update-activity)
    (match sig-auth
      sig-auth-details (try! (is-authorized (some {
        message-hash: (contract-call?
          'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.smart-wallet-standard-auth-helpers
          build-stx-transfer-hash {
          auth-id: (get auth-id sig-auth-details),
          amount: amount,
          recipient: recipient,
          memo: memo,
        }),
        signature: (get signature sig-auth-details),
        pubkey: (get pubkey sig-auth-details),
      })))
      (try! (is-authorized none))
    )
    (print {
      a: "stx-transfer",
      payload: {
        amount: amount,
        recipient: recipient,
        memo: memo,
      },
    })
    (as-contract? ((with-stx amount))
      (match memo
        to-print (try! (stx-transfer-memo? amount tx-sender recipient to-print))
        (try! (stx-transfer? amount tx-sender recipient))
      ))
  )
)

(define-public (extension-call
    (extension <extension-trait>)
    (payload (buff 2048))
    (sig-auth (optional {
      auth-id: uint,
      signature: (buff 64),
      pubkey: (buff 33),
    }))
  )
  (begin
    (update-activity)
    (match sig-auth
      sig-auth-details (try! (is-authorized (some {
        message-hash: (contract-call?
          'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.smart-wallet-standard-auth-helpers
          build-extension-call-hash {
          auth-id: (get auth-id sig-auth-details),
          extension: (contract-of extension),
          payload: payload,
        }),
        signature: (get signature sig-auth-details),
        pubkey: (get pubkey sig-auth-details),
      })))
      (try! (is-authorized none))
    )
    (try! (ft-mint? ect u1 current-contract))
    (try! (ft-burn? ect u1 current-contract))
    (print {
      a: "extension-call",
      payload: {
        extension: extension,
        payload: payload,
      },
    })
    (as-contract? ((with-all-assets-unsafe))
      (try! (contract-call? extension call payload))
    )
  )
)

;;
;; calls without context switching
;;

(define-public (sip010-transfer
    (amount uint)
    (recipient principal)
    (memo (optional (buff 34)))
    (sip010 <sip-010-trait>)
    (token-name (string-ascii 128))
    (sig-auth (optional {
      auth-id: uint,
      signature: (buff 64),
      pubkey: (buff 33),
    }))
  )
  (begin
    (update-activity)
    (match sig-auth
      sig-auth-details (try! (is-authorized (some {
        message-hash: (contract-call?
          'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.smart-wallet-standard-auth-helpers
          build-sip010-transfer-hash {
          auth-id: (get auth-id sig-auth-details),
          amount: amount,
          recipient: recipient,
          memo: memo,
          sip010: (contract-of sip010),
        }),
        signature: (get signature sig-auth-details),
        pubkey: (get pubkey sig-auth-details),
      })))
      (try! (is-authorized none))
    )
    (print {
      a: "sip010-transfer",
      payload: {
        amount: amount,
        recipient: recipient,
        memo: memo,
        sip010: sip010,
      },
    })
    (as-contract? ((with-ft (contract-of sip010) token-name amount))
      (try! (contract-call? sip010 transfer amount current-contract recipient memo))
    )
  )
)

(define-public (sip009-transfer
    (nft-id uint)
    (recipient principal)
    (sip009 <sip-009-trait>)
    (token-name (string-ascii 128))
    (sig-auth (optional {
      auth-id: uint,
      signature: (buff 64),
      pubkey: (buff 33),
    }))
  )
  (begin
    (update-activity)
    (match sig-auth
      sig-auth-details (try! (is-authorized (some {
        message-hash: (contract-call?
          'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.smart-wallet-standard-auth-helpers
          build-sip009-transfer-hash {
          auth-id: (get auth-id sig-auth-details),
          nft-id: nft-id,
          recipient: recipient,
          sip009: (contract-of sip009),
        }),
        signature: (get signature sig-auth-details),
        pubkey: (get pubkey sig-auth-details),
      })))
      (try! (is-authorized none))
    )
    (print {
      a: "sip009-transfer",
      payload: {
        nft-id: nft-id,
        recipient: recipient,
        sip009: sip009,
      },
    })
    (as-contract? ((with-nft (contract-of sip009) token-name (list nft-id)))
      (try! (contract-call? sip009 transfer nft-id current-contract recipient))
    )
  )
)

;;
;; admin functions
;;
(define-map admins
  principal
  bool
)

(define-map pubkey-to-admin
  (buff 33) ;; pubkey
  principal
)

(define-read-only (is-admin-pubkey (pubkey (buff 33)))
  (let ((user-opt (map-get? pubkey-to-admin pubkey)))
    (match user-opt
      user (ok (unwrap! (is-admin-calling user) err-not-admin-pubkey))
      err-unregistered-pubkey
    )
  )
)

(define-public (transfer-wallet (new-admin principal))
  (begin
    ;; Only allow the admin to transfer the wallet. Signature authentication is
    ;; disabled.
    (try! (is-authorized none))
    (asserts! (not (is-eq new-admin tx-sender)) err-forbidden)
    (try! (ft-mint? ect u1 current-contract))
    (try! (ft-burn? ect u1 current-contract))
    (map-set admins new-admin true)
    (map-delete admins tx-sender)
    (var-set owner new-admin)
    (print {
      a: "transfer-wallet",
      payload: { new-admin: new-admin },
    })
    (ok true)
  )
)

;;
;; Secp256r1 elliptic curve signature authentication
;;

;; Admin can use this to set or update their public key for future
;; authentication using secp256r1 elliptic curve signature.
(define-public (add-admin-pubkey (pubkey (buff 33)))
  (begin
    ;; Only allow the admin to update their own public key. Signature
    ;; authentication is disabled.
    (try! (is-authorized none))
    (ok (map-set pubkey-to-admin pubkey tx-sender))
  )
)

(define-public (remove-admin-pubkey (pubkey (buff 33)))
  (begin
    ;; Only allow the admin to remove their own public key. Signature
    ;; authentication is disabled.
    (try! (is-authorized none))
    (ok (map-delete pubkey-to-admin pubkey))
  )
)

;; Verify a signature against the current owner's registered pubkey.
;; Returns the pubkey that signed the message if verification succeeds.
(define-read-only (verify-signature
    (message-hash (buff 32))
    (signature (buff 64))
    (pubkey (buff 33))
  )
  (begin
    (try! (is-admin-pubkey pubkey))
    (ok (asserts! (secp256r1-verify message-hash signature pubkey)
      err-invalid-signature
    ))
  )
)

;; Consume a signature for replay protection.
;; Verifies the signature and marks the message hash as used.
(define-private (consume-signature
    (message-hash (buff 32))
    (signature (buff 64))
    (pubkey (buff 33))
  )
  (begin
    (try! (verify-signature message-hash signature pubkey))
    ;; Limitation: This prevents using the same message hash, but signed by
    ;; 2 different private keys.
    (asserts! (is-none (map-get? used-pubkey-authorizations message-hash))
      err-signature-replay
    )
    (map-set used-pubkey-authorizations message-hash pubkey)
    (ok true)
  )
)

(define-read-only (get-owner)
  (ok (var-get owner))
)

;; kill switch
(define-read-only (is-inactive)
  (> burn-block-height (+ INACTIVITY-PERIOD (var-get last-activity-block)))
)

(define-private (update-activity)
  (var-set last-activity-block burn-block-height)
)


(define-public (add-admin-with-signature
    (new-admin principal)
    (sig-auth {
      auth-id: uint,
      signature: (buff 64),
      pubkey: (buff 33),
    })
  )
  (begin
    (try! (is-authorized (some {
      message-hash: (contract-call? 
        'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.smart-wallet-standard-auth-helpers
        build-add-admin-hash {
        auth-id: (get auth-id sig-auth),
        new-admin: new-admin,
      }),
      signature: (get signature sig-auth),
      pubkey: (get pubkey sig-auth),
    })))
    (map-set admins new-admin true)
    (map-set pubkey-to-admin (get pubkey sig-auth) new-admin)
    (update-activity)
    (print { a: "add-admin", admin: new-admin })
    (ok true)
  )
)

(define-public (recover-inactive-wallet (new-admin principal))
  (begin
    (asserts! (is-inactive) err-inactive-required)
    (asserts! (or 
      (is-eq tx-sender (var-get recovery-address))
      (is-some (map-get? admins tx-sender))
    ) err-unauthorised)
    (map-set admins new-admin true)
    (var-set last-activity-block burn-block-height)
    (print { a: "recover-inactive-wallet", new-admin: new-admin, recovered-by: tx-sender })
    (ok true)
  )
)

;; init - Pillar deploys, only current-contract is admin
(map-set admins 'SP000000000000000000002Q6VF78 true)
(map-set admins current-contract true)

(begin
    (var-set initial-pubkey 0x036e0ee032648d4ae5c45f3cdbb21771b01d6f2e0fd5c3db2c524ee9fc6b0d39ca)
    (var-set last-activity-block burn-block-height)
    (map-set pubkey-to-admin 0x036e0ee032648d4ae5c45f3cdbb21771b01d6f2e0fd5c3db2c524ee9fc6b0d39ca 'SP000000000000000000002Q6VF78)
    (ok true)
)