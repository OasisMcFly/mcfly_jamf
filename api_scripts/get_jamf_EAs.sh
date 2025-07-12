#!/bin/bash

#---------------------------
# This script uses the Jamf Pro API to identify the IDs of computer extension
# attributes on a Jamf Pro server and performs the following:
#
# 1. Downloads each as XML
# 2. Identifies the EA/script name and type
# 3. Categorizes the downloaded extension attributes
# 4. If it's a macOS EA with a script, extracts the script
# 5. Saves any scritps as .sh or .py files by type
#---------------------------

#---------------------------
# USER CONFIGURATION - REQUIRED
# Set these values before running the script
#---------------------------
jamfUser=""         # Jamf Pro API username with sufficient read permissions
jamfPass=""         # Jamf Pro API password
jamfurl=""          # Full Jamf Pro URL (e.g. https://yourcompany.jamfcloud.com)
ea_download_dir="/path/to/folder/extension_attributes"  # Local path to save output files

#---------------------------
# Global Variables - Do not edit these
# These will be populated by the script
token=""
tokenExpirationEpoch="0"
current_epoch=""

#---------------------------
# Jamf API Bearertoken Script Functions
#---------------------------

# Requests a bearer token from the Jamf Pro API using the provided username and password.
getToken() {
	response=$(curl -s -u "$jamfUser":"$jamfPass" "$jamfurl"/api/v1/auth/token -X POST)
	token=$(echo "$response" | plutil -extract token raw -)
	tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
	tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
}

# Validates the current token by checking if it is expired or about to expire.
# If the token is expired or about to expire, it requests a new token.
validateToken() {
    current_epoch=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
    if [[ $((tokenExpirationEpoch - 300)) -le $current_epoch ]]; then
        echo "No valid token available, getting new token"
        getToken
    fi
}

# Invalidates the current API bearer token
# Sets Jamf user and password to empty strings
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

#---------------------------
# Script Specific Functions
#---------------------------

# Download the extension attribute information as raw XML,
# then format it to be readable.
DownloadComputerExtensionAttribute(){
	validateToken

	# Download EA XML to a temp file to check HTTP status before parsing content.
	# This avoids passing a failed or partial response to xmllint.
	httpStatus=$(curl -s -o /tmp/ea_"${ID}".xml -w "%{http_code}" --header "Authorization: Bearer ${token}" -H "Accept: application/xml" "${jamfurl}/JSSResource/computerextensionattributes/id/${ID}")
	if [[ "$httpStatus" -ne 200 ]]; then
		echo "Error: Failed to fetch EA ID $ID — HTTP status $httpStatus"
		return
	fi

	# Read the downloaded XML content for this EA ID into a variable and
	# Clean up the temporary file after reading
	ComputerExtensionAttribute=$(cat /tmp/ea_"${ID}".xml)
	rm /tmp/ea_"${ID}".xml

	# Warn if XML content is empty or malformed.
	if [[ -z "$ComputerExtensionAttribute" ]]; then
		echo "Error: Empty response for EA ID $ID"
		return
	fi

	# Attempt to format the XML content using xmllint.
	# If formatting fails, save the raw XML to a file for manual review.
	FormattedComputerExtensionAttribute=$(echo "$ComputerExtensionAttribute" | xmllint --format -)
	if [[ -z "$FormattedComputerExtensionAttribute" ]]; then
		echo "Warning: Failed to format EA ID $ID. Saving raw XML."
		echo "$ComputerExtensionAttribute" > "$ea_download_dir/EA_${ID}_unformatted.xml"
		return
	fi

	# Identify and display the extension attribute's name and type.
	DisplayName=$(echo "$FormattedComputerExtensionAttribute" | xmllint --xpath "/computer_extension_attribute/name/text()" - 2>/dev/null)
	EAInputType=$(echo "$FormattedComputerExtensionAttribute" | xmllint --xpath "/computer_extension_attribute/input_type/type/text()" - 2>/dev/null)

	if [[ -z "$DisplayName" ]]; then
		echo "Error: Missing display name for EA ID $ID"
	fi
	if [[ -z "$EAInputType" ]]; then
		echo "Error: Missing input type for EA ID $ID"
		return
	fi

	FinalAttribute=""
	FileName=""

	# If the EA is a script type, extract the embedded script contents and determine
	# if it's Python or shell by checking the shebang.
	# Otherwise, save the full EA definition as a formatted XML file.
	if [[ -n "$EAInputType" ]]; then
		if [[ "$EAInputType" = "script" ]]; then
			FileName=$(echo "$DisplayName" | sed 's/[:/[:cntrl:]]/_/g')
			FinalAttribute=$(echo "$FormattedComputerExtensionAttribute" | xmllint --xpath "/computer_extension_attribute/input_type/script/text()" - 2>/dev/null | perl -MHTML::Entities -pe 'decode_entities($_);')
			if [[ "$FinalAttribute" == \#!*python* ]]; then
				FileName="${FileName}.py"
			else
				FileName="${FileName}.sh"
			fi
		else
			FileName="${DisplayName}.xml"
			FinalAttribute="$FormattedComputerExtensionAttribute"
		fi
		echo "$FinalAttribute" | perl -MHTML::Entities -pe 'decode_entities($_);' > "$ea_download_dir/$FileName"
	else
		echo "Error: Unable to determine the attribute's input type"
	fi
}

#---------------------------
# Main Script Logic
#---------------------------

validateToken
mkdir -p "$ea_download_dir"
echo "Downloading extension attributes from \"$jamfurl\"..."

# Fetch the list of computer extension attribute IDs from the Jamf Pro API and save them to an array
ComputerExtensionAttribute_id_list=$(
  curl -s --header "Authorization: Bearer ${token}" \
  -H "Accept: application/xml" \
  "${jamfurl}/JSSResource/computerextensionattributes" |
  xmllint --xpath '//computer_extension_attributes/computer_extension_attribute/id/text()' - 2>/dev/null
)


# Set Parallelization for the EA download execution.
MaximumConcurrentJobs=10
ActiveJobs=0

# Loop through each ID and download the corresponding extension attribute
for ID in $ComputerExtensionAttribute_id_list; do
   ((ActiveJobs=ActiveJobs%MaximumConcurrentJobs)); ((ActiveJobs++==0)) && wait
   DownloadComputerExtensionAttribute &
done

invalidateToken

exit 0
