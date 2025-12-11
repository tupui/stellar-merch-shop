/**
 * React hook for NFC chip operations
 * Manages connection to NFC server and provides methods for chip interaction
 */

import { useState, useEffect, useCallback } from 'react';
import { nfcClient } from '../util/nfcClient';
import type { SorobanSignature } from '../util/crypto';
import type { KeyInfo } from '../util/nfcClient';

export interface UseNFCReturn {
  // Connection state
  connected: boolean;
  
  // Operation state
  signing: boolean;
  readingNDEF: boolean;
  writingNDEF: boolean;
  generatingKey: boolean;
  fetchingKey: boolean;
  
  // Methods
  connect: () => Promise<void>;
  readChip: (keyId?: number) => Promise<string>;
  signWithChip: (messageDigest: Uint8Array, keyId?: number) => Promise<SorobanSignature>;
  readNDEF: () => Promise<string | null>;
  writeNDEF: (url: string) => Promise<string>;
  generateKey: () => Promise<KeyInfo>;
  fetchKeyById: (keyId: number) => Promise<KeyInfo>;
}

export function useNFC(): UseNFCReturn {
  const [connected, setConnected] = useState(false);
  const [signing, setSigning] = useState(false);
  const [readingNDEF, setReadingNDEF] = useState(false);
  const [writingNDEF, setWritingNDEF] = useState(false);
  const [generatingKey, setGeneratingKey] = useState(false);
  const [fetchingKey, setFetchingKey] = useState(false);

  // Set up event listeners for connection state
  useEffect(() => {
    // Check initial connection state
    setConnected(nfcClient.isConnected());

    const handleEvent = (event: { type: string; data?: unknown }) => {
      switch (event.type) {
        case 'connected':
          setConnected(true);
          break;

        case 'disconnected':
          setConnected(false);
          break;
      }
    };

    nfcClient.addListener(handleEvent);

    return () => {
      nfcClient.removeListener(handleEvent);
    };
  }, []);


  const connect = useCallback(async () => {
    // Only connect if not already connected
    if (!nfcClient.isConnected()) {
      await nfcClient.connect();
    }
    // Update state based on actual connection (event listener will also update it, but this ensures immediate update)
    setConnected(nfcClient.isConnected());
  }, []);

  const readChip = useCallback(async (keyId?: number): Promise<string> => {
    // Check actual connection state and auto-connect if needed
    if (!nfcClient.isConnected()) {
      await connect();
    }

    // Let the server handle chip presence checking - it will throw an error if chip not present
    return await nfcClient.readPublicKey(keyId);
  }, [connect]);

  const signWithChip = useCallback(async (messageDigest: Uint8Array, keyId?: number): Promise<SorobanSignature> => {
    // Check actual connection state and auto-connect if needed
    if (!nfcClient.isConnected()) {
      await connect();
    }

    setSigning(true);
    try {
      // Let the server handle chip presence checking - it will throw an error if chip not present
      return await nfcClient.signMessage(messageDigest, keyId);
    } finally {
      setSigning(false);
    }
  }, [connect]);

  const readNDEF = useCallback(async (): Promise<string | null> => {
    // Check actual connection state and auto-connect if needed
    if (!nfcClient.isConnected()) {
      await connect();
    }

    setReadingNDEF(true);
    try {
      return await nfcClient.readNDEF();
    } finally {
      setReadingNDEF(false);
    }
  }, [connect]);

  const writeNDEF = useCallback(async (url: string): Promise<string> => {
    // Check actual connection state and auto-connect if needed
    if (!nfcClient.isConnected()) {
      await connect();
    }

    setWritingNDEF(true);
    try {
      return await nfcClient.writeNDEF(url);
    } finally {
      setWritingNDEF(false);
    }
  }, [connect]);

  const generateKey = useCallback(async (): Promise<KeyInfo> => {
    // Check actual connection state and auto-connect if needed
    if (!nfcClient.isConnected()) {
      await connect();
    }

    setGeneratingKey(true);
    try {
      return await nfcClient.generateKey();
    } finally {
      setGeneratingKey(false);
    }
  }, [connect]);

  const fetchKeyById = useCallback(async (keyId: number): Promise<KeyInfo> => {
    // Check actual connection state and auto-connect if needed
    if (!nfcClient.isConnected()) {
      await connect();
    }

    setFetchingKey(true);
    try {
      return await nfcClient.fetchKeyById(keyId);
    } finally {
      setFetchingKey(false);
    }
  }, [connect]);

  return {
    connected,
    signing,
    readingNDEF,
    writingNDEF,
    generatingKey,
    fetchingKey,
    connect,
    readChip,
    signWithChip,
    readNDEF,
    writeNDEF,
    generateKey,
    fetchKeyById
  };
}

