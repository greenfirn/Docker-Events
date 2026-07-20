xmrig: '03-cpu_threads.sh' ... %THREADS% in cmd will also add affinity with '0,2,3,etc' 1 off

if [[ "$MINER_NAME" == "xmrig" && "$ALGO" == "rx/0" ]]; then

bzminer: '04-algo_config.sh' ... some warthog presets

upper case rig names:

Worker name from hostname, normalized:

WORKER_NAME="$(cat /etc/hostname)"

WORKER_NAME="${WORKER_NAME//x/X}"

WORKER_NAME="${WORKER_NAME//t/T}"

WORKER_NAME="${WORKER_NAME//s/S}"
