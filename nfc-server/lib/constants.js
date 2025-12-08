/**
 * Constants for NFC Server
 */

// Blockchain Security 2Go Application Identifier (AID)
// From blocksec2go Python library: D2760000041502000100000001 (13 bytes)
// Note: Different from Swift code which uses 15 bytes - Python library is the reference
export const BLOCKCHAIN_AID = Buffer.from([
  0xD2, 0x76, 0x00, 0x00, 0x04, 0x15, 0x02, 0x00,
  0x01, 0x00, 0x00, 0x00, 0x01
]);

// NDEF Application Identifier (AID)
export const NDEF_AID = Buffer.from([0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01]);

// NDEF File Identifier
export const NDEF_FILE_ID = Buffer.from([0xE1, 0x04]);

// Server port
export const PORT = 8080;

// Tag types
export const TAG_ISO_14443_3 = 'TAG_ISO_14443_3';
export const TAG_ISO_14443_4 = 'TAG_ISO_14443_4';

