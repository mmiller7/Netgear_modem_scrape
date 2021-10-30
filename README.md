# Netgear_modem_scrape

This has been tested on my Netgear CM1100 Hardware Version 2.02 / Firmware Version V7.01.01

This is a modification on my previous Arris modem signals for monitoring over time, changed to accomodate the login process and data format of Netgear modems to access the signals.

This script should allow you to scrape the modem status data and write it out to a MQTT broker where you can then use something like HomeAssistant to take actions based on the data (graph it, issue automations to cycle a smartplug, etc)

Files:

netgear_modem_signal_dump.sh - the script which logs into tthe modem and scrapes/parses the data publishing JSON to MQTT 

netgear_modem_signgal.yaml - initial YAML to run the script periodically and import the startup status (I have the sensors for channels my ISP uses filled out, you may need to browse what your ISP offers and review published MQTT data to decide what you want)
