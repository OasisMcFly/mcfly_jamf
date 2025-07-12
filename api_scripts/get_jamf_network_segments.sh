#!/bin/zsh

#Global Variables
jamfUser=""
jamfPass=""
jamfurl=""
token=""
tokenExpirationEpoch="0"
current_epoch=""
output_file="/path/to/folder/NetworkSegments.csv"

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

# Function to fetch specific network segment info
fetch_network_segment_info() {
    local segment_id="$1"
    curl -s -X GET "$jamfurl/JSSResource/networksegments/id/$segment_id" \
        -H "Authorization: Bearer $token" \
        -H "Accept: application/json" | jq -r '
            if .network_segment then
                .network_segment |
                [
                    (.id // ""),
                    (.name // ""),
                    (.starting_address // ""),
                    (.ending_address // ""),
                    (.distribution_server // ""),
                    (.distribution_point // ""),
                    (.url // ""),
                    (.swu_server // ""),
                    (.building // ""),
                    (.departments // ""),
                    (.override_buildings // ""),
                    (.override_departments // "")
                ] | @csv
            else
                "ERROR: Segment not found or empty"
            end
        '
}

#function to fetch all network segments
fetch_network_segments() {
    curl -s -X GET "$jamfurl/JSSResource/networksegments" \
        -H "Authorization: Bearer $token" \
        -H "Accept: application/xml"
}

# Main Script Logic
########################

validateToken
echo "Retrieving Network Segments..."

network_segment_response=$(fetch_network_segments)
segment_ids=($(echo "$network_segment_response" | xmllint --xpath "//network_segment/id/text()" - 2>/dev/null))

# Parallelize the command for performance
MaximumConcurrentJobs=10
ActiveJobs=0

# Write to CSV
echo "Saving to $output_file..."
echo "ID,Name,Starting Address,Ending Address,Distribution Server,Distribution Point,URL,SWU Server,Building,Department,Override Buildings,Override Departments" > "$output_file"

for id in "${segment_ids[@]}"; do
    ((ActiveJobs=ActiveJobs%MaximumConcurrentJobs))
    ((ActiveJobs++==0)) && wait

    {
        network_segment_info_response=$(fetch_network_segment_info "$id")
        echo "$network_segment_info_response" >> "$output_file"
    } &
done

wait  # Wait for any remaining background jobs to complete

# Resort the output csv by Id number
# Extract the header
header=$(head -n 1 "$output_file")

# Sort the rest of the file by the first column (numerically), skipping the header
tail -n +2 "$output_file" | sort -t, -k1,1n > "${output_file}.sorted"

# Combine header + sorted data
echo "$header" > "$output_file"
cat "${output_file}.sorted" >> "$output_file"

# Clean up temp file
rm -f "${output_file}.sorted"

echo "Done! Network Segments saved to $output_file."
invalidateToken

exit
