#!/bin/bash

INPUT_FILE="$1"
OUTPUT_CSV="$2"

if [[ -z "$INPUT_FILE" || -z "$OUTPUT_CSV" ]]; then
    echo "Usage: $0 <input_log_file> <output_csv_file>"
    exit 1
fi

# Helper: CSV escape
csv_escape() {
    local s="$1"
    s="${s//"/""}"
    printf '"%s"' "$s"
}

# Read the file and split into blocks
blocks=()
block=""
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^\*{10,}$ ]]; then
        if [[ -n "$block" ]]; then
            blocks+=("$block")
            block=""
        fi
    else
        block+="$line"$'\n'
    fi
done < "$INPUT_FILE"
if [[ -n "$block" ]]; then
    blocks+=("$block")
fi

# Find max number of users in any block
max_users=0
declare -a parsed_blocks

for block in "${blocks[@]}"; do
    # Extract fields
    timestamp=$(echo "$block" | grep -m1 -E "^Execution Time:" | sed 's/^Execution Time: //')
    server=$(echo "$block" | grep -m1 -E "^Hostname:" | sed 's/^Hostname: //')
    tomcat_version=$(echo "$block" | grep -m1 -E "^Tomcat Version:" | sed 's/^Tomcat Version: //')
    tomcat_home=$(echo "$block" | grep -m1 -E "^Tomcat Home:" | sed 's/^Tomcat Home: //')
    config_path=$(echo "$block" | grep -m1 -E "^Config Path:" | sed 's/^Config Path: //')
    credential_handler=$(echo "$block" | grep -m1 -E "^[[:space:]]*Credential Handler:" | sed 's/^[[:space:]]*Credential Handler: //')
    algorithm=$(echo "$block" | grep -m1 -E "^[[:space:]]*Algorithm:" | sed 's/^[[:space:]]*Algorithm: //')
    iterations=$(echo "$block" | grep -m1 -E "^[[:space:]]*Iterations:" | sed 's/^[[:space:]]*Iterations: //')
    salt_length=$(echo "$block" | grep -m1 -E "^[[:space:]]*Salt Length:" | sed 's/^[[:space:]]*Salt Length: //')
    overall_status=$(echo "$block" | grep -m1 -E "^Overall Status:" | sed 's/^Overall Status: //')
    compliance=$(echo "$block" | grep -m1 -E "^[[:space:]]*Status:" | sed 's/^[[:space:]]*Status: //')
    audit_completed=$(echo "$block" | grep -q "^Audit completed" && echo "true" || echo "false")

    # Compliance details (semicolon separated)
    compliance_details=$(echo "$block" | grep -E "COMPLIANCE:|WARNING:|is owned by|permissions|root check|Root Execution Compliance Check|Detection method:|Tomcat process is not running as root|Tomcat service is configured to run as root|Tomcat service is configured to run as user|has insecure permissions|permissions are secure" | paste -sd ';' -)
    optional_warnings=$(echo "$block" | grep -E "^Warning: " | sed 's/^Warning: //' | paste -sd ';' -)

    # Users
    users=()
    while read -r userline; do
        userline=$(echo "$userline" | sed 's/^ *//;s/ *$//')
        # Match: username | passwordtype | compliance (allowing for extra spaces)
        if [[ "$userline" =~ ^([^|]+)[[:space:]]*\|[[:space:]]*([^|]+)[[:space:]]*\|[[:space:]]*([^|]+)$ ]]; then
            username="${BASH_REMATCH[1]}"
            passwordtype="${BASH_REMATCH[2]}"
            usercompliance="${BASH_REMATCH[3]}"
            users+=("$username|||$passwordtype|||$usercompliance")
        fi
    done < <(echo "$block" | awk '/\|/ && !/User Audit Results/ && !/Username \| Password Type \| Compliance/ && !/----/ {print}')

    if (( ${#users[@]} > max_users )); then
        max_users=${#users[@]}
    fi

    # Only add if this is a real audit block
    if [[ -n "$server" && -n "$tomcat_version" ]]; then
        parsed_blocks+=("$(csv_escape "$server"),$(csv_escape "$timestamp"),$(csv_escape "$tomcat_home"),$(csv_escape "$config_path"),$(csv_escape "$tomcat_version"),$(csv_escape "$credential_handler"),$(csv_escape "$algorithm"),$(csv_escape "$iterations"),$(csv_escape "$salt_length"),$(csv_escape "$overall_status"),$(csv_escape "$compliance"),$(csv_escape "$compliance_details"),$(csv_escape "$optional_warnings"),$audit_completed,${users[*]}")
    fi
done

# Write header
header="Server,Timestamp,TomcatHome,ConfigPath,TomcatVersion,CredentialHandler,Algorithm,Iterations,SaltLength,OverallStatus,Compliance,ComplianceDetails,OptionalWarnings,AuditCompleted"
for ((i=1; i<=max_users; i++)); do
    header+=",Username$i,PasswordType$i,UserCompliance$i"
done
echo "$header" > "$OUTPUT_CSV"

# Write rows
for row in "${parsed_blocks[@]}"; do
    IFS=',' read -r server timestamp tomcat_home config_path tomcat_version credential_handler algorithm iterations salt_length overall_status compliance compliance_details optional_warnings audit_completed users_str <<< "$row"
    IFS=' ' read -r -a users_arr <<< "$users_str"
    out="$server,$timestamp,$tomcat_home,$config_path,$tomcat_version,$credential_handler,$algorithm,$iterations,$salt_length,$overall_status,$compliance,$compliance_details,$optional_warnings,$audit_completed"
    for ((i=0; i<max_users; i++)); do
        if [[ -n "${users_arr[$i]}" ]]; then
            IFS='|||' read -r uname ptype ucomp <<< "${users_arr[$i]}"
            out+="$(csv_escape "$uname"),$(csv_escape "$ptype"),$(csv_escape "$ucomp")"
        else
            out+=',,,'
        fi
    done
    echo "$out" >> "$OUTPUT_CSV"
done

echo "Exported to CSV: $OUTPUT_CSV" 