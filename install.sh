#!/bin/bash

# Підключення загальних функцій та змінних з репозиторію
source <(curl -s https://raw.githubusercontent.com/R1M-NODES/utils/master/common.sh) || { echo "Failed to load common.sh"; exit 1; }

# Відображення логотипу
printLogo

echo -e "${YELLOW}Setting Node${NC}"

# Заміна на стандартний спосіб введення параметрів
echo -n "Press RPC URL: "
read RPC_URL

echo -n "Press you privat key: "
read PRIVATE_KEY

[[ "$PRIVATE_KEY" =~ ^0x ]] || exit 1

REGISTRY_ADDRESS="0x3B1554f346DFe5c482Bb4BA31b880c1C18412170"
IMAGE="ritualnetwork/infernet-node:1.4.0"
HOME_DIR="$HOME/infernet-container-starter"

update() {
    sudo apt update -y
}

install_main() {
    sudo apt update -y
    sudo apt install mc wget curl git htop netcat net-tools unzip jq build-essential ncdu tmux make cmake clang pkg-config libssl-dev protobuf-compiler bc lz4 screen -y
}

install_ufw() {
    bash <(curl -s https://raw.githubusercontent.com/R1M-NODES/utils/master/ufw.sh)
}

install_docker() {
    bash <(curl -s https://raw.githubusercontent.com/R1M-NODES/utils/master/docker-install.sh)
}

update
install_main
install_ufw
install_docker

cd "$HOME"
git clone https://github.com/ritual-net/infernet-container-starter
cd "$HOME_DIR"
cp "$HOME_DIR/projects/hello-world/container/config.json" "$HOME_DIR/deploy/config.json"

configure_json() {
    local file="$1"
    sed -i "s|\"rpc_url\": \"[^\"]*\"|\"rpc_url\": \"$RPC_URL\"|" "$file"
    sed -i "s|\"private_key\": \"[^\"]*\"|\"private_key\": \"$PRIVATE_KEY\"|" "$file"
    sed -i "s|\"registry_address\": \"[^\"]*\"|\"registry_address\": \"$REGISTRY_ADDRESS\"|" "$file"
    sed -i 's|"sleep": .*|"sleep": 3,|' "$file"
    sed -i 's|"batch_size": .*|"batch_size": 800,|' "$file"
    sed -i 's|"trail_head_blocks": .*|"trail_head_blocks": 3,|' "$file"
    sed -i 's|"sync_period": .*|"sync_period": 30|' "$file"
    sed -i 's|"starting_sub_id": .*|"starting_sub_id": 160000,|' "$file"
}

configure_json "$HOME_DIR/deploy/config.json"
configure_json "$HOME_DIR/projects/hello-world/container/config.json"

sed -i "s|address registry = .*|address registry = $REGISTRY_ADDRESS;|" "$HOME_DIR/projects/hello-world/contracts/script/Deploy.s.sol"
MAKEFILE="$HOME_DIR/projects/hello-world/contracts/Makefile"
sed -i "s|sender := .*|sender := $PRIVATE_KEY|" "$MAKEFILE"
sed -i "s|RPC_URL := .*|RPC_URL := $RPC_URL|" "$MAKEFILE"

DOCKER_COMPOSE="$HOME_DIR/deploy/docker-compose.yaml"
sed -i "s|ritualnetwork/infernet-node:.*|$IMAGE|" "$DOCKER_COMPOSE"
sed -i 's|0.0.0.0:4000:4000|0.0.0.0:4321:4000|' "$DOCKER_COMPOSE"
sed -i 's|8545:3000|8845:3000|' "$DOCKER_COMPOSE"
sed -i 's|container_name: infernet-anvil|container_name: infernet-anvil\n    restart: on-failure|' "$DOCKER_COMPOSE"

docker compose -f "$DOCKER_COMPOSE" up -d

cd "$HOME"
mkdir -p foundry
cd foundry
curl -L https://foundry.paradigm.xyz | bash
echo 'export PATH="$PATH:$HOME/.foundry/bin"' >> "$HOME/.profile"
source "$HOME/.profile"
foundryup

cd "$HOME_DIR/projects/hello-world/contracts/lib/"
rm -rf forge-std infernet-sdk
forge install --no-commit foundry-rs/forge-std
forge install --no-commit ritual-net/infernet-sdk

cd "$HOME_DIR"
project=hello-world make deploy-contracts >> logs.txt 2>&1
CONTRACT_ADDRESS=$(grep "Deployed SaysHello" logs.txt | awk '{print $NF}')
rm -f logs.txt

[ -z "$CONTRACT_ADDRESS" ] && exit 1

echo -e "${GREEN} Your contract address $CONTRACT_ADDRESS${NC}"
sed -i "s|0x13D69Cf7d6CE4218F646B759Dcf334D82c023d8e|$CONTRACT_ADDRESS|" "$HOME_DIR/projects/hello-world/contracts/script/CallContract.s.sol"

project=hello-world make call-contract

cd "$HOME_DIR/deploy"
docker compose down
sleep 3
sudo rm -f docker-compose.yaml
wget -q https://raw.githubusercontent.com/NodEligible/guides/refs/heads/main/ritual/docker-compose.yaml
docker compose up -d
docker rm -fv infernet-anvil &>/dev/null

echo -e "${GREEN}Ritual успешно установлен!${NC}"
