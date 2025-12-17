# supossed to replicate putting [0,2,...] cores in config, idk if this is done correctly for sure

TOTAL_THREADS=$(nproc)
CPU_THREADS=$((TOTAL_THREADS - 1))

if [[ "$MINER_NAME" == "xmrig" ]]; then

    if [[ "$ALGO" == "rx/0" ]]; then

        RX_THREADS=-1

        if [[ "$TOTAL_THREADS" -eq 32 ]]; then

            RX_THREADS=31
            RX_CORES=(0 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31)

        elif [[ "$TOTAL_THREADS" -eq 24 ]]; then

            RX_THREADS=23
            RX_CORES=(0 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23)

        fi

        # ===========================
        # Build affinity mask OR fallback
        # ===========================
        if [[ "$RX_THREADS" -eq -1 ]]; then

            ARGS="${ARGS//%CPU_THREADS%/$CPU_THREADS}"

        else
            BITMASK=0
            for core in "${RX_CORES[@]}"; do
                (( BITMASK |= (1 << core) ))
            done

            RX_MASK=$(printf "0x%X" "$BITMASK")
            AUTOFILL_CPU="$RX_THREADS --cpu-affinity=$RX_MASK"

            ARGS="${ARGS//%CPU_THREADS%/$AUTOFILL_CPU}"
        fi
    else
        # Non-rx/0 xmrig
        ARGS="${ARGS//%CPU_THREADS%/$CPU_THREADS}"
    fi
else
    # Not xmrig
    ARGS="${ARGS//%CPU_THREADS%/$CPU_THREADS}"
fi
