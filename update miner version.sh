# -- to update miner versions write miner.conf --

sudo tee /home/user/miner.conf > /dev/null <<'EOF'
XMRIG_VERSION        ALL "6.24.0"
BZMINER_VERSION      ALL "v23.0.2"
WILDRIG_VERSION      ALL "0.47.9"
SRBMINER_VERSION     ALL "3.0.6"
RIGEL_VERSION        ALL "1.23.0"
LOLMINER_VERSION     ALL "1.98"
ONEZEROMINER_VERSION ALL "1.7.3"
GMINER_VERSION       ALL "3.44"
EOF
