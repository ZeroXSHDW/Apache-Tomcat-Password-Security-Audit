#!/bin/bash
# CheckTomcatConfigUnix.sh
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
    echo "${log_message}"
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

    # Check directory name
    tomcat_home_lower=$(echo "$tomcat_home" | tr '[:upper:]' '[:lower:]')
    if [[ "$tomcat_home_lower" =~ tomcat7 ]]; then version="7.0"
    elif [[ "$tomcat_home_lower" =~ tomcat8 ]]; then version="8.5"
    elif [[ "$tomcat_home_lower" =~ tomcat9 ]]; then version="9.0"
    elif [[ "$tomcat_home_lower" =~ tomcat10 ]]; then version="10.0"
    fi

    # Check server.xml for version clues
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

    # Plaintext: No hex or colon
    if ! [[ "$password" =~ ^[0-9a-fA-F:]+$ ]]; then
        type="Plaintext"
        is_secure=0
    # Salted format (hash:salt)
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
    # Unsalted hashes
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

# Audit server.xml
audit_server_xml() {
    local server_xml_path="$1"
    local credential_handler="None"
    local algorithm="None"
    local iterations=0
    local salt_length=0

    if [ ! -f "$server_xml_path" ]; then
        write_log "Error parsing $server_xml_path: No such file or directory"
        echo "$credential_handler $algorithm $iterations $salt_length"
        return
    fi

    # Check for UserDatabaseRealm or MemoryRealm
    local realm_line=$(grep -E "org.apache.catalina.realm.(UserDatabaseRealm|MemoryRealm)" "$server_xml_path")
    if [ -z "$realm_line" ]; then
        echo "$credential_handler $algorithm $iterations $salt_length"
        return
    fi

    # Extract CredentialHandler
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
    local results=()

    if [ ! -f "$users_xml_path" ]; then
        write_log "Error parsing $users_xml_path: No such file or directory"
        return
    fi

    # Parse users
    while IFS= read -r user_line; do
        if [[ "$user_line" =~ username=\"([^\"]+)\".*password=\"([^\"]+)\" ]]; then
            local username="${BASH_REMATCH[1]:-Unknown}"
            local password="${BASH_REMATCH[2]:-}"
            read password_type is_secure <<< $(detect_password_type "$password")

            local status="Non-compliant"
            local issues=()
            local parameters=()

            # Parameter checks
            parameters+=("Password Type = $password_type [$( [ "$is_secure" -eq 1 ] && echo "PASS" || echo "FAIL" )]")
            parameters+=("CredentialHandler = $credential_handler [$( [ "$credential_handler" != "None" ] && echo "PASS" || echo "FAIL" )]")
            parameters+=("Algorithm = $handler_algorithm [$( [[ "$handler_algorithm" =~ ^(SHA-256|SHA-512|PBKDF2WithHmacSHA512)$ ]] && echo "PASS" || echo "FAIL" )]")
            parameters+=("Iterations = $iterations [$( [ "$iterations" -ge 10000 ] && echo "PASS" || echo "FAIL" )]")
            parameters+=("Salt Length = $salt_length [$( [ "$salt_length" -ge 16 ] && echo "PASS" || echo "FAIL" )]")

            # Compliance checks
            if [ "$password_type" = "Plaintext" ]; then
                issues+=("Plaintext passwords detected in tomcat-users.xml")
                issues+=("Recommendation: Use salted and iterated passwords (e.g., SHA-256 or PBKDF2)")
            elif [[ "$password_type" =~ ^(Hashed_MD5|Hashed_SHA1|Salted_MD5)$ ]]; then
                issues+=("Weak password hashing ($password_type) detected")
                issues+=("Recommendation: Use SHA-256, SHA-512, or PBKDF2")
            elif [[ "$password_type" =~ ^(Hashed_SHA256|Hashed_SHA512)$ ]]; then
                hash_type="${password_type#Hashed_}"
                if [ "$credential_handler" = "org.apache.catalina.realm.MessageDigestCredentialHandler" ] &&
                   [ "$handler_algorithm" = "$hash_type" ] &&
                   [ "$iterations" -ge 10000 ] && [ "$salt_length" -ge 16 ]; then
                    status="Compliant"
                else
                    issues+=("$password_type passwords should use salt and iterations")
                    issues+=("Recommendation: Configure MessageDigestCredentialHandler with saltLength >= 16 and iterations >= 10000")
                fi
            elif [ "$password_type" = "Salted_PBKDF2" ]; then
                if [ "$credential_handler" = "org.apache.catalina.realm.SecretKeyCredentialHandler" ] &&
                   [ "$handler_algorithm" = "PBKDF2WithHmacSHA512" ] &&
                   [ "$iterations" -ge 10000 ] && [ "$salt_length" -ge 16 ]; then
                    status="Compliant"
                else
                    issues+=("Salted_PBKDF2 requires SecretKeyCredentialHandler with PBKDF2")
                    issues+=("Recommendation: Configure SecretKeyCredentialHandler with PBKDF2, saltLength >= 16, iterations >= 10000")
                fi
            else
                issues+=("Unknown password type detected: $password_type")
                issues+=("Recommendation: Use a supported secure hashing algorithm")
            fi

            # Output results for this user
            write_log "- User '$username': $password_type password ($( [ "$is_secure" -eq 1 ] && echo "secure" || echo "insecure" ))" 2
            for param in "${parameters[@]}"; do
                write_log "- $param" 4
            done
            write_log "- Status: $status with NIST 800-53 IA-5 and CIS Tomcat Benchmark" 4
            for issue in "${issues[@]}"; do
                write_log "- $issue" 6
            done

            results+=("$status")
        fi
    done < <(grep "<user" "$users_xml_path")

    # Return overall compliance
    echo "${results[*]}"
}

# Main audit function
audit_tomcat_config() {
    write_log "Checking Apache Tomcat configuration security..."

    # Clear log file
    if ! : > "$LOG_FILE" 2>/dev/null; then
        write_log "Warning: Cannot clear $LOG_FILE. Continuing with existing log."
    fi

    # Find Tomcat configuration
    local conf_path=$(get_tomcat_config_path)
    if [ -z "$conf_path" ]; then
        write_log "Error: No Tomcat configuration directory found"
        exit 1
    fi
    write_log "Found Tomcat configuration at $conf_path"

    local tomcat_version=$(detect_tomcat_version "$(dirname "$conf_path")")
    write_log "Detected Tomcat version $tomcat_version at $conf_path"

    # Audit server.xml
    local server_xml_path="$conf_path/server.xml"
    write_log "Auditing server.xml at $server_xml_path"
    read credential_handler algorithm iterations salt_length <<< $(audit_server_xml "$server_xml_path")

    # Audit tomcat-users.xml
    local users_xml_path="$conf_path/tomcat-users.xml"
    write_log "Auditing tomcat-users.xml at $users_xml_path"
    IFS=' ' read -ra audit_results <<< $(audit_users_xml "$users_xml_path" "$credential_handler" "$algorithm" "$iterations" "$salt_length")

    # Overall status
    local overall_secure=1
    for result in "${audit_results[@]}"; do
        if [ "$result" = "Non-compliant" ]; then
            overall_secure=0
            break
        fi
    done

    write_log "Overall Configuration: $( [ "$overall_secure" -eq 1 ] && echo "Secure" || echo "Insecure" )"
    write_log "Audit completed"
}

# Execute audit
audit_tomcat_config
