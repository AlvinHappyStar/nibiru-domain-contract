#!/bin/bash

#Build Flag

NETWORK=testnet
FUNCTION=$1
CATEGORY=$2
PARAM_1=$3
PARAM_2=$4
PARAM_3=$5


export GOPATH=$HOME/go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
	
export PATH=/usr/local/go/bin:$PATH
export PATH=$HOME/go/bin:$PATH


case $NETWORK in
  devnet)
    NODE="http://localhost:26657"
    DENOM=ujunox
    CHAIN_ID=testing
    LP_TOKEN_CODE_ID=1
    WALLET="--from local"
    ADDR_ADMIN=$ADDR_LOCAL
    ;;
  testnet)
    NODE="https://rpc.itn-2.nibiru.fi:443"
    DENOM=unibi
    CHAIN_ID=nibiru-itn-2
    LP_TOKEN_CODE_ID=123
    WALLET="--from testnet-key"
    ADDR_ADMIN="nibi1dg46zswvavn8e6h5y6st34p6j5h3xf5m6ka4q4"
    ;;
  mainnet)
    NODE="https://nibid-rpc.polkachu.com:443"
    DENOM=$DENOM
    CHAIN_ID=comdex-1
    LP_TOKEN_CODE_ID=1
    WALLET="--from testnet-key"
    ADDR_ADMIN="nibi1dg46zswvavn8e6h5y6st34p6j5h3xf5m6ka4q4"
    ;;
esac

NODECHAIN=" --node $NODE --chain-id $CHAIN_ID"
TXFLAG=" $NODECHAIN --fees=2000000$DENOM  --gas=2000000 --gas-adjustment 1.3"




RELEASE_DIR="../release/"
INFO_DIR="../scripts/info/"
INFONET_DIR=$INFO_DIR$NETWORK"/"
CODE_DIR=$INFONET_DIR"code/"
ADDRESS_DIR=$INFONET_DIR"address/"

[ ! -d $RELEASE_DIR ] && mkdir $RELEASE_DIR
[ ! -d $INFO_DIR ] &&mkdir $INFO_DIR
[ ! -d $INFONET_DIR ] &&mkdir $INFONET_DIR
[ ! -d $CODE_DIR ] &&mkdir $CODE_DIR
[ ! -d $ADDRESS_DIR ] &&mkdir $ADDRESS_DIR


FILE_UPLOADHASH=$INFO_DIR"uploadtx.txt"
###################################################################################################
###################################################################################################
###################################################################################################
###################################################################################################
#Environment Functions
CreateEnv() {
    sudo apt-get update && sudo apt upgrade -y
    sudo apt-get install make build-essential gcc git jq chrony -y
    wget https://go.dev/dl/go1.19.9.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go1.19.9.linux-amd64.tar.gz
    rm -rf go1.19.9.linux-amd64.tar.gz

    export GOROOT=/usr/local/go
    export GOPATH=$HOME/go
    export GO111MODULE=on
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    
    rustup default stable
    rustup target add wasm32-unknown-unknown

    git clone https://github.com/sei-protocol/sei-chain
    cd sei-chain
    git fetch
    git checkout v2.0.46
    make install
    cd ../
    rm -rf sei-chain
}

RustBuild() {
    cd ..
    echo "================================================="
    echo "Rust Optimize Build Start"
    
    RUSTFLAGS='-C link-arg=-s' cargo wasm
    cp target/wasm32-unknown-unknown/release/*.wasm ./release/

}

Upload() {
    cd ..
    echo "================================================="
    echo "Upload $CATEGORY"
    UPLOADTX=$(nibid tx wasm store ./release/*.wasm $WALLET $TXFLAG --output json -y | jq -r '.txhash')
    
    echo "Upload txHash:"$UPLOADTX
    
    echo "================================================="
    echo "GetCode"
	CODE_ID=""
    while [[ $CODE_ID == "" ]]
    do 
        sleep 3
        CODE_ID=$(nibid query tx $UPLOADTX $NODECHAIN --output json | jq -r '.logs[0].events[1].attributes[1].value')
    done

    
    echo "Contract Code_id:"$CODE_ID

    cd scripts
    #save to FILE_CODE_ID
    echo $CODE_ID > $CODE_DIR$CATEGORY
}


InstantiateCw20() {
    CODE_CW20=$(cat $CODE_DIR"cw20_base")
    
    TXHASH=$(junod tx wasm instantiate $CODE_CW20 '{"name":"HOLE","symbol":"HOLE","decimals":6,"initial_balances":[{"address":"'$ADDR_ADMIN'","amount":"10000000000"}],"mint":{"minter":"'$ADDR_ADMIN'"},"marketing":{"marketing":"'$ADDR_ADMIN'","logo":{"url":""}}}' --label "HOLEV$CODE_CW20" --admin $ADDR_ADMIN $WALLET $TXFLAG -y --output json | jq -r '.txhash')
    echo $TXHASH
    CONTRACT_ADDR=""
    while [[ $CONTRACT_ADDR == "" ]]
    do
        sleep 3
        CONTRACT_ADDR=$(junod query tx $TXHASH $NODECHAIN --output json | jq -r '.logs[0].events[0].attributes[0].value')
    done
    echo $CONTRACT_ADDR
    echo $CONTRACT_ADDR > $ADDRESS_DIR"cw20_base"
}

InstantiateIncentive() {
    CODE_INCENTIVE=$(cat $CODE_DIR"domain")
    
    TXHASH=$(nibid tx wasm instantiate $CODE_INCENTIVE '{}' --label "domain_$CODE_INCENTIVE" --amount 1$DENOM --admin $ADDR_ADMIN $WALLET $TXFLAG -y --output json | jq -r '.txhash')
    # TXHASH=$(junod tx wasm instantiate $CODE_INCENTIVE '{"stake_token_address":"juno1t46z6hg8vvsena7sue0vg6w85ljar3cundplkre9sz0skeqkap9sxyyy6m", "reward_token_denom":"'$DENOM'", "apys":[{"duration":100000,"rate":10}], "reward_interval":10000}' --label "Incentive$CODE_INCENTIVE" --admin $ADDR_ADMIN $WALLET $TXFLAG -y --output json | jq -r '.txhash')
    echo $TXHASH
    CONTRACT_ADDR=""
    while [[ $CONTRACT_ADDR == "" ]]
    do
        sleep 3
        CONTRACT_ADDR=$(nibid query tx $TXHASH $NODECHAIN --output json | jq -r '.logs[0].events[2].attributes[0].value')
    done
    echo $CONTRACT_ADDR
    echo $CONTRACT_ADDR > $ADDRESS_DIR"domain"
}


ClaimRegister() {
    CONTRACT_INCENTIVE=$(cat $ADDRESS_DIR"domain")
    echo $(nibid tx wasm execute $CONTRACT_INCENTIVE '{"register": {"name": "name3", "duration": 1}}' --amount 1$DENOM --from testnet-key $TXFLAG)
}

ClaimExtend() {
    CONTRACT_INCENTIVE=$(cat $ADDRESS_DIR"domain")
    echo $(nibid tx wasm execute $CONTRACT_INCENTIVE '{"extend": {"name": "name2", "duration": 1}}' --amount 1000000$DENOM --from st $TXFLAG)
}

ClaimTransfer() {
    CONTRACT_INCENTIVE=$(cat $ADDRESS_DIR"domain")
    echo $(nibid tx wasm execute $CONTRACT_INCENTIVE '{"transfer": {"name": "name", "new_owner": "nibi1ev6ssfekarh6qnd469exdephd29u4llx93e39a"}}' --amount 1$DENOM --from testnet-key $TXFLAG)
}

WithDraw() {
    CONTRACT_INCENTIVE=$(cat $ADDRESS_DIR"domain")
    echo $(nibid tx wasm execute $CONTRACT_INCENTIVE '{"withdraw": {}}' --from testnet-key $TXFLAG -y)
}

Stake() {

    MSG='{"stake": {"lock_type": 0}}'
    ENCODEDMSG=$(echo $MSG | base64 -w 0)
    echo $ENCODEDMSG


    CONTRACT_INCENTIVE=$(cat $ADDRESS_DIR"incentive")
    CONTRACT_CW20=$(cat $ADDRESS_DIR"cw20_base")
    junod tx wasm execute $CONTRACT_CW20 '{"send":{"amount":"2000000","contract":"'$CONTRACT_INCENTIVE'","msg":"'$ENCODEDMSG'"}}' $WALLET $TXFLAG -y
    
}

UpdateOwner() {
    CONTRACT_INCENTIVE=$(cat $ADDRESS_DIR"incentive")
    junod tx wasm execute $CONTRACT_INCENTIVE '{"update_owner":{"owner":"'$ADDR_ADMIN'"}}' $WALLET $TXFLAG -y
}

#UpdateEnabled

PrintConfig() {
    CONTRACT_INCENTIVE=$(cat $ADDRESS_DIR"incentive")
    junod query wasm contract-state smart $CONTRACT_INCENTIVE '{"config":{}}' $NODECHAIN
}

MigrateSale() { 
    echo "================================================="
    echo "MigrateSale Contract"
    
    CONTRACT_ADDR=juno1g7v2vrx95uxpwhpdyj6r0qgrlt3kqjqygwp6wy6ayktrklz4v04s06apfn
    echo $CONTRACT_ADDR
    
    
    TXHASH=$(printf "y\npassword\n" | junod tx wasm migrate $CONTRACT_ADDR $(cat $CODE_DIR"incentive") '{}' $WALLET $TXFLAG -y --output json | jq -r '.txhash')
    echo $TXHASH   
    
}


PrintStaker() {
    CONTRACT_INCENTIVE=$(cat $ADDRESS_DIR"incentive")
    junod query wasm contract-state smart $CONTRACT_INCENTIVE '{"staker":{"address":"'$ADDR_ADMIN'"}}' $NODECHAIN
}

#################################################################################
PrintWalletBalance() {
    echo "native balance"
    echo "========================================="
    junod query bank balances $ADDR_ADMIN $NODECHAIN
    echo "========================================="
    echo "BLOCK Token balance"
    echo "========================================="
    junod query wasm contract-state smart $REWARD_TOKEN_ADDRESS '{"balance":{"address":"'$ADDR_ADMIN'"}}' $NODECHAIN
    echo "========================================="
    echo "LP Token balance"
    echo "========================================="
    junod query wasm contract-state smart $STAKE_TOKEN_ADDRESS '{"balance":{"address":"'$ADDR_ADMIN'"}}' $NODECHAIN
}

#################################### End of Function ###################################################
if [[ $FUNCTION == "" ]]; then
    #  RustBuild
    # CATEGORY=domain
    #  Upload
    
    InstantiateIncentive
    # ClaimRegister
    # ClaimExtend
    # WithDraw
    #printf "y\npassword\n" | Upload
    # # CATEGORY=cw20_base
    # # printf "y\npassword\n" | Upload
    
    # # sleep 4
    # # printf "y\npassword\n" | InstantiateCw20
    # sleep 4
    # MigrateSale
    # printf "y\npassword\n" | InstantiateIncentive
    # sleep 4
    # printf "y\npassword\n" | Stake
    # sleep 4

    # PrintConfig
    # sleep 1
    # PrintStaker

else
    $FUNCTION $CATEGORY
fi
