#[cfg(not(feature = "library"))]
use cosmwasm_std::entry_point;
use cosmwasm_std::{
    attr, to_binary, Addr, Binary, Deps, DepsMut, Env, MessageInfo, Response, StdResult,CosmosMsg, Order
};

use cw2::{set_contract_version};
use crate::error::ContractError;
use crate::msg::{
    ConfigResponse, ExecuteMsg, InstantiateMsg, QueryMsg, NameRecord, AddressRecord, ResolveRecordResponse, ResolveAddressResponse
};

use crate::state::{
    Config, CONFIG, NAMERESOLVER, ADDRRESOLVER
};

use crate::util;
// Version info, for migration info
const CONTRACT_NAME: &str = "domain";
const CONTRACT_VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn instantiate(
    deps: DepsMut,
    _env: Env,
    info: MessageInfo,
    _msg: InstantiateMsg,
) -> StdResult<Response> {
    set_contract_version(deps.storage, CONTRACT_NAME, CONTRACT_VERSION)?;

    let config = Config {
        owner: info.sender.clone(),
        denom: cw20::Denom::Native(info.funds[0].denom.clone()),
        enabled: true,
        amount: 0u128.into(),
    };
    
    CONFIG.save(deps.storage, &config)?;

    Ok(Response::default())
}

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn execute(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    msg: ExecuteMsg,
) -> Result<Response, ContractError> {
    match msg {
        ExecuteMsg::UpdateOwner { owner } => util::execute_update_owner(deps.storage, deps.api, info.sender.clone(), owner),
        ExecuteMsg::UpdateEnabled { enabled } => util::execute_update_enabled(deps.storage, deps.api, info.sender.clone(), enabled),
        ExecuteMsg::Register { name, duration} => execute_register(deps, env, info, name, duration),
        ExecuteMsg::Extend { name, duration} => execute_extend(deps, env, info, name, duration),
        ExecuteMsg::Withdraw { } => execute_withdraw(deps, env, info),
    }
}

pub fn execute_register(
    deps: DepsMut,
    _env: Env,
    info: MessageInfo,
    name: String,
    duration: u64,
) -> Result<Response, ContractError> {

    util::check_enabled(deps.storage)?;

    let key = name.as_bytes();
    let record = NameRecord { owner: info.sender.clone() };


    let expired_date = _env.block.time.seconds() + duration * 365 * 24 * 3600;
    

    if (NAMERESOLVER.may_load(deps.storage, key)?).is_some() {
        // name is already taken
        return Err(ContractError::NameTaken { name });
    }

    let addr_key = info.sender.clone();

    let mut addr_record = match ADDRRESOLVER.may_load(deps.storage, addr_key.clone())? {
        Some(address_records) => address_records,
        None => vec![],
    };

    addr_record.push(AddressRecord{name : name.clone(), expired: expired_date});
    // name is available
    NAMERESOLVER.save(deps.storage, key, &record)?;

    ADDRRESOLVER.save(deps.storage, addr_key, &addr_record)?;

    return Ok(Response::new()
        .add_attributes(vec![
            attr("action", "register"),
            attr("address", record.owner),
            attr("name", name),
        ]));
}

pub fn execute_extend(
    deps: DepsMut,
    _env: Env,
    info: MessageInfo,
    name: String,
    duration: u64,
) -> Result<Response, ContractError> {

    util::check_enabled(deps.storage)?;

    let addr_key = info.sender.clone();

    let mut addr_record = match ADDRRESOLVER.may_load(deps.storage, addr_key.clone())? {
        Some(address_records) => address_records,
        None => vec![],
    };

    for record in &mut addr_record {
        if record.name == name {
            record.expired = record.expired + duration * 365 * 24 * 3600;
            break;
        }
    }

    ADDRRESOLVER.save(deps.storage, addr_key, &addr_record)?;

    return Ok(Response::new()
        .add_attributes(vec![
            attr("action", "register"),
            attr("name", name),
            attr("expired", duration.to_string())
        ]));
}

pub fn execute_withdraw(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
) -> Result<Response, ContractError> {

    util::check_owner(deps.storage, deps.api, info.sender.clone())?;

    let cfg = CONFIG.load(deps.storage)?;
    
    let contract_amount = util::get_token_amount_of_address(deps.querier, cfg.denom.clone(), env.contract.address.clone())?;

    let mut messages:Vec<CosmosMsg> = vec![];
    messages.push(util::transfer_token_message(deps.querier, cfg.denom.clone(), contract_amount, info.sender.clone())?);

    
    return Ok(Response::new()
        .add_messages(messages)
        .add_attributes(vec![
            attr("action", "withdraw"),
            attr("address", info.sender.clone()),
            attr("amount", contract_amount),
        ]));
}


#[cfg_attr(not(feature = "library"), entry_point)]
pub fn query(deps: Deps, env: Env, msg: QueryMsg) -> StdResult<Binary> {
    match msg {
        QueryMsg::Config {} 
            => to_binary(&query_config(deps, env)?),
        QueryMsg::ResolveRecord { name } => to_binary(&query_resolver(deps, name)?),
        QueryMsg::ResolveAddr { address } => to_binary(&query_address_resolver(deps, address)?),
        QueryMsg::ResolveAllAddr { } => to_binary(&query_all_address_resolver(deps)?),        
    }
}

pub fn query_config(deps: Deps, env: Env) -> StdResult<ConfigResponse> {
    let cfg = CONFIG.load(deps.storage)?;
    let treasury_amount = util::get_token_amount_of_address(deps.querier, cfg.denom.clone(), env.contract.address.clone()).unwrap();
    Ok(ConfigResponse {
        owner: cfg.owner,
        amount: treasury_amount,
        denom: cfg.denom,
        enabled: cfg.enabled
    })
}

pub fn query_address_resolver(deps: Deps, address: Addr) -> StdResult<ResolveAddressResponse> {
    // let key = deps.api.addr_validate(&address);

    let list = ADDRRESOLVER.load(deps.storage, address)?;

    Ok(ResolveAddressResponse { list })
}

pub fn query_resolver(deps: Deps, name: String) -> StdResult<ResolveRecordResponse> {
    let key = name.as_bytes();

    let address = match NAMERESOLVER.may_load(deps.storage, key)? {
        Some(record) => Some(String::from(&record.owner)),
        None => None,
    };

    Ok(ResolveRecordResponse { address })
}

pub fn query_all_address_resolver(deps: Deps) -> StdResult<Vec<(Addr, Vec<AddressRecord>)>> {

    let mut all_data: Vec<(Addr, Vec<AddressRecord>)> = Vec::new();

    for item in ADDRRESOLVER.range(deps.storage, None, None, Order::Ascending) {
        let (key, value) = item?;
        all_data.push((key.clone(), value));
    }

    Ok(all_data)
}

