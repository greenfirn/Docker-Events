'03-cpu_threads.sh': xmrig 'rx/0' ... %THREADS% in cmd will also add affinity with '0,2,3,etc' 1 off

'04-algo_config.sh': bzminer... %WARTHOG_TARGET% in cmd

'02-load_configs.sh': Worker name from hostname, upper case rig name x,t,s

WORKER_NAME="$(cat /etc/hostname)"

WORKER_NAME="${WORKER_NAME//x/X}"

WORKER_NAME="${WORKER_NAME//t/T}"

WORKER_NAME="${WORKER_NAME//s/S}"
