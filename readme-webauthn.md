# WebAuthn Passkey Support for Smart Wallet Standard

## Overview

The Smart Wallet Standard supports signature-based authentication using secp256r1 (P-256) keys. This document explains the challenges with WebAuthn passkey integration and available solutions.

## The Problem

WebAuthn passkeys (Face ID, Touch ID, Windows Hello) use secp256r1 keys, which seems like a perfect match. However, there are two issues:

### Issue 1: WebAuthn Signature Wrapper

When you sign with a passkey, the browser doesn't sign your data directly. Instead it signs:

```
sha256(authenticatorData || sha256(clientDataJSON))
```

Where `clientDataJSON` contains your challenge (the message hash) plus metadata like the website origin.

This wrapper is a security feature - it proves which website requested the signature and prevents replay attacks across sites.

### Issue 2: secp256r1-verify Double-Hash Bug

The current Clarity implementation of `secp256r1-verify` has a bug where it hashes the input internally before verifying:

```
secp256r1-verify(messageHash, signature, pubkey)
  → actually verifies against sha256(messageHash)
```

This bug is being fixed in Clarity 5 (see [PR #6763](https://github.com/stacks-network/stacks-core/pull/6763)).

### Why These Issues Conflict

For WebAuthn to work, the contract needs to verify against what WebAuthn actually signed. But:

1. WebAuthn signs: `sha256(authenticatorData || sha256(clientDataJSON))`
2. We'd need to pass `authenticatorData || sha256(clientDataJSON)` to the contract
3. But `secp256r1-verify` expects a 32-byte hash, not variable-length data
4. And even if we pre-hash it, the double-hash bug means it gets hashed again

The math simply doesn't work out with the current implementation.

## Solutions

### Solution 1: Wait for Clarity 5 (Recommended for Native Passkeys)

When Clarity 5 ships, `secp256r1-verify` will verify directly without internal hashing. Then:

1. Frontend captures `authenticatorData` and `clientDataJSON` from WebAuthn
2. Contract reconstructs: `sha256(authenticatorData || sha256(clientDataJSON))`
3. Contract verifies signature against that hash
4. ✅ Works!

See `webauthn-utils.clar` for the Clarity 5 implementation.

### Solution 2: Use Turnkey (Available Now)

[Turnkey](https://turnkey.com) provides secure key infrastructure:

1. User authenticates with their passkey (Face ID, etc.) to Turnkey
2. Turnkey holds a separate signing key in their secure enclave
3. Turnkey signs the raw message hash - no WebAuthn wrapper
4. Contract verifies normally

**Tradeoff**: Keys are custodied by Turnkey (though in secure hardware). Users authenticate with passkeys but don't directly sign with them.

### Solution 3: Use secp256k1 with Turnkey (Available Now, Simpler)

Instead of secp256r1, use the standard Bitcoin curve:

1. Change contract to use `secp256k1-verify` instead of `secp256r1-verify`
2. Turnkey holds secp256k1 keys (same curve as Bitcoin/Stacks)
3. No double-hash bug issues
4. Well-tested, battle-proven curve

## Comparison

| Approach                    | Available       | Self-Custody       | Cross-Platform         | Implementation      |
| --------------------------- | --------------- | ------------------ | ---------------------- | ------------------- |
| Native WebAuthn (Clarity 5) | After hard-fork | ✅ Full            | Via iCloud/Google sync | webauthn-utils.clar |
| Turnkey + secp256r1         | Now             | ❌ Turnkey custody | ✅ Any device          | Moderate changes    |
| Turnkey + secp256k1         | Now             | ❌ Turnkey custody | ✅ Any device          | Minimal changes     |

## File Structure

```
contracts/
├── webauthn-utils.clar              # Clarity 5 WebAuthn verification
├── smart-wallet-v1.clar             # Turnkey version (secp256k1)
├── smart-wallet.clar                # Original (secp256r1, needs Clarity 5 for WebAuthn)
└── smart-wallet-standard-auth-helpers.clar
```

## Testing

For local testing without real passkeys, you can generate secp256r1 keypairs in Node.js:

```typescript
import { generateKeyPairSync, sign } from "crypto";

const { publicKey, privateKey } = generateKeyPairSync("ec", {
  namedCurve: "prime256v1", // secp256r1
});

const signature = sign(null, messageHash, {
  key: privateKey,
  dsaEncoding: "ieee-p1363", // 64-byte r||s format
});
```

This is how the test suite works - it generates ephemeral keys for testing, not real passkeys.

```

---

**3. Message for Brice and Friedger**
```

We've been working on WebAuthn passkey integration for the Smart Wallet Standard and hit a wall with the secp256r1-verify double-hash bug.

WebAuthn signs `sha256(authenticatorData || sha256(clientDataJSON))` but we can't reconstruct this for verification because (1) secp256r1-verify expects 32 bytes and (2) it hashes again internally. The math doesn't work out until Clarity 5 lands with the fix from PR #6763.

For now we're exploring Turnkey as a bridge solution - users auth with passkeys, Turnkey holds the signing key. Would love to sync on timeline for Clarity 5 and whether there's any workaround we're missing.
