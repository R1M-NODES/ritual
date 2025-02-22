#!/bin/bash

# Підключення загальних функцій та змінних з репозиторію
source <(curl -s https://raw.githubusercontent.com/R1M-NODES/utils/master/common.sh) || { echo "Failed to load common.sh"; exit 1; }

# Відображення логотипу
printLogo

# Запит параметрів у користувача (один раз)
echo -e "Setting Node"
RPC_URL=$(request_param "Press RPC URL")
PRIVATE_KEY=$(request_param "Press your private key")

# Константи
REGISTRY_ADDRESS="0x3B1554f346DFe5c482Bb4BA31b880c1C18412170"
IMAGE="ritualnetwork/infernet-node:1.4.0"

# Оновлення системи та встановлення залежностей
printGreen "Installing system dependencies"
sudo apt update -y && sudo apt install -y mc wget curl git htop netcat net-tools unzip jq \
    build-essential ncdu tmux make cmake clang pkg-config libssl-dev protobuf-compiler bc lz4 screen || { echo "Failed to install dependencies"; exit 1; }

# Встановлення Docker та Docker Compose
printGreen "Installing Docker and Docker Compose"
bash <(curl -s https://raw.githubusercontent.com/R1M-NODES/utils/master/docker-install.sh) || { echo "Failed to install Docker"; exit 1; }

# Встановлення допоміжних скриптів
bash <(curl -s https://raw.githubusercontent.com/R1M-NODES/utils/master/rush-install.sh)
bash <(curl -s https://raw.githubusercontent.com/R1M-NODES/utils/master/ufw.sh)
bash <(curl -s https://raw.githubusercontent.com/R1M-NODES/utils/master/go_install.sh)

# Клонування репозиторію
cd "$HOME" || exit 1
git clone https://github.com/ritual-net/infernet-container-starter && cd infernet-container-starter || { echo "Failed to clone repository"; exit 1; }
cp "$HOME/infernet-container-starter/projects/hello-world/container/config.json" "$HOME/infernet-container-starter/deploy/config.json"

# Конфігурація JSON файлів
configure_json() {
    local file=$1
    sed -i "s|\"rpc_url\": \"[^\"]*\"|\"rpc_url\": \"$RPC_URL\"|" "$file" &&
    sed -i "s|\"private_key\": \"[^\"]*\"|\"private_key\": \"$PRIVATE_KEY\"|" "$file" &&
    sed -i "s|\"registry_address\": \"[^\"]*\"|\"registry_address\": \"$REGISTRY_ADDRESS\"|" "$file" &&
    sed -i 's|"sleep": .*|"sleep": 3,|' "$file" &&
    sed -i 's|"batch_size": .*|"batch_size": 800,|' "$file" &&
    sed -i 's|"trail_head_blocks": .*|"trail_head_blocks": 3,|' "$file" &&
    sed -i 's|"sync_period": .*|"sync_period": 30|' "$file" &&
    sed -i 's|"starting_sub_id": .*|"starting_sub_id": 160000,|' "$file"
}

configure_json "$HOME/infernet-container-starter/deploy/config.json"
configure_json "$HOME/infernet-container-starter/projects/hello-world/container/config.json"

# Конфігурація Deploy.s.sol
sed -i "s|address registry = .*|address registry = $REGISTRY_ADDRESS;|" "$HOME/infernet-container-starter/projects/hello-world/contracts/script/Deploy.s.sol"

# Конфігурація Makefile
MAKEFILE="$HOME/infernet-container-starter/projects/hello-world/contracts/Makefile"
sed -i "s|sender := .*|sender := $PRIVATE_KEY|" "$MAKEFILE"
sed -i "s|RPC_URL := .*|RPC_URL := $RPC_URL|" "$MAKEFILE"

# Конфігурація docker-compose
DOCKER_COMPOSE="$HOME/infernet-container-starter/deploy/docker-compose.yaml"
sed -i "s|ritualnetwork/infernet-node:.*|ritualnetwork/infernet-node:1.4.0|" "$DOCKER_COMPOSE"
sed -i 's|0.0.0.0:4000:4000|0.0.0.0:4321:4000|' "$DOCKER_COMPOSE"
sed -i 's|8545:3000|8845:3000|' "$DOCKER_COMPOSE"
sed -i 's|container_name: infernet-anvil|container_name: infernet-anvil\n    restart: on-failure|' "$DOCKER_COMPOSE"

# Запуск контейнерів
docker compose -f "$DOCKER_COMPOSE" up -d || { echo "Failed to start containers"; exit 1; }

# Встановлення Foundry
printGreen "Installing Foundry"
cd "$HOME" || exit 1
mkdir -p foundry && cd foundry || exit 1
curl -L https://foundry.paradigm.xyz | bash || { echo "Failed to install Foundry"; exit 1; }
echo 'export PATH="$PATH:$HOME/.foundry/bin"' >> "$HOME/.profile"
source "$HOME/.profile"
foundryup || { echo "Failed to update Foundry"; exit 1; }

# Встановлення залежностей контрактів
cd "$HOME/infernet-container-starter/projects/hello-world/contracts/lib/" || exit 1
rm -rf forge-std infernet-sdk
forge install --no-commit foundry-rs/forge-std || exit 1
forge install --no-commit ritual-net/infernet-sdk || exit 1

# Деплой контрактів
cd "$HOME/infernet-container-starter" || exit 1
project=hello-world make deploy-contracts >> logs.txt 2>&1 || { echo "Failed to deploy contracts"; exit 1; }
CONTRACT_ADDRESS=$(grep "Deployed SaysHello" logs.txt | awk '{print $NF}')
rm -f logs.txt

# Оновлення адреси контракту
sed -i "s|0x13D69Cf7d6CE4218F646B759Dcf334D82c023d8e|$CONTRACT_ADDRESS|" "$HOME/infernet-container-starter/projects/hello-world/contracts/script/CallContract.s.sol"

# Виклик контракту
project=hello-world make call-contract || { echo "Failed to call contract"; exit 1; }

# Фінальна конфігурація
cd "$HOME/infernet-container-starter/deploy" || exit 1
docker compose down
sleep 3
sudo rm -f docker-compose.yaml
wget -q https://raw.githubusercontent.com/NodEligible/guides/refs/heads/main/ritual/docker-compose.yaml
docker compose up -d || { echo "Failed to start final containers"; exit 1; }
docker rm -fv infernet-anvil &>/dev/null

printGreen "Installation completed successfully!"
