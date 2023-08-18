# Poweranalyzer - a bash script for better battery estimation

This is poweranalyzer, a simple bash script to read the current battery discharging cycle and estimate the battery time left.

## How to run

simply execute the bash script (*sudo is not needed*).

## Example of output and explanation (my current reading):

    Current battery:                2.08 Wh
    Percentage:                     3%
    Running on battery for:         7 hours, 40 minutes, 32 seconds
    Current power usage:            6.084 W
    Average power usage:            7.19542 W

    Time to empty:          0 hours, 17 minutes, 21 seconds
    Battery full-span:      7 hours, 57 minutes, 53 seconds

The output is as follows: 
- `Current battery` gives the current battery available (in W*h)  
- `Percentage` is the the percentage of battery available  
- `Running on battery for` is the time that your computer has been running on battery (minus suspend time, **see notes**)  
- `Current power usage` is the reading from ACPI (it might not be available in your system)  
- `Average power usage` is the average power consumption of the battery (calculated based on the current battery, the running time in battery and the full battery capacity)
- `Time to empty` and `Battery full-span` are self explanatory.

## Notes

The `Running on battery for` calculates the time that the laptop has been running in battery by looking in the journalctl log for *suspend* states. Therefore, this value does not account for the time that your laptop has been in suspended mode. This seems to give a good and accurate calculation of the time remaining of the battery.

The script only works if:
- You are discharging the battery of your laptop;  
- At least 1% of battery has been discharged (after the last charging cycle);  
- Initial estimations (when you have discharged a small quantity of battery) might be a bit off.

## Work to do

This script has not been tested in many computers and distributions. I have used Arch Linux (Thinkpad Carbon X1 gen 9) and tested in Ubuntu (Asus Zenbook).
