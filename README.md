-- Docker Events watcher --
- start/stop mining with active idle job Clore / Octaspace

- main build install scripts in source folder
- for ubuntu server 24.04 use image "ubuntu:24.04" as placeholder idle job
- on Clore / Octaspace or set something different in .conf
- batch files can be used to send new .conf files to a list of rigs from windows pc
- services assume .conf files are in /home/user/ and named rig-cpu.conf or rig-gpu.conf

- start/stop/pause idle job and watch logs to test...
- sudo journalctl -u docker_events_cpu.service -f
- sudo journalctl -u docker_events_gpu.service -f

- miners load in screen session by name of miner by default
- sudo screen -ls to list active sessions
- sudo screen -r name to re-open session
- ctrl a+d to leave session with miner runnning
- ctrl c to stop miner
- exit to close screen session

- if you dont want to use auto cpu threads -1 and affinity then dont add %CPU_THREADS% to your args
- see rig conf examples...

Some portions of this project were developed with assistance from ChatGPT.
