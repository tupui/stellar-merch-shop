/**
 * useChipAuth Hook
 * Reusable hook for chip signature authentication pattern
 * Used by both mint and transfer operations
 */

import { useNFC } from "./useNFC";
import { hexToBytes, determineRecoveryId } from "../util/crypto";

export interface ChipAuthResult {
  publicKey: string;
  publicKeyBytes: Buffer;
  signature: Buffer;
  recoveryId: number;
}

export const useChipAuth = () => {
  const { readChip, signWithChip, connect, connected } = useNFC();

  const authenticateWithChip = async (
    keyId: number,
    messageHash: Uint8Array | string
  ): Promise<ChipAuthResult> => {
    // Ensure we're connected to NFC server (check actual state and auto-connect)
    // The readChip and signWithChip methods will auto-connect, but we can also connect here
    // to ensure connection is established before starting the auth flow
    if (!connected) {
      await connect();
    }

    // Validate keyId
    if (isNaN(keyId) || keyId < 1 || keyId > 255) {
      throw new Error('Key ID must be between 1 and 255');
    }

    // Convert messageHash to Uint8Array if it's a string
    const messageHashBytes = typeof messageHash === 'string' 
      ? hexToBytes(messageHash) 
      : messageHash;

    // Validate message hash length
    if (messageHashBytes.length !== 32) {
      throw new Error(`Invalid message hash length: expected 32 bytes, got ${messageHashBytes.length} bytes`);
    }

    // 1. Read chip's public key
    const chipPublicKey = await readChip(keyId);

    // 2. NFC chip signs the hash
    const signatureResult = await signWithChip(messageHashBytes, keyId);
    const { signatureBytes } = signatureResult;

    // Validate signature bytes length
    if (signatureBytes.length !== 64) {
      throw new Error(`Invalid signature length: expected 64 bytes, got ${signatureBytes.length} bytes`);
    }

    // 3. Determine recovery ID by trying all 4 possibilities (0-3)
    let recoveryId: number;
    try {
      recoveryId = await determineRecoveryId(messageHashBytes, signatureBytes, chipPublicKey);
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      console.error('Failed to determine recovery ID:', errorMsg);
      console.error('Message hash (hex):', Array.from(messageHashBytes).map(b => b.toString(16).padStart(2, '0')).join(''));
      console.error('Signature (hex, first 32 bytes):', Array.from(signatureBytes.slice(0, 32)).map(b => b.toString(16).padStart(2, '0')).join(''));
      console.error('Public key:', chipPublicKey);
      throw new Error(`Could not determine recovery ID: ${errorMsg}`);
    }

    // Ensure recoveryId is a valid integer between 0 and 3
    if (!Number.isInteger(recoveryId) || recoveryId < 0 || recoveryId > 3) {
      throw new Error(`Invalid recovery ID: ${recoveryId}. Must be an integer between 0 and 3.`);
    }

    // Convert chip's public key (hex string) to bytes for passing to contract
    const chipPublicKeyBytes = hexToBytes(chipPublicKey);

    // Validate public key format (must be 65 bytes, uncompressed, starting with 0x04)
    if (chipPublicKeyBytes.length !== 65) {
      throw new Error(`Invalid public key length: expected 65 bytes (uncompressed), got ${chipPublicKeyBytes.length} bytes`);
    }
    if (chipPublicKeyBytes[0] !== 0x04) {
      throw new Error(`Invalid public key format: expected uncompressed key (starting with 0x04), got 0x${chipPublicKeyBytes[0].toString(16).padStart(2, '0')}`);
    }

    console.log('Chip authentication successful:', {
      recoveryId,
      publicKeyLength: chipPublicKeyBytes.length,
      signatureLength: signatureBytes.length,
      messageHashLength: messageHashBytes.length
    });

    return {
      publicKey: chipPublicKey,
      publicKeyBytes: Buffer.from(chipPublicKeyBytes),
      signature: Buffer.from(signatureBytes),
      recoveryId,
    };
  };

  return { authenticateWithChip };
};
