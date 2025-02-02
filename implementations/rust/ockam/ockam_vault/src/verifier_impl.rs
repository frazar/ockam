use crate::software_vault::SoftwareVault;
use crate::xeddsa::XEddsaVerifier;
use crate::VaultError;
use arrayref::array_ref;
use ockam_core::Result;
use ockam_core::{async_trait, compat::boxed::Box};
use ockam_vault_core::{PublicKey, Signature, Verifier, CURVE25519_PUBLIC_LENGTH};

#[async_trait]
impl Verifier for SoftwareVault {
    /// Verify signature with xeddsa algorithm. Only curve25519 is supported.
    async fn verify(
        &mut self,
        signature: &Signature,
        public_key: &PublicKey,
        data: &[u8],
    ) -> Result<bool> {
        // TODO: Add public key type
        if public_key.as_ref().len() == CURVE25519_PUBLIC_LENGTH && signature.as_ref().len() == 64 {
            let signature_array = array_ref!(signature.as_ref(), 0, 64);
            return Ok(x25519_dalek::PublicKey::from(*array_ref!(
                public_key.as_ref(),
                0,
                CURVE25519_PUBLIC_LENGTH
            ))
            .verify(data.as_ref(), signature_array));
        }

        #[cfg(feature = "bls")]
        if public_key.as_ref().len() == 96 && signature.as_ref().len() == 112 {
            use signature_bbs_plus::MessageGenerators;
            use signature_bbs_plus::Signature as BBSSignature;
            use signature_core::lib::Message;

            let bls_public_key =
                ::signature_bls::PublicKey::from_bytes(array_ref!(public_key.as_ref(), 0, 96))
                    .unwrap();
            let generators = MessageGenerators::from_public_key(bls_public_key, 1);
            let messages = [Message::hash(data.as_ref())];
            let signature_array = array_ref!(signature.as_ref(), 0, 112);
            let signature_bbs = BBSSignature::from_bytes(signature_array).unwrap();
            let res = signature_bbs.verify(&bls_public_key, &generators, messages.as_ref());
            return Ok(res.unwrap_u8() == 1);
        }

        Err(VaultError::InvalidPublicKey.into())
    }
}
