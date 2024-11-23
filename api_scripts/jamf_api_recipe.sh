#!/bin/zsh

# Written by Nathaniel Clements
# Based on Jamf API recipes for Bearer Token Authorization and Client Credentials Authorization

# Jamf API Token recipe with all the relevant functions needed to access the Jamf API
# with either a username/password or with clientId/clientSecret. The script will ask which auth type
# you want to set and set a "tokenType" variable based on that. The script is designed 
# to only ever need you to call two functions: "validateToken" and "invalidateToken".
# All the other functions are called through those functions. The script expects that you will
# run the script locally. The script will prompt you for all needed variables including your 
# jamf credentials and url.

# Usage
########
# validateToken
# ...some code...
# invalidateToken

#Global Variables
jamfUser=""
jamfPass=""
jamfurl=""
token=""
tokenExpirationEpoch="0"
tokenType=""
current_epoch=""

# Script Functions

checkCredentials() {
    if [[ -z "$tokenType" ]]; then
        echo "Token type needs to be set!"
        echo -n "Enter 0 for Username/password or Enter 1 for clientID/secret: "
        read tokenType
    fi

    if [[ "$tokenType" != "0" && "$tokenType" != "1" ]]; then
        log_error "Invalid token type. Exiting..."
        exit 1
    fi

    if [[ -z "$jamfurl" ]]; then
          echo "Jamf URL needs to be set!"
          echo -n "Please provide the full url to your Jamf instance:"
          read jamfurl
      fi   

    if [[ -z "$jamfUser" ]]; then
        if [[ "$tokenType" = "0" ]]; then
            echo -n "Enter Jamf Username: "
        elif [[ "$tokenType" = "1" ]]; then
            echo -n "Enter Jamf Client ID: "
        fi
        read jamfUser
    fi

    if [[ -z "$jamfPass" ]]; then
        if [[ "$tokenType" = "0" ]]; then
            echo -n "Enter Jamf Password: "
        elif [[ "$tokenType" = "1" ]]; then
            echo -n "Enter Jamf Client Secret: "
        fi
        read -s jamfPass
        echo ""
    fi
}

getBearerToken() {
  response=$(curl -s -u "$jamfUser":"$jamfPass" "$jamfurl"/api/v1/auth/token -X POST)
	token=$(echo "$response" | plutil -extract token raw -)
	tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
	tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
}

getAccessToken() {
  response=$(curl --silent --location --request POST "${jamfurl}/api/oauth/token" \
 	  --header "Content-Type: application/x-www-form-urlencoded" \
 	  --data-urlencode "jamfUser=${jamfUser}" \
 	  --data-urlencode "grant_type=client_credentials" \
 	  --data-urlencode "jamfPass=${jamfPass}")
  token=$(echo "$response" | grep -o '"access_token":"[^"]*' | sed 's/"access_token":"//')
  tokenExpiresIn=$(echo "$response" | grep -o '"expires_in":[0-9]*' | sed 's/"expires_in"://')
  tokenExpirationEpoch=$(($(date +%s) + $token_expires_in - 1))
}

validateBearerToken() {
    current_epoch=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
    if [[ $((tokenExpirationEpoch - 300)) -le $current_epoch ]]; then
        echo "No valid token available, getting new token"
        getBearerToken
    fi
}

validateAccessToken() {
 	current_epoch=$(date +%s)
    if [[ tokenExpirationEpoch -le current_epoch ]]; then
        echo "No valid token available, getting new token"
        getAccessToken
    fi
}

validateToken() {
  checkCredentials
  if [[ "$tokenType" = "0" ]]; then
    validateBearerToken
  elif [[ "$tokenType" = "1" ]]; then
    validateAccessToken
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
