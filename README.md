-- Docker Events watcher --
- install scripts in source folder 

- start/stop mining when idle job active Clore / Octaspace --
- batch files can be used to send new .conf files to a list of rigs from windows pc
- services assume .conf files are in /home/user/ and named rig-cpu.conf or rig-gpu.conf
- use "ubuntu:24.04" on Clore / Octaspace as idle job with no options ... or set something different in .conf

- pause/stop idle job and watch logs to test...
- 'sudo journalctl -u docker_events_cpu.service -f' or 'sudo journalctl -u docker_events_gpu.service -f'

- miners load in screen session...
- attach using .. sudo screen -r 'miner name by default'

- if you dont use %CPU_THREADS% in your .conf then auto cpu threads/affinity will not get added to the final cmd
- see rig conf examples...

Some portions of this project were developed with assistance from ChatGPT.
