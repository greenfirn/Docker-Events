if [[ "$ALGO" == "warthog" ]]; then
    echo "Using warthog settings"
    # Compute Warthog target
    if [ "$TOTAL_THREADS" -ge 32 ]; then
        WARTHOG_TARGET=47000000
    elif [ "$TOTAL_THREADS" -ge 24 ]; then
        WARTHOG_TARGET=37000000
    else
        WARTHOG_TARGET=30000000
    fi
	
	ARGS="${ARGS//%WARTHOG_TARGET%/$WARTHOG_TARGET}"
fi