#!/bin/bash
# CheckTomcatConfigUnixBash.sh
# Audit Apache Tomcat configuration for security compliance with NIST 800-53 IA-5 and CIS Tomcat Benchmark

# Log setup
LOG_FILE="/tmp/TomcatManager.csv"
log_messages=()

write_log() {
    local message="$1"
    log_messages+=("$message")
    echo -e "$message"
}

# Ensure log file has header
if [ ! -f "$LOG_FILE" ]; then
    if ! echo "Timestamp,Message" > "$LOG_FILE" 2>/dev/null; then
        echo "Warning: Cannot create $LOG_FILE. Logging to console only." >&2
    fi
fi

# Function to detect Tomcat path
get_tomcat_config_path() {
    if [ -n "${CATALINA_HOME}" ] && [ -d "${CATALINA_HOME}/conf" ] && [ -f "${CATALINA_HOME}/conf/server.xml" ]; then
        echo "${CATALINA_HOME}/conf"
        return
    fi
    for path in \
        "/opt/tomcat/conf" \
        "/usr/local/tomcat/conf" \
        "/var/lib/tomcat7/conf" \
        "/var/lib/tomcat8/conf" \
        "/var/lib/tomcat9/conf" \
        "/var/lib/tomcat10/conf" \
        "/usr/share/tomcat7/conf" \
        "/usr/share/tomcat8/conf" \
        "/usr/share/tomcat9/conf" \
        "/usr/share/tomcat10/conf"; do
        if [ -d "${path}" ] && [ -f "${path}/server.xml" ]; then
            echo "${path}"
            return
        fi
    done
    echo ""
}

# Detect Tomcat version
detect_tomcat_version() {
    local tomcat_home="$1"
    local version_file="${tomcat_home}/RELEASE-NOTES"
    local server_xml="${tomcat_home}/conf/server.xml"
    local version="7.0"  # Default fallback

    if [ -f "$version_file" ]; then
        version_line=$(grep "Apache Tomcat Version" "$version_file" | head -1)
        if [[ "$version_line" =~ Apache\ Tomcat\ Version\ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
            full_version="${BASH_REMATCH[1]}"
            if [[ "$full_version" == 7.0.* ]]; then version="7.0"
            elif [[ "$full_version" == 8.5.* ]]; then version="8.5"
            elif [[ "$full_version" == 9.0.* ]]; then version="9.0"
            elif [[ "$full_version" == 10.0.* ]]; then version="10.0"
            elif [[ "$full_version" == 10.1.* ]]; then version="10.1"
            fi
        fi
    fi

    tomcat_home_lower=$(echo "$tomcat_home" | tr '[:upper:]' '[:lower:]')
    if [[ "$tomcat_home_lower" =~ tomcat7 ]]; then version="7.0"
    elif [[ "$tomcat_home_lower" =~ tomcat8 ]]; then version="8.5"
    elif [[ "$tomcat_home_lower" =~ tomcat9 ]]; then version="9.0"
    elif [[ "$tomcat_home_lower" =~ tomcat10 ]]; then version="10.0"
    fi

    if [ -f "$server_xml" ]; then
        if grep -q "org.apache.catalina.startup.VersionLoggerListener" "$server_xml"; then
            content=$(cat "$server_xml")
            if [[ "$tomcat_home_lower" =~ tomcat10 || "$content" =~ 10\. ]]; then version="10.0"
            elif [[ "$content" =~ 9\. ]]; then version="9.0"
            elif [[ "$content" =~ 8\. ]]; then version="8.5"
            elif [[ "$content" =~ 7\. ]]; then version="7.0"
            fi
        fi
    fi

    if [ "$version" = "7.0" ]; then
        write_log "Warning: Could not determine Tomcat version at $tomcat_home, defaulting to 7.0"
    fi
    echo "$version"
}

# Detect password type
detect_password_type() {
    local password="$1"
    local type="Unknown"
    local is_secure=0

    if ! [[ "$password" =~ ^[0-9a-fA-F:]+$ ]]; then
        type="Plaintext"
        is_secure=0
    elif [[ "$password" =~ ^([0-9a-fA-F]+):([0-9a-fA-F]+)$ ]]; then
        local hash_part="${BASH_REMATCH[1]}"
        local hash_length=${#hash_part}
        if [ "$hash_length" -eq 32 ] && [[ "$hash_part" =~ ^[0-9a-fA-F]{32}$ ]]; then
            type="Salted_MD5"
            is_secure=0
        elif [ "$hash_length" -ge 32 ] && [[ "$hash_part" =~ ^[0-9a-fA-F]+$ ]]; then
            type="Salted_PBKDF2"
            is_secure=1
        else
            type="Unknown"
            is_secure=0
        fi
    else
        local length=${#password}
        if [ "$length" -eq 32 ] && [[ "$password" =~ ^[0-9a-fA-F]{32}$ ]]; then
            type="Hashed_MD5"
            is_secure=0
        elif [ "$length" -eq 40 ] && [[ "$password" =~ ^[0-9a-fA-F]{40}$ ]]; then
            type="Hashed_SHA1"
            is_secure=0
        elif [ "$length" -eq 64 ] && [[ "$password" =~ ^[0-9a-fA-F]{64}$ ]]; then
            type="Hashed_SHA256"
            is_secure=1
        elif [ "$length" -eq 128 ] && [[ "$password" =~ ^[0-9a-fA-F]{128}$ ]]; then
            type="Hashed_SHA512"
            is_secure=1
        fi
    fi

    echo "$type $is_secure"
}

# Check configuration compliance for Tomcat version
check_config_compliance() {
    local tomcat_version="$1"
    local credential_handler="$2"
    local algorithm="$3"
    local iterations="$4"
    local salt_length="$5"
    local config_status="Non-compliant"

    if [ "$tomcat_version" = "7.0" ]; then
        if [ "$credential_handler" = "org.apache.catalina.realm.MessageDigestCredentialHandler" ] && \
           [ "$algorithm" = "SHA-256" ]; then
            config_status="Compliant"
        else
            config_status="Non-compliant, requires MessageDigestCredentialHandler with SHA-256"
        fi
    elif [ "$tomcat_version" = "8.5" ]; then
        if [ "$credential_handler" = "org.apache.catalina.realm.MessageDigestCredentialHandler" ] && \
           [ "$algorithm" = "SHA-512" ] && \
           [ "$iterations" -ge 10000 ] && [ "$salt_length" -ge 16 ]; then
            config_status="Compliant"
        else
            config_status="Non-compliant, requires MessageDigestCredentialHandler with SHA-512, iterations >= 10000, saltLength >= 16"
        fi
    else # Tomcat 9.0, 10.0, 10.1
        if [ "$credential_handler" = "org.apache.catalina.realm.SecretKeyCredentialHandler" ] && \
           [ "$algorithm" = "PBKDF2WithHmacSHA512" ] && \
           [ "$iterations" -ge 10000 ] && [ "$salt_length" -ge 16 ]; then
            config_status="Compliant"
        else
            config_status="Non-compliant, requires SecretKeyCredentialHandler with PBKDF2WithHmacSHA512, iterations >= 10000, saltLength >= 16"
        fi
    fi

    printf "%s" "$config_status"
}

# Audit server.xml
audit_server_xml() {
    local server_xml_path="$1"
    local credential_handler="None"
    local algorithm="None"
    local iterations=0
    local salt_length=0

    if [ ! -f "$server_xml_path" ]; then
        echo "$credential_handler $algorithm $iterations $salt_length"
        return
    fi

    local realm_line=$(grep -E "org.apache.catalina.realm.(UserDatabaseRealm|MemoryRealm)" "$server_xml_path")
    if [ -z "$realm_line" ]; then
        echo "$credential_handler $algorithm $iterations $salt_length"
        return
    fi

    local ch_line=$(awk '/<CredentialHandler/,/\/>/' "$server_xml_path" | tr -d '\n' | sed 's/.*<CredentialHandler\s*\([^>]*\)\/>.*/\1/')
    if [ -n "$ch_line" ]; then
        credential_handler=$(echo "$ch_line" | grep -o 'className="[^"]*"' | sed 's/className="\([^"]*\)"/\1/' || echo "Unknown")
        algorithm=$(echo "$ch_line" | grep -o 'algorithm="[^"]*"' | sed 's/algorithm="\([^"]*\)"/\1/' || echo "None")
        iterations=$(echo "$ch_line" | grep -o 'iterations=[0-9]*' | sed 's/iterations=\([0-9]*\)/\1/' || echo "0")
        salt_length=$(echo "$ch_line" | grep -o 'saltLength=[0-9]*' | sed 's/saltLength=\([0-9]*\)/\1/' || echo "0")
    fi

    echo "$credential_handler $algorithm $iterations $salt_length"
}

# Main audit function
audit_tomcat_config() {
    # Check for sudo/root privileges
    if [ "$EUID" -ne 0 ]; then
        local timestamp=$(TZ=Asia/Kolkata date "+%Y-%m-%d %H:%M:%S")
        write_log "ERROR: This script must be run as root or with sudo"
        local combined_message=$(IFS=";"; echo "${log_messages[*]}")
        local log_entry="$timestamp,\"$combined_message\""
        if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
            echo "Warning: Cannot write to $LOG_FILE." >&2
        fi
        exit 1
    fi

    # Get execution time and hostname
    local exec_time=$(TZ=Asia/Kolkata date "+%Y-%m-%d %H:%M:%S")
    local hostname=$(hostname)
    local conf_path=$(get_tomcat_config_path)
    local tomcat_version=""
    local server_status="Unknown"
    local user_compliance="No users found"
    local overall_status="Secure"
    local user_count=0
    local non_compliant_users=0

    # Check if Tomcat is installed
    if [ -z "$conf_path" ]; then
        local summary="Timestamp: $exec_time, Hostname: $hostname, Error: Tomcat is not installed on Server, Overall Status: Insecure"
        write_log "$summary"
        local combined_message=$(IFS=";"; echo "${log_messages[*]}")
        local log_entry="$timestamp,\"$combined_message\""
        if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
            echo "Warning: Cannot write to $LOG_FILE." >&2
        fi
        return
    fi

    tomcat_version=$(detect_tomcat_version "$(dirname "$conf_path")")

    # Audit server.xml
    local server_xml_path="$conf_path/server.xml"
    if [ -f "$server_xml_path" ]; then
        read credential_handler algorithm iterations salt_length <<< $(audit_server_xml "$server_xml_path")
        server_status=$(check_config_compliance "$tomcat_version" "$credential_handler" "$algorithm" "$iterations" "$salt_length")
        if [[ "$server_status" != "Compliant" ]]; then
            overall_status="Insecure"
        fi
    else
        server_status="Server config file not found"
        overall_status="Insecure"
    fi

    # Audit tomcat-users.xml
    local users_xml_path="$conf_path/tomcat-users.xml"
    audit_results=()
    user_compliance_array=()
    if [ -f "$users_xml_path" ]; then
        local content
        content=$(cat "$users_xml_path" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$content" ]; then
            local user_lines
            user_lines=$(echo "$content" | grep '<user' || true)
            if [ -n "$user_lines" ]; then
                while IFS= read -r user_line; do
                    if [ -z "$user_line" ]; then
                        continue
                    fi
                    local username
                    local password
                    username=$(echo "$user_line" | sed -n 's/.*username="\([^"]*\)".*/\1/p')
                    password=$(echo "$user_line" | sed -n 's/.*password="\([^"]*\)".*/\1/p')
                    if [ -n "$username" ] && [ -n "$password" ]; then
                        ((user_count++))
                        read password_type is_secure <<< $(detect_password_type "$password")

                        local compliance_status="Non-compliant"
                        if [ "$password_type" = "Plaintext" ]; then
                            compliance_status="Non-compliant"
                        elif [[ "$password_type" =~ ^(Hashed_MD5|Salted_MD5)$ ]]; then
                            compliance_status="Non-compliant"
                        elif [ "$password_type" = "Hashed_SHA1" ]; then
                            compliance_status="Non-compliant"
                        elif [ "$password_type" = "Hashed_SHA256" ]; then
                            if [ "$tomcat_version" = "7.0" ]; then
                                compliance_status="Compliant"
                            elif [ "$credential_handler" = "None" ] || [ "$handler_algorithm" != "SHA-256" ] || \
                                 [ "$iterations" -lt 10000 ] || [ "$salt_length" -lt 16 ]; then
                                compliance_status="Non-compliant"
                            else
                                compliance_status="Compliant"
                            fi
                        elif [ "$password_type" = "Hashed_SHA512" ]; then
                            if [ "$tomcat_version" = "7.0" ]; then
                                compliance_status="Non-compliant"
                            elif [ "$credential_handler" = "None" ] || [ "$handler_algorithm" != "SHA-512" ] || \
                                 [ "$iterations" -lt 10000 ] || [ "$salt_length" -lt 16 ]; then
                                compliance_status="Non-compliant"
                            else
                                compliance_status="Compliant"
                            fi
                        elif [ "$password_type" = "Salted_PBKDF2" ]; then
                            if [ "$tomcat_version" = "7.0" ]; then
                                compliance_status="Non-compliant"
                            elif [ "$tomcat_version" = "8.5" ]; then
                                if [ "$credential_handler" = "None" ] || \
                                   [[ ! "$handler_algorithm" =~ ^(SHA-256|SHA-512)$ ]] || \
                                   [ "$iterations" -lt 10000 ] || [ "$salt_length" -lt 16 ]; then
                                    compliance_status="Non-compliant"
                                else
                                    compliance_status="Compliant"
                                fi
                            else
                                if [ "$credential_handler" = "org.apache.catalina.realm.SecretKeyCredentialHandler" ] && \
                                   [ "$handler_algorithm" = "PBKDF2WithHmacSHA512" ] && \
                                   [ "$iterations" -ge 10000 ] && [ "$salt_length" -ge 16 ]; then
                                    compliance_status="Compliant"
                                else
                                    compliance_status="Non-compliant"
                                fi
                            fi
                        else
                            compliance_status="Non-compliant"
                        fi

                        audit_results+=("$compliance_status")
                        user_compliance_array+=("$username:$compliance_status")
                        if [ "$compliance_status" = "Non-compliant" ]; then
                            ((non_compliant_users++))
                        fi
                    fi
                done <<< "$user_lines"
            fi
        fi
    fi

    # Summarize user audit
    if [ "$user_count" -gt 0 ]; then
        user_compliance="Users: $(IFS=','; echo "${user_compliance_array[*]}")"
        if [ "$non_compliant_users" -gt 0 ]; then
            overall_status="Insecure"
        fi
    else
        user_compliance="Users: No users found"
    fi

    # Produce single-line output
    local summary="Timestamp: $exec_time, Hostname: $hostname, Config Path: $conf_path, Tomcat Version: $tomcat_version, Server Status: $server_status, $user_compliance, Overall Status: $overall_status"
    write_log "$summary"

    # Write single CSV line
    local timestamp="$exec_time"
    local combined_message=$(IFS=";"; echo "${log_messages[*]}")
    local log_entry="$timestamp,\"$combined_message\""
    if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
        echo "Warning: Cannot write to $LOG_FILE." >&2
    fi
}

# Execute audit
audit_tomcat_config
