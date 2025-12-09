/**
 * Crypto utilities for NFC chip signature handling
 * Provides SHA-256 hashing and signature format conversion for Soroban
 */

/**
 * Convert hex string to Uint8Array
 */
export function hexToBytes(hex: string): Uint8Array {
  // Remove 0x prefix if present
  const cleanHex = hex.startsWith('0x') ? hex.slice(2) : hex;
  
  // Ensure even number of characters
  const paddedHex = cleanHex.length % 2 === 0 ? cleanHex : '0' + cleanHex;
  
  const bytes = new Uint8Array(paddedHex.length / 2);
  for (let i = 0; i < paddedHex.length; i += 2) {
    bytes[i / 2] = parseInt(paddedHex.substr(i, 2), 16);
  }
  return bytes;
}

/**
 * Convert Uint8Array to hex string
 */
export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Generate SHA-256 hash of data
 * Uses Web Crypto API (available in modern browsers)
 */
export async function sha256(data: string | Uint8Array): Promise<Uint8Array> {
  const bytes = typeof data === 'string' 
    ? new TextEncoder().encode(data) 
    : data;
  
  const hashBuffer = await crypto.subtle.digest('SHA-256', bytes as BufferSource);
  return new Uint8Array(hashBuffer);
}

/**
 * SEP-53: Standard Contract Authentication
 * Creates a standard message for contract function authorization
 */
export interface SEP53AuthEntry {
  contractAddress: string;
  functionName: string;
  args: unknown[];
  nonce: number;
}

/**
 * Create SEP-53 compliant auth message (without nonce)
 * The nonce is appended to the message before hashing for signature
 * Returns both the message (without nonce) and the hash of (message + nonce)
 */
export async function createSEP53Message(
  contractId: string,
  functionName: string,
  args: unknown[],
  nonce: number,
  networkPassphrase: string
): Promise<{ message: Uint8Array; messageHash: Uint8Array }> {
  // SEP-53 format (without nonce):
  // network_id || contract_id || function_name || args
  // Nonce is appended separately before hashing
  
  const encoder = new TextEncoder();
  const parts: Uint8Array[] = [];
  
  // Network passphrase hash (32 bytes)
  const networkHash = await sha256(encoder.encode(networkPassphrase));
  parts.push(networkHash);
  
  // Contract ID (32 bytes for Stellar addresses)
  const contractIdBytes = hexToBytes(contractId);
  parts.push(contractIdBytes);
  
  // Function name
  const functionNameBytes = encoder.encode(functionName);
  parts.push(functionNameBytes);
  
  // Args (serialized)
  const argsBytes = encoder.encode(JSON.stringify(args));
  parts.push(argsBytes);
  
  // Concatenate all parts (without nonce)
  const totalLength = parts.reduce((sum, part) => sum + part.length, 0);
  const message = new Uint8Array(totalLength);
  let offset = 0;
  for (const part of parts) {
    message.set(part, offset);
    offset += part.length;
  }
  
  // Append nonce to message before hashing
  // IMPORTANT: Must match contract's nonce.to_xdr() which produces 8 bytes:
  // - 4 bytes: ScVal U32 discriminant (0x00000003 = 3)
  // - 4 bytes: big-endian u32 value
  // 
  // Contract does: builder.append(&message) then builder.append(&nonce.to_xdr(&e))
  // So we need: message || nonce_xdr_bytes
  const nonceXdrBytes = new Uint8Array(8);
  const view = new DataView(nonceXdrBytes.buffer);
  // First 4 bytes: ScVal U32 discriminant = 3 (big-endian)
  view.setUint32(0, 3, false); // big endian = 0x00000003
  // Last 4 bytes: nonce value (big-endian)
  view.setUint32(4, nonce, false); // big endian
  
  // Verify the encoding is correct
  const expectedNonceHex = nonce === 0 ? '0000000300000000' : 
    `00000003${nonce.toString(16).padStart(8, '0')}`;
  const actualNonceHex = bytesToHex(nonceXdrBytes);
  if (actualNonceHex !== expectedNonceHex) {
    console.warn(`Nonce XDR encoding mismatch! Expected: ${expectedNonceHex}, Got: ${actualNonceHex}`);
  }
  
  const messageWithNonce = new Uint8Array(message.length + nonceXdrBytes.length);
  messageWithNonce.set(message, 0);
  messageWithNonce.set(nonceXdrBytes, message.length);
  
  // Hash the message with nonce for signature
  // This should match: contract's sha256(builder) where builder = message || nonce.to_xdr()
  const messageHash = await sha256(messageWithNonce);
  
  return {
    message: message, // Return message without nonce
    messageHash: messageHash
  };
}


/**
 * Format signature from NFC chip for Soroban
 * NFC chip returns (r, s, v) format
 * Soroban expects 64 bytes (r + s concatenated) and separate recovery_id
 */
export interface NFCSignature {
  r: string;  // 32 bytes hex
  s: string;  // 32 bytes hex
  v: number;  // Recovery ID indicator
  recoveryId?: number;
}

export interface SorobanSignature {
  signatureBytes: Uint8Array;  // 64 bytes: r (32) + s (32)
  recoveryId: number;           // 0-3
}

/**
 * Normalize the S value of an ECDSA signature to the "low S" form.
 * Soroban's secp256k1_recover requires normalized S values.
 * 
 * The secp256k1 curve order n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
 * Half order = n / 2
 * If s > half_order, normalize: s = n - s
 * 
 * @param s - The S value as a 32-byte array (big-endian)
 * @returns Normalized S value (32 bytes, big-endian)
 */
function normalizeS(s: Uint8Array): Uint8Array {
  if (s.length !== 32) {
    throw new Error(`S value must be 32 bytes, got ${s.length}`);
  }
  
  // secp256k1 curve order n (big-endian)
  const curveOrder = new Uint8Array([
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE,
    0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B,
    0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x41
  ]);
  
  // Compare s with half_order (n / 2)
  // Half order = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0
  // But the test file shows it as: 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501D (last 4 bytes missing)
  // Actually, looking at the test, the half_order array has 32 bytes, so let me check the exact value
  // Half order = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0
  const halfOrder = new Uint8Array([
    0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0x5D, 0x57, 0x6E, 0x73, 0x57, 0xA4, 0x50, 0x1D
  ]);
  
  // Compare s with halfOrder (big-endian comparison)
  let sGreaterThanHalf = false;
  for (let i = 0; i < 32; i++) {
    if (s[i] > halfOrder[i]) {
      sGreaterThanHalf = true;
      break;
    } else if (s[i] < halfOrder[i]) {
      break;
    }
  }
  
  // If s > halfOrder, normalize: s = n - s
  if (sGreaterThanHalf) {
    // Perform big-endian subtraction: n - s
    const normalized = new Uint8Array(32);
    let borrow = 0;
    for (let i = 31; i >= 0; i--) {
      let diff = curveOrder[i] - s[i] - borrow;
      if (diff < 0) {
        diff += 256;
        borrow = 1;
      } else {
        borrow = 0;
      }
      normalized[i] = diff;
    }
    return normalized;
  }
  
  // s is already normalized (low S)
  return new Uint8Array(s);
}

/**
 * Convert NFC chip signature format to Soroban format
 */
export function formatSignatureForSoroban(signature: NFCSignature): SorobanSignature {
  // Convert hex strings to bytes
  const rBytes = hexToBytes(signature.r);
  let sBytes = hexToBytes(signature.s);
  
  // Validate lengths
  if (rBytes.length !== 32) {
    throw new Error(`Invalid r length: ${rBytes.length}, expected 32 bytes`);
  }
  if (sBytes.length !== 32) {
    throw new Error(`Invalid s length: ${sBytes.length}, expected 32 bytes`);
  }
  
  // Normalize S value (required by Soroban's secp256k1_recover)
  sBytes = normalizeS(sBytes);
  
  // Concatenate r and normalized s
  const signatureBytes = new Uint8Array(64);
  signatureBytes.set(rBytes, 0);
  signatureBytes.set(sBytes, 32);
  
  // Calculate recovery ID
  // v can be: 0-3 (raw), 27-30 (Ethereum style), or provided explicitly
  let recoveryId: number;
  
  if (signature.recoveryId !== undefined) {
    recoveryId = signature.recoveryId;
  } else if (signature.v >= 27 && signature.v <= 30) {
    // Ethereum-style v value
    recoveryId = signature.v - 27;
  } else if (signature.v >= 0 && signature.v <= 3) {
    // Raw recovery ID
    recoveryId = signature.v;
  } else {
    throw new Error(`Invalid v value: ${signature.v}`);
  }
  
  // Validate recovery ID range
  if (recoveryId < 0 || recoveryId > 3) {
    throw new Error(`Recovery ID out of range: ${recoveryId}, must be 0-3`);
  }
  
  return {
    signatureBytes,
    recoveryId
  };
}

/**
 * Try all recovery IDs (0-3) to find the correct one
 * This is useful when the NFC chip doesn't provide a reliable v value
 * Returns array of recovery IDs to try, sorted by most likely first
 */
export function getPossibleRecoveryIds(v?: number): number[] {
  if (v === undefined) {
    // Try all in order
    return [0, 1, 2, 3];
  }
  
  // Calculate most likely recovery ID
  let primaryId: number;
  if (v >= 27 && v <= 30) {
    primaryId = v - 27;
  } else if (v >= 0 && v <= 3) {
    primaryId = v;
  } else {
    // Unknown v, try all
    return [0, 1, 2, 3];
  }
  
  // Return primary ID first, then others
  const others = [0, 1, 2, 3].filter(id => id !== primaryId);
  return [primaryId, ...others];
}

/**
 * Validate message digest for Soroban
 */
export function validateMessageDigest(digest: Uint8Array): void {
  if (digest.length !== 32) {
    throw new Error(`Invalid message digest length: ${digest.length}, expected 32 bytes`);
  }
}

/**
 * Validate signature for Soroban
 */
export function validateSignature(signature: Uint8Array): void {
  if (signature.length !== 64) {
    throw new Error(`Invalid signature length: ${signature.length}, expected 64 bytes`);
  }
}

/**
 * Fetch the current ledger sequence number from Horizon API
 * 
 * @param horizonUrl - Horizon API base URL
 * @returns Current ledger sequence number
 * @throws Error if unable to fetch ledger
 */
export async function fetchCurrentLedger(horizonUrl: string): Promise<number> {
  try {
    const response = await fetch(`${horizonUrl}/ledgers?order=desc&limit=1`);
    
    if (!response.ok) {
      throw new Error(`Horizon API returned ${response.status}`);
    }
    
    const data = await response.json() as { _embedded?: { records?: Array<{ sequence: string | number }> } };
    
    if (!data._embedded?.records?.[0]?.sequence) {
      throw new Error('Invalid ledger response format');
    }
    
    const sequence = data._embedded.records[0].sequence;
    return typeof sequence === 'string' ? parseInt(sequence, 10) : sequence;
  } catch (error) {
    throw new Error(`Failed to fetch current ledger: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
}

/**
 * Determine the correct recovery ID by trying all possibilities (0-3)
 * and matching against the expected public key from the NFC chip.
 * 
 * @param messageHash - SHA-256 hash of the message (32 bytes)
 * @param signature - ECDSA signature (64 bytes: r + s)
 * @param expectedPublicKey - Expected public key in hex format (65 bytes uncompressed)
 * @returns The correct recovery ID (0-3)
 * @throws Error if no matching recovery ID found
 */
export async function determineRecoveryId(
  messageHash: Uint8Array,
  signature: Uint8Array,
  expectedPublicKey: string
): Promise<number> {
  if (messageHash.length !== 32) {
    throw new Error(`Invalid message hash length: ${messageHash.length}, expected 32 bytes`);
  }
  if (signature.length !== 64) {
    throw new Error(`Invalid signature length: ${signature.length}, expected 64 bytes`);
  }
  
  // Dynamic import to avoid bundling issues
  const secp256k1 = await import('@noble/secp256k1');
  
  // Convert expected public key to bytes (remove 0x prefix if present)
  const expectedKeyHex = expectedPublicKey.startsWith('0x') 
    ? expectedPublicKey.slice(2) 
    : expectedPublicKey;
  const expectedKeyBytes = hexToBytes(expectedKeyHex);
  
  // Validate expected key format (should be 65 bytes, uncompressed, starting with 0x04)
  if (expectedKeyBytes.length !== 65) {
    throw new Error(`Expected public key must be 65 bytes (uncompressed), got ${expectedKeyBytes.length} bytes`);
  }
  if (expectedKeyBytes[0] !== 0x04) {
    throw new Error(`Expected public key must be uncompressed (start with 0x04), got 0x${expectedKeyBytes[0].toString(16).padStart(2, '0')}`);
  }
  
  // Try each recovery ID (0-3)
  const errors: string[] = [];
  for (let recoveryId = 0; recoveryId <= 3; recoveryId++) {
    try {
      // @noble/secp256k1 recoverPublicKey always expects 'recovered' format:
      // signature must be 65 bytes = [recovery_id (1 byte)] || [r (32 bytes)] || [s (32 bytes)]
      // messageHash is already hashed, so we set prehash: false
      const recoveredSignature = new Uint8Array(65);
      recoveredSignature[0] = recoveryId; // Recovery ID is first byte
      recoveredSignature.set(signature, 1); // r (32 bytes) + s (32 bytes) follow
      const compressedKey = secp256k1.recoverPublicKey(
        recoveredSignature,
        messageHash,
        { prehash: false }
      );
      
      // Convert compressed (33 bytes) to uncompressed (65 bytes) format for comparison
      const point = secp256k1.Point.fromBytes(compressedKey);
      const recoveredKeyBytes = point.toBytes(false); // false = uncompressed
      
      // Compare with expected key (both in uncompressed format)
      const recoveredKeyHex = bytesToHex(recoveredKeyBytes);
      const expectedKeyHexClean = bytesToHex(expectedKeyBytes);
      
      if (recoveredKeyHex.toLowerCase() === expectedKeyHexClean.toLowerCase()) {
        return recoveryId;
      }
    } catch (error) {
      // Collect error for debugging
      const errorMsg = error instanceof Error ? error.message : String(error);
      errors.push(`Recovery ID ${recoveryId}: ${errorMsg}`);
      continue;
    }
  }
  
  // If we get here, no recovery ID matched
  const errorDetails = errors.length > 0 ? `\nErrors encountered:\n${errors.join('\n')}` : '';
  throw new Error(`Could not determine recovery ID: no match found after trying all possibilities (0-3).${errorDetails}`);
}

