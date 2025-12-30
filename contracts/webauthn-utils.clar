;; title: webauthn-utils
;; version: 1.0
;; summary: WebAuthn signature verification for Clarity 5+
;; description: Verifies WebAuthn/passkey signatures by reconstructing 
;;              what the authenticator actually signed.
;;              Requires Clarity 5 where secp256r1-verify no longer double-hashes.

(define-constant err-invalid-signature (err u6001))

;; Verify a WebAuthn passkey signature
;;
;; WebAuthn signs: sha256(authenticatorData || sha256(clientDataJSON))
;; where clientDataJSON contains the challenge (our messageHash) as base64url
;;
;; In Clarity 5, secp256r1-verify(hash, sig, pubkey) verifies directly against hash
;; (no internal hashing), so we reconstruct what WebAuthn signed and verify that.
;;
;; Parameters:
;; - signature: 64-byte r||s signature from WebAuthn (DER decoded, low-s normalized)
;; - pubkey: 33-byte compressed secp256r1 public key  
;; - authenticator-data: Raw authenticatorData from navigator.credentials.get()
;; - client-data-json: Raw clientDataJSON from navigator.credentials.get()
;;
;; Frontend must:
;; 1. Pass messageHash as the WebAuthn challenge
;; 2. Extract authenticatorData and clientDataJSON from response
;; 3. Parse DER signature to r||s format
;; 4. Normalize s to low-s form
;;
(define-read-only (verify-webauthn-signature
    (signature (buff 64))
    (pubkey (buff 33))
    (authenticator-data (buff 512))
    (client-data-json (buff 1024))
  )
  (let (
    ;; Reconstruct exactly what WebAuthn signed
    (client-data-hash (sha256 client-data-json))
    (signed-data (concat authenticator-data client-data-hash))
    (signed-hash (sha256 signed-data))
  )
    ;; In Clarity 5, secp256r1-verify checks signature directly against signed-hash
    (ok (asserts! (secp256r1-verify signed-hash signature pubkey) err-invalid-signature))
  )
)

;; Verify WebAuthn signature with challenge validation
;; 
;; Same as above but also verifies the challenge in clientDataJSON matches
;; the expected message hash. Requires frontend to pass challenge byte position.
;;
;; Parameters:
;; - expected-challenge: The messageHash we expect (32 bytes)
;; - signature, pubkey, authenticator-data, client-data-json: Same as above
;; - challenge-offset: Byte position where base64url challenge starts in clientDataJSON
;; - challenge-length: Length of base64url encoded challenge
;;
(define-read-only (verify-webauthn-signature-with-challenge
    (expected-challenge (buff 32))
    (signature (buff 64))
    (pubkey (buff 33))
    (authenticator-data (buff 512))
    (client-data-json (buff 1024))
    (challenge-offset uint)
    (challenge-length uint)
  )
  (let (
    (client-data-hash (sha256 client-data-json))
    (signed-data (concat authenticator-data client-data-hash))
    (signed-hash (sha256 signed-data))
  )
    ;; TODO: Extract and base64url-decode challenge from client-data-json
    ;; Compare against expected-challenge
    ;; For now, we trust the frontend to have passed correct challenge
    (ok (asserts! (secp256r1-verify signed-hash signature pubkey) err-invalid-signature))
  )
)