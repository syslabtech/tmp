#!/bin/sh

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
    
    # Run the command and capture the output and error
    TEST_OUTPUT=$($SUDO smartctl -t short "$DEVICE" 2>&1)
    
    # Check if the output mentions 'please try adding \'-d megaraid,N\''
    if echo "$TEST_OUTPUT" | grep -q "please try adding '-d megaraid"; then
        # Extract the suggested megaraid,N value if present
        MEGARAID_ID=0
        
        if [ -n "$MEGARAID_ID" ]; then
            echo "Retrying with '-d megaraid,$MEGARAID_ID'"
            $SUDO smartctl -t short -d megaraid,$MEGARAID_ID "$DEVICE"
        else
            echo "Failed to determine megaraid ID. Please check manually."
        fi
    else
        echo "Smartctl test initiated successfully on $DEVICE."
    fi
}

# Function to run smartctl -a and save the output to a single file
run_smartctl_a() {
    DEVICE=$1
    MOUNT_PATH=$2

    echo "Running smartctl -a on $DEVICE"

    # Attempt the first smartctl -a command
    OUTPUT=$($SUDO smartctl -a "$DEVICE" 2>&1)

    # Check for the 'please try adding \'-d megaraid,N\'' message
    if echo "$OUTPUT" | grep -q "please try adding '-d megaraid"; then
        # Extract the suggested megaraid ID
        MEGARAID_ID=0
        
        if [ -n "$MEGARAID_ID" ]; then
            echo "Retrying with '-d megaraid,$MEGARAID_ID'"
            # Retry with the suggested megaraid option
            OUTPUT=$($SUDO smartctl -a -d megaraid,$MEGARAID_ID "$DEVICE" 2>&1)
        else
            echo "Unable to determine megaraid ID. Please check manually."
        fi
    fi

    # Modify the output to replace newlines and carriage returns
    MODIFIED_OUTPUT=$(echo "$OUTPUT" | sed ':a;N;$!ba;s/\n/|||/g' | sed 's/\r/:::/g' | sed 's/|||[|]\{1,\}/|||/g' | sed 's/:::|||/|||/g')

    # Append both original and modified output to their respective files
    # echo "DISK_HEALTH_DATA:host:$(hostname),disk_path:$DEVICE,mount_path:$MOUNT_PATH|||$OUTPUT" >> smartctl_drivescan_normal_output.log
    echo "DISK_HEALTH_DATA:host:$(hostname),disk_path:$DEVICE,mount_path:$MOUNT_PATH|||$MODIFIED_OUTPUT" >> smartctl_drivescan_output.log
}


# Clear the file at the beginning of the script
echo "Clearing output file..."
> smartctl_drivescan_output.log  # This clears the file at the start of each run

# Check if /etc/os-release file exists
if [ -f /etc/os-release ]; then
    # Source the /etc/os-release file to get environment variables
    . /etc/os-release

    # Extract the OS name and version, and store the version in OS_INFO
    OS_NAME=$(echo "$NAME" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
    OS_INFO="$VERSION_ID"

    # Check if sudo is available
    check_sudo

    # Check if the system is Ubuntu or Alpine
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

    # Run the smartctl --scan command and store the output in a temporary variable
    SCAN_OUTPUT=$(smartctl --scan)

    # Iterate through each line of the smartctl scan output
    echo "$SCAN_OUTPUT" | while read -r LINE; do
        # Extract the device path (e.g., /dev/sda or /dev/nvme0)
        DEVICE=$(echo "$LINE" | awk '{print $1}')
        DEVICE_TYPE=$(echo "$LINE" | awk '{print $3}')

        # If the device type is nvme, skip the test
        if [ "$DEVICE_TYPE" = "nvme" ]; then
            echo "Skipping NVMe device: $DEVICE"
        else
            # Run the smartctl short test on non-NVMe devices
            run_smartctl_test "$DEVICE"
        fi
    done

    echo "Sleeping for 5 minutes..."
    sleep 10 # Adjust the sleep time as needed for the tests to complete

    # Iterate through each line of the smartctl scan output
    echo "$SCAN_OUTPUT" | while read -r LINE; do
        # Extract the device path (e.g., /dev/sda or /dev/nvme0)
        DEVICE=$(echo "$LINE" | awk '{print $1}')
        DEVICE_TYPE=$(echo "$LINE" | awk '{print $3}')
        # MOUNT_POINT=(df -h | grep "$DEVICE" | head -n 1 | awk '{print $6}')
        MOUNT_POINT=$($SUDO df -h | grep /dev/sda | head -n 1 | awk '{print $6}')
        # Run smartctl -a and append the output to the combined output file
        run_smartctl_a "$DEVICE" "$MOUNT_POINT"
    done

else
    echo "The /etc/os-release file does not exist. Unable to detect OS."
fi
