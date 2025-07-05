#!/bin/bash

##############################################################################
# Jamf Pro API Script: Fix Invalid Site Assignments
##############################################################################

# This script is designed to fix devices in Jamf that have an invalid/null site assignment.
# It will check each device's site ID and update it to our companies default site if necessary.


##############################################################################
# Global User Set Variables
##############################################################################
# Edit these as needed for your Jamf environment
# Ensure you have the necessary permissions to run this script and access the Jamf Pro API.
# Check your Jamf instance for the correct site ID to use based on your needs

jamfUser="" # Input your Jamf username here
jamfPass="" # Input your Jamf password here
jamfurl="" # Input your Jamf Pro URL here, e.g., https://yourjamfpro.jamfcloud.com
default_site_id="" # Set the default site ID # to use for devices with invalid assignments

# Global Script Variables
# Blank values will be populated by the script, do not edit these
token="" 
tokenExpirationEpoch="0"
currentEpoch=""
jss_ids=()  # Array to store JSS IDs
max_parallel_requests=10  # Limit the number of parallel processes to 10

# Script Functions


getToken() {
  response=$(curl -s -u "$jamfUser":"$jamfPass" "$jamfurl"/api/v1/auth/token -X POST)
	token=$(echo "$response" | plutil -extract token raw -)
	tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
	tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
}

validateToken() {
    currentEpoch=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
    if [[ $((tokenExpirationEpoch - 300)) -le $currentEpoch ]]; then
        echo "Token is either expired or expiring soon, getting a new token..."
        getToken
    fi
}

invalidateToken() {
  responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${token}" "$jamfurl/api/v1/auth/invalidate-token" -X POST -s -o /dev/null)
  if [[ ${responseCode} == 204 ]]; then
    echo "Token has been invalidated"
    token=""
    tokenExpirationEpoch="0"
  elif [[ ${responseCode} == 401 ]]; then
		echo "Token already invalid"  
  else
    echo "An unknown error occurred invalidating the token"
  fi
  jamfUser=""
  jamfPass=""
}

# Function to fetch all JSS IDs
getAllJSSIDs() {
    echo "Fetching JSS ID list..."

    # Make the API call to get the list of computers (basic subset includes ID)
    response=$(curl -s -X 'GET' \
      "${jamfurl}/JSSResource/computers/subset/basic" \
      -H "accept: application/xml" \
      -H "Authorization: Bearer ${token}")

    # Extract all JSS IDs and save them to an array
    mapfile -t jss_ids < <(echo "$response" | xmllint --xpath '//computer/id/text()' - | tr '\n' '\n')
}

# Function to get device info, check site ID, and update if necessary
updateDeviceSite() {
    jss_id=$1
    token=$2  # Passed in as argument, not read from disk

    # Perform the curl request and capture the response
    response=$(curl -s -X 'GET' \
      "${jamfurl}/JSSResource/computers/id/${jss_id}/subset/General" \
      -H "accept: application/xml" \
      -H "Authorization: Bearer ${token}")

    site_id=$(echo "$response" | xmllint --xpath 'string(//computer/general/site/id)' -)
    device_name=$(echo "$response" | xmllint --xpath 'string(//computer/general/name)' -)

    if [[ "$site_id" == "-1" ]]; then
        curl -s -X 'PUT' \
          "${jamfurl}/JSSResource/computers/id/${jss_id}" \
          -H "Content-Type: application/xml" \
          -H "Authorization: Bearer ${token}" \
          -d "<computer><general><site><id>${default_site_id}</id></site></general></computer>" \
          >/dev/null 2>&1

        echo "JSS ID: $jss_id - $device_name has been changed to the correct site."
    fi
}

# Function to process JSS IDs in parallel
processJSSIDsInParallel() {
    export -f updateDeviceSite
    export jamfurl
    printf "%s\n" "${jss_ids[@]}" | xargs -P $max_parallel_requests -I {} bash -c 'updateDeviceSite "$@"' _ {} "$token"
}

# Main Script Logic
validateToken
getAllJSSIDs
echo "Total devices found: ${#jss_ids[@]}"
echo "Grab a coffee as this can take awhile. Searching for devices with an invalid Jamf Site Assignment..."
processJSSIDsInParallel
echo "Site reassignment process complete!"
invalidateToken
