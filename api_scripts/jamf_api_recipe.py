#!/opt/homebrew/opt/python3

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
bearer_token = ''
token_expiration_epoch = 0

# Jamf API Bearer Token Functions
def get_token():
    """
    Obtains a new bearer token from the Jamf Pro API.
    """
    global bearer_token, token_expiration_epoch
    response = requests.post(f'{JAMF_URL}/api/v1/auth/token', auth=(JAMF_USER, JAMF_PASS), timeout=20)
    data = response.json()
    bearer_token = data['token']
    expiration_str = data['expires'].split('.')[0]
    expiration_dt = datetime.strptime(expiration_str, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
    token_expiration_epoch = int(expiration_dt.timestamp())

def validate_token():
    """
    Checks if the current bearer token is valid.
    If the token is expired or about to expire, obtains a new token.
    """
    now_utc_epoch = int(datetime.now(timezone.utc).timestamp())
    if token_expiration_epoch - 300 <= now_utc_epoch:
        print("No valid token available, getting new token")
        get_token()

def invalidate_token():
    """
    Invalidates the current bearer token and clears credentials.
    """
    global bearer_token, token_expiration_epoch, JAMF_USER, JAMF_PASS
    headers = {"Authorization": f"Bearer {bearer_token}"}
    response = requests.post(f"{JAMF_URL}/api/v1/auth/invalidate-token", headers=headers, timeout=20)

    if response.status_code in [204, 401]:
        print("Token is invalidated")
        bearer_token = ''
        token_expiration_epoch = 0
    else:
        print(f"Unknown error invalidating token: {response.status_code} - {response.text}")

    JAMF_USER = ''
    JAMF_PASS = ''

# Main Script
validate_token()
#some test code
invalidate_token()
