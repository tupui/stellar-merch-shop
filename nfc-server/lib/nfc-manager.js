/**
 * NFC Connection Manager
 * Handles NFC reader initialization, card detection, and connection state
 */

import { NFC, TAG_ISO_14443_4 } from 'nfc-pcsc';
import { TAG_ISO_14443_3 } from './constants.js';

export class NFCManager {
  constructor() {
    this.nfc = null;
    this.currentReader = null;
    this.currentCard = null;
    this.chipPresent = false;
    this.cardReadyPromise = null;
    this.cardReadyResolve = null;
  }

  /**
   * Initialize nfc-pcsc for all NFC operations (APDU and NDEF)
   * @param {Function} onCardDetected - Callback when card is detected
   * @param {Function} onCardRemoved - Callback when card is removed
   * @param {Function} onStatusChange - Callback for status changes
   */
  init(onCardDetected, onCardRemoved, onStatusChange) {
    this.nfc = new NFC();
    this.onCardDetected = onCardDetected;
    this.onCardRemoved = onCardRemoved;
    this.onStatusChange = onStatusChange;
    
    this.nfc.on('reader', (reader) => {
      console.log(`NFC Reader detected: ${reader.reader.name}`);
      
      // Only use reader 2 (Identiv uTrust 4701 F Dual Interface Reader(2))
      if (!reader.reader.name.includes('(2)')) {
        console.log(`Skipping reader "${reader.reader.name}" - only using reader (2)`);
        return;
      }
      
      console.log(`Using reader: ${reader.reader.name}`);
      this.currentReader = reader;
      reader.autoProcessing = false;
      
      reader.on('card', async (card) => {
        try {
          console.log(`Card detected: ${card.type}, UID: ${card.uid || 'N/A'}`);
          this.currentCard = card;
          this.chipPresent = true;
          
          await new Promise(resolve => setTimeout(resolve, 200));
          
          if (!this.currentCard || !this.chipPresent) {
            console.warn('Card was removed during initialization');
            return;
          }
          
          if (!reader.connection) {
            console.warn('Connection not established, waiting a bit more...');
            await new Promise(resolve => setTimeout(resolve, 200));
          }
          
          if (this.cardReadyResolve) {
            this.cardReadyResolve();
          }
          
          if (this.onStatusChange) {
            this.onStatusChange();
          }
        } catch (error) {
          console.error('Error handling card detection:', error);
          this.currentCard = null;
          this.chipPresent = false;
        }
      });
      
      reader.on('card.off', (card) => {
        console.log('Card removed', card ? `(UID: ${card.uid || 'N/A'})` : '');
        this.currentCard = null;
        this.chipPresent = false;
        
        if (this.cardReadyPromise) {
          const { reject, timeout } = this.cardReadyPromise;
          clearTimeout(timeout);
          reject(new Error('Card was removed'));
          this.cardReadyPromise = null;
          this.cardReadyResolve = null;
        }
        
        if (this.onStatusChange) {
          this.onStatusChange();
        }
      });
      
      reader.on('error', (err) => {
        console.error('NFC Reader error:', err);
        if (err.message && (err.message.includes('transmitting') || err.message.includes('connection'))) {
          console.warn('Reader connection error detected, clearing card state');
          this.currentCard = null;
          this.chipPresent = false;
          if (this.onStatusChange) {
            this.onStatusChange();
          }
        }
      });
    });
    
    this.nfc.on('error', (err) => {
      console.error('NFC error:', err);
    });
  }

  /**
   * Verify basic prerequisites (reader and card state)
   */
  verifyConnection() {
    return !!(this.currentReader && this.currentCard && this.chipPresent);
  }

  /**
   * Wait for card to be detected and ready for operations
   */
  async waitForCardReady() {
    if (!this.currentReader) {
      throw new Error('No NFC reader available');
    }

    if (this.currentCard && this.chipPresent) {
      if (this.currentCard.type === TAG_ISO_14443_4) {
        if (!this.verifyConnection()) {
          throw new Error('Connection lost, card needs to be re-presented');
        }
        await new Promise(resolve => setTimeout(resolve, 100));
        if (!this.verifyConnection() || !this.currentReader.connection) {
          throw new Error('Connection lost during wait');
        }
        return;
      }
      
      await new Promise(resolve => setTimeout(resolve, 50));
      
      if (!this.currentCard || !this.chipPresent) {
        throw new Error('Card was removed during initialization');
      }
      
      return;
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        if (this.cardReadyPromise && this.cardReadyPromise.resolve === resolve) {
          this.cardReadyPromise = null;
          this.cardReadyResolve = null;
        }
        reject(new Error('Timeout waiting for card. Please place the chip on the reader.'));
      }, 10000);

      this.cardReadyPromise = { resolve, reject, timeout };
      this.cardReadyResolve = () => {
        clearTimeout(timeout);
        if (this.cardReadyPromise && this.cardReadyPromise.resolve === resolve) {
          this.cardReadyPromise = null;
          this.cardReadyResolve = null;
        }
        resolve();
      };
    });
  }

  /**
   * Clear card state (used for error recovery)
   */
  clearCardState() {
    this.currentCard = null;
    this.chipPresent = false;
    if (this.cardReadyPromise) {
      const { reject, timeout } = this.cardReadyPromise;
      clearTimeout(timeout);
      this.cardReadyPromise = null;
      this.cardReadyResolve = null;
      reject(new Error('Card state cleared due to error'));
    }
  }

  getReader() {
    return this.currentReader;
  }

  getCard() {
    return this.currentCard;
  }

  isChipPresent() {
    return this.chipPresent;
  }
}

