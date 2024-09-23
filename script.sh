#!/bin/sh

CONSOLIDATED_LOG="smartctl_full_log.txt"
SUMMARY_LOG="smartctl_summary_log.txt"

# Function to check if sudo is installed
check_sudo() {
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        SUDO=""
    fi
}

# Function to run smartctl short test
run_smartctl_test() {
    DEVICE=$1
    echo "Running smartctl test on $DEVICE"
    $SUDO smartctl -t short "$DEVICE"
}

# Function to run smartctl -a and save the output to a file
run_smartctl_a() {
    DEVICE=$1
    LOG_FILE=$2

    echo "Saving smartctl output of $DEVICE to $LOG_FILE"
    $SUDO smartctl -a "$DEVICE" > "$LOG_FILE"
}

# Function to extract specific data from the smartctl output and store it in a log file
# Function to extract specific data from the smartctl output and store it in a log file
extract_smartctl_info() {
    FULL_LOG=$1
    OUTPUT_LOG=$2
    DEVICE_NAME=$3

    echo "==== Extracting Data for $DEVICE_NAME ====" >> "$OUTPUT_LOG"

    # Extract fixed fields
    MODEL_FAMILY=$(grep -i 'Model Family' "$FULL_LOG" | awk -F: '{print $2}' | xargs)
    DEVICE_MODEL=$(grep -i 'Device Model' "$FULL_LOG" | awk -F: '{print $2}' | xargs)
    SERIAL_NUMBER=$(grep -i 'Serial Number' "$FULL_LOG" | awk -F: '{print $2}' | xargs)

    # Corrected extraction for Power_On_Hours and Lifetime_Writes_GiB
    POWER_ON_HOURS=$(grep -i 'Power_On_Hours' "$FULL_LOG" | awk '{print $10}' | xargs)
    LIFETIME_WRITES_GIB=$(grep -i 'Lifetime_Writes_GiB' "$FULL_LOG" | awk '{print $10}' | xargs)

    # Append extracted values to the summary log
    echo "Model Family: ${MODEL_FAMILY:-N/A}" >> "$OUTPUT_LOG"
    echo "Device Model: ${DEVICE_MODEL:-N/A}" >> "$OUTPUT_LOG"
    echo "Serial Number: ${SERIAL_NUMBER:-N/A}" >> "$OUTPUT_LOG"
    echo "Power On Hours: ${POWER_ON_HOURS:-N/A}" >> "$OUTPUT_LOG"

    # Write data handling (Host Writes or Lifetime Writes in GiB)
    if [ -n "$LIFETIME_WRITES_GIB" ]; then
        echo "Lifetime Writes (GiB): $LIFETIME_WRITES_GIB" >> "$OUTPUT_LOG"
    else
        echo "Write Data: N/A" >> "$OUTPUT_LOG"
    fi

    echo "==== End of Data for $DEVICE_NAME ====" >> "$OUTPUT_LOG"
    echo "" >> "$OUTPUT_LOG"
}


# Main script execution

# Check if /etc/os-release file exists
if [ -f /etc/os-release ]; then
    # Source the /etc/os-release file to get environment variables
    . /etc/os-release

    # Extract the OS name and version
    OS_NAME=$(echo "$NAME" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
    OS_INFO="$VERSION_ID"

    # Check if sudo is available
    check_sudo

    # Install smartmontools based on the detected OS
    if [ "$OS_NAME" = "ubuntu" ]; then
        echo "Ubuntu detected. Version: $OS_INFO"
        $SUDO apt update
        $SUDO apt install -y smartmontools
    elif [ "$OS_NAME" = "alpine" ]; then
        echo "Alpine Linux detected. Version: $OS_INFO"
        $SUDO apk update
        $SUDO apk add smartmontools
    else
        echo "Unsupported operating system: $OS_NAME"
    fi

    # Scan for devices
    SCAN_OUTPUT=$(smartctl --scan)

    # Iterate through each line of the smartctl scan output
    echo "$SCAN_OUTPUT" | while read -r LINE; do
        DEVICE=$(echo "$LINE" | awk '{print $1}')
        DEVICE_TYPE=$(echo "$LINE" | awk '{print $3}')

        # Skip NVMe devices
        if [ "$DEVICE_TYPE" = "nvme" ]; then
            echo "Skipping NVMe device: $DEVICE"
        else
            run_smartctl_test "$DEVICE"
        fi
    done

    # Wait for the test to complete
    echo "Sleeping for 5 minutes..."
    sleep 0

    # Clear the summary log
    : > "$SUMMARY_LOG"

    echo "$SCAN_OUTPUT" | while read -r LINE; do
        DEVICE=$(echo "$LINE" | awk '{print $1}')
        DEVICE_TYPE=$(echo "$LINE" | awk '{print $3}')
        DEVICE_NAME=$(basename "$DEVICE")
        FULL_LOG="${DEVICE_NAME}_output.txt"

        # Run smartctl -a for each device and save the output
        run_smartctl_a "$DEVICE" "$FULL_LOG"

        # Extract relevant data and append to the summary log
        extract_smartctl_info "$FULL_LOG" "$SUMMARY_LOG" "$DEVICE_NAME"
    done

    echo "SMART summary and full logs created successfully."
    echo "Summary of SMART data saved to $SUMMARY_LOG"

else
    echo "The /etc/os-release file does not exist. Unable to detect OS."
fi
