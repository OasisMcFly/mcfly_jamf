#!/bin/sh

# Get jamf_api_recipe source file
# Source Variable List: jamfUser, jamfPass, jamfurl, bearerToken
# Source Function list: validateToken, invaladiteToken
source "path_to_git_repo/jamf_api_recipe"

#Global Variables
log_file="path_to_log_file" # Log file to record errors
success_number=() # Initialize an array to track Success numbers
fail_number=() # Initialize an array to track Failure numbers
failed_to_update=() # Initialize an array to track failed Jamf ID numbers

# update array
# Can be ran on a single Jamf ID or an array of many
# place Jamf ID#s in the array with a space between them
# Example: needs_update=(1 4 7 19 201 498 1011)
needs_update=()

# Main Script Logic
validateToken

for id in "${needs_update[@]}"; do
  echo "Updating computer with ID: $id"
  
  response=$(curl -X 'POST' \
    "$jamfurl/api/v1/jamf-management-framework/redeploy/$id" \
    -H 'accept: application/json' \
    -H "Authorization: Bearer $token" \
    -d '' 2>&1)  # Redirect both stdout and stderr to capture the response
  
  if [[ $response == *"httpStatus"* && $response == *"500"* ]]; then
    echo "Failed to update computer with ID: $id. Check log file for more info"
    echo "Failed to update computer with ID: $id" >> "$log_file"
    echo "Error details: $response" >> "$log_file"
    fail_number+=1
    failed_to_update+=("$id")
  else
    echo "Successfully updated computer with ID: $id"
    echo "Successfully updated computer with ID: $id" >> "$log_file"
    success_number+=1
  fi
    
  validateToken
done

# Final report and exit
echo "Failed to update items: $failed_to_update" >> "$log_file"
echo "Successful: ${#success_number}"
echo "Failed: ${#fail_number}"
invalidateToken
exit
