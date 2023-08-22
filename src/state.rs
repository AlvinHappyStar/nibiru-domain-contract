use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use cosmwasm_std::{Addr, Uint128};
use crate::msg::{
    NameRecord, AddressRecord
};

use cw_storage_plus::{Item, Map};
use cw20::Denom;


#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, JsonSchema)]
pub struct Config {
    /// Owner If None set, contract is frozen.
    pub owner: Addr,
    pub denom: Denom,
    pub enabled: bool,
    pub amount: Uint128
}

pub const CONFIG_KEY: &str = "config";
pub const CONFIG: Item<Config> = Item::new(CONFIG_KEY);

pub const RESOLVE_KEY: &str = "NAMERESOLVER";
pub const NAMERESOLVER: Map<&[u8], NameRecord> = Map::new(RESOLVE_KEY);

pub const ADDR_RESOLVE_KEY: &str = "ADDRRESOLVER";
pub const ADDRRESOLVER: Map<Addr, Vec<AddressRecord>> = Map::new(ADDR_RESOLVE_KEY);