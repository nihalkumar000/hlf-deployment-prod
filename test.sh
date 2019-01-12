docker exec -it cli peer chaincode invoke -o orderer0.example.com:7050 -n mycc -c '{"Args":["set", "a", "20"]}' -C mychannel
docker exec -it cli peer chaincode query -n mycc -c '{"Args":["query","a"]}' -C mychannel
