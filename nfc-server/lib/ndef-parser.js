/**
 * NDEF parsing utilities
 */

/**
 * Parse NDEF URL from raw data
 * Handles both TLV-wrapped (Type 2 tags) and raw NDEF (Type 4 tags) formats
 * @param {Buffer} data - Raw NDEF data
 * @returns {string|null} - Parsed URL or null if not a URL record
 */
export function parseNDEFUrl(data) {
  try {
    if (!data || data.length === 0) {
      return null;
    }
    
    let ndefData = data;
    
    // Check if it's wrapped in TLV (starts with 0x03) - Type 2 tags or Type 4 tags with TLV
    if (data[0] === 0x03) {
      let tlvLength = data[1];
      // Handle extended length (if length byte is 0xFF, next 2 bytes are length)
      let tlvDataOffset = 2;
      if (tlvLength === 0xFF) {
        tlvLength = (data[2] << 8) | data[3];
        tlvDataOffset = 4;
      }
      if (tlvLength === 0) return null; // Empty NDEF message
      if (tlvLength > data.length - tlvDataOffset) {
        console.log(`parseNDEFUrl: TLV length (${tlvLength}) exceeds available data (${data.length - tlvDataOffset})`);
        return null;
      }
      ndefData = data.slice(tlvDataOffset, tlvDataOffset + tlvLength);
      console.log(`parseNDEFUrl: Unwrapped TLV, TLV length: ${tlvLength}, NDEF data length: ${ndefData.length}`);
    }
    // Otherwise, assume it's a raw NDEF record (from APDU) - starts with flags byte
    
    // Parse NDEF record
    if (ndefData.length < 5) {
      console.log(`parseNDEFUrl: NDEF data too short: ${ndefData.length} bytes`);
      return null;
    }
    
    console.log(`parseNDEFUrl: Parsing NDEF record (${ndefData.length} bytes), first 20 bytes: ${ndefData.slice(0, 20).toString('hex')}`);
    const recordHeader = ndefData[0];
    const typeLength = ndefData[1];
    console.log(`parseNDEFUrl: Record header: 0x${recordHeader.toString(16)}, typeLength: ${typeLength}`);
    const hasIdLength = (recordHeader & 0x08) !== 0; // IL flag (bit 3)
    console.log(`parseNDEFUrl: IL flag: ${hasIdLength}, SR flag: ${(recordHeader & 0x10) !== 0}`);
    
    // Payload length can be 1 byte (short record, SR=1) or 3 bytes (long record, SR=0)
    let payloadLength;
    let idLength = 0;
    let typeOffset;
    
    if (recordHeader & 0x10) {
      // Short record (SR=1): 1-byte payload length
      payloadLength = ndefData[2];
      typeOffset = 3;
      console.log(`parseNDEFUrl: Short record (SR=1), payloadLength: ${payloadLength}, initial typeOffset: ${typeOffset}`);
      
      // If IL flag is set, there's an ID length byte
      if (hasIdLength) {
        idLength = ndefData[3];
        typeOffset = 4;
        console.log(`parseNDEFUrl: IL flag set, idLength: ${idLength}, typeOffset: ${typeOffset}`);
      } else {
        // Backward compatibility: Check if there's an ID length byte even when IL=0
        // Some old records might have been written with ID length byte
        // If type byte at offset 3 is 0x00 and next byte is 0x55, assume ID length byte exists
        if (ndefData.length > 4 && ndefData[3] === 0x00 && ndefData[4] === 0x55) {
          console.log(`parseNDEFUrl: Detected ID length byte (0x00) even though IL=0, skipping it`);
          idLength = 0;
          typeOffset = 4; // Skip the 0x00 byte
        }
      }
    } else {
      // Long record (SR=0): 3-byte payload length
      payloadLength = (ndefData[2] << 16) | (ndefData[3] << 8) | ndefData[4];
      typeOffset = 5;
      console.log(`parseNDEFUrl: Long record (SR=0), payloadLength: ${payloadLength}, initial typeOffset: ${typeOffset}`);
      
      // If IL flag is set, there's an ID length byte
      if (hasIdLength) {
        idLength = ndefData[5];
        typeOffset = 6;
        console.log(`parseNDEFUrl: IL flag set, idLength: ${idLength}, typeOffset: ${typeOffset}`);
      } else {
        // Backward compatibility: Check if there's an ID length byte even when IL=0
        if (ndefData.length > 6 && ndefData[5] === 0x00 && ndefData[6] === 0x55) {
          console.log(`parseNDEFUrl: Detected ID length byte (0x00) even though IL=0, skipping it`);
          idLength = 0;
          typeOffset = 6; // Skip the 0x00 byte
        }
      }
    }
    
    if (typeLength !== 1) {
      console.log(`parseNDEFUrl: Not a URL record (typeLength=${typeLength})`);
      return null; // Not a URL record
    }
    
    console.log(`parseNDEFUrl: Calculated typeOffset: ${typeOffset}, payloadLength: ${payloadLength}, idLength: ${idLength}`);
    const type = ndefData[typeOffset];
    console.log(`parseNDEFUrl: Type byte at offset ${typeOffset}: 0x${type.toString(16)} (expected 0x55)`);
    if (type !== 0x55) {
      console.log(`parseNDEFUrl: Not a URL record (type=0x${type.toString(16)}, expected 0x55)`);
      console.log(`parseNDEFUrl: Data around type offset: ${ndefData.slice(Math.max(0, typeOffset - 2), Math.min(ndefData.length, typeOffset + 5)).toString('hex')}`);
      return null; // Not a URL record (U = 0x55)
    }
    
    const payloadOffset = typeOffset + typeLength + idLength;
    if (payloadOffset + payloadLength > ndefData.length) {
      console.log(`parseNDEFUrl: Payload offset out of bounds (offset=${payloadOffset}, length=${ndefData.length}, payloadLength=${payloadLength})`);
      return null;
    }
    
    const payload = ndefData.slice(payloadOffset, payloadOffset + payloadLength);
    
    if (payload.length === 0) {
      console.log('parseNDEFUrl: Empty payload');
      return null;
    }
    
    // Parse URL prefix
    const prefix = payload[0];
    
    // URL prefix codes: https://www.ndef.org/resources/url-prefixes
    const prefixes = {
      0x00: '',
      0x01: 'http://www.',
      0x02: 'https://www.',
      0x03: 'http://',
      0x04: 'https://',
    };
    
    const url = (prefixes[prefix] || '') + payload.slice(1).toString('utf-8');
    console.log(`parseNDEFUrl: Successfully parsed URL: ${url}`);
    return url;
  } catch (error) {
    console.error('NDEF parse error:', error, 'Data hex:', data?.toString('hex')?.substring(0, 100));
    return null;
  }
}

/**
 * Create NDEF URL record
 * @param {string} url - URL to encode
 * @returns {Buffer} - NDEF record as Buffer
 */
export function createNDEFUrlRecord(url) {
  // Determine URL prefix
  let prefix = 0x04; // https://
  let urlWithoutPrefix = url;
  
  if (url.startsWith('https://www.')) {
    prefix = 0x02;
    urlWithoutPrefix = url.substring(12);
  } else if (url.startsWith('http://www.')) {
    prefix = 0x01;
    urlWithoutPrefix = url.substring(11);
  } else if (url.startsWith('https://')) {
    prefix = 0x04;
    urlWithoutPrefix = url.substring(8);
  } else if (url.startsWith('http://')) {
    prefix = 0x03;
    urlWithoutPrefix = url.substring(7);
  }
  
  const urlBytes = Buffer.from(urlWithoutPrefix, 'utf-8');
  
  // NDEF Record Header
  // MB=1 (Message Begin), ME=1 (Message End), CF=0, SR=1 (Short Record), IL=0, TNF=0x01 (Well Known Type)
  const recordHeader = 0xD1; // 11010001
  
  // Type Length (1 byte for "U")
  const typeLength = 0x01;
  
  // Payload Length (1 byte for short record: prefix + URL)
  const payloadLength = 1 + urlBytes.length;
  
  // Type (U = 0x55)
  const type = 0x55;
  
  // Build NDEF Record
  // Note: ID length byte is only included if IL=1 (bit 3 of recordHeader)
  // Since we always use IL=0, we don't include the ID length byte
  // This matches the test file format: [flags][typeLength][payloadLength][type][payload]
  const ndefRecord = Buffer.concat([
    Buffer.from([recordHeader]),
    Buffer.from([typeLength]),
    Buffer.from([payloadLength]),
    // ID length byte omitted when IL=0 (per NDEF spec)
    Buffer.from([type]),
    Buffer.from([prefix]),
    urlBytes
  ]);
  
  // NDEF Message TLV
  const ndefMessageLength = ndefRecord.length;
  let tlvHeader;
  
  if (ndefMessageLength < 255) {
    // Short form: [0x03][length]
    tlvHeader = Buffer.from([0x03, ndefMessageLength]);
  } else {
    // Extended form: [0x03][0xFF][length high][length low]
    tlvHeader = Buffer.from([
      0x03,
      0xFF,
      (ndefMessageLength >> 8) & 0xFF,
      ndefMessageLength & 0xFF
    ]);
  }
  
  return Buffer.concat([tlvHeader, ndefRecord]);
}

