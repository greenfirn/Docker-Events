sudo tee /usr/local/bin/gpu_apply_ocs.sh > /dev/null <<'EOF'
#!/bin/bash
echo "Setting 4070TiS for mining... Keryx"

py-nvtool --setcore 2580 --setcoreoffset 150 --setmemoffset 2000

EOF

# make it executable
sudo chmod +x /usr/local/bin/gpu_apply_ocs.sh

# manual test
sudo /usr/local/bin/gpu_apply_ocs.sh
