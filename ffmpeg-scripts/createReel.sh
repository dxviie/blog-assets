#!/bin/bash

# Default values
input_file=""
start_time=0
duration=""
speed_modifier=1.0
rotation=0
crop_ratio="none"
target_size="original"
quality="medium"
smallest_file=false
skip_prompts=false # Corresponds to -y in PowerShell

# --- Presets ---
declare -A size_presets=(
    ["original"]="original"
    ["256x256"]="256x256"
    ["512x512"]="512x512"
    ["640x640"]="640x640"
    ["720x720"]="720x720"
    ["1024x1024"]="1024x1024"
    ["nHD"]="640x360"
    ["qHD"]="960x540"
    ["HD"]="1280x720"
    ["FHD"]="1920x1080"
    ["2K"]="2048x1080"
    ["UHD"]="3840x2160"
    ["4K"]="4096x2160"
)

declare -A quality_presets=(
    ["high"]=18
    ["medium"]=23
    ["low"]=28
    ["verylow"]=35
)

declare -A rotation_options=(
    ["0"]="No rotation"
    ["90"]="Rotate 90 degrees right (clockwise)"
    ["180"]="Rotate 180 degrees"
    ["270"]="Rotate 90 degrees left (counter-clockwise)"
)

declare -A crop_options=(
    ["none"]="No cropping"
    ["1:1"]="Square (1:1)"
    ["16:9"]="Widescreen (16:9)"
    ["9:16"]="Vertical (9:16)"
)

# --- Helper Functions ---

# Function to check if a key exists in an associative array
key_exists() {
    local key="$1"
    local array_name="$2"
    local cmd="[[ -v ${array_name}[$key] ]]"
    eval "$cmd"
}

# Function to prompt for input if not provided
get_user_input() {
    local prompt="$1"
    local default_value="$2"
    local validator_func="$3" # Function name as string or empty
    local is_required="$4"    # "true" or "false" string

    if [[ "$skip_prompts" == true && -n "$default_value" ]]; then
        echo "$default_value"
        return
    fi

    local input=""
    local valid=false
    while [[ "$valid" == false ]]; do
        read -p "$prompt [default: $default_value]: " input
        if [[ -z "$input" ]]; then
            input="$default_value"
        fi

        if [[ -n "$validator_func" ]]; then
            if $validator_func "$input"; then
                valid=true
            else
                echo "Invalid input. Please try again."
            fi
        else
            valid=true # No validator provided
        fi

        if [[ "$valid" == true && "$is_required" == "true" && -z "$input" ]]; then
            echo "This field is required. Please provide a value."
            valid=false
        fi
    done
    echo "$input"
}

# --- Validators (examples) ---
validate_integer() { [[ "$1" =~ ^[0-9]+$ ]]; }
validate_float() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }
validate_rotation() { key_exists "$1" "rotation_options"; }
validate_crop() { key_exists "$1" "crop_options"; }
validate_size() { key_exists "$1" "size_presets"; }
validate_quality() { key_exists "$1" "quality_presets"; }

# --- Argument Parsing using getopt ---
# Note: Requires GNU getopt. On macOS: brew install gnu-getopt then potentially add to PATH
# Or adjust the script to use built-in getopts (less flexible)
TEMP=$(getopt -o i:s:d:r:q:y --long input:,start:,duration:,rotation:,quality:,speed:,crop:,target:,smallest,yes -n "$0" -- "$@")

if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around '$TEMP': they are essential!
eval set -- "$TEMP"
unset TEMP

while true ; do
    case "$1" in
        -i|--input) input_file="$2" ; shift 2 ;;
        -s|--start) start_time="$2" ; shift 2 ;;
        -d|--duration) duration="$2" ; shift 2 ;;
        --speed) speed_modifier="$2" ; shift 2 ;;
        -r|--rotation) rotation="$2" ; shift 2 ;;
        --crop) crop_ratio="$2" ; shift 2 ;;
        --target) target_size="$2" ; shift 2 ;;
        -q|--quality) quality="$2" ; shift 2 ;;
        --smallest) smallest_file=true ; shift ;;
        -y|--yes) skip_prompts=true ; shift ;;
        --) shift ; break ;;
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

# --- Get User Input if needed ---

if [[ -z "$input_file" ]]; then
    input_file=$(get_user_input "Enter input file path" "" "" "true")
fi

# Check if input file exists
if [[ ! -f "$input_file" ]]; then
    echo "Error: Input file does not exist: $input_file" >&2
    exit 1
fi

# Get start time if not provided or invalid
if ! validate_integer "$start_time"; then
     start_time=$(get_user_input "Enter start time (in seconds)" "0" "validate_integer" "false")
fi

# Get duration if not provided or invalid
if [[ -n "$duration" ]] && ! validate_integer "$duration"; then
    echo "Warning: Invalid duration provided, ignoring."
    duration=""
fi
if [[ -z "$duration" ]]; then
    duration_input=$(get_user_input "Enter duration in seconds (leave empty for full video)" "" "validate_integer" "false")
    if [[ -n "$duration_input" ]]; then
        duration="$duration_input"
    fi
fi

# Get speed modifier if not provided or invalid
if ! validate_float "$speed_modifier"; then
    speed_modifier=$(get_user_input "Enter speed modifier (1.0 = normal speed)" "1.0" "validate_float" "false")
fi

# Get rotation if not provided or invalid
if ! validate_rotation "$rotation"; then
    echo "Rotation options:"
    for key in "${!rotation_options[@]}"; do echo "$key - ${rotation_options[$key]}"; done | sort -n
    rotation=$(get_user_input "Select rotation angle" "0" "validate_rotation" "false")
fi

# Get crop ratio if not provided or invalid
if ! validate_crop "$crop_ratio"; then
    echo "Crop ratio options:"
    for key in "${!crop_options[@]}"; do echo "$key - ${crop_options[$key]}"; done
    crop_ratio=$(get_user_input "Select crop ratio" "none" "validate_crop" "false")
fi

# Get target size if not provided or invalid
if ! validate_size "$target_size"; then
    echo "Target size options:"
    for key in "${!size_presets[@]}"; do echo "$key - ${size_presets[$key]}"; done | sort
    target_size=$(get_user_input "Select target size" "original" "validate_size" "false")
fi

# Override quality if smallest_file is specified
if [[ "$smallest_file" == true ]]; then
    quality="verylow"
    echo "Smallest file requested, setting quality to verylow."
fi

# Get quality if not provided or invalid
if ! validate_quality "$quality"; then
    echo "Quality options:"
    for key in "${!quality_presets[@]}"; do echo "$key - CRF: ${quality_presets[$key]}"; done
    quality=$(get_user_input "Select quality" "medium" "validate_quality" "false")
fi

# --- Construct Output Filename ---
base_name=$(basename "$input_file")
base_name_no_ext="${base_name%.*}" # Remove extension

output_file="${base_name_no_ext}-edited"
if (( start_time > 0 )); then output_file+="-s${start_time}"; fi
if [[ -n "$duration" ]]; then output_file+="-d${duration}"; fi
# Use bc for float comparison
if (( $(echo "$speed_modifier != 1.0" | bc -l) )); then output_file+="-speed${speed_modifier}"; fi
if (( rotation != 0 )); then output_file+="-r${rotation}"; fi
if [[ "$crop_ratio" != "none" ]]; then output_file+="-crop${crop_ratio//:/}"; fi # Replace :
if [[ "$target_size" != "original" ]]; then output_file+="-${target_size}"; fi
if [[ "$quality" != "medium" ]]; then output_file+="-q${quality}"; fi
output_file+=".mp4"

echo "Output file will be: $output_file"

# --- Construct FFmpeg Filters ---
filters=()
is_vertical_rotation=false

# Rotation filter
if (( rotation != 0 )); then
    rotate_filter=""
    case "$rotation" in
        90) rotate_filter="transpose=1"; is_vertical_rotation=true ;; # 90 degrees clockwise
        180) rotate_filter="transpose=2,transpose=2" ;;               # 180 degrees
        270) rotate_filter="transpose=2"; is_vertical_rotation=true ;; # 90 degrees counterclockwise
    esac
    if [[ -n "$rotate_filter" ]]; then
        filters+=("$rotate_filter")
    fi
fi

# Crop filter
if [[ "$crop_ratio" != "none" ]]; then
    crop_filter=""
    case "$crop_ratio" in
        "1:1") crop_filter="crop=min(iw\,ih):min(iw\,ih)" ;; # Square crop
        "16:9") crop_filter="crop=iw:iw*9/16" ;;              # 16:9 crop
        "9:16") crop_filter="crop=ih*9/16:ih" ;;              # 9:16 crop
    esac
    if [[ -n "$crop_filter" ]]; then
        filters+=("$crop_filter")
    fi
fi

# Scale filter - more complex due to potential rotation and 1:1 crop interaction
cropped_size_w=""
cropped_size_h=""

# Get original dimensions if needed for 1:1 crop scaling
if [[ "$crop_ratio" == "1:1" ]] || [[ "$target_size" != "original" ]]; then
    probe_output=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$input_file")
    if [[ $? -ne 0 || -z "$probe_output" ]]; then
        echo "Error: Could not get video dimensions using ffprobe." >&2
        exit 1
    fi
    original_width=$(echo "$probe_output" | cut -d'x' -f1)
    original_height=$(echo "$probe_output" | cut -d'x' -f2)

    if [[ "$crop_ratio" == "1:1" ]]; then
       if (( original_width < original_height )); then
           cropped_size_w=$original_width
           cropped_size_h=$original_width
       else
           cropped_size_w=$original_height
           cropped_size_h=$original_height
       fi
    else # No crop or non-1:1 crop
        cropped_size_w=$original_width
        cropped_size_h=$original_height
    fi

    # Account for rotation affecting the *effective* cropped dimensions before scaling
    if [[ "$is_vertical_rotation" == true ]]; then
        temp_w=$cropped_size_w
        cropped_size_w=$cropped_size_h
        cropped_size_h=$temp_w
    fi
fi

if [[ "$target_size" != "original" ]]; then
    target_dims_str="${size_presets[$target_size]}"
    target_width=$(echo "$target_dims_str" | cut -d'x' -f1)
    target_height=$(echo "$target_dims_str" | cut -d'x' -f2)

    # Only add scale if target differs from (potentially rotated) cropped size
    if [[ -z "$cropped_size_w" ]] || (( target_width != cropped_size_w )) || (( target_height != cropped_size_h )); then
         # Use scale and pad to fit within target dimensions while preserving aspect ratio
        scale_filter="scale=${target_width}:${target_height}:force_original_aspect_ratio=decrease,pad=${target_width}:${target_height}:(ow-iw)/2:(oh-ih)/2:color=black"
        filters+=("$scale_filter")
        echo "Applying scale/pad to ${target_width}x${target_height}"
    else
         echo "Target size matches cropped/rotated size. No scaling needed."
    fi
fi


# FPS and Speed filter
filters+=("fps=24") # Set target FPS
if (( $(echo "$speed_modifier != 1.0" | bc -l) )); then
    filters+=("setpts=PTS/${speed_modifier}")
fi

# Join filters
filter_string=$(printf "%s," "${filters[@]}")
filter_string="${filter_string%,}" # Remove trailing comma

# --- Construct FFmpeg Command ---
crf="${quality_presets[$quality]}"

additional_options=""
if [[ "$smallest_file" == true ]]; then
    # Options for smallest file size
    additional_options="-preset veryslow -b:v 500k -maxrate 500k -bufsize 1000k"
    echo "Using smallest file settings: CRF $crf, maxrate 500k, veryslow preset"
else
    # Default to a faster preset for general use
    additional_options="-preset faster"
    echo "Using quality '$quality': CRF $crf, faster preset"
fi

# Build command array for safety
cmd_array=("ffmpeg")
cmd_array+=("-ss" "$start_time")
if [[ -n "$duration" ]]; then
    cmd_array+=("-t" "$duration")
fi
cmd_array+=("-i" "$input_file")

if [[ -n "$filter_string" ]]; then
     cmd_array+=("-vf" "$filter_string")
fi

cmd_array+=("-c:v" "libx264")
cmd_array+=($additional_options) # Add options as separate elements if they contain spaces
cmd_array+=("-crf" "$crf")

# Audio settings
if [[ "$quality" == "verylow" || "$smallest_file" == true ]]; then
    cmd_array+=("-ac" "1" "-b:a" "64k") # Mono audio, low bitrate
else
    cmd_array+=("-c:a" "aac" "-b:a" "128k") # Default stereo AAC
fi

cmd_array+=("-y" "$output_file") # Overwrite output without asking

# --- Execute Command ---
echo "Executing command:"
printf "%q " "${cmd_array[@]}" # Print quoted command for user
echo # Newline

"${cmd_array[@]}" # Execute the command array

# --- Check Result ---
if [[ $? -eq 0 && -f "$output_file" ]]; then
    # Determine stat command based on OS
    stat_cmd=""
    if [[ "$(uname)" == "Darwin" ]]; then # macOS
        stat_cmd="stat -f %z"
    else # Assuming Linux
        stat_cmd="stat -c %s"
    fi

    original_size_bytes=$($stat_cmd "$input_file")
    new_size_bytes=$($stat_cmd "$output_file")

    # Use bc for floating point calculations
    original_size_mb=$(echo "scale=2; $original_size_bytes / (1024*1024)" | bc -l)
    new_size_mb=$(echo "scale=2; $new_size_bytes / (1024*1024)" | bc -l)

    reduction_percent=0
    if (( $(echo "$original_size_bytes > 0" | bc -l) )); then
        reduction_percent=$(echo "scale=2; (1 - ($new_size_bytes / $original_size_bytes)) * 100" | bc -l)
    fi

    echo "-------------------------------------"
    echo "Video created successfully: $output_file"
    echo "Original size: ${original_size_mb} MB"
    echo "New size: ${new_size_mb} MB"
    echo "Size reduction: ${reduction_percent}%"
    echo "-------------------------------------"
else
    echo "Error: Failed to create video '$output_file'." >&2
    exit 1
fi

exit 0