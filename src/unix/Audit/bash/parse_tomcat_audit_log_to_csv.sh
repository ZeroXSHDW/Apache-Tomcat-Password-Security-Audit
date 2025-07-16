#!/bin/bash

# Ensure running with Bash
if [ -z "$BASH_VERSION" ]; then
  echo "This script must be run with bash."
  exit 1
fi

# Set locale for UTF-8 compatibility
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# Minimal argument check
if [ $# -lt 2 ]; then
  echo "Usage: $0 <input_log_file> <output_csv_file>"
  exit 1
fi

INPUT_FILE="$1"
OUTPUT_CSV="$2"

# Convert input file to Unix line endings (handles Windows \r\n)
TMPUNIX=$(mktemp)
tr -d '\r' < "$INPUT_FILE" > "$TMPUNIX"
INPUT_FILE="$TMPUNIX"

# CSV escape function for proper output (handles commas, quotes, newlines)
csv_escape() {
    local s="$1"
    s="${s//\"/\"\"}" # double quotes
    # If the field contains a comma, quote, or newline, wrap in double quotes
    if [[ "$s" == *\"* || "$s" == *,* || "$s" == *$'\n'* ]]; then
        printf '"%s"' "$s"
    else
        printf '%s' "$s"
    fi
}

# Fuzzy field matching: returns the first field in the block that matches the target (case-insensitive, allows for typos)
fuzzy_field_match() {
    local block="$1"
    local field="$2"
    local best_match=""
    local best_score=0
    while IFS= read -r line; do
        trimmed=$(echo "$line" | sed 's/^ *//;s/ *$//')
        echo "$trimmed" | grep -q ":" || continue
        candidate_field=$(echo "$trimmed" | cut -d: -f1 | sed 's/^ *//;s/ *$//')
        candidate_value=$(echo "$trimmed" | cut -d: -f2- | sed 's/^ *//;s/ *$//')
        score=0
        i=0
        while [ $i -lt ${#field} ] && [ $i -lt ${#candidate_field} ]; do
            c1=$(echo "${field:$i:1}" | tr '[:upper:]' '[:lower:]')
            c2=$(echo "${candidate_field:$i:1}" | tr '[:upper:]' '[:lower:]')
            [ "$c1" = "$c2" ] && score=$((score+1)) || break
            i=$((i+1))
        done
        if [ $score -gt $best_score ]; then
            best_score=$score
            best_match="$candidate_value"
        fi
    done <<< "$block"
    if [ $best_score -ge $(( (${#field}*2)/5 )) ]; then
        echo "$best_match"
    fi
}

# Helper function: extract a field from a block (fuzzy, trims whitespace)
extract_field() {
    local block="$1"
    local field="$2"
    fuzzy_field_match "$block" "$field"
}

# Helper function: extract user rows from a block
extract_users() {
    local block="$1"
    local in_table=0
    echo "$block" | while IFS= read -r line; do
        trimmed=$(echo "$line" | sed 's/^ *//;s/ *$//')
        if [ $in_table -eq 0 ]; then
            echo "$trimmed" | grep -iq 'User Audit Results:' && in_table=1 && continue
        fi
        if [ $in_table -eq 1 ]; then
            # Skip the user table header row (use POSIX grep -i and avoid | inside [] brackets)
            echo "$trimmed" | grep -i '^username[ ]*|[ ]*password type[ ]*|[ ]*compliance' >/dev/null && continue
            # Only accept lines that match the user row pattern: non-empty, three fields separated by pipes, not dashes or headers
            echo "$trimmed" | grep -E '^[^|][^|]*\|[^|][^|]*\|[^|][^|]*$' >/dev/null || continue
            IFS='|' read uname ptype ucomp <<EOF
$trimmed
EOF
            uname_trim=$(echo "$uname" | sed 's/^ *//;s/ *$//')
            ptype_trim=$(echo "$ptype" | sed 's/^ *//;s/ *$//')
            ucomp_trim=$(echo "$ucomp" | sed 's/^ *//;s/ *$//')
            # Skip if any field is empty or only dashes
            [ -z "$uname_trim" ] || [ -z "$ptype_trim" ] || [ -z "$ucomp_trim" ] && continue
            echo "$uname_trim" | grep -q '^[ -]*$' && continue
            echo "$ptype_trim" | grep -q '^[ -]*$' && continue
            echo "$ucomp_trim" | grep -q '^[ -]*$' && continue
            echo "$uname_trim|$ptype_trim|$ucomp_trim"
            # End user table if we hit a line that looks like a section divider or the end of the block
            echo "$trimmed" | grep -Eq '^=+$|^Overall Status:' && break
        fi
    done
}

# Helper function: extract compliance/warning lines
extract_compliance_details() {
    local block="$1"
    local inblock=0
    local details=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^====\ Tomcat\ Root\ Execution\ Compliance\ Check\ ==== ]]; then
            inblock=1
            continue
        fi
        if [[ "$line" =~ ^====\ End\ of\ Root\ Execution\ Compliance\ Check\ ==== ]]; then
            inblock=0
        fi
        if [ $inblock -eq 1 ]; then
            details+=("$(echo "$line" | sed 's/^ *//;s/ *$//')")
        fi
    done <<< "$block"
    local joined=""
    for d in "${details[@]}"; do
        if [ -n "$joined" ]; then
            joined+=";"
        fi
        joined+="$d"
    done
    echo "$joined"
}

extract_optional_warnings() {
    local block="$1"
    local warnings=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*Warning: ]]; then
            warnings+=("$(echo "$line" | sed 's/^[ ]*Warning:[ ]*//I;s/^ *//;s/ *$//')")
        fi
    done <<< "$block"
    local joined=""
    for w in "${warnings[@]}"; do
        if [ -n "$joined" ]; then
            joined+=";"
        fi
        joined+="$w"
    done
    echo "$joined"
}

# Split input into blocks using Bash array (robust for macOS)
blocks=()
current_block=""
while IFS= read -r line || [ -n "$line" ]; do
    if echo "$line" | grep -qE '^\*{65,}[[:space:]]*$'; then
        if [ -n "$current_block" ]; then
            blocks+=("$current_block")
            current_block=""
        fi
    else
        current_block+="$line"$'\n'
    fi
done < "$INPUT_FILE"
# Add the last block if any
if [ -n "$current_block" ]; then
    blocks+=("$current_block")
fi

# Write CSV header before processing any blocks
max_users=0
block=""

declare -a header=("Server" "Timestamp" "TomcatHome" "ConfigPath" "TomcatVersion" "CredentialHandler" "Algorithm" "Iterations" "SaltLength" "OverallStatus" "Compliance" "ComplianceDetails" "OptionalWarnings" "AuditCompleted")
# We'll determine max_users in the first pass, so defer header writing until after

# First pass: determine max_users
for block in "${blocks[@]}"; do
    block=$(echo "$block" | sed '/./,$!d')
    [ -z "$(echo "$block" | tr -d '\n[:space:]')" ] && continue
    if echo "$block" | grep -iq "Hostname:" && echo "$block" | grep -iq "Tomcat Version:"; then
        user_count=0
        while IFS= read -r uline; do
            user_count=$((user_count+1))
        done < <(extract_users "$block")
        [ $user_count -gt $max_users ] && max_users=$user_count
    fi
done

# Now write the header with the correct number of user columns
header=("Server" "Timestamp" "TomcatHome" "ConfigPath" "TomcatVersion" "CredentialHandler" "Algorithm" "Iterations" "SaltLength" "OverallStatus" "Compliance" "ComplianceDetails" "OptionalWarnings" "AuditCompleted")
for i in $(seq 1 $max_users); do
    header+=("Username$i" "PasswordType$i" "UserCompliance$i")
done
(IFS=,; echo "${header[*]}" > "$OUTPUT_CSV")

# Second pass: process and write each row
first_block_printed=0
for block in "${blocks[@]}"; do
    block=$(echo "$block" | sed '/./,$!d')
    [ -z "$(echo "$block" | tr -d '\n[:space:]')" ] && continue
    if echo "$block" | grep -iq "Hostname:" && echo "$block" | grep -iq "Tomcat Version:"; then
        # Extract fields
        timestamp=$(extract_field "$block" "Execution Time")
        server=$(extract_field "$block" "Hostname")
        tomcat_version=$(extract_field "$block" "Tomcat Version")
        tomcat_home=$(extract_field "$block" "Tomcat Home")
        config_path=$(extract_field "$block" "Config Path")
        credential_handler=$(extract_field "$block" "Credential Handler")
        algorithm=$(extract_field "$block" "Algorithm")
        iterations=$(extract_field "$block" "Iterations")
        salt_length=$(extract_field "$block" "Salt Length")
        overall_status=$(extract_field "$block" "Overall Status")
        compliance=$(extract_field "$block" "Status")
        audit_completed=$(echo "$block" | grep -iq "Audit completed" && echo "true" || echo "false")
        compliance_details=$(extract_compliance_details "$block")
        optional_warnings=$(extract_optional_warnings "$block")
        user_lines=()
        user_count=0
        while IFS= read -r uline; do
            user_lines+=("$uline")
            user_count=$((user_count+1))
        done < <(extract_users "$block")
        row_arr=()
        row_arr+=("$(csv_escape "$server")")
        row_arr+=("$(csv_escape "$timestamp")")
        row_arr+=("$(csv_escape "$tomcat_home")")
        row_arr+=("$(csv_escape "$config_path")")
        row_arr+=("$(csv_escape "$tomcat_version")")
        row_arr+=("$(csv_escape "$credential_handler")")
        row_arr+=("$(csv_escape "$algorithm")")
        row_arr+=("$(csv_escape "$iterations")")
        row_arr+=("$(csv_escape "$salt_length")")
        row_arr+=("$(csv_escape "$overall_status")")
        row_arr+=("$(csv_escape "$compliance")")
        row_arr+=("$(csv_escape "$compliance_details")")
        row_arr+=("$(csv_escape "$optional_warnings")")
        row_arr+=("$(csv_escape "$audit_completed")")
        for i in $(seq 1 $max_users); do
            idx=$((i-1))
            if [ $idx -lt $user_count ]; then
                IFS='|' read uname ptype ucomp <<EOF
${user_lines[$idx]}
EOF
                row_arr+=("$(csv_escape "$uname")")
                row_arr+=("$(csv_escape "$ptype")")
                row_arr+=("$(csv_escape "$ucomp")")
            else
                row_arr+=("")
                row_arr+=("")
                row_arr+=("")
            fi
        done
        # Build the CSV row as a string
        row_str=""
        for ((i=0; i<${#row_arr[@]}; i++)); do
            # Add comma if not the first field
            if [ $i -ne 0 ]; then
                row_str+="," 
            fi
            row_str+="${row_arr[$i]}"
        done

        # Use printf to write to file for robust handling
        printf '%s\n' "$row_str" >> "$OUTPUT_CSV"
    fi
done

# At the end, clean up temp file
rm -f "$TMPUNIX" 