/**
 * NDEF Read/Write Operations
 * Handles all NDEF operations via APDU commands
 */

import { NDEF_AID, NDEF_FILE_ID } from "./constants.js";
import { parseNDEFUrl, createNDEFUrlRecord } from "./ndef-parser.js";

export class NDEFOperations {
  constructor(nfcManager) {
    this.nfcManager = nfcManager;
  }

  /**
   * Read NDEF data via APDU sequence
   */
  async readNDEFViaAPDU() {
    const reader = this.nfcManager.getReader();
    if (!this.nfcManager.verifyConnection() || !reader.connection) {
      throw new Error("Connection not available");
    }

    await new Promise((resolve) => setTimeout(resolve, 100));

    if (
      !reader.connection ||
      !this.nfcManager.getCard() ||
      !this.nfcManager.isChipPresent()
    ) {
      throw new Error("Connection lost during initialization");
    }

    // Step 1: Select NDEF Application
    console.log("readNDEFViaAPDU: Step 1 - Selecting NDEF Application...");
    const selectApp = Buffer.concat([
      Buffer.from([0x00, 0xa4, 0x04, 0x00, NDEF_AID.length]),
      NDEF_AID,
      Buffer.from([0x00]),
    ]);

    let response = await reader.transmit(selectApp, 40);
    console.log(
      `readNDEFViaAPDU: SELECT NDEF Application response: ${response.toString("hex")}`,
    );

    if (
      response.length < 2 ||
      response[response.length - 2] !== 0x90 ||
      response[response.length - 1] !== 0x00
    ) {
      throw new Error(
        `Failed to select NDEF application: status=${response.slice(-2).toString("hex")}`,
      );
    }
    console.log("readNDEFViaAPDU: SELECT NDEF Application successful");

    // Step 2: Select NDEF File
    console.log("readNDEFViaAPDU: Step 2 - Selecting NDEF File...");
    const selectFile = Buffer.from([
      0x00,
      0xa4,
      0x00,
      0x0c,
      0x02,
      ...NDEF_FILE_ID,
    ]);
    response = await reader.transmit(selectFile, 40);
    console.log(
      `readNDEFViaAPDU: SELECT NDEF File response: ${response.toString("hex")}`,
    );
    if (
      response.length < 2 ||
      response[response.length - 2] !== 0x90 ||
      response[response.length - 1] !== 0x00
    ) {
      throw new Error(
        `Failed to select NDEF file: status=${response.slice(-2).toString("hex")}`,
      );
    }
    console.log("readNDEFViaAPDU: SELECT NDEF File successful");

    // Step 3: Read NLEN (2 bytes at offset 0) to get NDEF message length
    const readNlen = Buffer.from([0x00, 0xb0, 0x00, 0x00, 0x02]);
    response = await reader.transmit(readNlen, 4);
    if (
      response.length < 2 ||
      response[response.length - 2] !== 0x90 ||
      response[response.length - 1] !== 0x00
    ) {
      throw new Error(
        `Failed to read NLEN: status=${response.slice(-2).toString("hex")}`,
      );
    }

    const nlen = response.readUInt16BE(0);
    if (nlen === 0) {
      return Buffer.alloc(0);
    }

    console.log(`readNDEFViaAPDU: NLEN = ${nlen} bytes`);

    // Step 4: Read actual NDEF data (starting from offset 2)
    const maxReadLength = 255 - 2;
    let ndefDataBuffer = Buffer.alloc(0);
    let currentOffset = 2;

    while (ndefDataBuffer.length < nlen) {
      const bytesToRead = Math.min(nlen - ndefDataBuffer.length, maxReadLength);

      console.log(
        `readNDEFViaAPDU: Reading chunk at offset ${currentOffset}, length ${bytesToRead}...`,
      );

      const readBinary = Buffer.from([
        0x00,
        0xb0,
        (currentOffset >> 8) & 0xff,
        currentOffset & 0xff,
        bytesToRead,
      ]);

      response = await reader.transmit(readBinary, bytesToRead + 2);
      if (
        response.length < 2 ||
        response[response.length - 2] !== 0x90 ||
        response[response.length - 1] !== 0x00
      ) {
        throw new Error(
          `Failed to read NDEF data chunk: status=${response.slice(-2).toString("hex")}`,
        );
      }

      ndefDataBuffer = Buffer.concat([ndefDataBuffer, response.slice(0, -2)]);
      currentOffset += bytesToRead;
    }

    return ndefDataBuffer;
  }

  /**
   * Write NDEF data via APDU sequence
   */
  async writeNDEFViaAPDU(ndefMessage) {
    const reader = this.nfcManager.getReader();
    if (!this.nfcManager.verifyConnection() || !reader.connection) {
      throw new Error("Connection not available");
    }

    console.log(
      "writeNDEFViaAPDU: Waiting for connection stability after previous operations...",
    );
    await new Promise((resolve) => setTimeout(resolve, 500));

    if (
      !reader.connection ||
      !this.nfcManager.getCard() ||
      !this.nfcManager.isChipPresent()
    ) {
      throw new Error("Connection lost during initialization");
    }

    // Step 1: Select NDEF Application
    console.log("writeNDEFViaAPDU: Step 1 - Selecting NDEF Application...");
    const selectApp = Buffer.concat([
      Buffer.from([0x00, 0xa4, 0x04, 0x00, NDEF_AID.length]),
      NDEF_AID,
      Buffer.from([0x00]),
    ]);

    let response;
    try {
      response = await reader.transmit(selectApp, 40);
      console.log(
        `writeNDEFViaAPDU: SELECT NDEF Application response: ${response.toString("hex")}`,
      );
    } catch (error) {
      console.error("writeNDEFViaAPDU: SELECT NDEF Application failed:", error);
      if (error.message && error.message.includes("unpowered")) {
        this.nfcManager.clearCardState();
      }
      throw error;
    }

    if (
      response.length < 2 ||
      response[response.length - 2] !== 0x90 ||
      response[response.length - 1] !== 0x00
    ) {
      throw new Error(
        `Failed to select NDEF application: status=${response.slice(-2).toString("hex")}`,
      );
    }
    console.log("writeNDEFViaAPDU: ✅ SELECT NDEF Application successful");

    // Step 2: Select NDEF File
    console.log("writeNDEFViaAPDU: Step 2 - Selecting NDEF File...");
    const selectFile = Buffer.from([
      0x00,
      0xa4,
      0x00,
      0x0c,
      0x02,
      ...NDEF_FILE_ID,
    ]);
    response = await reader.transmit(selectFile, 40);
    console.log(
      `writeNDEFViaAPDU: SELECT NDEF File response: ${response.toString("hex")}`,
    );
    if (
      response.length < 2 ||
      response[response.length - 2] !== 0x90 ||
      response[response.length - 1] !== 0x00
    ) {
      console.log(
        "writeNDEFViaAPDU: Standard SELECT failed, trying alternative...",
      );
      const selectFileAlt = Buffer.from([
        0x00,
        0xa4,
        0x00,
        0x00,
        0x02,
        ...NDEF_FILE_ID,
      ]);
      response = await reader.transmit(selectFileAlt, 40);
      console.log(
        `writeNDEFViaAPDU: Alternative SELECT response: ${response.toString("hex")}`,
      );
      if (
        response.length < 2 ||
        response[response.length - 2] !== 0x90 ||
        response[response.length - 1] !== 0x00
      ) {
        throw new Error(
          `Failed to select NDEF file: status=${response.slice(-2).toString("hex")}`,
        );
      }
    }
    console.log("writeNDEFViaAPDU: ✅ SELECT NDEF File successful");

    // Step 2.5: Read current NLEN
    console.log("writeNDEFViaAPDU: Step 2.5 - Reading current NLEN...");
    const readNlen = Buffer.from([0x00, 0xb0, 0x00, 0x00, 0x02]);
    response = await reader.transmit(readNlen, 4);
    console.log(
      `writeNDEFViaAPDU: Read NLEN response: ${response.toString("hex")}`,
    );
    if (
      response.length >= 2 &&
      response[response.length - 2] === 0x90 &&
      response[response.length - 1] === 0x00
    ) {
      const currentNlen = response.readUInt16BE(0);
      console.log(`writeNDEFViaAPDU: Current NLEN: ${currentNlen} bytes`);
    } else {
      console.log(
        `writeNDEFViaAPDU: Could not read NLEN: status=${response.slice(-2).toString("hex")}`,
      );
    }

    // Step 3: Write NDEF data at offset 2
    console.log(
      `writeNDEFViaAPDU: Step 3 - Writing ${ndefMessage.length} bytes of NDEF data at offset 2...`,
    );
    const writeData = Buffer.concat([
      Buffer.from([0x00, 0xd6, 0x00, 0x02, ndefMessage.length]),
      ndefMessage,
    ]);

    response = await reader.transmit(writeData, 2);
    console.log(
      `writeNDEFViaAPDU: Write data response: ${response.toString("hex")}`,
    );
    if (
      response.length < 2 ||
      response[response.length - 2] !== 0x90 ||
      response[response.length - 1] !== 0x00
    ) {
      throw new Error(
        `Failed to write NDEF data: status=${response.slice(-2).toString("hex")}`,
      );
    }
    console.log("writeNDEFViaAPDU: NDEF data written successfully");

    // Step 4: Update NLEN
    console.log(
      `writeNDEFViaAPDU: Step 4 - Updating NLEN to ${ndefMessage.length}...`,
    );
    const nlenBuffer = Buffer.alloc(2);
    nlenBuffer.writeUInt16BE(ndefMessage.length, 0);
    const updateNlen = Buffer.concat([
      Buffer.from([0x00, 0xd6, 0x00, 0x00, 0x02]),
      nlenBuffer,
    ]);

    response = await reader.transmit(updateNlen, 2);
    console.log(
      `writeNDEFViaAPDU: Update NLEN response: ${response.toString("hex")}`,
    );
    if (
      response.length < 2 ||
      response[response.length - 2] !== 0x90 ||
      response[response.length - 1] !== 0x00
    ) {
      const statusHex = response.slice(-2).toString("hex");
      if (statusHex === "6985") {
        console.warn(
          "writeNDEFViaAPDU: NLEN update failed with 6985 (chip may be locked), but data was written",
        );
      } else {
        throw new Error(`Failed to update NLEN: status=${statusHex}`);
      }
    } else {
      console.log("writeNDEFViaAPDU: NLEN updated successfully");
    }

    console.log(
      `writeNDEFViaAPDU: Successfully wrote ${ndefMessage.length} bytes and updated NLEN`,
    );
    await new Promise((resolve) => setTimeout(resolve, 200));
  }

  /**
   * Internal method to read NDEF data (for verification)
   */
  async readNDEFInternal() {
    if (!this.nfcManager.verifyConnection()) {
      throw new Error("Card needs to be re-presented");
    }

    try {
      const ndefData = await this.readNDEFViaAPDU();

      if (!ndefData || ndefData.length === 0) {
        console.log("readNDEFInternal: No NDEF data read");
        return null;
      }

      console.log(
        `readNDEFInternal: Read ${ndefData.length} bytes, hex: ${ndefData.toString("hex").substring(0, 100)}...`,
      );

      const ndefUrl = parseNDEFUrl(ndefData);
      console.log(`readNDEFInternal: Parsed URL: ${ndefUrl || "null"}`);
      return ndefUrl;
    } catch (error) {
      console.error(
        "readNDEFInternal: Error reading NDEF for verification:",
        error,
      );
      return null;
    }
  }

  /**
   * Read NDEF with retry logic
   */
  async readNDEF(maxRetries = 3) {
    let lastError = null;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await this.nfcManager.waitForCardReady();

        if (!this.nfcManager.verifyConnection()) {
          throw new Error("Card needs to be re-presented");
        }

        const reader = this.nfcManager.getReader();
        if (!reader.connection) {
          console.log("Connection not ready, waiting a bit more...");
          await new Promise((resolve) => setTimeout(resolve, 200));
          if (!reader.connection) {
            throw new Error(
              "Connection not established - card may need to be re-presented",
            );
          }
        }

        const ndefData = await this.readNDEFViaAPDU();
        const ndefUrl = parseNDEFUrl(ndefData);
        return ndefUrl;
      } catch (error) {
        lastError = error;
        const errorMessage = error.message || String(error);
        const isUnpowered = errorMessage.includes("unpowered");

        if (isUnpowered) {
          this.nfcManager.clearCardState();
          await new Promise((resolve) => setTimeout(resolve, 500));
          continue;
        }

        const isRetryable =
          errorMessage.includes("transmitting") ||
          errorMessage.includes("timeout") ||
          errorMessage.includes("Card was removed") ||
          errorMessage.includes("connection");

        if (!isRetryable || attempt === maxRetries) {
          throw error;
        }

        console.warn(
          `NDEF read attempt ${attempt}/${maxRetries} failed, retrying...`,
          errorMessage,
        );
        await new Promise((resolve) => setTimeout(resolve, 200 * attempt));
      }
    }

    throw lastError;
  }

  /**
   * Write NDEF with retry logic and verification
   */
  async writeNDEF(url, maxRetries = 3) {
    if (!url || typeof url !== "string" || url.trim().length === 0) {
      throw new Error("Invalid URL: URL must be a non-empty string");
    }

    let urlToWrite = url.trim();
    if (
      !urlToWrite.startsWith("http://") &&
      !urlToWrite.startsWith("https://")
    ) {
      urlToWrite = "https://" + urlToWrite;
    }

    if (urlToWrite.length > 200) {
      throw new Error("URL too long: Maximum 200 characters supported");
    }

    let lastError = null;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await this.nfcManager.waitForCardReady();

        if (!this.nfcManager.verifyConnection()) {
          throw new Error("Connection lost, card needs to be re-presented");
        }

        const ndefMessage = createNDEFUrlRecord(urlToWrite);

        if (!ndefMessage || ndefMessage.length === 0) {
          throw new Error("Failed to create NDEF message");
        }

        const reader = this.nfcManager.getReader();
        if (!reader.connection) {
          console.log("Connection not ready, waiting a bit more...");
          await new Promise((resolve) => setTimeout(resolve, 200));
          if (!reader.connection) {
            throw new Error(
              "Connection not established - card may need to be re-presented",
            );
          }
        }

        // Always use APDU write for Type 4 tags
        await this.writeNDEFViaAPDU(ndefMessage);

        // Verify by reading back
        console.log("writeNDEF: Write completed, verifying by reading back...");
        await new Promise((resolve) => setTimeout(resolve, 300));
        const verifyUrl = await this.readNDEFInternal();
        console.log(
          `writeNDEF: Verification read returned: ${verifyUrl || "null"}`,
        );

        if (verifyUrl === null) {
          throw new Error(
            `Write verification failed: wrote "${urlToWrite}" but read back null. The write may not have persisted.`,
          );
        } else if (verifyUrl !== urlToWrite) {
          throw new Error(
            `Write verification failed: wrote "${urlToWrite}" but read "${verifyUrl}"`,
          );
        }

        console.log(
          `writeNDEF: Verification successful! Wrote and verified: ${urlToWrite}`,
        );
        return urlToWrite;
      } catch (error) {
        lastError = error;
        const errorMessage = error.message || String(error);
        const isUnpowered = errorMessage.includes("unpowered");

        if (isUnpowered) {
          this.nfcManager.clearCardState();
          await new Promise((resolve) => setTimeout(resolve, 500));
          continue;
        }

        const isRetryable =
          errorMessage.includes("transmitting") ||
          errorMessage.includes("timeout") ||
          errorMessage.includes("Card was removed") ||
          errorMessage.includes("connection");

        if (!isRetryable || attempt === maxRetries) {
          throw error;
        }

        console.warn(
          `NDEF write attempt ${attempt}/${maxRetries} failed, retrying...`,
          errorMessage,
        );
        await new Promise((resolve) => setTimeout(resolve, 200 * attempt));
      }
    }

    throw lastError;
  }
}

