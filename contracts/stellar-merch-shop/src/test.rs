extern crate std;

use soroban_sdk::{testutils::Address as _, Address, Bytes, BytesN, Env, String};
use soroban_sdk::xdr::ToXdr;
use crate::{StellarMerchShop, StellarMerchShopClient};

fn create_client<'a>(e: &Env, admin: &Address) -> StellarMerchShopClient<'a> {
    let address = e.register(
        StellarMerchShop,
        (
            admin,
            &String::from_str(e, "TestNFT"),
            &String::from_str(e, "TNFT"),
            &String::from_str(e, "https://example.com/token/"),
        ),
    );
    StellarMerchShopClient::new(e, &address)
}

#[test]
fn test_metadata() {
    let e = Env::default();
    e.mock_all_auths();

    let admin = Address::generate(&e);
    let client = create_client(&e, &admin);

    let name = client.name();
    assert_eq!(name, String::from_str(&e, "TestNFT"));
    
    let symbol = client.symbol();
    assert_eq!(symbol, String::from_str(&e, "TNFT"));
}

#[test]
fn test_print_message_hash_for_signing() {
    let e = Env::default();
    
    // Create test message that produces hash 53d79d1d1cdcb175a480d34dddf359d3bf9f441d35d5e86b8a3ea78afba9491b
    // This matches the hash used in blockchain2go CLI and test_mint_structure
    let message = Bytes::from_slice(&e, b"test message for minting");
    let nonce: u32 = 0;
    
    // Build message with nonce (as contract does)
    let mut builder = Bytes::new(&e);
    builder.append(&message.clone());
    builder.append(&nonce.to_xdr(&e));
    
    // Hash the message (as contract does)
    let message_hash = e.crypto().sha256(&builder);
    
    // Convert Hash<32> to BytesN<32> to get the raw bytes
    let hash_bytes: BytesN<32> = message_hash.clone().into();
    let hash_array = hash_bytes.to_array();
    
    // Print the message hash in hex format for manual signing
    std::println!("\n=== Message Hash for Manual Signing ===");
    std::println!("Message: 'test message for minting'");
    std::println!("Message length: {} bytes", message.len());
    std::println!("Nonce: {}", nonce);
    std::println!("Message Hash (hex, single line): ");
    for byte in hash_array {
        std::print!("{:02x}", byte);
    }
    std::println!();
    std::println!("Expected hash: 53d79d1d1cdcb175a480d34dddf359d3bf9f441d35d5e86b8a3ea78afba9491b");
    std::println!("========================================\n");
    
    // This test always passes - it's just for printing
    assert!(true);
}

#[test]
fn test_mint_structure() {
    let e = Env::default();
    e.mock_all_auths();
    
    let admin = Address::generate(&e);
    let to = Address::generate(&e);
    let client = create_client(&e, &admin);
    
    // Create test message and nonce that produces hash 53d79d1d1cdcb175a480d34dddf359d3bf9f441d35d5e86b8a3ea78afba9491b
    // This is the hash that was signed by the NFC chip via blockchain2go CLI
    let message = Bytes::from_slice(&e, b"test message for minting");
    let nonce: u32 = 0;
    
    // Build message hash for manual recovery testing (for signatures after first)
    let mut builder = Bytes::new(&e);
    builder.append(&message.clone());
    builder.append(&nonce.to_xdr(&e));
    let message_hash = e.crypto().sha256(&builder);
    
    // Expected token ID (public key from NFC chip)
    let expected_token_id = BytesN::from_array(
        &e,
        &[
            0x04, 0x24, 0xf8, 0xcd, 0x2c, 0x99, 0xc9, 0x57, 0x91, 0x59, 0xc9, 0x9c, 0x99, 0x1c, 0xa9, 0x36,
            0x3c, 0x5c, 0x89, 0x6a, 0x33, 0x88, 0xc8, 0x78, 0xe8, 0xa2, 0xf5, 0x78, 0xc1, 0xee, 0xd7, 0xfa,
            0x27, 0x19, 0x44, 0x18, 0x50, 0x43, 0x0a, 0xd8, 0x7d, 0xbd, 0x43, 0x72, 0x96, 0x4a, 0xd2, 0x2d,
            0xc0, 0xc9, 0xaa, 0x29, 0xfb, 0x64, 0x78, 0xd5, 0xf9, 0x72, 0x2b, 0x0e, 0x45, 0x36, 0xd0, 0xdc,
            0x2f,
        ],
    );
    
    // Test signatures: (r, s) pairs in 64-byte format, parsed from DER signatures from blockchain2go CLI
    // These are the three signatures generated for message hash 53d79d1d1cdcb175a480d34dddf359d3bf9f441d35d5e86b8a3ea78afba9491b
    let signatures = [
        // Signature 1: DER 30450221008adf4042...1945
        ([0x8a, 0xdf, 0x40, 0x42, 0xf3, 0x48, 0x31, 0x36, 0xc9, 0x44, 0x9a, 0xca, 0x2a, 0x5d, 0xf3, 0x8e, 0xc9, 0x58, 0x74, 0x38, 0x2d, 0x56, 0x47, 0x25, 0x53, 0xcd, 0xc6, 0xcb, 0xbd, 0x3c, 0x06, 0x33], [0x24, 0x68, 0x6b, 0x1f, 0xa8, 0xb8, 0x0c, 0x00, 0x13, 0x05, 0x0b, 0x70, 0x5e, 0x4c, 0x41, 0xf6, 0x9a, 0xe3, 0xec, 0x89, 0x5f, 0xc3, 0x1e, 0x0c, 0x35, 0x9b, 0xf9, 0xfe, 0x28, 0x89, 0x19, 0x45]),
        // Signature 2: DER 30460221008d379c71...24f6
        ([0x8d, 0x37, 0x9c, 0x71, 0x59, 0xca, 0xae, 0x0c, 0x86, 0xa4, 0x95, 0x7b, 0xba, 0x3e, 0x21, 0x83, 0xbf, 0x07, 0xa9, 0x0d, 0xb6, 0x14, 0x2a, 0xbb, 0xf3, 0x6a, 0xbd, 0xc3, 0xcb, 0x6c, 0xd8, 0xe4], [0xb2, 0x61, 0xf8, 0x93, 0xa6, 0xb6, 0x14, 0x72, 0x12, 0x8d, 0x46, 0xdd, 0xf7, 0x42, 0x34, 0xae, 0x08, 0x15, 0xa5, 0x68, 0xef, 0x78, 0xa6, 0x22, 0x68, 0x07, 0xa0, 0xe4, 0x4c, 0xc2, 0x24, 0xf6]),
        // Signature 3: DER 3046022100c1544d94...45c2
        ([0xc1, 0x54, 0x4d, 0x94, 0xaa, 0x33, 0x82, 0x20, 0xa0, 0x6a, 0xc3, 0x40, 0x55, 0x92, 0x9a, 0xa7, 0xa8, 0xf9, 0x6c, 0x02, 0xa0, 0xa8, 0x27, 0x09, 0xf8, 0x03, 0xb3, 0x6d, 0xcc, 0x04, 0x14, 0x3f], [0x99, 0xdd, 0xac, 0x7d, 0xb0, 0x3f, 0xc8, 0xe5, 0x7e, 0x51, 0x06, 0x7d, 0x7d, 0x1b, 0x37, 0xfc, 0xd7, 0xd0, 0xd1, 0x2e, 0x46, 0x77, 0x40, 0x23, 0x21, 0x52, 0x9a, 0xbe, 0x11, 0x2d, 0x45, 0xc2]),
    ];
    
    // Normalize s values: secp256k1 curve order n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
    // Half order = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0
    // If s > half_order, use n - s
    fn normalize_s(s: &[u8; 32]) -> [u8; 32] {
        // secp256k1 half curve order (big-endian)
        let half_order: [u8; 32] = [
            0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x5D, 0x57, 0x6E, 0x73, 0x57, 0xA4, 0x50, 0x1D,
        ];
        // secp256k1 curve order (big-endian)
        let curve_order: [u8; 32] = [
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE,
            0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B, 0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x41,
        ];
        
        // Compare s with half_order (big-endian comparison: most significant byte first)
        let mut s_greater_than_half = false;
        for i in 0..32 {
            if s[i] > half_order[i] {
                s_greater_than_half = true;
                break;
            } else if s[i] < half_order[i] {
                break;
            }
        }
        
        if s_greater_than_half {
            // s > half_order, so normalize: s = n - s
            // Subtract s from curve_order (big-endian subtraction with borrow)
            let mut result = [0u8; 32];
            let mut borrow = 0u16;
            for i in (0..32).rev() {
                let curve_byte = curve_order[i] as u16;
                let s_byte = s[i] as u16;
                let total_to_subtract = s_byte + borrow;
                
                if curve_byte >= total_to_subtract {
                    result[i] = (curve_byte - total_to_subtract) as u8;
                    borrow = 0;
                } else {
                    result[i] = ((256u16 + curve_byte) - total_to_subtract) as u8;
                    borrow = 1;
                }
            }
            result
        } else {
            *s
        }
    }
    
    // Test all signatures: verify contract can recover token_id from signature
    // The client determines recovery_id and passes it to the contract
    // The contract verifies that the signature recovers to the provided token_id
    
    for (idx, (r, s)) in signatures.iter().enumerate() {
        // Normalize s value (required by Soroban's secp256k1_recover)
        let s_normalized = normalize_s(s);
        
        let mut sig_bytes = [0u8; 64];
        sig_bytes[..32].copy_from_slice(r);
        sig_bytes[32..].copy_from_slice(&s_normalized);
        let signature = BytesN::from_array(&e, &sig_bytes);
        
        // Determine the correct recovery_id by trying all possibilities (0-3)
        // This simulates what the client does with determineRecoveryId
        let mut correct_recovery_id: Option<u32> = None;
        for recovery_id in 0u32..=3u32 {
            let recovered = e.crypto().secp256k1_recover(&message_hash, &signature, recovery_id);
            if recovered == expected_token_id {
                correct_recovery_id = Some(recovery_id);
                break;
            }
        }
        
        // Verify we found a valid recovery_id
        assert!(correct_recovery_id.is_some(), "Signature {} failed: no recovery_id (0-3) recovers to expected token_id", idx + 1);
        let recovery_id = correct_recovery_id.unwrap();
        
        // For first signature, actually call mint to test full flow
        // For others, just verify the recovery_id determination works
        if idx == 0 {
            // Call mint with recovery_id and token_id
            // Contract will use recovery_id to recover and verify it matches token_id
            let recovered_token_id = client.mint(
                &to,
                &message,
                &signature,
                &recovery_id,
                &expected_token_id,
                &nonce,
            );
            
            // Verify contract returned the correct token_id
            assert_eq!(recovered_token_id, expected_token_id, "Signature {} failed: contract did not recover to expected token_id (recovery_id: {})", idx + 1, recovery_id);
        }
    }
}
