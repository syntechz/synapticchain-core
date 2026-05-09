#!/bin/bash
set -e
echo "Installing SynapticChain API Gateway..."
if ! command -v node &> /dev/null; then
    echo "Node.js not found. Install: curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs"
    exit 1
fi
if ! command -v redis-cli &> /dev/null; then
    echo "Installing Redis..."
    apt-get update && apt-get install -y redis-server
    systemctl enable redis-server
    systemctl start redis-server
fi
npm install
mkdir -p logs
if command -v pm2 &> /dev/null; then
    pm2 start pm2.config.js
    pm2 save
else
    echo "Starting with node (install PM2 for production: npm i -g pm2)..."
    nohup node server.js > logs/gateway.log 2>&1 &
fi
echo "Gateway installed! Test: curl http://localhost:8080/health"
