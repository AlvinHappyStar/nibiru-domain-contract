use cosmwasm_std::{StdError};
use hex::FromHexError;
use thiserror::Error;

#[derive(Error, Debug, PartialEq)]
pub enum ContractError {
    #[error("{0}")]
    Std(#[from] StdError),

    #[error("{0}")]
    Hex(#[from] FromHexError),

    #[error("Unauthorized")]
    Unauthorized {},

    #[error("Disabled")]
    Disabled {},

    #[error("NativeInputZero")]
    NativeInputZero {},

    #[error("Cw20InputZero")]
    Cw20InputZero {},
    
    #[error("TokenTypeMismatch")]
    TokenTypeMismatch {},

    #[error("Name has been taken (name {name})")]
    NameTaken { name: String },

    #[error("Cannot migrate from different contract type: {previous_contract}")]
    CannotMigrate { previous_contract: String },
}
