## https://github.com/Akisoft41/py-nvtool/releases

sudo tee /usr/local/bin/gpu_apply_ocs.sh > /dev/null <<'EOF'
#!/bin/bash
echo "Setting 4070TiS for mining... Keryx"

py-nvtool --setcore 2580 --setcoreoffset 150 --setmem 0 --setmemoffset 2000

EOF

# make it executable
sudo chmod +x /usr/local/bin/gpu_apply_ocs.sh

# manual test
sudo /usr/local/bin/gpu_apply_ocs.sh



sudo tee /usr/local/bin/gpu_apply_ocs.sh > /dev/null <<'EOF'
#!/bin/bash
echo "Setting 4070TiS for mining... Keryx"

py-nvtool --setcore 2100 --setcoreoffset 300 --setmem 0 --setmemoffset 2000
EOF

# make it executable
sudo chmod +x /usr/local/bin/gpu_apply_ocs.sh

# manual test
sudo /usr/local/bin/gpu_apply_ocs.sh
