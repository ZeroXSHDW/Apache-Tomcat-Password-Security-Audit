#!/bin/bash
# CheckTomcatConfigUnixBash.sh
# Audit Apache Tomcat configuration for security compliance with NIST 800-53 IA-5 and CIS Tomcat Benchmark

# Log setup
LOG_FILE="/tmp/TomcatManager.log"

write_log() {
    local message="$1"
    local indent=${2:-0}
    local indent_spaces=$(printf "%${indent}s" | tr ' ' ' ')
    local log_message="${indent_spaces}${message}"
    
    if ! echo "${log_message}" >> "${LOG_FILE}" 2>/dev/null; then
        echo "Warning: Cannot write to ${LOG_FILE}. Logging to console only." >&2
    fi
    echo -e "${log_message}"
}

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
    local issue=""
    local recommendation=""

    if [ "$tomcat_version" = "7.0" ]; then
        if [ "$credential_handler" = "org.apache.catalina.realm.MessageDigestCredentialHandler" ] && \
           [ "$algorithm" = "SHA-256" ]; then
            config_status="Compliant for Tomcat 7.0"
        else
            issue="Tomcat 7.0 requires MessageDigestCredentialHandler with SHA-256"
            recommendation="Recommendation: Configure MessageDigestCredentialHandler with algorithm='SHA-256'"
        fi
    elif [ "$tomcat_version" = "8.5" ]; then
        if [ "$credential_handler" = "org.apache.catalina.realm.MessageDigestCredentialHandler" ] && \
           [ "$algorithm" = "SHA-512" ] && \
           [ "$iterations" -ge 10000 ] && [ "$salt_length" -ge 16 ]; then
            config_status="Compliant for Tomcat 8.5"
        else
            issue="Tomcat 8.5 requires MessageDigestCredentialHandler with SHA-512, iterations >= 10000, saltLength >= 16"
            recommendation="Recommendation: Configure MessageDigestCredentialHandler with algorithm='SHA-512', iterations='10000', saltLength='16'"
        fi
    else # Tomcat 9.0, 10.0, 10.1
        if [ "$credential_handler" = "org.apache.catalina.realm.SecretKeyCredentialHandler" ] && \
           [ "$algorithm" = "PBKDF2WithHmacSHA512" ] && \
           [ "$iterations" -ge 10000 ] && [ "$salt_length" -ge 16 ]; then
            config_status="Compliant for Tomcat $tomcat_version"
        else
            issue="Tomcat $tomcat_version requires SecretKeyCredentialHandler with PBKDF2WithHmacSHA512, iterations >= 10000, saltLength >= 16"
            recommendation="Recommendation: Configure SecretKeyCredentialHandler with algorithm='PBKDF2WithHmacSHA512', iterations='10000', saltLength='16'"
        fi
    fi

    echo "$config_status|$issue|$recommendation"
}

# Audit server.xml
audit_server_xml() {
    local server_xml_path="$1"
    local credential_handler="None"
    local algorithm="None"
    local iterations=0
    local salt_length=0

    if [ ! -f "$server_xml_path" ]; then
        write_log "Error: $server_xml_path not found"
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
        iterations=$(echo "$ch_line" | grep -o 'iterations="[0-9]*"' | sed 's/iterations="\([0-9]*\)"/\1/' || echo "0")
        salt_length=$(echo "$ch_line" | grep -o 'saltLength="[0-9]*"' | sed 's/saltLength="\([0-9]*\)"/\1/' || echo "0")
    fi

    echo "$credential_handler $algorithm $iterations $salt_length"
}

# Audit tomcat-users.xml
audit_users_xml() {
    local users_xml_path="$1"
    local credential_handler="$2"
    local handler_algorithm="$3"
    local iterations="$4"
    local salt_length="$5"
    local tomcat_version="$6"
    local results=()
    local user_count=0

    if [ ! -f "$users_xml_path" ]; then
        write_log "Error: $users_xml_path not found"
        return
    fi

    write_log "User Audit Results:"
    write_log "Username | Password Type | Compliance"
    write_log "---------|---------------|-----------"

    while IFS= read -r user_line; do
        if [[ "$user_line" =~ username=\"([^\"]+)\".*password=\"([^\"]+)\" ]]; then
            ((user_count++))
            local username="${BASH_REMATCH[1]:-Unknown}"
            local password="${BASH_REMATCH[2]:-}"
            read password_type is_secure <<< $(detect_password_type "$password")

            local compliance_status="Non-compliant"
            local issues=()

            if [ "$password_type" = "Plaintext" ]; then
                compliance_status="Non-compliant"
                issues+=("Plaintext passwords detected. Use salted SHA-256 or PBKDF2.")
            elif [[ "$password_type" =~ ^(Hashed_MD5|Salted_MD5)$ ]]; then
                compliance_status="Non-compliant"
                issues+=("Weak MD5 hashing detected. Use SHA-256 or PBKDF2.")
            elif [ "$password_type" = "Hashed_SHA1" ]; then
                compliance_status="Non-compliant"
                issues+=("Weak SHA1 hashing detected. Use SHA-256 or PBKDF2.")
            elif [ "$password_type" = "Hashed_SHA256" ]; then
                if [ "$tomcat_version" = "7.0" ]; then
                    compliance_status="Compliant"
                elif [ "$credential_handler" = "None" ] || [ "$handler_algorithm" != "SHA-256" ] || \
                     [ "$iterations" -lt 10000 ] || [ "$salt_length" -lt 16 ]; then
                    compliance_status="Non-compliant"
                    issues+=("SHA256 requires salt and iterations.")
                else
                    compliance_status="Compliant"
                fi
            elif [ "$password_type" = "Hashed_SHA512" ]; then
                if [ "$tomcat_version" = "7.0" ]; then
                    compliance_status="Non-compliant"
                    issues+=("SHA512 not supported in Tomcat 7.0. Use SHA-256.")
                elif [ "$credential_handler" = "None" ] || [ "$handler_algorithm" != "SHA-512" ] || \
                     [ "$iterations" -lt 10000 ] || [ "$salt_length" -lt 16 ]; then
                    compliance_status="Non-compliant"
                    issues+=("SHA512 requires salt and iterations.")
                else
                    compliance_status="Compliant"
                fi
            elif [ "$password_type" = "Salted_PBKDF2" ]; then
                if [ "$tomcat_version" = "7.0" ]; then
                    compliance_status="Non-compliant"
                    issues+=("PBKDF2 not supported in Tomcat 7.0. Use SHA-256.")
                elif [ "$tomcat_version" = "8.5" ]; then
                    if [ "$credential_handler" = "None" ] || \
                       [[ ! "$handler_algorithm" =~ ^(SHA-256|SHA-512)$ ]] || \
                       [ "$iterations" -lt 10000 ] || [ "$salt_length" -lt 16 ]; then
                        compliance_status="Non-compliant"
                        issues+=("PBKDF2 requires compatible handler.")
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
                        issues+=("PBKDF2 requires SecretKeyCredentialHandler.")
                    fi
                fi
            else
                compliance_status="Non-compliant"
                issues+=("Unknown password type: $password_type.")
            fi

            write_log "$username | $password_type | $compliance_status"
            for issue in "${issues[@]}"; do
                write_log "  - $issue" 2
            done

            results+=("$compliance_status")
        fi
    done < <(grep "<user" "$users_xml_path" || echo "")

    if [ "$user_count" -eq 0 ]; then
        write_log "No users found in $users_xml_path"
    fi

    echo "${results[*]}"
}

# Main audit function
audit_tomcat_config() {
    write_log "Apache Tomcat Security Audit"
    write_log "==========================="

    if ! : > "$LOG_FILE" 2>/dev/null; then
        write_log "Warning: Cannot clear $LOG_FILE. Continuing with existing log."
    fi

    local conf_path=$(get_tomcat_config_path)
    if [ -z "$conf_path" ]; then
        write_log "Error: No Tomcat configuration directory found"
        exit 1
    fi
    write_log "Config Path: $conf_path"

    local tomcat_version=$(detect_tomcat_version "$(dirname "$conf_path")")
    write_log "Tomcat Version: $tomcat_version"

    local server_xml_path="$conf_path/server.xml"
    write_log "Auditing server.xml"
    read credential_handler algorithm iterations salt_length <<< $(audit_server_xml "$server_xml_path")

    write_log "Server Configuration:"
    compliance_output=$(check_config_compliance "$tomcat_version" "$credential_handler" "$algorithm" "$iterations" "$salt_length")
    config_status=$(echo "$compliance_output" | awk -F'|' '{print $1}')
    issue=$(echo "$compliance_output" | awk -F'|' '{print $2}')
    recommendation=$(echo "$compliance_output" | awk -F'|' '{print $3}')
    write_log "  Status: $config_status"
    write_log "  CredentialHandler: $credential_handler"
    write_log "  Algorithm: $algorithm"
    write_log "  Iterations: $iterations"
    write_log "  Salt Length: $salt_length"
    if [[ "$config_status" =~ ^Non-compliant ]]; then
        write_log "  - $issue" 2
        write_log "  - $recommendation" 2
    fi

    local users_xml_path="$conf_path/tomcat-users.xml"
    write_log "Auditing tomcat-users.xml"
    IFS=' ' read -ra audit_results <<< $(audit_users_xml "$users_xml_path" "$credential_handler" "$algorithm" "$iterations" "$salt_length" "$tomcat_version")

    local overall_secure=1
    if [[ "$config_status" =~ ^Non-compliant ]] || [ ${#audit_results[@]} -eq 0 ]; then
        overall_secure=0
    else
        for result in "${audit_results[@]}"; do
            if [[ "$result" =~ ^Non-compliant ]]; then
                overall_secure=0
                break
            fi
        done
    fi

    write_log "==========================="
    write_log "Overall Status: $( [ "$overall_secure" -eq 1 ] && echo "Secure" || echo "Insecure" )"
    write_log "Audit completed. Log: $LOG_FILE"
}

# Execute audit
audit_tomcat_config
