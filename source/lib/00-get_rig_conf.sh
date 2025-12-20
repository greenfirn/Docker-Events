get_rig_conf() {

    local key=""
    local gpu_id=""
    local cfg_file=""

    # -------------------------------------------------
    # Signature normalization
    #
    # get_rig_conf KEY GPU
    # get_rig_conf FILE KEY GPU
    # -------------------------------------------------
    if [[ $# -eq 2 ]]; then
        cfg_file="$CFG_FILE"
        key="$1"
        gpu_id="$2"
    elif [[ $# -eq 3 ]]; then
        cfg_file="$1"
        key="$2"
        gpu_id="$3"
    else
        echo "[get_rig_conf] Invalid arguments" >&2
        return 1
    fi

    [[ -f "$cfg_file" ]] || { echo ""; return; }

    local selected_value=""
    local file_key file_gpu rest value

    # Read key, gpu, and rest of line into rest_of_line
    while read -r file_key file_gpu rest_of_line; do

        # Skip empty or comment lines
        [[ -z "$file_key" || "$file_key" =~ ^# ]] && continue

        # Skip non-matching keys
        [[ "$file_key" != "$key" ]] && continue

        # Everything after 2nd column is the value
        value="$rest_of_line"

        # Remove surrounding quotes
        value="${value#\"}"
        value="${value%\"}"

        # GPU-specific match overrides ALL
        if [[ "$file_gpu" == "$gpu_id" ]]; then
            selected_value="$value"
            break
        fi

        # ALL fallback
        if [[ "$file_gpu" == "ALL" ]]; then
            selected_value="$value"
        fi

    done < "$cfg_file"

    echo "$selected_value"
}