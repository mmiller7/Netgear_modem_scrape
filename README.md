# Netgear_modem_scrape

This has been tested on my Netgear CM1100 Hardware Version 2.02 / Firmware Version V7.01.01

This is a modification on my previous Arris modem signals for monitoring over time, changed to accomodate the login process and data format of Netgear modems to access the signals.

This script should allow you to scrape the modem status data and write it out to a MQTT broker where you can then use something like HomeAssistant to take actions based on the data (graph it, issue automations to cycle a smartplug, etc)

Files:

netgear_modem_signal_dump.sh - the script which logs into the modem and scrapes/parses the data publishing JSON to MQTT 

netgear_modem_signgal.yaml - initial YAML to run the script periodically and import the startup status (I have the sensors for channels my ISP uses filled out, you may need to browse what your ISP offers and review published MQTT data to decide what you want)



Install Process:


Prerequisite: MQTT configured and working on Home Assistant

1. Create the following folders:
- /config/bin
- /config/bin/mosquitto_deps
- /config/bin/mosquitto_deps/lib
- /config/netgear_modem_signal_scraper

2. Copy the dependency files into place (I used SSH with the `cp  from_path  to_path` command):
- From: `/usr/bin/mosquitto_pub` To: `/config/bin/mosquitto_deps/mosquitto_pub`
- From: `/usr/lib/libmosquitto.so.1` To: `/config/bin/mosquitto_deps/lib/libmosquitto.so.1`
- From: `/usr/lib/libcares.so.2` To: `/config/bin/mosquitto_deps/lib/libcares.so.2`

3. Download my script off GitHub:
- /config/netgear_modem_signal_scraper/netgear_signal_dump.sh

4. Edit the `netgear_signal_dump.sh` file and modify the lines at the top:
The "baseURL" should be your modem's IP address, which is normally 192.168.100.1
```
# Default mqtt_password is "password"
modem_username="admin"
modem_password="password"
baseURL='http://192.168.100.1'

# Settings for MQTT mqtt_broker to publish stats
mqtt_broker="192.168.1.221"
mqtt_username="your_mqtt_username_here"
mqtt_password="your_mqtt_password_here"
mqtt_topic="homeassistant/sensor/modemsignals"
```

Optional:
At this point, if you wish, it should be possible to do an initial test.  By opening a MQTT Explorer/Browser, and then in the SSH addon running `/config/netgear_modem_signal_scraper/netgear_signal_dump.sh` it should scrape the modem and publish new topics.  One of the published topics should be `homeassistant/sensor/modemsignals/login` which will provide information about problems or success of the modem login-process of the script while scraping the data.

5. Now, you will need to configure Home Assistant to connect to the sensors and run the script.  For this, I recommend using [packages](https://www.home-assistant.io/docs/configuration/packages/) to split out the large amount of configuration for organization.
- Create a new folder to store your package YAML files.  `/config/packages_yaml`
- Add an include line to your `/configuration.yaml` to read the packages (think of this as many stand-alone configuration.yaml files with custom names, which you can group in subfolders any way you like)
```
homeassistant:
  packages: !include_dir_named packages_yaml
```

6. Download my sample YAML file off GitHub and place it somewhere in the packages_yaml folder we set up in step 5:
- /config/packages_yaml/network_monitoring/netgear_modem_signal.yaml

7. Log into your modem signal status page (typically 192.168.100.1) manually and take note of how many channels you have downstream and upstream, and their numbers.  You will need this information to set up matching sensors that read off MQTT and expose the sensors to Home Assistant as entities.  This must be set up by you as the combination of channels varies depending on your ISP and subscription plan what your modem is provisioned for.  My example has 32 downstream QAM, 1 downstream ODFM, 4 upstream QAM, and 0 upstream ODFM channels.

8. Modify the example netgear_modem_signals.yaml file automation to adjust when the signal-scrape is triggered.  This is near the top, around the line `# Run the test on startup, and hourly` and in my example I have a number of "ping sensors" (set up elsewhere beyond the scope of this guide) that immediately read modem signals when there is a change in connectivity even if the number of minutes has not elapsed.

9. Modify the example netgear_modem_signals.yaml file to match your modem's channels provisioned.  This is below the line `# Generated sensors below` in the file, and very repetitive.
The fields are split into several sections of interest for you to review/update
- Downstream `MQTT Inputs` (1-32 are QAM, 33 a single ODFM)
- Downstream `Averages` (provides easy min/avg/max across all 33 sample channels for each type of data)
- Upstream `MQTT Inputs` (1-4 QAM, no ODFM)
- Upstream `Averages` (provides easy min/avg/max across all 4 sample channels)

10. Go to Home Assistant control panel, and validate your configuration.  If there are any errors, review those files before restarting Home Assistant.

11. Restart Home Assistant so it loads all the new changes.

12. Observe that the new sensors load in and populate.  A good one to start looking at is `sensor.cable_modem_web_ui_login_status` which should indicate the success or failure of the scrape script logging into the modem.  If this reports a value of "success" then you should have signal data stored in the other sensor fields ready for use in dashboards and automations.

