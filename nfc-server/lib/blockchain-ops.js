/**
 * Blockchain Application APDU Operations
 * Handles all operations related to the Blockchain Security 2Go application
 */

import { BLOCKCHAIN_AID } from './constants.js';

export class BlockchainOperations {
  constructor(nfcManager) {
    this.nfcManager = nfcManager;
  }

  /**
   * Select Blockchain application
   */
  async selectApplication() {
    const reader = this.nfcManager.getReader();
    if (!this.nfcManager.verifyConnection() || !reader.connection) {
      throw new Error('Connection not available');
    }
    
    await new Promise(resolve => setTimeout(resolve, 100));
    
    if (!reader.connection || !this.nfcManager.getCard() || !this.nfcManager.isChipPresent()) {
      throw new Error('Connection lost during initialization');
    }
    
    console.log(`selectApplication: Selecting Blockchain app (AID: ${BLOCKCHAIN_AID.toString('hex')})`);
    
    const selectApp = Buffer.concat([
      Buffer.from([0x00, 0xA4, 0x04, 0x00, BLOCKCHAIN_AID.length]),
      BLOCKCHAIN_AID,
      Buffer.from([0x00])
    ]);
    
    console.log(`selectApplication: Sending APDU: ${selectApp.toString('hex')}`);
    
    let response;
    try {
      response = await reader.transmit(selectApp, 40);
      console.log(`selectApplication: Response: ${response.toString('hex')}`);
    } catch (error) {
      console.error('selectApplication: Transmit failed:', error);
      this.nfcManager.clearCardState();
      throw new Error(`Failed to transmit SELECT command: ${error.message}`);
    }
    
    if (response.length < 2) {
      this.nfcManager.clearCardState();
      throw new Error(`Invalid response length: ${response.length}`);
    }
    
    const status = response.slice(-2);
    if (status[0] !== 0x90 || status[1] !== 0x00) {
      const statusHex = status.toString('hex');
      console.error(`selectApplication: Failed with status: ${statusHex}`);
      throw new Error(`Failed to select Blockchain application: status=${statusHex}`);
    }
    
    console.log('selectApplication: Success');
    return true;
  }

  /**
   * Get key information including public key and signature counters
   */
  async getKeyInfo(keyHandle = 1) {
    console.log(`getKeyInfo: Using key ID ${keyHandle}`);
    const reader = this.nfcManager.getReader();
    if (!this.nfcManager.verifyConnection() || !reader.connection) {
      throw new Error('Connection not available');
    }
    
    if (keyHandle < 0 || keyHandle > 255) {
      throw new Error(`Invalid keyHandle: ${keyHandle} (must be 0-255)`);
    }
    
    try {
      await this.selectApplication();
      await new Promise(resolve => setTimeout(resolve, 50));
      
      if (!reader.connection || !this.nfcManager.getCard() || !this.nfcManager.isChipPresent()) {
        throw new Error('Connection lost after SELECT application');
      }
      
      console.log(`getKeyInfo: Getting key info for handle ${keyHandle}`);
      
      const getKeyInfo = Buffer.from([
        0x00, 0x16, keyHandle, 0x00, 0x00
      ]);
      
      console.log(`getKeyInfo: Sending APDU: ${getKeyInfo.toString('hex')}`);
      
      const response = await reader.transmit(getKeyInfo, 255);
      console.log(`getKeyInfo: Response length: ${response.length}`);
      
      if (response.length < 2 || response[response.length - 2] !== 0x90 || response[response.length - 1] !== 0x00) {
        const statusHex = response.slice(-2).toString('hex');
        const statusCode = response[response.length - 2] << 8 | response[response.length - 1];
        
        if (statusCode === 0x6a88) {
          throw new Error(`Key ID ${keyHandle} does not exist on this chip`);
        }
        
        console.error(`getKeyInfo: Failed with status: ${statusHex}`);
        throw new Error(`Failed to get key info: status=${statusHex}`);
      }
      
      const data = response.slice(0, response.length - 2);
      
      if (data.length < 73) {
        throw new Error(`Invalid key info response: expected at least 73 bytes (4+4+65), got ${data.length}`);
      }
      
      const globalCounter = data.readUInt32BE(0);
      const keyCounter = data.readUInt32BE(4);
      const publicKey = data.slice(8, 73);
      
      if (publicKey.length !== 65) {
        throw new Error(`Invalid public key length: expected 65 bytes, got ${publicKey.length}`);
      }
      
      const publicKeyHex = publicKey.toString('hex');
      console.log(`getKeyInfo: Success for key ID ${keyHandle}, public key: ${publicKeyHex.substring(0, 20)}...${publicKeyHex.substring(publicKeyHex.length - 20)}, full: ${publicKeyHex}, counters: global=${globalCounter}, key=${keyCounter}`);
      
      return {
        publicKey: publicKeyHex,
        globalCounter,
        keyCounter
      };
    } catch (error) {
      console.error('getKeyInfo: Error:', error);
      if (error.message && (error.message.includes('unpowered') || error.message.includes('Connection') || error.message.includes('transmit'))) {
        this.nfcManager.clearCardState();
      }
      throw error;
    }
  }

  /**
   * Generate a new keypair on the chip
   */
  async generateKey() {
    const reader = this.nfcManager.getReader();
    if (!this.nfcManager.verifyConnection() || !reader.connection) {
      throw new Error('Connection not available');
    }
    
    try {
      await this.selectApplication();
      await new Promise(resolve => setTimeout(resolve, 50));
      
      if (!reader.connection || !this.nfcManager.getCard() || !this.nfcManager.isChipPresent()) {
        throw new Error('Connection lost after SELECT application');
      }
      
      console.log('generateKey: Generating new keypair...');
      
      const generateKey = Buffer.from([0x00, 0x02, 0x00, 0x00, 0x00]);
      
      console.log(`generateKey: Sending APDU: ${generateKey.toString('hex')}`);
      
      const response = await reader.transmit(generateKey, 40);
      console.log(`generateKey: Response length: ${response.length}`);
      
      if (response.length < 2 || response[response.length - 2] !== 0x90 || response[response.length - 1] !== 0x00) {
        const statusHex = response.slice(-2).toString('hex');
        console.error(`generateKey: Failed with status: ${statusHex}`);
        throw new Error(`Failed to generate key: status=${statusHex}`);
      }
      
      const keyId = response[0];
      console.log(`generateKey: Success, new key ID: ${keyId}`);
      
      return keyId;
    } catch (error) {
      console.error('generateKey: Error:', error);
      if (error.message && (error.message.includes('unpowered') || error.message.includes('Connection') || error.message.includes('transmit'))) {
        this.nfcManager.clearCardState();
      }
      throw error;
    }
  }

  /**
   * Fetch key information by key ID
   */
  async fetchKeyById(keyId) {
    if (!keyId || keyId < 1 || keyId > 255) {
      throw new Error(`Invalid key ID: ${keyId} (must be 1-255)`);
    }
    
    const keyInfo = await this.getKeyInfo(keyId);
    return {
      keyId,
      publicKey: keyInfo.publicKey,
      globalCounter: keyInfo.globalCounter,
      keyCounter: keyInfo.keyCounter
    };
  }

  /**
   * Generate signature for a 32-byte message hash
   */
  async generateSignature(keyHandle, messageDigest) {
    const reader = this.nfcManager.getReader();
    if (!this.nfcManager.verifyConnection() || !reader.connection) {
      throw new Error('Connection not available');
    }
    
    if (!messageDigest || messageDigest.length !== 32) {
      throw new Error('Message digest must be exactly 32 bytes');
    }
    
    if (keyHandle < 0 || keyHandle > 255) {
      throw new Error(`Invalid keyHandle: ${keyHandle} (must be 0-255)`);
    }
    
    try {
      await this.selectApplication();
      await new Promise(resolve => setTimeout(resolve, 50));
      
      if (!reader.connection || !this.nfcManager.getCard() || !this.nfcManager.isChipPresent()) {
        throw new Error('Connection lost after SELECT application');
      }
      
      console.log(`generateSignature: Generating signature for key handle ${keyHandle} (this should match the key ID used in readPublicKey)`);
      
      const generateSig = Buffer.concat([
        Buffer.from([0x00, 0x18, keyHandle, 0x00, 0x20]),
        messageDigest,
        Buffer.from([0x00])
      ]);
      
      console.log(`generateSignature: Sending APDU: ${generateSig.toString('hex').substring(0, 20)}...`);
      
      const response = await reader.transmit(generateSig, 255);
      console.log(`generateSignature: Response length: ${response.length}`);
      
      if (response.length < 2 || response[response.length - 2] !== 0x90 || response[response.length - 1] !== 0x00) {
        const statusHex = response.slice(-2).toString('hex');
        console.error(`generateSignature: Failed with status: ${statusHex}`);
        throw new Error(`Failed to generate signature: status=${statusHex}`);
      }
      
      const data = response.slice(0, response.length - 2);
      
      if (data.length < 8) {
        throw new Error(`Invalid signature response: expected at least 8 bytes (counters), got ${data.length}`);
      }
      
      const globalCounter = data.readUInt32BE(0);
      const keyCounter = data.readUInt32BE(4);
      const derSignature = data.slice(8);
      
      console.log(`generateSignature: Success, counters: global=${globalCounter}, key=${keyCounter}, signature length: ${derSignature.length}`);
      
      return {
        signature: derSignature,
        globalCounter,
        keyCounter
      };
    } catch (error) {
      console.error('generateSignature: Error:', error);
      if (error.message && (error.message.includes('unpowered') || error.message.includes('Connection') || error.message.includes('transmit'))) {
        this.nfcManager.clearCardState();
      }
      throw error;
    }
  }
}

