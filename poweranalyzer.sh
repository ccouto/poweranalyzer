#!/bin/bash

# test="1,9"
# test_float=$(echo $test | tr , .)
# echo $test_float
# bat_lastcharge=$(awk "BEGIN {print $test_float / 1.1}")
# echo $bat_lastcharge

# Get battery information using upower command
output=$(upower -i /org/freedesktop/UPower/devices/battery_BAT0)

# Extract model and serial numbers using grep and awk
model=$(echo "$output" | grep "model:" | awk '{print $2}')
serial=$(echo "$output" | grep "serial:" | awk '{print $2}')

#Extract current status of the battery
bat_full=$(echo "$output" | grep "energy-full:" | awk '{print $2}' | tr , .)
cur_battery=$(echo "$output" | grep "energy:" | awk '{print $2}' | tr , .)
cur_battery_percent=$(echo "$output" | grep "percentage:" | awk '{print $2}' | tr , .)
cur_state=$(echo "$output" | grep "state:" | awk '{print $2}' | tr , .)

# Check if cur_state is "charging"
if [ "$cur_state" = "charging" ]; then
    echo "Stopping script: Battery is charging"
    #exit 1  # Exit the script with a non-zero status code
fi

#echo "Model is $model"
#echo "Serial is $serial"

# List files in the /var/lib/upower directory
files=$(ls /var/lib/upower)

# Loop through the files and look for the one containing "model", "serial", and "history-charge"
for file in $files; do
	if [[ $file == *"$model"* ]] && [[ $file == *"$serial"* ]] && [[ $file == *"history-charge"* ]]; then
	#echo "Yes in $file"
	last_discharging_line=$(grep "discharging" "/var/lib/upower/$file" | tail -n 1)
	#echo "$last_discharging_line"
	break
	fi
done

#echo "the file is still $file"

# Read the file into an array
mapfile -t lines < "/var/lib/upower/$file"

# Loop through the array in reverse
# for (( i=${#lines[@]}-1; i>=0; i-- )); do
#     line="${lines[$i]}"
#     if [[ $line == *"	charging"* ]]; then
#         if (( i < ${#lines[@]}-1 )); then
#             last_charging_line="${lines[$i+1]}"
#             echo "Line containing 'charging': $line"
#             echo "Next line: $last_charging_line"
#         else
#             echo "Line containing 'charging': $line (last line)"
#             last_charging_line=$line
#         fi
#         break
#     fi
# done

# Read the file into an array
# mapfile -t lines < "/var/lib/upower/$file"

#
#
#   NOTE: we use the second line after the last *charging* to avoid problems
#
#
# Loop through the array in reverse
for ((i=${#lines[@]}-1; i>=0; i--)); do
    line="${lines[$i]}"
    if [[ $line == *"	charging"* ]]; then
        if ((i < ${#lines[@]}-2)); then  # Note the change in index
            second_next_line="${lines[$i+1]}"  # Retrieve the second next line using $i+2
            #echo "Line containing 'charging': $line"
            #echo "Second next line: $second_next_line"
            last_charging_line=$second_next_line
        else
            #echo "Line containing 'charging': $line (second last line)"
            last_charging_line=$line  # No need to modify this line
        fi
        break
    fi
done




first_discharging_line=$(grep "unknown" "/var/lib/upower/$file" | tail -n 1)
#echo "first is $first_discharging_line"
#last_charging_line=$(grep "	charging" "/var/lib/upower/$file" | tail -n 1)
#echo "$last_charging_line"
    if [ -z "$last_charging_line" ]; then  
    	first_discharging_line=$(grep "unknown" "/var/lib/upower/$file" | tail -n 2)
        last_charging_line="$first_discharging_line"
    fi

# Split last_charging_line by spaces and extract date and bat_lastcharge values
read -r start_bat bat_lastcharge _ <<< "$last_charging_line | tr , ."

# We compare the last charging date with the last boot
#start_date=$(journalctl -b 0 | head -n 1 | awk '{print $1, $2, $3}')
#start_date_unix=$(date -d "$start_date" +"%s")
#if [[ "$start_date_unix" > "$start_bat" ]]; then
#    start_bat_ignore="$start_date_unix"
#fi

# Echo the extracted values
#echo "Last Discharging Line: $last_discharging_line"
#echo "Last Charging Line: $last_charging_line"
#echo "Extracted Date: $start_bat"
#echo "Extracted bat_lastcharge: $bat_lastcharge"
echo "Current battery:		$cur_battery Wh"
echo "Percentage:			$cur_battery_percent"


#check if a least 1% of battery have been consumed, stop otherwise
cur_battery_percent=${cur_battery_percent%"%"}  #we remove the % symbol
bat_lastcharge=$(printf "%.0f" "$bat_lastcharge")
difference_bat=$((bat_lastcharge - cur_battery_percent))
#


bat_lastcharge=$(awk "BEGIN {print $bat_lastcharge * $bat_full / 100}")
#echo "Calculated last charge:		$bat_lastcharge	Wh"

# Function to convert date to seconds since epoch (Unix timestamp)
date_to_seconds() {
    date -d "$1" +%s
}

# Function to convert seconds to hours, minutes, and seconds format
seconds_to_hms() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(( (seconds % 3600) / 60 ))
    local seconds=$(( seconds % 60 ))
    echo "${hours} hours, ${minutes} minutes, ${seconds} seconds"
}

# Get the first line from "journalctl -b 0"
journalctl_output=$(journalctl -o short-iso --since "@$start_bat" | head -n 1)
journalctl_output_suspend=$(journalctl -o short-iso --since "@$start_bat" -t systemd-sleep |grep -E "systemd-sleep.*sleep state")

current_seconds=$(date +%s)
# Get the start date from "journalctl -b 0 | head -n 1"
# original start_date:
#start_date=$(journalctl --since "@$start_bat" | head -n 1 | awk '{print $1, $2, $3}')
# we use this to avoid recalling journalct:
start_date=$(echo $journalctl_output | head -n 1 | awk '{print $1}')

# Convert start date to seconds
start_seconds=$(date_to_seconds "$start_date")

# Get the current date in seconds
current_seconds=$(date +%s)

# Calculate the difference in seconds
total_seconds=$((current_seconds - start_seconds))

# Read the remaining input from here document
input_data=$(cat << EOF
$journalctl_output_suspend
EOF
)

#journalctl -b 0 |grep -E "systemd-sleep&sleep state"

# Split the input into lines
IFS=$'\n' read -r -d '' -a lines <<< "$input_data"
difference=0
# Calculate the difference in seconds for each line
for ((i = 0; i < ${#lines[@]} - 1; i++)); do
    current_line="${lines[$i]}"
    next_line="${lines[$i + 1]}"

    # Extract the timestamps from the lines
    #current_timestamp=$(echo "$current_line" | awk '{print $1, $2, $3}')
    current_timestamp=$(echo "$current_line" | awk '{print $1}')
    #next_timestamp=$(echo "$next_line" | awk '{print $1, $2, $3}')
    next_timestamp=$(echo "$next_line" | awk '{print $1}')

    # Convert timestamps to seconds
    current_seconds=$(date_to_seconds "$current_timestamp")
    next_seconds=$(date_to_seconds "$next_timestamp")

    # Calculate the difference in seconds
    difference=$((next_seconds - current_seconds))

    # Check if the line contains "System returned from sleep state."
    if echo "$current_line" | grep -q "Entering sleep state 'suspend'"; then
        # If it does, set the current timestamp to the next timestamp
        total_seconds=$((total_seconds-difference))
    fi

    #echo "Time difference between Line $i and Line $((i + 1)): $difference seconds"
done

formatted_output=$(seconds_to_hms "$total_seconds")
echo "Running on battery for:		$formatted_output"
if ((difference_bat <= 1)); then
    echo "Stopping script not enough reading data (at least 1% change is needed)"
    exit 1  # Exit the script with a non-zero status code
fi

# Calculate using awk
calculated_value=$(awk -v blc="$bat_lastcharge" -v cb="$cur_battery" -v ts="$total_seconds" 'BEGIN {print (blc - cb) / (ts / 3600)}')

# get the current power usage:
if [ -e "/sys/class/power_supply/BAT0/power_now" ]; then
    power_now=$(cat /sys/class/power_supply/BAT0/power_now)
    # Calculate power in milliWatts (mW) by dividing microWatts by 1000
    power_mw=$((power_now / 1000000))
    power_mw=$(awk "BEGIN {print $power_now / 1000000}")
    echo "Current power usage:		${power_mw} W"
fi

# Echo the calculated result
echo "Average power usage:		$calculated_value W"
echo ""

#final estimations
estimated_empty_time=$(awk -v er="$calculated_value" -v cb="$cur_battery" 'BEGIN {print (cb/er) * 3600}')
#echo "time is $estimated_empty_time"
#estimated_empty_time=$(printf "%.0f" "$estimated_empty_time")
LC_NUMERIC=C estimated_empty_time=$(LC_NUMERIC=C printf "%.0f" $estimated_empty_time)
formatted_output=$(seconds_to_hms "estimated_empty_time")
echo "Time to empty:		$formatted_output"

estimated_fullempty_time=$(awk -v er="$calculated_value" -v cb="$bat_full" 'BEGIN {print (cb/er) * 3600}')
estimated_fullempty_time=$(printf "%.0f" "$estimated_fullempty_time")
formatted_output=$(seconds_to_hms "estimated_fullempty_time")
echo "Battery full-span:	$formatted_output"
#echo
#echo

