#!/bin/bash
version="0.0.2"

LC_NUMERIC=C

verbose=0
#acc_line=1     #legacy code
use_laptop_mode=0 #default is no laptopmode unless requested
cycle=0

# Process the arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            echo "batfetch $version"
            exit 1
            ;;
        --help)
            echo "batfetch $version"
            echo "A bash script for better battery estimation using systemd and acpi calls"
            echo "see <github.com/ccouto>"
            echo ""
            echo "Available options are:"
            echo "--getcycles   gives the number of cycles currently available on the acpi log"
            echo "--cycle %num   gives the battery info the cycle %num, example --cycle 0 gives info for last cycle"
            echo ""
            echo "The output is as follows:"
            echo ""
            #echo "Current battery			current battery available (in W*h)"
            #echo "Percentage			percentage of battery available"
            echo "Running on battery for        time running on battery (minus suspend and shutdown time)"  
            echo "Battery consumed              the % of battery consumed in the analysed cycle"
            echo "Average power usage           average power consumption (calculated based on running on battery)"
            echo "Current power usage           power usage from ACPI (it might not be available in your system)"
            echo "Time to empty                 available time running on battery"
            echo "Battery cycle duration        the full cycle duration since started running on battery until battery is empty"
            echo "Battery full-span             based on average, the full battery timespan"
            echo ""
            echo "Note: this script is still experimental, if you get strange readings, let the battery discharge slightly more and try again."
            exit 1

            ;;
        --cycle)
            shift  # Move to the next argument after --cycle
            if [ $# -gt 0 ]; then
                cycle="$1"
                echo "We are reading the cycle #$1"
            else
                echo "Error: --cycle option requires a value."
                exit 1
            fi
            ;;
        --getcycles)
            cycle=-1
            ;;
        -v)
            verbose=1       #gives some more info
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

#functions:

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

#read lines for discharing
last_discharging_line=""

#cur_cycle stores the current charge-discharge cycle (it is also used to count the # of cycles in acpi log)
cur_cycle=0

# Loop through the array in reverse
for ((i=${#lines[@]}-1; i>=0; i--)); do
    line="${lines[$i]}"
    
    if [[ $line == *"	discharging"* ]] && [[ $last_discharging_line == "" ]]; then
        last_discharging_line=$line
    fi
    if [[ $line == *"	charging"* || $line == *"	fully-charged"* ]] && [[ -n $last_discharging_line ]]; then
        shift=1
        if [[ ${lines[$i+1]} == *"	unknown"* ]] || [[ ${lines[$i+1]} == *"	pending-charge"* ]] ; then
            shift=2
            #echo "shift it!"
        fi
        echo "we are at line $i which is : $line"
        echo "we are interested in line ${lines[$i+$shift]}"

        if [[ $cur_cycle == $cycle ]]; then
            read -r start_bat bat_lastchargeread _ <<< "${lines[$i+$shift]} | tr , ."  
            read -r end_bat charge_status_end _ <<< "$last_discharging_line | tr , ."    
            bat_lastchargeread_num=$(awk "BEGIN {print $bat_lastchargeread}")
            charge_status_end_num=$(awk "BEGIN {print $charge_status_end}")

            echo "Running on battery since $(date -d "@$start_bat" +"%d/%m/%y at %T") with $bat_lastchargeread_num%"
            
            #we are checking if the cycle is the current one, if it is (cycle=0) make some updates to read values and present info
            if [[ $cycle -gt 0 ]]; then
            echo "until $(date -d "@$end_bat" +"%d/%m/%y at %T") with $charge_status_end_num%"
            else
            charge_status_end_num=$cur_battery_percent
            echo "until now (current cycle) with $charge_status_end_num"
            fi
            
            seconds_elapsed=$((end_bat - start_bat))
            if [[ $seconds_elapsed == 0 ]]; then
                echo "Please wait for battery to discharge a bit more (remember that there is a delay until it reaches the acpi log...)"
                exit 1
            fi

            #echo "Running on battery for:		$(seconds_to_hms "$((seconds_elapsed))") (since last $charge_cycle_event)"

            mapfile -t lines_jctl < <(journalctl _PID=1 --since "@$start_bat" --until "@$end_bat" -o short-iso) # | grep -E "(-- Boot|Sleep|Shutting down|Load Kernel)")

            sleep_total=0
            shutdown_total=0

            for ((j=0; j<${#lines_jctl[@]}; j++)); do

                if [[ ${lines_jctl[$j]} == *"Starting System Suspend"* ]]; then
                    sleep_start=$(echo "${lines_jctl[$j]}" | awk '{print $1}')
                    sleep_end=$(echo "${lines_jctl[$j+1]}" | awk '{print $1}')
                    # Convert short ISO dates to Unix timestamps
                    sleep_start=$(date -d "$sleep_start" +%s)
                    sleep_end=$(date -d "$sleep_end" +%s)

                    # Calculate the time difference in seconds
                    sleep_seconds_elapsed=$((sleep_end - sleep_start))
                    seconds_elapsed=$((seconds_elapsed - sleep_seconds_elapsed))
                    sleep_total=$((sleep_total+$sleep_seconds_elapsed))
                    
                fi
                if [[ ${lines_jctl[$j]} == *"-- Boot"* ]]; then
                    sleep_start=$(echo "${lines_jctl[$j-1]}" | awk '{print $1}')
                    sleep_end=$(echo "${lines_jctl[$j+1]}" | awk '{print $1}')
                    # Convert short ISO dates to Unix timestamps
                    sleep_start=$(date -d "$sleep_start" +%s)
                    sleep_end=$(date -d "$sleep_end" +%s)

                    # Calculate the time difference in seconds
                    sleep_seconds_elapsed=$((sleep_end - sleep_start))
                    seconds_elapsed=$((seconds_elapsed - sleep_seconds_elapsed))
                    shutdown_total=$((shutdown_total+$sleep_seconds_elapsed))
                    
                fi

                cur_cycle=0
                #echo $"${lines_jctl[$j]}"
            done

            break
        else
            cur_cycle=$((cur_cycle + 1))
            last_discharging_line=""
        fi
    fi
done

if [[ $cur_cycle > 0 ]]; then
    echo "Available cycles are $((cur_cycle-2))"
    exit 1
fi

if [[ $sleep_total > 0 ]]; then
    echo "during this cycle the computer was sleeping for $(seconds_to_hms "$((sleep_total))")"
fi
if [[ $shutdown_total > 0 ]]; then
    echo "during this cycle the computer was shutdown for $(seconds_to_hms "$((shutdown_total))")"
fi

bat_consumed=$(awk "BEGIN {print $bat_lastchargeread - $charge_status_end}")
bat_lastcharge=$(awk "BEGIN {print $bat_lastchargeread * $bat_full / 100}")
charge_status_end=$(awk "BEGIN {print $charge_status_end * $bat_full / 100}")

# Calculate using awk
avr_power_usage=$(awk -v blc="$bat_lastcharge" -v cb="$charge_status_end" -v ts="$seconds_elapsed" 'BEGIN {print (blc - cb) / (ts / 3600)}')

#final estimations for cycle, empty and full bat span:
estimated_empty_time=$(awk -v er="$avr_power_usage" -v cb="$cur_battery" 'BEGIN {print (cb/er) * 3600}')
estimated_empty_time=$(printf "%.0f" $estimated_empty_time)
estimated_fullempty_time=$(awk -v er="$avr_power_usage" -v cb="$bat_full" 'BEGIN {print (cb/er) * 3600}')
estimated_fullempty_time=$(printf "%.0f" "$estimated_fullempty_time")
estimated_cycleempty_time=$((estimated_empty_time + seconds_elapsed))

# Show the result for running on bat
#echo "Running on battery for:		$(seconds_to_hms "$((total_seconds+seconds_to_add))") (since last $charge_cycle_event)"
echo ""
echo "Running on battery for:		$(seconds_to_hms "$((seconds_elapsed))")"
echo "Battery consumed:               $bat_consumed %"
echo "Average power usage:		$avr_power_usage W"
echo ""
# get the current power usage if the file exists
if [ -e "/sys/class/power_supply/BAT0/power_now" ]; then
    power_now=$(cat /sys/class/power_supply/BAT0/power_now)
    # Calculate power in milliWatts (mW) by dividing microWatts by 1000
    power_mw=$((power_now / 1000000))
    power_mw=$(awk "BEGIN {print $power_now / 1000000}")
    echo "Current power usage:		${power_mw} W ($cur_state)"
else
    #it was not read, try from the upower file
    read -r _ power_mw __ ___ <<< $(upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep energy-rate)
    echo "Current power usage:		${power_mw} W (upower, $cur_state)"
fi

echo ""
if [[ $cycle == 0 ]]; then
echo "Time to empty:			$(seconds_to_hms "estimated_empty_time")"
echo "Battery cycle duration:		$(seconds_to_hms "estimated_cycleempty_time")"
fi
echo "Battery full-span:		$(seconds_to_hms "estimated_fullempty_time")"


