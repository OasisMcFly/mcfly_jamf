#!/bin/bash

# This script uses the Jamf Pro API to identify the IDs of MacOS Scripts on a Jamf Pro server and performs the following:
#
# 1. Downloads each as XML
# 2. Identifies the script name and extracts the script contents
# 5. Saves scripts as .sh or .py files by type

# Bearer token Variables
jamfUser=""
jamfPass=""
jamfurl=""
token=""
tokenExpirationEpoch="0"
current_epoch=""

# Script Specific Variables
script_download_dir="/path/to/folder//macos_scripts"  # Change this to your desired directory

# API Bearertoken Script Functions
######################################

getToken() {
	response=$(curl -s -u "$jamfUser":"$jamfPass" "$jamfurl"/api/v1/auth/token -X POST)
	token=$(echo "$response" | plutil -extract token raw -)
	tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
	tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
}

validateToken() {
    current_epoch=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
    if [[ $((tokenExpirationEpoch - 300)) -le $current_epoch ]]; then
        echo "No valid token available, getting new token"
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

# Download the script information as raw XML,
# then format it to be readable.
DownloadScript(){
    validateToken

    FormattedScript=$(curl -s --header "Authorization: Bearer ${token}" -H "Accept: application/xml" "${jamfurl}/JSSResource/scripts/id/${ID}" -X GET | xmllint --format - )
    if [[ -z "$FormattedScript" || "$FormattedScript" == *"Document is empty"* ]]; then
        echo "ERROR: Failed to download or parse script with ID $ID" >&2
        return
    fi

    # Identify and display the script's name.
    DisplayName=$(echo "$FormattedScript" | xmllint --xpath "/script/name/text()" - 2>/dev/null | sed -e 's|:|(colon)|g' -e 's/\//\\/g')
    if [[ -z "$DisplayName" ]]; then
        echo "ERROR: Could not extract script name for ID $ID" >&2
        return
    fi

    # Extract script contents to a temporary variable
    ScriptContents=$(echo "$FormattedScript" | xmllint --xpath '/script/script_contents/text()' - 2>/dev/null | sed -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e 's/&amp;/\&/g')
    if [[ -z "$ScriptContents" ]]; then
        echo "ERROR: Could not extract script contents for ID $ID" >&2
        return
    fi

    # Determine file extension based on shebang
    if echo "$ScriptContents" | grep -qE '^#!.*(python|python3)'; then
        extension="py"
    elif echo "$ScriptContents" | grep -qE '^#!.*(zsh|bash|sh)'; then
        extension="sh"
    else
        extension="txt"
    fi

    output_path="$script_download_dir/${DisplayName}.${extension}"
    echo "$ScriptContents" > "$output_path"
}

# Main Script Logic
#################################
echo "Downloading scripts from $jamfurl..."
validateToken
mkdir -p "$script_download_dir"

Script_id_list=$(/usr/bin/curl -s --header "Authorization: Bearer ${token}" -H "Accept: application/xml" "${jamfurl}/JSSResource/scripts" | xmllint --xpath "//id" - 2>/dev/null)
Script_id=$(echo "$Script_id_list" | grep -Eo "[0-9]+")

# Download latest version of all advanced computer searches. For performance reasons, we
# parallelize the execution.
MaximumConcurrentJobs=10
ActiveJobs=0

for ID in ${Script_id}; do
   ((ActiveJobs=ActiveJobs%MaximumConcurrentJobs)); ((ActiveJobs++==0)) && wait
   DownloadScript &
done

invalidateToken

exit 0
