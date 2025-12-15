/**
 * NDEF parsing utilities
 */

/**
 * Parse NDEF URL from raw NDEF record data
 * @param {Buffer} data - Raw NDEF record data (format: [flags][typeLength][payloadLength][type][payload])
 * @returns {string|null} - Parsed URL or null if not a URL record
 */
export function parseNDEFUrl(data) {
  try {
    if (!data || data.length === 0) {
      return null;
    }

    // Raw NDEF record starts with flags byte

    // Parse NDEF record
    if (data.length < 5) {
      console.log(`parseNDEFUrl: NDEF data too short: ${data.length} bytes`);
      return null;
    }

    console.log(
      `parseNDEFUrl: Parsing NDEF record (${data.length} bytes), first 20 bytes: ${data.slice(0, 20).toString("hex")}`,
    );
    const recordHeader = data[0];
    const typeLength = data[1];
    console.log(
      `parseNDEFUrl: Record header: 0x${recordHeader.toString(16)}, typeLength: ${typeLength}`,
    );
    const hasIdLength = (recordHeader & 0x08) !== 0; // IL flag (bit 3)
    console.log(
      `parseNDEFUrl: IL flag: ${hasIdLength}, SR flag: ${(recordHeader & 0x10) !== 0}`,
    );

    // Payload length can be 1 byte (short record, SR=1) or 3 bytes (long record, SR=0)
    let payloadLength;
    let idLength = 0;
    let typeOffset;

    if (recordHeader & 0x10) {
      // Short record (SR=1): 1-byte payload length
      payloadLength = data[2];
      typeOffset = 3;
      console.log(
        `parseNDEFUrl: Short record (SR=1), payloadLength: ${payloadLength}, initial typeOffset: ${typeOffset}`,
      );

      // If IL flag is set, there's an ID length byte
      if (hasIdLength) {
        idLength = data[3];
        typeOffset = 4;
        console.log(
          `parseNDEFUrl: IL flag set, idLength: ${idLength}, typeOffset: ${typeOffset}`,
        );
      }
    } else {
      // Long record (SR=0): 3-byte payload length
      payloadLength = (data[2] << 16) | (data[3] << 8) | data[4];
      typeOffset = 5;
      console.log(
        `parseNDEFUrl: Long record (SR=0), payloadLength: ${payloadLength}, initial typeOffset: ${typeOffset}`,
      );

      // If IL flag is set, there's an ID length byte
      if (hasIdLength) {
        idLength = data[5];
        typeOffset = 6;
        console.log(
          `parseNDEFUrl: IL flag set, idLength: ${idLength}, typeOffset: ${typeOffset}`,
        );
      }
    }

    if (typeLength !== 1) {
      console.log(`parseNDEFUrl: Not a URL record (typeLength=${typeLength})`);
      return null; // Not a URL record
    }

    console.log(
      `parseNDEFUrl: Calculated typeOffset: ${typeOffset}, payloadLength: ${payloadLength}, idLength: ${idLength}`,
    );
    const type = data[typeOffset];
    console.log(
      `parseNDEFUrl: Type byte at offset ${typeOffset}: 0x${type.toString(16)} (expected 0x55)`,
    );
    if (type !== 0x55) {
      console.log(
        `parseNDEFUrl: Not a URL record (type=0x${type.toString(16)}, expected 0x55)`,
      );
      console.log(
        `parseNDEFUrl: Data around type offset: ${data.slice(Math.max(0, typeOffset - 2), Math.min(data.length, typeOffset + 5)).toString("hex")}`,
      );
      return null; // Not a URL record (U = 0x55)
    }

    const payloadOffset = typeOffset + typeLength + idLength;
    if (payloadOffset + payloadLength > data.length) {
      console.log(
        `parseNDEFUrl: Payload offset out of bounds (offset=${payloadOffset}, length=${data.length}, payloadLength=${payloadLength})`,
      );
      return null;
    }

    const payload = data.slice(payloadOffset, payloadOffset + payloadLength);

    if (payload.length === 0) {
      console.log("parseNDEFUrl: Empty payload");
      return null;
    }

    // Parse URL prefix
    const prefix = payload[0];

    // URL prefix codes: https://www.ndef.org/resources/url-prefixes
    const prefixes = {
      0x00: "",
      0x01: "http://www.",
      0x02: "https://www.",
      0x03: "http://",
      0x04: "https://",
    };

    const url = (prefixes[prefix] || "") + payload.slice(1).toString("utf-8");
    console.log(`parseNDEFUrl: Successfully parsed URL: ${url}`);
    return url;
  } catch (error) {
    console.error(
      "NDEF parse error:",
      error,
      "Data hex:",
      data?.toString("hex")?.substring(0, 100),
    );
    return null;
  }
}

/**
 * Create NDEF URL record (raw format, no TLV wrapper)
 * For Type 4 tags accessed via APDU, the raw NDEF record is written directly
 * @param {string} url - URL to encode
 * @returns {Buffer} - Raw NDEF record as Buffer (format: [flags][typeLength][payloadLength][type][payload])
 */
export function createNDEFUrlRecord(url) {
  // Determine URL prefix
  let prefix = 0x04; // https://
  let urlWithoutPrefix = url;

  if (url.startsWith("https://www.")) {
    prefix = 0x02;
    urlWithoutPrefix = url.substring(12);
  } else if (url.startsWith("http://www.")) {
    prefix = 0x01;
    urlWithoutPrefix = url.substring(11);
  } else if (url.startsWith("https://")) {
    prefix = 0x04;
    urlWithoutPrefix = url.substring(8);
  } else if (url.startsWith("http://")) {
    prefix = 0x03;
    urlWithoutPrefix = url.substring(7);
  }

  const urlBytes = Buffer.from(urlWithoutPrefix, "utf-8");

  // NDEF Record Header
  // MB=1 (Message Begin), ME=1 (Message End), CF=0, SR=1 (Short Record), IL=0, TNF=0x01 (Well Known Type)
  const recordHeader = 0xd1; // 11010001

  // Type Length (1 byte for "U")
  const typeLength = 0x01;

  // Payload Length (1 byte for short record: prefix + URL)
  const payloadLength = 1 + urlBytes.length;

  // Type (U = 0x55)
  const type = 0x55;

  // Build raw NDEF Record (no TLV wrapper)
  // Format: [flags][typeLength][payloadLength][type][payload]
  // ID length byte is omitted when IL=0 (per NDEF spec)
  const ndefRecord = Buffer.concat([
    Buffer.from([recordHeader]),
    Buffer.from([typeLength]),
    Buffer.from([payloadLength]),
    Buffer.from([type]),
    Buffer.from([prefix]),
    urlBytes,
  ]);

  return ndefRecord;
}
