sudo tee /usr/local/bin/gpu_apply_ocs.sh > /dev/null <<'EOF'
#!/bin/bash
echo "Setting 3090 for mining... Keryx"

py-nvtool --setcore 1650 --setcoreoffset 200 --setmemoffset 1000

EOF

# make it executable
sudo chmod +x /usr/local/bin/gpu_apply_ocs.sh

# manual test
sudo /usr/local/bin/gpu_apply_ocs.sh
