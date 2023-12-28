# batfetch - a bash script for better battery estimation

This is batfetch (former poweranalyser), a simple bash script to read the current battery discharging cycle and estimate the battery time left.

## How to run

simply execute the bash script (*sudo is not needed*).
> use `batfetct -c 1` to analyse previous cycle  
> 
> use `batfetch --getcycles` to see how many cycles are available to read

## Example of output and explanation (my current reading):

    Running on battery since 27/12/23 at 17:55:46 with 86%
    until now (current cycle) with 27%
    during this cycle the computer was sleeping for 18 hours, 18 minutes, 13 seconds

    Running on battery for:         6 hours, 0 minutes, 25 seconds
    Battery consumed:               59 %
    Average power usage:            4.87562 W

    Current power usage:            4.894 W (discharging)

    Time to empty:                  2 hours, 45 minutes, 16 seconds
    Battery cycle duration:         8 hours, 45 minutes, 41 seconds
    Battery full-span:              10 hours, 10 minutes, 53 seconds

The output is as follows: 
- `Running on battery for`        time running on battery (minus suspend and shutdown time, **see notes**)  
- `Battery consumed`              the % of battery consumed in the analysed cycle
- `Average power usage`           average power consumption (calculated based on running on battery)
- `Current power usage`           power usage from ACPI (it might not be available in your system)
- `Time to empty`                 available time running on battery
- `Battery cycle duration`        the full cycle duration since started running on battery until battery is empty
- `Battery full-span`             based on average, the full battery timespan

## Notes

The `Running on battery for` calculates the time that the laptop has been running in battery by looking in the journalctl log for *suspend* and *shutdown* states. Therefore, this value does not account for the time that your laptopis not running (in suspended mode or shutdown). This seems to give a good and accurate calculation of the time remaining of the battery.

## Work to do

This script has not been tested in many computers and distributions. I have used Arch Linux (Thinkpad Carbon X1 gen 9) and tested in Ubuntu (Asus Zenbook).
