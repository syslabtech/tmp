#!/bin/sh

# Function to check if sudo is installed
check_sudo() {
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        SUDO=""
    fi
}


create_diskmonitoring_folder() {
    # Check if the folder /var/diskmonitoring exists
    if [ ! -d "/var/diskmonitoring" ]; then
        # If it doesn't exist, create it with root permissions
        echo "Creating /var/diskmonitoring folder with root permissions"
        $SUDO mkdir -p /var/diskmonitoring
        # Allow the owner (root) and the group (users) to read/write, others can only read
        $SUDO chmod 777 /var/diskmonitoring
    else
        echo "/var/diskmonitoring already exists. Skipping creation."
    fi
}



MAX_TEST_TIME=0

# Function to extract minutes
extract_minutes_from_output() {
    local output="$1"
    local minutes=$(echo "$output" | grep -oE 'Please wait ([0-9]+) minutes' | awk '{print $3}')
    if [ -z "$minutes" ]; then
        echo 0  # Return 0 if no match is found
    else
        echo "$minutes"  # Return extracted minutes
    fi
}

# Function to process and update TEST_TIME
update_test_time() {
    local output="$1"
    local extracted_time=$(extract_minutes_from_output "$output")

    # Update the global variable if the extracted value is greater
    if [ "$extracted_time" -gt "$MAX_TEST_TIME" ]; then
        MAX_TEST_TIME=$extracted_time
    fi
    echo "extracted time $extracted_time"
    echo "assign time $MAX_TEST_TIME"
}


run_smartctl_test() {
    DEVICE=$1
    echo "Running smartctl test on $DEVICE"

    # Run the command and capture the output and error
    TEST_OUTPUT=$($SUDO smartctl -t short "$DEVICE" 2>&1)
    update_test_time "$TEST_OUTPUT"
    # Check if the output mentions 'please try adding \"-d megaraid,N\"'
    if echo "$TEST_OUTPUT" | grep -q "please try adding '-d megaraid"; then
        echo "Retrying with '-d megaraid,N'"
        MEGARAID_ID=0
        while :; do
            OUTPUT=$($SUDO smartctl -t short -d megaraid,$MEGARAID_ID "$DEVICE" 2>&1)
            update_test_time "$OUTPUT"
            if echo "$OUTPUT" | grep -q "INQUIRY failed"; then
                echo "Smartctl open device: $DEVICE [megaraid_disk_$(printf '%02d' $MEGARAID_ID)] failed: INQUIRY failed"
                break
            fi
            echo "Smartctl test initiated successfully with '-d megaraid,$MEGARAID_ID'"
            MEGARAID_ID=$((MEGARAID_ID + 1))
        done

    # Check if the output mentions 'requires option \"-d cciss,N\"'
    elif echo "$TEST_OUTPUT" | grep -q "requires option '-d cciss"; then
        echo "Retrying with '-d cciss,N'"
        CCISS_ID=0
        while :; do
            OUTPUT=$($SUDO smartctl -t short -d cciss,$CCISS_ID "$DEVICE" 2>&1)
            update_test_time "$OUTPUT"
            if echo "$OUTPUT" | grep -q "No such device or address"; then
                echo "Smartctl open device: $DEVICE [cciss_disk_$(printf '%02d' $CCISS_ID)] [SCSI/SAT] failed: INQUIRY [SAT]: No such device or address"
                break
            fi
            echo "Smartctl test initiated successfully with '-d cciss,$CCISS_ID'"           
            CCISS_ID=$((CCISS_ID + 1))
        done

    else
        echo "Smartctl test initiated successfully on $DEVICE."
    fi

    echo "The maximum short test time encountered was $MAX_TEST_TIME minutes."

}

echo "new time $MAX_SHORT_TEST_TIME"

# Function to run smartctl -a and save the output to a single file
run_smartctl_a() {
    DEVICE=$1
    MOUNT_PATH=$2

    echo "Running smartctl -a on $DEVICE"

    # Attempt the first smartctl -a command
    OUTPUT=$($SUDO smartctl -a "$DEVICE" 2>&1)

    # Check for the 'please try adding \"-d megaraid,N\"' message
    if echo "$OUTPUT" | grep -q "please try adding '-d megaraid"; then
        echo "Retrying with '-d megaraid,N'"
        MEGARAID_ID=0
        while :; do
            OUTPUT=$($SUDO smartctl -a -d megaraid,$MEGARAID_ID "$DEVICE" 2>&1)
            if echo "$OUTPUT" | grep -q "INQUIRY failed"; then
                echo "Smartctl open device: $DEVICE [megaraid_disk_$(printf '%02d' $MEGARAID_ID)] failed: INQUIRY failed"
                break
            fi
            echo "Smartctl -a initiated successfully with '-d megaraid,$MEGARAID_ID'"
            # Modify the output to replace newlines and carriage returns
            MODIFIED_OUTPUT=$(echo "$OUTPUT" | sed ':a;N;$!ba;s/\n/|||/g' | sed 's/\r/:::/g' | sed 's/|||[|]\{1,\}/|||/g' | sed 's/:::|||/|||/g')
            # echo $MODIFIED_OUTPUT
            # Append both original and modified output to their respective files
            echo "DISK_HEALTH_DATA:host:$(hostname),disk_path:$DEVICE,mount_path:$MOUNT_PATH|||$MODIFIED_OUTPUT" >> /var/diskmonitoring/smartctl_drivescan_output.log
            
            MEGARAID_ID=$((MEGARAID_ID + 1))
        done
    fi

    # Check for the 'requires option \"-d cciss,N\"' message
    if echo "$OUTPUT" | grep -q "requires option '-d cciss"; then
        echo "Retrying with '-d cciss,N'"
        CCISS_ID=0
        while :; do
            OUTPUT=$($SUDO smartctl -a -d cciss,$CCISS_ID "$DEVICE" 2>&1)
            if echo "$OUTPUT" | grep -q "No such device or address"; then
                echo "Smartctl open device: $DEVICE [cciss_disk_$(printf '%02d' $CCISS_ID)] [SCSI/SAT] failed: INQUIRY [SAT]: No such device or address"
                break
            fi
            echo "Smartctl -a initiated successfully with '-d cciss,$CCISS_ID'"
            # Modify the output to replace newlines and carriage returns
            MODIFIED_OUTPUT=$(echo "$OUTPUT" | sed ':a;N;$!ba;s/\n/|||/g' | sed 's/\r/:::/g' | sed 's/|||[|]\{1,\}/|||/g' | sed 's/:::|||/|||/g')
            echo $MODIFIED_OUTPUT
            # Append both original and modified output to their respective files
            echo "DISK_HEALTH_DATA:host:$(hostname),disk_path:$DEVICE,mount_path:$MOUNT_PATH|||$MODIFIED_OUTPUT" >> /var/diskmonitoring/smartctl_drivescan_output.log
            
            CCISS_ID=$((CCISS_ID + 1))
        done
    fi

    echo "TIME: $(date)" >> /var/diskmonitoring/script_run_time
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
    create_diskmonitoring_folder

    # # Check if the system is Ubuntu or Alpine
    # if [ "$OS_NAME" = "ubuntu" ]; then
    #     echo "Ubuntu detected. Version: $OS_INFO"
    #     $SUDO apt update
    #     $SUDO apt install -y smartmontools

    # elif [ "$OS_NAME" = "alpine" ]; then
    #     echo "Alpine Linux detected. Version: $OS_INFO"
    #     $SUDO apk update
    #     $SUDO apk add smartmontools

    # else
    #     echo "Unsupported operating system: $OS_NAME"
    # fi

    # Run the smartctl --scan command and store the output in a temporary variable
    SCAN_OUTPUT=$(smartctl --scan -d scsi && smartctl --scan -d nvme)

    # Check if SCAN_OUTPUT is blank
    # if [ -z "$SCAN_OUTPUT" ]; then
    #     echo "No devices found in smartctl --scan. Defaulting to /dev/sda."
    #     SCAN_OUTPUT="/dev/sda"
    # fi
    
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
    sleep 300  # Adjust the sleep time as needed for the tests to complete

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
