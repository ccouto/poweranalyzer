#!/bin/bash
version="0.0.2"

LC_NUMERIC=C

verbose=0
#acc_line=1     #legacy code
use_laptop_mode=0 #default is no laptopmode unless requested
period=0

# Process the arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            echo "poweranalyzer $version"
            exit 1
            ;;
        --help)
            echo "batfetch $version"
            echo "A bash script for better battery estimation using systemd and acpi calls"
            echo "ccouto <ccouto@ua.pt>"
            echo ""
            echo "Available options are:"
            echo "--getcycles   gives the number of cycles currently available on the acpi log"
            echo "--cycle %num   gives the battery info the cycle %num, example --cycle 0 gives info for last cycle"
            echo ""
            echo "The output is as follows:"
            echo ""
            #echo "Current battery			current battery available (in W*h)"
            #echo "Percentage			percentage of battery available"
            echo "Running on battery for		time running on battery (minus suspend and shutdown time)"  
            echo "Current power usage		power usage from ACPI (it might not be available in your system)"
            echo "Average power usage		average power consumption (calculated based on running on battery)"
            echo "Time to empty			available time running on battery"
            echo "Battery full-span		based on average, the full battery timespan"
            echo ""
            echo "Note: this script is still experimental, if you get strange readings, let the battery discharge slightly more and try again."
            exit 1
            #echo "version $version"
            #echo "Carlos Couto"
            ;;
        --cycle)
            shift  # Move to the next argument after --cycle
            if [ $# -gt 0 ]; then
                period="$1"
                echo "We are reading the cycle #$1"
            else
                echo "Error: --cycle option requires a value."
                exit 1
            fi
            ;;
        --getcycles)
            period=-1
            ;;
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

# Check if cur_state is "charging"
#if [ "$cur_state" != "discharging" ]; then
#    echo "Stopping script: Battery is not discharging."
#    exit 1  # Exit the script with a non-zero status code
#fi

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

first_discharging_line=""
last_discharging_line=""
bat_lastcharge=-1

cur_period=0


# Loop through the array in reverse
for ((i=${#lines[@]}-1; i>=0; i--)); do
    line="${lines[$i]}"
    
    if [[ $line == *"	discharging"* ]] && [[ $last_discharging_line == "" ]]; then
        last_discharging_line=$line
    fi
    if [[ $line == *"	charging"* ]] && [[ -n $last_discharging_line ]]; then
    
        #echo "we are at line $i which is : $line"
        #echo "we are interested in line ${lines[$i+1]}"
        if [[ $cur_period == $period ]]; then
            read -r start_bat bat_lastchargeread _ <<< "${lines[$i+1]} | tr , ."  
            read -r end_bat charge_status_end _ <<< "$last_discharging_line | tr , ."    
            echo "Bat started at $bat_lastchargeread on $(date -d "@$start_bat" +"%d/%m/%y at %T")"
            echo "Bat ended at $charge_status_end on $(date -d "@$end_bat" +"%d/%m/%y at %T")"
            seconds_elapsed=$((end_bat - start_bat))

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
                    
                    #echo "Allright sleeped for $(seconds_to_hms "$((sleep_seconds_elapsed))")"
                    #echo "Sleep info $sleep_start until $sleep_end"
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
                    
                    #echo "Allright on the dark for $(seconds_to_hms "$((sleep_seconds_elapsed))")"
                    #echo "Sleep info $sleep_start until $sleep_end"
                fi

                cur_period=0
                #echo $"${lines_jctl[$j]}"
            done




            #last_discharging_line=$line
            break
        else
            cur_period=$((cur_period + 1))
            last_discharging_line=""
        fi
    fi
done

if [[ $cur_period > 0 ]]; then
    echo "Available cycles are $((cur_period-2))"
    exit 1
fi

if [[ $sleep_total > 0 ]]; then
    echo "During this period the computer was sleeping for $(seconds_to_hms "$((sleep_total))")"
fi
if [[ $shutdown_total > 0 ]]; then
    echo "During this period the computer was shutdown for $(seconds_to_hms "$((shutdown_total))")"
fi

bat_consumed=$(awk "BEGIN {print $bat_lastchargeread - $charge_status_end}")
#bat_consumed=$((bat_lastchargeread-charge_status_end))



bat_lastcharge=$(awk "BEGIN {print $bat_lastchargeread * $bat_full / 100}")
charge_status_end=$(awk "BEGIN {print $charge_status_end * $bat_full / 100}")
#echo "Calculated last charge:		$bat_lastcharge	Wh"

# Calculate using awk
avr_power_usage=$(awk -v blc="$bat_lastcharge" -v cb="$charge_status_end" -v ts="$seconds_elapsed" 'BEGIN {print (blc - cb) / (ts / 3600)}')
#echo "Average power usage was:		$avr_power_usage W"
#final estimations
estimated_empty_time=$(awk -v er="$avr_power_usage" -v cb="$cur_battery" 'BEGIN {print (cb/er) * 3600}')
estimated_empty_time=$(printf "%.0f" $estimated_empty_time)

#previously we were calculating the battery full span based on the full battery capacity and average power usage (calculate_full=1)
#however, this has shown to be somehow inconsistent, we now present the full battery span as the simple calculation of running time + time to empty (calculate_full=0)
#calculate_full=1
#if [ $calculate_full -eq 1 ]; then
    estimated_fullempty_time=$(awk -v er="$avr_power_usage" -v cb="$bat_full" 'BEGIN {print (cb/er) * 3600}')
    estimated_fullempty_time=$(printf "%.0f" "$estimated_fullempty_time")
#else
    estimated_cycleempty_time=$((estimated_empty_time + total_seconds + seconds_to_add))
#fi

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
    echo "Current power usage:		${power_mw} W"
else
    #it was not read, try from the upower file
    read -r _ power_mw __ ___ <<< $(upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep energy-rate)
    echo "Current power usage:		${power_mw} W (upower)"
fi

# only show the results if there is enough data
# if ((difference_bat <= 1)); then
#     #echo $difference_bat
#     echo "Discharging started at $bat_lastcharge_store %. At least 1% discharge is needed, leaving..."
#     exit 1  # Exit the script with a non-zero status code
# fi

# Shows the results of calculations
echo ""
echo "Time to empty:			$(seconds_to_hms "estimated_empty_time")"
if [ $verbose -eq 1 ]; then
echo "Battery cycle duration:		$(seconds_to_hms "estimated_cycleempty_time")"
fi
echo "Battery full-span:		$(seconds_to_hms "estimated_fullempty_time")"


