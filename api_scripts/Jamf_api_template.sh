#!/bin/zsh

# Get jamf_api_recipe source file
# Source Variable List: jamfUser, jamfPass, jamfurl, bearerToken
# Source Function list: validateToken, invaladiteToken
source "path_to_git_repo/jamf_api_recipe"

# Main Script Logic
########################

validateToken

#some code

invalidateToken

exit