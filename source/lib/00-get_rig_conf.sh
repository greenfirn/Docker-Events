get_rig_conf() {
    local default_oc_file="/home/user/rig-cpu.conf"

    # Safe checks under set -u
    if [[ -n "${oc_file:-}" ]]; then
        cfg_file="$oc_file"
    elif [[ -n "${OC_FILE:-}" ]]; then
        cfg_file="$OC_FILE"
    else
        cfg_file="$default_oc_file"
    fi

    local key="$1"     # e.g., TARGET_IMAGE
    local gpu_id="$2"  # usually "0" in your examples

    # If file missing, return empty
    [[ ! -f "$cfg_file" ]] && echo "" && return

    local selected_value=""
    local file_key file_gpu rest_of_line value

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