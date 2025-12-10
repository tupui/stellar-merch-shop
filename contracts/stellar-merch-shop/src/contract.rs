//! NFT - NFT binding

use soroban_sdk::{contractimpl, contracttype, panic_with_error, Address, Bytes, BytesN, Env, String};
use soroban_sdk::xdr::ToXdr;
use crate::{errors, events, NFCtoNFTContract, StellarMerchShop, StellarMerchShopArgs, StellarMerchShopClient};

#[contracttype]
pub enum DataKey {
    Admin,
    Nonce,
    NextTokenId,
    MaxTokens,
}

#[contracttype]
pub enum NFTStorageKey {
    ChipNonce(u64),
    Owner(u64),
    PublicKey(u64),
    TokenIdByPublicKey(BytesN<65>),
    Balance(Address),
    Approval(u64),
    ApprovalForAll(Address /* owner */, Address /* operator */),
    Name,
    Symbol,
    URI,
}

#[contractimpl]
impl NFCtoNFTContract for StellarMerchShop {

    fn __constructor(e: &Env, admin: Address, name: String, symbol: String, uri: String, max_tokens: u64) {
        e.storage().instance().set(&DataKey::Admin, &admin);

        e.storage().instance().set(&NFTStorageKey::Name, &name);
        e.storage().instance().set(&NFTStorageKey::Symbol, &symbol);
        e.storage().instance().set(&NFTStorageKey::URI, &uri);

        e.storage().instance().set(&DataKey::MaxTokens, &max_tokens);
        e.storage().instance().set(&DataKey::NextTokenId, &0u64);
    }

    fn mint(
        e: &Env,
        to: Address,
        message: Bytes,
        signature: BytesN<64>,
        recovery_id: u32,
        public_key: BytesN<65>,
        nonce: u32,
    ) -> u64 {
        let mut builder: Bytes = Bytes::new(&e);
        builder.append(&message.clone());
        builder.append(&nonce.clone().to_xdr(&e));
        let message_hash = e.crypto().sha256(&builder);

        let recovered = e.crypto().secp256k1_recover(&message_hash, &signature, recovery_id);
        if recovered != public_key {
            panic_with_error!(&e, &errors::NonFungibleTokenError::InvalidSignature);
        }

        let public_key_lookup = NFTStorageKey::TokenIdByPublicKey(public_key.clone());
        if e
            .storage()
            .persistent()
            .get::<NFTStorageKey, u64>(&public_key_lookup)
            .is_some()
        {
            panic_with_error!(&e, &errors::NonFungibleTokenError::TokenAlreadyMinted);
        }

        let token_id: u64 = e
            .storage()
            .instance()
            .get(&DataKey::NextTokenId)
            .unwrap();
        let max_tokens: u64 = e
            .storage()
            .instance()
            .get(&DataKey::MaxTokens)
            .unwrap();

        if token_id >= max_tokens {
            panic_with_error!(&e, &errors::NonFungibleTokenError::TokenIDsAreDepleted);
        }

        e.storage().instance().set(&DataKey::NextTokenId, &(token_id + 1));
        e.storage().persistent().set(&NFTStorageKey::Owner(token_id), &to);
        e.storage().persistent().set(&NFTStorageKey::PublicKey(token_id), &public_key);
        e.storage().persistent().set(&public_key_lookup, &token_id);
        e.storage().persistent().set(&NFTStorageKey::ChipNonce(token_id), &nonce);

        events::Mint { to, token_id }.publish(&e);

        token_id
    }

    fn balance(e: &Env, owner: Address) -> u32 {
        todo!()
    }

    fn owner_of(e: &Env, token_id: u64) -> Address {
        e.storage().persistent()
        .get(&NFTStorageKey::Owner(token_id))
        .unwrap_or_else(|| panic_with_error!(e, errors::NonFungibleTokenError::NonExistentToken))
    }

    fn transfer(e: &Env, from: Address, to: Address, token_id: u64) {
        let owner = Self::owner_of(e, token_id);
        if owner != from {
            panic_with_error!(e, &errors::NonFungibleTokenError::IncorrectOwner);
        }
        e.storage().persistent().set(&NFTStorageKey::Owner(token_id), &to);
        events::Transfer { from, to, token_id }.publish(e);
    }

    fn transfer_from(e: &Env, spender: Address, from: Address, to: Address, token_id: u64) {
        todo!()
    }

    fn approve(e: &Env, approver: Address, approved: Address, token_id: u64, live_until_ledger: u32) {
        todo!()
    }

    fn approve_for_all(e: &Env, owner: Address, operator: Address, live_until_ledger: u32) {
        todo!()
    }

    fn get_approved(e: &Env, token_id: u64) -> Option<Address> {
        todo!()
    }

    fn is_approved_for_all(e: &Env, owner: Address, operator: Address) -> bool {
        todo!()
    }

    fn get_nonce(e: &Env, token_id: u64) -> u32 {
        e.storage().persistent()
        .get(&NFTStorageKey::ChipNonce(token_id))
        .unwrap_or_else(|| panic_with_error!(e, errors::NonFungibleTokenError::NonExistentToken))
    }

    fn name(e: &Env) -> String {
            e.storage()
            .instance()
            .get(&NFTStorageKey::Name)
            .unwrap()
    }

    fn symbol(e: &Env) -> String {
            e.storage()
            .instance()
            .get(&NFTStorageKey::Symbol)
            .unwrap()
    }

    fn token_uri(e: &Env, token_id: u64) -> String {
        // Verify token exists
        let _owner = Self::owner_of(e, token_id);

        let base_uri: String = e
            .storage()
            .instance()
            .get(&NFTStorageKey::URI)
            .unwrap();

        // Construct URI: {base_uri}/{token_id}
        let mut uri_bytes = Bytes::new(e);
        uri_bytes.append(&Bytes::from(base_uri));
        uri_bytes.append(&Bytes::from_slice(e, b"/"));
        uri_bytes.append(&Bytes::from_array(e, &token_id.to_be_bytes()));

        String::from(uri_bytes)
    }

}
