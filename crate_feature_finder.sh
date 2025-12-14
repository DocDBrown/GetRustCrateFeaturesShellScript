#!/bin/bash

# Base URL for the crates.io API
CRATES_IO_API_BASE="https://crates.io/api/v1"
# Delay between API requests to be polite (in seconds)
REQUEST_DELAY=0.2

# Function to fetch JSON from a URL and handle basic errors
# Arguments:
#   $1: URL to fetch
# Returns:
#   JSON string on success, empty string on failure
#   Returns 0 on success, 1 on curl/network failure, 0 for 404 (handled case)
fetch_json() {
	local url="$1"
	local response_and_status
	local http_status
	local response_body

	# Use -s for silent, --max-time for timeout
	# -w "\n%{http_code}" appends the HTTP status code on a new line to stdout.
	# This helps in reliably separating the body from the status code.
	if ! response_and_status=$(curl -s --max-time 10 -w $'\n%{http_code}' "$url" 2>/dev/null); then
		echo "Error: curl command failed for $url" >&2
		return 1
	fi

	# Ensure we have some output to parse
	if [[ -z "$response_and_status" ]]; then
		echo "Error: curl command failed for $url" >&2
		return 1
	fi

	# Split response into body and status code using bash string ops (portable across GNU/BSD).
	http_status="${response_and_status##*$'\n'}"
	response_body="${response_and_status%$'\n'*}"

	# Handle 2xx success, 404 as handled empty, and other statuses as errors.
	if [[ "$http_status" =~ ^2[0-9][0-9]$ ]]; then
		printf '%s' "$response_body"
		sleep "$REQUEST_DELAY" # Be polite
		return 0
	elif [[ "$http_status" == "404" ]]; then
		# Crate or version not found. This is a handled case, not necessarily an error for the script's logic.
		printf '%s' ""
		sleep "$REQUEST_DELAY"
		return 0
	else
		echo "Error: Failed to fetch $url. HTTP Status: $http_status. Response: ${response_body:0:100}..." >&2
		return 1
	fi
}

# Only run main when executed directly, not when sourced by tests
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	# Main script logic
	if [[ $# -eq 0 ]]; then
		echo "Usage: $0 <crate_name_1> [crate_name_2] ..." >&2
		exit 1
	fi

	for crate_name in "$@"; do
		# 1. Try to get max_version from /api/v1/crates/{name}
		CRATE_INFO_URL="${CRATES_IO_API_BASE}/crates/${crate_name}"
		if ! crate_info_json=$(fetch_json "$CRATE_INFO_URL"); then
			echo "Skipping '$crate_name': Failed to retrieve crate info due to network/curl error." >&2
			continue
		fi

		target_version=""
		if [[ -n "$crate_info_json" ]]; then
			max_version=$(printf '%s' "$crate_info_json" | jq -r '.crate.max_version // empty')
			if [[ -n "$max_version" ]]; then
				target_version="$max_version"
			fi
		fi

		if [[ -z "$target_version" ]]; then
			# 2. If max_version is empty or not found, fetch all versions and pick the first non-yanked one
			VERSIONS_URL="${CRATES_IO_API_BASE}/crates/${crate_name}/versions"
			if ! versions_json=$(fetch_json "$VERSIONS_URL"); then
				echo "Skipping '$crate_name': Failed to retrieve versions list due to network/curl error." >&2
				continue
			fi

			if [[ -n "$versions_json" ]]; then
				# Find the first non-yanked version number
				target_version=$(printf '%s' "$versions_json" | jq -r '.versions[] | select(.yanked == false) | .num' | head -n 1)
			fi

			if [[ -z "$target_version" ]]; then
				echo "Skipping '$crate_name': No non-yanked versions found or could not retrieve versions." >&2
				continue
			fi
		fi

		# 3. Now that we have a target_version, fetch its metadata and check features
		VERSION_METADATA_URL="${CRATES_IO_API_BASE}/crates/${crate_name}/${target_version}"
		if ! version_metadata_json=$(fetch_json "$VERSION_METADATA_URL"); then
			echo "Skipping '$crate_name': Failed to retrieve metadata for version '$target_version' due to network/curl error." >&2
			continue
		fi

		if [[ -z "$version_metadata_json" ]]; then
			echo "Skipping '$crate_name': Could not retrieve metadata for version '$target_version' (empty response)." >&2
			continue
		fi

		# Check if the features map is non-empty
		feature_count=$(printf '%s' "$version_metadata_json" | jq -r '.version.features | to_entries | length // 0')

		if [[ "$feature_count" -gt 0 ]]; then
			echo "$crate_name"
		fi
	done
fi
