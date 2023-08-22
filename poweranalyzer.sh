#!/bin/bash
LC_NUMERIC=C

verbose=0
#acc_line=1     #legacy code

# Process the arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -v)
            verbose=1
            ;;
        # -acc)
        #     #this option reads the second line instead of the first discharging line
        #     acc_line=2
        #     ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

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
    exit 1  # Exit the script with a non-zero status code
fi

if [ $verbose -eq 1 ]; then
    echo "Battery info:"
    echo "Model is $model"
    echo "Serial is $serial"
    echo "Battery full is $bat_full Wh"
    echo
fi

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

# Read the file into an array
mapfile -t lines < "/var/lib/upower/$file"

last_charging_line=""
bat_lastcharge=-1

# Loop through the array in reverse
for ((i=${#lines[@]}-1; i>=0; i--)); do
    line="${lines[$i]}"
    if [[ $line == *"	charging"* || $line == *"	fully-charged"* ]]; then
    #if [[ $line == *"	charging"* ]]; then
        if ((i < ${#lines[@]}-0)); then  # Note the change in index
            last_charging_line_zero="${lines[$i+1]}"  # Retrieve the first line after last charging (it should be discharging)
            last_charging_line="${lines[$i+2]}"  # For the measurements we take the second discharing line, this is because on some systems the charging thresholds might make some differences
            #note: we are getting some strange readings when we get fully-charged state
            #for that particular case we consider now the last_charging_line_zero to be that line
            if [[ $line == *"	fully-charged"* ]]; then
                last_charging_line_zero=$line
                last_charging_line=$line
            fi
            timestamp1=$(echo $last_charging_line_zero | awk '{print $1}')
            timestamp2=$(echo $last_charging_line | awk '{print $1}')
            #echo "last line zero is $last_charging_line_zero"
            #calculate the interval between these two values in seconds
            #timestamp1=${last_charging_line_zero%% *}
            #timestamp2=${last_charging_line%% *}
            seconds_to_add=$((timestamp2 - timestamp1))
            #echo "Line containing 'charging': $line"
            #echo "Second next line: $second_next_line"
            #echo "there: $last_charging_line" 
        else
            #echo "Line containing 'charging': $line (second last line)"
            last_charging_line=$line  # No need to modify this line
        fi
        break
    fi

    if [[ $line == *"	discharging"* ]]; then

        read -r start_bat bat_lastchargeread _ <<< "$line | tr , ."        
        read -r start_bat bat_lastchargeread_before _ <<< "${lines[$i-1]} | tr , ."
        bat_lastchargeread=$(printf "%.0f" "$bat_lastchargeread")
        bat_lastchargeread_before=$(printf "%.0f" "$bat_lastchargeread_before")
        if (($bat_lastchargeread_before < $bat_lastchargeread )); then
            last_charging_line_zero=$line
            last_charging_line=$line            
            seconds_to_add=0
            #we got the line
            #sometimes if the charging occurs during suspend time only, the $file will not contain this information
            #however, we can still check if this occurred by looking at the bat carge values, if it has increased, it means that there was some charging that went unlogged
            break
        fi
    fi

done

# Check if last_charging_line is empty if so, we need to exit otherwise results are wrong
if [[ -z "$last_charging_line" ]]; then
    echo "We are stopping this script because there is not enough information about discharging state. Please wait until the battery is slightly discharged."
    exit 1
fi

#next is some legacy code, to be removed later
# first_discharging_line=$(grep "unknown" "/var/lib/upower/$file" | tail -n 1)
# #echo "first is $first_discharging_line"
# #last_charging_line=$(grep "	charging" "/var/lib/upower/$file" | tail -n 1)
# #echo "$last_charging_line"
#     if [ -z "$last_charging_line" ]; then  
#     	first_discharging_line=$(grep "unknown" "/var/lib/upower/$file" | tail -n 2)
#         last_charging_line="$first_discharging_line"
#     fi

# Split last_charging_line by spaces and extract date and bat_lastcharge values
read -r start_bat bat_lastcharge _ <<< "$last_charging_line | tr , ."
read -r start_bat_4sus bat_lastcharge2 _ <<< "$last_charging_line_zero | tr , ."

# Echo the extracted values
if [ $verbose -eq 1 ]; then
#    echo "Verbose mode is enabled."
echo "Last Discharging Line: $last_discharging_line"
echo "Last Charging Line: $last_charging_line"
echo "Extracted Date: $start_bat"
echo "Extracted bat_lastcharge: $bat_lastcharge"
fi
echo "Current battery:		$cur_battery Wh"
echo "Percentage:			$cur_battery_percent"


#check if a least 1% of battery have been consumed, stop otherwise
cur_battery_percent=${cur_battery_percent%"%"}  #we remove the % symbol
bat_lastcharge=$(printf "%.0f" "$bat_lastcharge")
bat_lastcharge_store=$bat_lastcharge
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

# Get the first line from "journalctl" after the start of discharging state
start_date=$(journalctl -o short-iso --since "@$start_bat" | head -n 1 | awk '{print $1}')

#get the systemd status for sleeping states
journalctl_output_suspend=$(journalctl -o short-iso --since "@$start_bat_4sus" -t systemd-sleep |grep -E "systemd-sleep.*sleep state")

#current time in seconds
current_seconds=$(date +%s)

#convert start_date to seconds
start_seconds=$(date_to_seconds "$start_date")

# Calculate the difference in seconds
total_seconds=$((current_seconds - start_seconds))

# Split the input into lines
IFS=$'\n' read -r -d '' -a lines <<< "$journalctl_output_suspend"
difference=0
# Calculate the difference in seconds for each line
for ((i = 0; i < ${#lines[@]} - 1; i++)); do
    current_line="${lines[$i]}"
    next_line="${lines[$i + 1]}"

    # Extract the timestamps from the lines
    current_timestamp=$(echo "$current_line" | awk '{print $1}')
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
done

# Calculate using awk
avr_power_usage=$(awk -v blc="$bat_lastcharge" -v cb="$cur_battery" -v ts="$total_seconds" 'BEGIN {print (blc - cb) / (ts / 3600)}')

#final estimations
estimated_empty_time=$(awk -v er="$avr_power_usage" -v cb="$cur_battery" 'BEGIN {print (cb/er) * 3600}')
estimated_empty_time=$(printf "%.0f" $estimated_empty_time)

#previously we were calculating the battery full span based on the full battery capacity and average power usage (calculate_full=1)
#however, this has shown to be somehow inconsistent, we now present the full battery span as the simple calculation of running time + time to empty (calculate_full=0)
calculate_full=1
if [ $calculate_full -eq 1 ]; then
    estimated_fullempty_time=$(awk -v er="$avr_power_usage" -v cb="$bat_full" 'BEGIN {print (cb/er) * 3600}')
    estimated_fullempty_time=$(printf "%.0f" "$estimated_fullempty_time")
else
    estimated_fullempty_time=$((estimated_empty_time + total_seconds + seconds_to_add))
fi
# Show the result for running on bat
echo "Running on battery for:		$(seconds_to_hms "$((total_seconds+seconds_to_add))")"

# get the current power usage if the file exists
if [ -e "/sys/class/power_supply/BAT0/power_now" ]; then
    power_now=$(cat /sys/class/power_supply/BAT0/power_now)
    # Calculate power in milliWatts (mW) by dividing microWatts by 1000
    power_mw=$((power_now / 1000000))
    power_mw=$(awk "BEGIN {print $power_now / 1000000}")
    echo "Current power usage:		${power_mw} W"
fi

# only show the results if there is enough data
if ((difference_bat <= 1)); then
    #echo $difference_bat
    echo "Discharging started at $bat_lastcharge_store %, we are stopping script not enough reading data (at least 1% change is needed)"
    exit 1  # Exit the script with a non-zero status code
fi

# Shows the results of calculations
echo "Average power usage:		$avr_power_usage W"
echo ""
echo "Time to empty:		$(seconds_to_hms "estimated_empty_time")"
echo "Battery full-span:	$(seconds_to_hms "estimated_fullempty_time")"


