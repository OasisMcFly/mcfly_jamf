#!/bin/zsh

#Global Variables
client_id=""
client_secret=""
jamfurl=""
bearerToken=""
tokenExpirationEpoch="0"

# Jamf Client ID Script Functions
getToken() {
  checkCredentials
  response=$(curl --silent --location --request POST "${jamfurl}/api/oauth/token" \
 	  --header "Content-Type: application/x-www-form-urlencoded" \
 	  --data-urlencode "client_id=${client_id}" \
 	  --data-urlencode "grant_type=client_credentials" \
 	  --data-urlencode "client_secret=${client_secret}")
  bearerToken=$(echo "$response" | plutil -extract access_token raw -)
  tokenExpiresIn=$(echo "$response" | plutil -extract expires_in raw -)
  tokenExpirationEpoch=$(($current_epoch + $tokenExpiresIn - 300))
}

validateToken() {
 	current_epoch=$(date +%s)
    if [[ tokenExpirationEpoch -le current_epoch ]]; then
        echo "No valid token available, getting new token"
        getToken
    fi
}

invalidateToken() {
	responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${bearerToken}" $jamfurl/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
	if [[ ${responseCode} == 204 ]]; then
		echo "Token is invalidated"
		bearerToken=""
		tokenExpirationEpoch="0"
	elif [[ ${responseCode} == 401 ]]; then
		echo "Token already invalid"
	else
		echo "An unknown error occurred invalidating the token"
	fi
	client_id=""
    client_secret=""
}


# Main Script
validateToken
# some code
invalidateToken
exit 0
