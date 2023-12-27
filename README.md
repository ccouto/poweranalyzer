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

## Most recent example of my current readings (Lenovo Thinkpad Carbon X1 Gen 9)

    Current battery:                2.05 Wh
    Percentage:                     3%
    Running on battery for:         8 hours, 47 minutes, 39 seconds (since last boot)
    Current power usage:            7.172 W
    Average power usage:            5.06287 W

    Time to empty:                  0 hours, 24 minutes, 18 seconds
    Battery cycle duration:         9 hours, 11 minutes, 57 seconds
    Battery full-span:              10 hours, 20 minutes, 10 seconds

## Most recent example of my current readings (Lenovo Thinkpad Carbon X1 Gen 9) with tlp:

    Current battery:                2.01 Wh
    Percentage:                     3%
    Running on battery for:         8 hours, 53 minutes, 31 seconds (since last charge)
    Current power usage:            5.051 W
    Average power usage:            4.84214 W

    Time to empty:                  0 hours, 24 minutes, 54 seconds
    Battery cycle duration:         9 hours, 18 minutes, 22 seconds
    Battery full-span:              10 hours, 41 minutes, 52 seconds

## A record (01-11-2023, charged to 99% from the beginning)

    Current battery:                1.51 Wh
    Percentage:                     2%
    Running on battery for:         10 hours, 12 minutes, 50 seconds (since last charge)
    Current power usage:            4.81 W
    Average power usage:            4.71863 W

    Time to empty:                  0 hours, 19 minutes, 12 seconds
    Battery full-span:              10 hours, 44 minutes, 56 seconds


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
