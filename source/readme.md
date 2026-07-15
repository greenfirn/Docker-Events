1. 'write - script files--LATEST...'
2. 'write - api.conf'
3. 'write - miner_conf.sh'
4. 'no-container-docker_events_monitor--LATEST...', clore, etc
5. 'write - rig-gpu.sh' / 'keryx-custom_miner-rig-gpu.sh' / 'peakminer-custom-gpu.sh' ... rig conf examples
6. 'py-nvtool/py-nvtool.txt' -- 'gpu_reset - Nvidia-py-nvtool.sh', 'apply'

-- naming/layout may have changed --

no-container-docker_events_monitor-clore.sh ... run idle job parallel with clore idle job (empty script ubuntu image etc)

podman_events_monitor.sh ... Nosana podman containers

no-docker_launcher.sh ... same miner conf,api,etc for no docker mining rigs

keryx-dummy-cpu-service.sh ... keryx-miner service named same as cpu service for easy dashboard control on gpu only mining rig
