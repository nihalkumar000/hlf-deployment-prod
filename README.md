# Fabric Network

This project contains the production ready hyperldger fabric deployment
configurations. Following is the network structure

```
1. one org (org1)
2. three peers (peer0.org1.example.com, peer1.org1.example.com, peer2.org1.example)
3. one ca
4. three oreders with kafka
```

Following are the steps to confire and deploy the cluster

## 1. Generate configs

### 1.1 Setup Env

In order to generate certificates, genesis block, channel config transactions
we need to use scripts on `bin` directory. Need add bin to $PATH and define the
config path

```
export PATH=${PWD}/bin:${PWD}:$PATH
export FABRIC_CFG_PATH=${PWD}/config
```

### 1.2 Generate crypto

Now we need to generate crypto metirials for our orders, peers, ca etc. 

```
cryptogen generate --config=./config/crypto-config.yaml
```

### 1.3 Generate genisis block 

Need to generate genesis block for orders

```
configtxgen -profile OneOrgsOrdererGenesis -outputBlock ./config/orderer.block
```

### 1.4 generate channel configuration transaction

```
configtxgen -profile OneOrgsChannel -outputCreateChannelTx ./config/channel.tx -channelID mychannel
```

###1.5 generate anchor peer transaction 

Need to generate anchor peer transactions for each org. In his case we have
only org1, if there are mutiple orgs, do this step for all orgs(ex org1, org2 etc)

```
configtxgen -profile OneOrgsChannel -outputAnchorPeersUpdate ./config/Org1MSPanchors.tx -channelID mychannel -asOrg Org1MSP
```

## 2. Deploy dockers

### 2.1 Add ca certificate info

Before start the services with docker compose, we need to add the CA certificate
configs which generated via cryptogen to ca service defines in
`docker-compose-kafka.yaml`. CA certificates and keys can be found in
`crypto/peerOrganizations/org1.example.com/ca` directory

```
# defines certificate autorities ca file, this file generates by cryptogen
- FABRIC_CA_SERVER_CA_CERTFILE=/etc/hyperledger/fabric-ca-server-config/ca.org1.example.com-cert.pem

# defines certificate authorities key file, this files generates by cryptogen
- FABRIC_CA_SERVER_CA_KEYFILE=/etc/hyperledger/fabric-ca-server-config/73c0730c0661b906fd6e266407e7a1d0f40b26ab1d5e3ea3155bb6e82688188a_sk
```

### 2.2 Start network

Now we can start the fabric network and cli container

```
docker-compose -f deployment/docker-compose-kafka.yaml up -d
docker-compose -f deployment/docker-compose-cli.yaml up -d
```

## 3 Setup channel

### 3.1 create channel

We are creating the channel with using channel.tx which generates previously 
on 2nd section. 

```
docker exec -e "CORE_PEER_LOCALMSPID=Org1MSP" -e "CORE_PEER_MSPCONFIGPATH=/var/hyperledger/users/Admin@org1.example.com/msp" peer0.org1.example.com peer channel create -o orderer0.example.com:7050 -c mychannel -f /var/hyperledger/configs/channel.tx
```

Next we need to join all of our peers(3 peers) into this channel.  

### 3.2 Join peer0 to channel

```
docker exec -e "CORE_PEER_LOCALMSPID=Org1MSP" -e "CORE_PEER_MSPCONFIGPATH=/var/hyperledger/users/Admin@org1.example.com/msp" peer0.org1.example.com peer channel join -b mychannel.block
```

### 3.3 Copy mychannel.block 

when creating channel with peero.org1.example.com, it generates `mychanell.block` 
file inside peer0.org1.example.com container, we need to copy that file into 
`peer1.org1.example.com` and `peer2.org1.example.com` containers inorder to peer1
and peer2 to join the channel. I'm use `docker cp` command here
for it

```
docker cp peer0.org1.example.com:/mychannel.block .
docker cp mychannel.block peer1.org1.example.com:/mychannel.block
docker cp mychannel.block peer2.org1.example.com:/mychannel.block
rm mychannel.block
```

if you use cli container to create channel and join peers, you don't need to copy
the files - https://hyperledger-fabric.readthedocs.io/en/stable/install_instantiate.html

### 3.4 Join peer1 to channel

```
docker exec -e "CORE_PEER_LOCALMSPID=Org1MSP" -e "CORE_PEER_MSPCONFIGPATH=/var/hyperledger/users/Admin@org1.example.com/msp" peer1.org1.example.com peer channel join -b mychannel.block
```

### 3.5 Join pee2 to channel


## 4. Install chaincode

NOw we need to install chaincode which resides on `chaincode` directory on all
peers. WE are using cli container to install the chaincode. We need to define cli
container connecting peer to install the chaincode on each peer. COnnecting
peers defines with `CORE_PEER_ADDRESS` env varirable on cli container

```
- CORE_PEER_ADDRESS=peer1.org1.example.com:7051
```

### 4.1. Install on peer0 

```
# define connecting peer to peer0 on docker-compose-cli 
- CORE_PEER_ADDRESS=peer0.org1.example.com:7051

# install chaincode
docker exec -it cli peer chaincode install -n mycc -p github.com/chaincode -v v0
```

### 4.2 Install on peer1 

```
# define connecting peer to peer1 on docker-compose-cli 
- CORE_PEER_ADDRESS=peer1.org1.example.com:7051

# install chaincode
docker exec -it cli peer chaincode install -n mycc -p github.com/chaincode -v v0
```

### 4.3 Install on peer2

```
# define connecting peer to peer2 on docker-compose-cli 
- CORE_PEER_ADDRESS=peer2.org1.example.com:7051

# install chaincode
docker exec -it cli peer chaincode install -n mycc -p github.com/chaincode -v v0
```

## Instantiate chaincode

Now we need to instatiate chaincode on channel. No need to do this with each
and every peer, only need to do once on the channel.

```
docker exec -it cli peer chaincode instantiate -o orderer0.example.com:7050 -C mychannel -n mycc github.com/chaincode -v v0 -c '{"Args": ["a", "100"]}'
```

## 5. Do transactions 

Now our network is ready we can do invoke/query transactions with the installed 
chaincode 

### 5.1 Invoke

With `invoke` chaincode can modify the state of the variables in ledger. Each 
'invoke' transaction will be added to the 'block' in the ledge (update ledger state).

You can connect to any peer and do invoke/query transations. IN here I'm
connected to peer0 and executed below invoke transaction

```
# added - CORE_PEER_ADDRESS=peer0.org1.example.com:7051 in cli container
docker exec -it cli peer chaincode invoke -o orderer0.example.com:7050 -n mycc -c '{"Args":["set", "a", "20"]}' -C mychannel
```

### 5.2 Query 

With `query` chain code will read the current state and send it back to user. This 
transaction is not saved in blockchain (not update ledger state)

Now I'm execuring this query by connecting to peer2

```
# added - CORE_PEER_ADDRESS=peer1.org1.example.com:7051 in cli container
docker exec -it cli peer chaincode query -n mycc -c '{"Args":["query","a"]}' -C mychannel
```
