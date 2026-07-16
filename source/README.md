** fixed log trim, was just stopping at 10mb 'no-container-docker_events_monitor--LATEST.sh' **

-- 'rig-confs/keryx-custom-rig-gpu.sh' creates huge log file while install/download model --

'no-container-docker_events_monitor--LATEST...' is most recent updated, others may not work as is

-- naming/layout may have changed for clore, nosana, etc --

1. 'write - script files--LATEST...' (see source/lib to explore original seperate files)
2. 'write - api.conf' -- api settings
3. 'write - miner_conf.sh' -- miner versions
4. 'no-docker_launcher.sh' or 'no-container-docker_events_monitor--LATEST', clore, etc
5. 'rig-confs' -- "flightsheets"
6. 'py-nvtool/py-nvtool.txt' -- 'overclocks'

'no-container-docker_events_monitor--LATEST...' for octaspace

'source/manual_start_gpu.sh', 'source/manual_stop_gpu.sh' another option for octaspace start/stop idle miner (sudo manual_...)

'no-container-docker_events_monitor-clore.sh' ... run idle job parallel with clore idle job (empty script ubuntu image etc)

'podman_events_monitor.sh' ... Nosana podman containers

'no-docker_launcher.sh' ... same miner conf,api,etc for no docker mining rigs

'keryx-dummy-cpu-service.sh' ... keryx-miner service named same as cpu service for easy dashboard control on gpu only mining rig
