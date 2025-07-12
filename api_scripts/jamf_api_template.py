#!/usr/local/bin/managed_python3

"""
Jamf API Recipe Script
Contains functions to manage Jamf Pro API bearer tokens:
(get_token, validate_token, invalidate_token)
and variables for user credentials and API URL:
(JAMF_USER, JAMF_PASS, JAMF_URL)
"""

from datetime import datetime, timezone
import requests

# Global Variables
JAMF_USER = ''
JAMF_PASS = ''
JAMF_URL = ''
BEARER_TOKEN = ''
TOKEN_EXPIRATION_EPOCH = 0

# Jamf API Bearer Token Functions
def get_token():
    """
    Obtains a new bearer token from the Jamf Pro API.
    """
    global BEARER_TOKEN, TOKEN_EXPIRATION_EPOCH
    response = requests.post(f'{JAMF_URL}/api/v1/auth/token', auth=(JAMF_USER, JAMF_PASS), timeout=20)
    data = response.json()
    BEARER_TOKEN = data['token']
    expiration_str = data['expires'].split('.')[0]
    expiration_dt = datetime.strptime(expiration_str, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
    TOKEN_EXPIRATION_EPOCH = int(expiration_dt.timestamp())

def validate_token():
    """
    Checks if the current bearer token is valid.
    If the token is expired or about to expire, obtains a new token.
    """
    now_utc_epoch = int(datetime.now(timezone.utc).timestamp())
    if TOKEN_EXPIRATION_EPOCH - 300 <= now_utc_epoch:
        print("No valid token available, getting new token")
        get_token()

def invalidate_token():
    """
    Invalidates the current bearer token and clears credentials.
    """
    global BEARER_TOKEN, TOKEN_EXPIRATION_EPOCH, JAMF_USER, JAMF_PASS
    headers = {"Authorization": f"Bearer {BEARER_TOKEN}"}
    response = requests.post(f"{JAMF_URL}/api/v1/auth/invalidate-token", headers=headers, timeout=20)

    if response.status_code in [204, 401]:
        print("Token is invalidated")
        BEARER_TOKEN = ''
        TOKEN_EXPIRATION_EPOCH = 0
    else:
        print(f"Unknown error invalidating token: {response.status_code} - {response.text}")

    JAMF_USER = ''
    JAMF_PASS = ''

# Main Script
##################

validate_token()

#some test code

invalidate_token()
