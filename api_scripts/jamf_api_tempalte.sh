#!/bin/bash

#Global Variables
jamfUser=""
jamfPass=""
jamfurl=""
token=""
tokenExpirationEpoch="0"
current_epoch=""

# Script Functions
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

# Main Script Logic

validateToken

# some code

invalidateToken
