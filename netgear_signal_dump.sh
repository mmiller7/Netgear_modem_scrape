#!/bin/bash

# Default mqtt_password is "password"
modem_username="admin"
modem_password="password"
baseURL='http://192.168.100.1'

# Settings for MQTT mqtt_broker to publish stats
mqtt_broker="192.168.1.221"
mqtt_username="your_mqtt_username_here"
mqtt_password="your_mqtt_password_here"
mqtt_topic="homeassistant/sensor/modemsignals"

# HomeAssistant doesn't expose this to the container so we have to hack it up
# Comment these out for a "normal" host that knows where mosquitto_pub is on its own
export LD_LIBRARY_PATH='/config/bin/mosquitto_deps/lib'
mqtt_pub_exe="/config/bin/mosquitto_deps/mosquitto_pub"
# Uncomment tthis for a "normal" host that knows where mosquitto_pub is on its own
#mqtt_pub_exe="mosquitto_pub"

# Cookie file path
cookie_path="$0.cookie"

#####################################
# Prep functions to interface modem #
#####################################

# This function publishes login status helpful for debugging
function loginStatus () {
	#echo "Modem login: $1"
	# Publish MQTT to announce status
	if [ "$2" != "" ]; then
		message="{ \"login\": \"$1\", \"detail\": \"$2\" }"
	else
		message="{ \"login\": \"$1\" }"
	fi
	$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${mqtt_topic}/login" -m "$message" || echo "MQTT-Pub Error!"
}

# Fetch the page and then print the result
webToken=""
realSessionId=""
lastPageFetch=""

function pageDive () {
  toFetch="$1"
  referPage="$2"
  depth=$(( $depth + 1 ))
  lastPageFetch="$toFetch"

  if [[ "$depth" -ge 5 ]]; then
    loginStatus "max_redirect_exceeded"
  else

	  # Fetch the page
	  if [ "$referPage" != "" ]; then
	    referURL="${baseURL}${referPage}"
	  fi

		# Decide which request to make (if page requires post data)
		if [ "$toFetch" == "/goform/GenieLogin" ]; then
			data=$(curl --connect-timeout 5 -v -s -e "$referURL" -b "$cookie_path" -c "$cookie_path" -X POST -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "loginUsername=$modem_username" --data-urlencode "loginPassword=$modem_password" --data "login=1" --data "webToken=$webToken" "${baseURL}${toFetch}"  2>&1)
			exitCode=$?
		elif [ "$toFetch" == "/goform/MultiLogin" ]; then
			data=$(curl --connect-timeout 5 -v -s -e "$referURL" -b "$cookie_path" -c "$cookie_path" -X POST -H 'Content-Type: application/x-www-form-urlencoded' --data "yes=yes" --data "Act=yes" --data "RetailSessionId=$retailSessionId" --data "webToken=$webToken" "${baseURL}${toFetch}"  2>&1)
			exitCode=$?
		else
			data=$(curl --connect-timeout 10 -v -s -e "$referURL" -b "$cookie_path" -c "$cookie_path" "${baseURL}${toFetch}" 2>&1)
			exitCode=$?
		fi


	  # Check for timeout and decide what to do next
	  if [ "$exitCode" == 28 ]; then 
		loginStatus "failed_timeout" "${toFetch}"
		exit 11
	  fi

	  # Get redirect location if any
	  redirectPage=$(echo "$data" | egrep 'window.top.location|< Location: ' | awk '{print $3}' | sed 's/[";]//g')

	  # Pull out hidden fields if applicable
	  webToken=$(echo "$data" | egrep -o 'name="webToken" value=[0-9]+' | egrep -o '[0-9]+')
	  retailSessionId=$(echo "$data" | egrep -o 'name=\"RetailSessionId\" value=\"[^\"]*\"' | awk -F "\"" '{print $4}')

	  # Decide if we need to submit a form and redirect
	  #loginStatus "toFetch=$toFetch"
	  if [ "$toFetch" == "/GenieLogin.asp" ]; then
	    redirectPage="/goform/GenieLogin"
	  elif [ "$toFetch" == "/MultiLogin.asp" ]; then
	    redirectPage="/goform/MultiLogin"
	  fi

	  # Drill down if applicable
	  if [ "$redirectPage" == "" ]; then
	    echo "$data"
	  else
	    loginStatus "redirect" "${redirectPage}"
	    pageDive "$redirectPage" "$toFetch"
	  fi
  fi
  depth=$(( $depth - 1 ))
}




# This function gets a dynamic session-cookie from the modem
function getSession () {

	# Perform the login, or verify we are already logged in
	pageDive > /dev/null 

}

# This function fetches the HTML status page from the modem for parsing
function getResult () {
# Finally, we can request the page

	result=$(pageDive '/DocsisStatus.asp' 'GenieIndex.asp')

	# If we were given GenieIndex instead of DocsisStatus, that means it went thru a redirect
	# so we will try exactly one more time.
	if [ "$(echo "$result" | grep -c '> GET /GenieIndex.asp HTTP/1.1')" == "1" ] ; then
		result=$(pageDive '/DocsisStatus.asp' 'GenieIndex.asp')
	fi


}



#############################
# Log in and fetch the data #
#############################

# Get the result from the modem
#getSession;
getResult;

# See if we were successful
if [ "$(echo "$result" | grep -c 'Downstream Bonded Channels')" == "0" ] ; then
	loginStatus "failed_retrying"

#	# If we failed (got a login prompt) try once more for new token
	rm "$cookie_path"
	pageDive '/MultiLogin.asp' > /dev/null
	pageDive '/Logout.asp' > /dev/null
	pageDive '/Logout.asp' > /dev/null
	rm "$cookie_path"

	getSession;
	getResult;
fi

# See if we were successful
if [ "$(echo "$result" | grep -c 'Downstream Bonded Channels')" == "0" ] ; then
	# At this point, if we weren't successful, we give up
	loginStatus "failed"
	exit 21
else
	loginStatus "success"
	#echo "$result"
fi

# Log out afterward
#pageDive '/Logout.asp' > /dev/null



####################
# Parse the result #
####################

#echo "Raw:"
#echo -e "$result"

#echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g' | awk -F "<tableclass=['\"]simpleTable['\"]>|</table>" '{print "\nStartup:\n" $2 "\n\nDown\n" $4 "\n\nUp\n" $6 "\n" }'
#startup_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/Hz//g;s/<[/]\?strong>//g;s/<![^>]*>//g;s/<[/]\?[bui]>//g' | awk -F "tableid=\"startup_procedure_table\"" '{print $2}'  )
startup_status=$(echo "$result" | tr '\n\r' ' ' | sed 's/\t//g;s/ //g;s/<!--Hiddenconfigfilefield-->//g' | awk -F "tableid=\"startup_procedure_table\"" '{print $2}' | awk -F "</table>" '{print $1}')
downstream_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/Hz//g;s/<[/]\?strong>//g;s/<![^>]*>//g' | awk -F "<[/]?tabindex=-1>" '{print $5}' | awk -F "</table>" '{print $1}')
upstream_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/Hz//g;s/<[/]\?strong>//g;s/<![^>]*>//g' | awk -F "<[/]?tabindex=-1>" '{print $7}' | awk -F "</table>" '{print $1}')
ofdm_downstream_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/Hz//g;s/<[/]\?strong>//g;s/<![^>]*>//g' | awk -F "<[/]?tabindex=-1>" '{print $9}' | awk -F "</table>" '{print $1}')
ofdm_upstream_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/Hz//g;s/<[/]\?strong>//g;s/<![^>]*>//g' | awk -F "<[/]?tabindex=-1>" '{print $11}' | awk -F "</table>" '{print $1}')
system_up_time=$(echo "$result" | grep "SystemUpTime" | awk -F "</b>|</font>" '{print $2}')

# Break out by line
startup_rows=$(echo "$startup_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')
downstream_rows=$(echo "$downstream_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')
upstream_rows=$(echo "$upstream_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')
ofdm_downstream_rows=$(echo "$ofdm_downstream_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')
ofdm_upstream_rows=$(echo "$ofdm_upstream_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')
# Note: system_up_time is a single value and does not need additional parsing

# Break out columns

# Parse out the startup status HTML table into JSON and publish
#echo "$startup_rows"
#echo "$startup_rows" | sed 's/<th[^>]*>[^<]*<\/th>//g;s/^<td[^>]*>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g' | grep -v "^$"
# Helper function to more easily build JSON per field
function pubStartupStatusValue () {
	# Break out field information
	procedure_name="$1"
	procedure_status="$2"
	procedure_comment="$3"
	# Build the message payload
	message=""
	# If exists, insert stattus
	if [ "$procedure_status" != "" ]; then
		if [[ "$procedure_status" =~ ^[0-9]+$ ]]; then
			message="${message} \"status\": $procedure_status"
		else
			message="${message} \"status\": \"$procedure_status\""
		fi
	fi
	# If exists, insert comment
	if [ "$procedure_comment" != "" ]; then
		# If message is not empty, insert separator comma
		if [ "$message" != "" ]; then
			message="${message}, "
		fi
		message="${message} \"comment\": \"$procedure_comment\""
	fi
	message="{ ${message} }"
	$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${mqtt_topic}/startup_procedure/${procedure_name}" -m "$message"
}
echo "$startup_rows" | grep -v "^$" | tail -n +2 | while read -r line; do
	to_parse=$(echo "$line" | sed 's/<th[^>]*>[^<]*<\/th>//g;s/^<td[^>]*>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g')
	procedure_name=$(echo $to_parse | awk '{print $1}')
	procedure_status=$(echo $to_parse | awk '{print $2}')
	procedure_comment=$(echo $to_parse | awk '{print $3}')
	pubStartupStatusValue "$procedure_name" "$procedure_status" "$procedure_comment"
done



# Parse out the downstream HTML table into JSON and publish
#echo "$downstream_rows" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g'
counter=0
echo "$downstream_rows" | tail -n +3 | while read -r line; do
	counter=$(($counter+1))
	#echo "${mqtt_topic}/downstream/$counter"
	to_parse=$(echo "$line" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g')
	message=$(
		echo "{"
		echo "$to_parse" | awk '{ print "\"Channel\": "$1","
															print "\"LockStatus\": \""$2"\","
															print "\"Modulation\": \""$3"\","
															print "\"ChannelID\": "$4","
															print "\"Frequency\": "$5","
															print "\"Power\": "$6","
															print "\"SNR_MER\" :"$7","
															print "\"Unerrored\" :"$8","
															print "\"Corrected\" :"$9","
															print "\"Uncorrectable\" :"$10 }'
		echo "}"
	)
	$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${mqtt_topic}/downstream/${counter}" -m "$message"
done

# Parse out the upstream HTML table into JSON and publish
#echo "$upstream_rows" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g'
counter=0
echo "$upstream_rows" | tail -n +3 | while read -r line; do
	counter=$(($counter+1))
	#echo "${mqtt_topic}/upstream/$counter"
	to_parse=$(echo "$line" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g')
	message=$(
		echo "{"
		echo "$to_parse" | awk '{ print "\"Channel\": "$1","
															print "\"LockStatus\": \""$2"\","
															print "\"Modulation\": \""$3"\","
															print "\"ChannelID\": "$4","
															print "\"Frequency\": "$5","
															print "\"Power\": "$6 }'
		echo "}"
	)
	$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${mqtt_topic}/upstream/${counter}" -m "$message"
done

# Parse out the OFDM downstream HTML table into JSON and publish
counter=0
echo "$ofdm_downstream_rows" | tail -n +3 | while read -r line; do
	counter=$(($counter+1))
	to_parse=$(echo "$line" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g')
	message=$(
		echo "{"
		echo "$to_parse" | awk '{ print "\"Channel\": "$1","
															print "\"LockStatus\": \""$2"\","
															print "\"Modulation_ProfileID\": \""$3"\","
															print "\"ChannelID\": "$4","
															print "\"Frequency\": "$5","
															print "\"Power\": "$6","
															print "\"SNR_MER\" :"$7","
															print "\"ActiveSubcarrier_NumberRange\": \""$8"\","
															print "\"Unerrored\" :"$9","
															print "\"Corrected\" :"$10","
															print "\"Uncorrectable\" :"$11 }'
		echo "}"
	)
	$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${mqtt_topic}/ofdm_downstream/${counter}" -m "$message"
done

# Parse out the OFDM upstream HTML table into JSON and publish
#echo "$upstream_rows" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g'
counter=0
echo "$ofdm_upstream_rows" | tail -n +3 | while read -r line; do
	counter=$(($counter+1))
	#echo "${mqtt_topic}/upstream/$counter"
	to_parse=$(echo "$line" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g')
	message=$(
		echo "{"
		echo "$to_parse" | awk '{ print "\"Channel\": "$1","
															print "\"LockStatus\": \""$2"\","
															print "\"Modulation_ProfileID\": \""$3"\","
															print "\"ChannelID\": "$4","
															print "\"Frequency\": "$5","
															print "\"Power\": "$6 }'
		echo "}"
	)
	$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${mqtt_topic}/ofdm_upstream/${counter}" -m "$message"
done

# Publish the system up time from the modem
message="{ \"SystemUpTime\": \"$system_up_time\" }"
$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${mqtt_topic}/system_up_time" -m "$message"

#echo ""
