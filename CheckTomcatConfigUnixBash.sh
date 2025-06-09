#!/bin/bash
# CheckTomcatConfigUnixBash.sh
# Audit Apache Tomcat configuration for security compliance with NIST 800-53 IA-5 and CIS Tomcat Benchmark

# Log setup
LOG_FILE="/tmp/TomcatManager.csv"
log_messages=()

write_log() {
    local message="$1"
    local indent=${2:-0}
    local indent_spaces=$(printf "%${indent}s" | tr ' ' ' ')
    local log_message="${indent_spaces}${message}"
    
    log_messages+=("$log_message")
    echo -e "${log_message}"
}

# Ensure log file has header
if [ ! -f "$LOG_FILE" ]; then
    if ! echo "Timestamp,Message" > "$LOG_FILE" 2>/dev/null; then
        echo "Warning: Cannot create $LOG_FILE. Logging to console only." >&2
        logger -t TomcatAudit "Warning: Cannot create $LOG_FILE."
    fi
fi

# Function to detect Tomcat path
get_tomcat_config_path() {
    # Check CATALINA_BASE first (for split configurations)
    if [ -n "${CATALINA_BASE}" ] && [ -d "${CATALINA_BASE}/conf" ] && [ -f "${CATALINA_BASE}/conf/server.xml" ]; then
        write_log "Found Tomcat configuration at CATALINA_BASE: ${CATALINA_BASE}/conf"
        echo "${CATALINA_BASE}/conf"
        return
    fi

    # Check CATALINA_HOME
    if [ -n "${CATALINA_HOME}" ] && [ -d "${CATALINA_HOME}/conf" ] && [ -f "${CATALINA_HOME}/conf/server.xml" ]; then
        write_log "Found Tomcat configuration at CATALINA_HOME: ${CATALINA_HOME}/conf"
        echo "${CATALINA_HOME}/conf"
        return
    fi

    # Infer CATALINA_HOME from catalina.sh if unset
    if [ -z "$CATALINA_HOME" ]; then
        local catalina_script
        catalina_script=$(command -v catalina.sh 2>/dev/null)
        if [ -n "$catalina_script" ] && [ -f "$catalina_script" ]; then
            CATALINA_HOME=$(dirname "$(dirname "$catalina_script")")
            write_log "Inferred CATALINA_HOME from catalina.sh: $CATALINA_HOME"
            if [ -d "${CATALINA_HOME}/conf" ] && [ -f "${CATALINA_HOME}/conf/server.xml" ]; then
                echo "${CATALINA_HOME}/conf"
                return
            fi
        fi
    fi

    # Search common paths
    for path in \
        "/opt/tomcat/conf" \
        "/usr/local/tomcat/conf" \
        "/var/lib/tomcat7/conf" \
        "/var/lib/tomcat8/conf" \
        "/var/lib/tomcat9/conf" \
        "/var/lib/tomcat10/conf" \
        "/usr/share/tomcat/conf" \
        "/usr/share/tomcat7/conf" \
        "/usr/share/tomcat8/conf" \
        "/usr/share/tomcat9/conf" \
        "/usr/share/tomcat10/conf" \
        "/etc/tomcat/conf" \
        "/etc/tomcat7/conf" \
        "/etc/tomcat8/conf" \
        "/etc/tomcat9/conf" \
        "/etc/tomcat10/conf"; do
        if [ -d "${path}" ] && [ -f "${path}/server.xml" ]; then
            write_log "Found Tomcat configuration at: ${path}"
            echo "${path}"
            return
        fi
    done

    # Fallback to find command (limited to common directories to avoid long searches)
    write_log "No Tomcat configuration found in common paths, attempting to locate server.xml..."
    local found_path
    found_path=$(find /etc /usr /var /opt -type f -path "*/conf/server.xml" -exec dirname {} \; 2>/dev/null | head -n 1)
    if [ -n "$found_path" ]; then
        write_log "Found Tomcat configuration via find: ${found_path}"
        echo "$found_path"
        return
    fi

    write_log "ERROR: Could not locate Tomcat configuration directory."
    echo ""
}

# Detect Tomcat version
detect_tomcat_version() {
    local tomcat_home="$1"
    local version_file="${tomcat_home}/RELEASE-NOTES"
    local server_xml="${tomcat_home}/conf/server.xml"
    local catalina_jar="${tomcat_home}/lib/catalina.jar"
    local version="unknown"
    local full_version=""

    # Validate tomcat_home
    if [ ! -d "$tomcat_home" ]; then
        write_log "ERROR: Tomcat home directory $tomcat_home does not exist"
        return 1
    fi

    # Method 1: Check RELEASE-NOTES
    if [ -f "$version_file" ]; then
        write_log "Checking RELEASE-NOTES for version..."
        version_line=$(grep "Apache Tomcat Version" "$version_file" | head -n 1)
        if [[ "$version_line" =~ Apache\ Tomcat\ Version\ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
            full_version="${BASH_REMATCH[1]}"
            if [[ "$full_version" == 7.0.* ]]; then version="7.0"
            elif [[ "$full_version" == 8.0.* ]]; then version="8.0"
            elif [[ "$full_version" == 8.5.* ]]; then version="8.5"
            elif [[ "$full_version" == 9.0.* ]]; then version="9.0"
            elif [[ "$full_version" == 10.0.* ]]; then version="10.0"
            elif [[ "$full_version" == 10.1.* ]]; then version="10.1"
            fi
            write_log "Version found in RELEASE-NOTES: $full_version ($version)"
        else
            write_log "No version found in RELEASE-NOTES"
        fi
    else
        write_log "RELEASE-NOTES not found at $version_file"
    fi

    # Method 2: Check directory name
    if [ "$version" = "unknown" ]; then
        write_log "Checking directory name for version..."
        tomcat_home_lower=$(echo "$tomcat_home" | tr '[:upper:]' '[:lower:]')
        if [[ "$tomcat_home_lower" =~ tomcat7 ]]; then version="7.0"
        elif [[ "$tomcat_home_lower" =~ tomcat8 ]]; then version="8.5"
        elif [[ "$tomcat_home_lower" =~ tomcat9 ]]; then version="9.0"
        elif [[ "$tomcat_home_lower" =~ tomcat10 ]]; then version="10.0"
        fi
        [ "$version" != "unknown" ] && write_log "Version inferred from directory: $version"
    fi

    # Method 3: Check server.xml for VersionLoggerListener
    if [ "$version" = "unknown" ] && [ -f "$server_xml" ]; then
        write_log "Checking server.xml for version..."
        if grep -q "org.apache.catalina.startup.VersionLoggerListener" "$server_xml"; then
            content=$(cat "$server_xml")
            if [[ "$content" =~ 10\.[0-1] ]]; then version="10.0"
            elif [[ "$content" =~ 9\.0 ]]; then version="9.0"
            elif [[ "$content" =~ 8\.5 ]]; then version="8.5"
            elif [[ "$content" =~ 8\.0 ]]; then version="8.0"
            elif [[ "$content" =~ 7\.0 ]]; then version="7.0"
            fi
            [ "$version" != "unknown" ] && write_log "Version inferred from server.xml: $version"
        else
            write_log "No VersionLoggerListener found in server.xml"
        fi
    elif [ ! -f "$server_xml" ]; then
        write_log "server.xml not found at $server_xml"
    fi

    # Method 4: Check catalina.jar manifest
    if [ "$version" = "unknown" ] && [ -f "$catalina_jar" ] && command -v unzip >/dev/null; then
        write_log "Checking catalina.jar manifest for version..."
        manifest_version=$(unzip -p "$catalina_jar" META-INF/MANIFEST.MF 2>/dev/null | grep "Implementation-Version" | sed -n 's/.*Implementation-Version: \([0-9]+\.[0-9]+\.[0-9]+\).*/\1/p')
        if [ -n "$manifest_version" ]; then
            if [[ "$manifest_version" == 7.0.* ]]; then version="7.0"
            elif [[ "$manifest_version" == 8.0.* ]]; then version="8.0"
            elif [[ "$manifest_version" == 8.5.* ]]; then version="8.5"
            elif [[ "$manifest_version" == 9.0.* ]]; then version="9.0"
            elif [[ "$manifest_version" == 10.0.* ]]; then version="10.0"
            elif [[ "$manifest_version" == 10.1.* ]]; then version="10.1"
            fi
            write_log "Version found in catalina.jar manifest: $manifest_version ($version)"
        else
            write_log "No version found in catalina.jar manifest"
        fi
    elif [ ! -f "$catalina_jar" ]; then
        write_log "catalina.jar not found at $catalina_jar"
    fi

    # Method 5: Run version.sh (if executable and Java is available)
    if [ "$version" = "unknown" ] && [ -x "${tomcat_home}/bin/version.sh" ] && command -v java >/dev/null; then
        write_log "Running version.sh to determine version..."
        version_output=$("${tomcat_home}/bin/version.sh" 2>/dev/null | grep "Server version" | sed -n 's/.*Apache Tomcat\/\([0-9]+\.[0-9]+\.[0-9]+\).*/\1/p')
        if [ -n "$version_output" ]; then
            if [[ "$version_output" == 7.0.* ]]; then version="7.0"
            elif [[ "$version_output" == 8.0.* ]]; then version="8.0"
            elif [[ "$version_output" == 8.5.* ]]; then version="8.5"
            elif [[ "$version_output" == 9.0.* ]]; then version="9.0"
            elif [[ "$version_output" == 10.0.* ]]; then version="10.0"
            elif [[ "$version_output" == 10.1.* ]]; then version="10.1"
            fi
            write_log "Version found from version.sh: $version_output ($version)"
        else
            write_log "No version found from version.sh"
        fi
    elif [ ! -x "${tomcat_home}/bin/version.sh" ]; then
        write_log "version.sh not found or not executable at ${tomcat_home}/bin/version.sh"
    fi

    # Method 6: Check package manager (Debian/Ubuntu)
    if [ "$version" = "unknown" ] && command -v dpkg >/dev/null; then
        write_log "Checking package manager for Tomcat version..."
        tomcat_package=$(dpkg -l | grep '^ii' | grep -E 'tomcat[0-9]+' | awk '{print $2}' | head -n 1)
        if [ -n "$tomcat_package" ]; then
            if [[ "$tomcat_package" =~ tomcat7 ]]; then version="7.0"
            elif [[ "$tomcat_package" =~ tomcat8 ]]; then version="8.5"
            elif [[ "$tomcat_package" =~ tomcat9 ]]; then version="9.0"
            elif [[ "$tomcat_package" =~ tomcat10 ]]; then version="10.0"
            fi
            [ "$version" != "unknown" ] && write_log "Version inferred from package manager: $version"
        else
            write_log "No Tomcat package found via dpkg"
        fi
    fi

    # Method 7: Check systemd service file
    if [ "$version" = "unknown" ] && command -v systemctl >/dev/null; then
        write_log "Checking systemd service file for version..."
        service_file=$(find /etc/systemd/system /lib/systemd/system -name 'tomcat*.service' -type f 2>/dev/null | head -n 1)
        if [ -n "$service_file" ]; then
            version_output=$(grep -E 'CATALINA_HOME|ExecStart' "$service_file" | grep -oE 'tomcat[0-9]+' | head -n 1)
            if [ -n "$version_output" ]; then
                if [[ "$version_output" =~ tomcat7 ]]; then version="7.0"
                elif [[ "$version_output" =~ tomcat8 ]]; then version="8.5"
                elif [[ "$version_output" =~ tomcat9 ]]; then version="9.0"
                elif [[ "$version_output" =~ tomcat10 ]]; then version="10.0"
                fi
                [ "$version" != "unknown" ] && write_log "Version inferred from systemd service: $version"
            else
                write_log "No version found in systemd service file"
            fi
        else
            write_log "No Tomcat systemd service file found"
        fi
    fi

    # Fallback: Assume 7.0 with warning
    if [ "$version" = "unknown" ]; then
        version="7.0"
        write_log "WARNING: Could not determine Tomcat version at $tomcat_home, defaulting to 7.0"
        write_log "  - Ensure RELEASE-NOTES, catalina.jar, version.sh, or a Tomcat package is present"
        write_log "  - Manual verification recommended"
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
            config_status="Compliant for Tomcat 7.0"
        else
            write_log "  - Tomcat 7.0 requires MessageDigestCredentialHandler with SHA-256" 2
            write_log "  - Recommendation: Configure MessageDigestCredentialHandler with algorithm='SHA-256'" 2
        fi
    elif [ "$tomcat_version" = "8.0" ] || [ "$tomcat_version" = "8.5" ]; then
        if [ "$credential_handler" = "org.apache.catalina.realm.MessageDigestCredentialHandler" ] && \
           [ "$algorithm" = "SHA-512" ] && \
           [ "$iterations" -ge 10000 ] && [ "$salt_length" -ge 16 ]; then
            config_status="Compliant for Tomcat $tomcat_version"
        else
            write_log "  - Tomcat $tomcat_version requires MessageDigestCredentialHandler with SHA-512, iterations >= 10000, saltLength >= 16" 2
            write_log "  - Recommendation: Configure MessageDigestCredentialHandler with algorithm='SHA-512', iterations='10000', saltLength='16'" 2
        fi
    else # Tomcat 9.0, 10.0, 10.1
        if [ "$credential_handler" = "org.apache.catalina.realm.SecretKeyCredentialHandler" ] && \
           [ "$algorithm" = "PBKDF2WithHmacSHA512" ] && \
           [ "$iterations" -ge 10000 ] && [ "$salt_length" -ge 16 ]; then
            config_status="Compliant for Tomcat $tomcat_version"
        else
            write_log "  - Tomcat $tomcat_version requires SecretKeyCredentialHandler with PBKDF2WithHmacSHA512, iterations >= 10000, saltLength >= 16" 2
            write_log "  - Recommendation: Configure SecretKeyCredentialHandler with algorithm='PBKDF2WithHmacSHA512', iterations='10000', saltLength='16'" 2
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
        write_log "Error: $server_xml_path not found"
        echo "$credential_handler $algorithm $iterations $salt_length"
        return 1
    fi

    local realm_line=$(grep -E "org.apache.catalina.realm.(UserDatabaseRealm|MemoryRealm)" "$server_xml_path")
    if [ -z "$realm_line" ]; then
        write_log "Warning: No UserDatabaseRealm or MemoryRealm found in $server_xml_path"
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

# Main audit function
audit_tomcat_config() {
    # Check for sudo/root privileges
    if [ "$EUID" -ne 0 ]; then
        local timestamp=$(TZ=Asia/Kolkata date "+%Y-%m-%d %H:%M:%S")
        write_log "ERROR - This script must be run as root or with sudo"
        local combined_message=$(IFS="; "; echo "${log_messages[*]}")
        local log_entry="$timestamp,\"$combined_message\""
        if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
            echo "Warning: Cannot write to $LOG_FILE." >&2
            logger -t TomcatAudit "Warning: Cannot write to $LOG_FILE."
        fi
        exit 1
    fi

    # Get execution time and hostname
    local exec_time=$(TZ=Asia/Kolkata date "+%Y-%m-%d %H:%M:%S")
    local hostname=$(hostname)
    write_log "Execution Time: $exec_time"
    write_log "Hostname: $hostname"
    write_log "==========================="

    # Get Tomcat configuration path
    local conf_path=$(get_tomcat_config_path)
    if [ -z "$conf_path" ]; then
        write_log "ERROR - No Tomcat configuration directory found"
        write_log "  - Checked CATALINA_HOME: ${CATALINA_HOME:-unset}"
        write_log "  - Checked CATALINA_BASE: ${CATALINA_BASE:-unset}"
        write_log "  - Searched paths: /opt/tomcat/conf, /usr/share/tomcat*/conf, /etc/tomcat*/conf, etc."
        write_log "  - Ensure Tomcat is installed and CATALINA_HOME or CATALINA_BASE is set correctly"
        write_log "  - Try running: sudo find / -name server.xml"
        local timestamp="$exec_time"
        local combined_message=$(IFS="; "; echo "${log_messages[*]}")
        local log_entry="$timestamp,\"$combined_message\""
        if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
            echo "Warning: Cannot write to $LOG_FILE." >&2
            logger -t TomcatAudit "Warning: Cannot write to $LOG_FILE."
        fi
        exit 1
    fi
    write_log "Config Path: $conf_path"

    # Validate server.xml
    local server_xml_path="$conf_path/server.xml"
    if [ ! -f "$server_xml_path" ]; then
        write_log "ERROR - server.xml not found at $server_xml_path"
        write_log "  - The Tomcat installation at $(dirname "$conf_path") appears incomplete"
        write_log "  - Please verify the installation or set CATALINA_HOME correctly"
        local timestamp="$exec_time"
        local combined_message=$(IFS="; "; echo "${log_messages[*]}")
        local log_entry="$timestamp,\"$combined_message\""
        if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
            echo "Warning: Cannot write to $LOG_FILE." >&2
            logger -t TomcatAudit "Warning: Cannot write to $LOG_FILE."
        fi
        exit 1
    fi

    # Detect Tomcat version
    local tomcat_home=$(dirname "$conf_path")
    local tomcat_version=$(detect_tomcat_version "$tomcat_home")
    if [ $? -ne 0 ]; then
        write_log "ERROR - Failed to detect Tomcat version due to invalid installation"
        local timestamp="$exec_time"
        local combined_message=$(IFS="; "; echo "${log_messages[*]}")
        local log_entry="$timestamp,\"$combined_message\""
        if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
            echo "Warning: Cannot write to $LOG_FILE." >&2
            logger -t TomcatAudit "Warning: Cannot write to $LOG_FILE."
        fi
        exit 1
    fi
    write_log "Tomcat Version: $tomcat_version"

    # Audit server.xml
    write_log "Auditing server.xml"
    read credential_handler algorithm iterations salt_length <<< $(audit_server_xml "$server_xml_path")
    if [ $? -ne 0 ]; then
        write_log "ERROR - Failed to audit server.xml"
        local timestamp="$exec_time"
        local combined_message=$(IFS="; "; echo "${log_messages[*]}")
        local log_entry="$timestamp,\"$combined_message\""
        if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
            echo "Warning: Cannot write to $LOG_FILE." >&2
            logger -t TomcatAudit "Warning: Cannot write to $LOG_FILE."
        fi
        exit 1
    fi

    write_log "Server Configuration:"
    config_status=$(check_config_compliance "$tomcat_version" "$credential_handler" "$algorithm" "$iterations" "$salt_length")
    write_log "  Status: $config_status"
    write_log "  Credential Handler: $credential_handler"
    write_log "  Algorithm: $algorithm"
    write_log "  Iterations: $iterations"
    write_log "  Salt Length: $salt_length"

    # Audit tomcat-users.xml
    local users_xml_path="$conf_path/tomcat-users.xml"
    write_log "Auditing tomcat-users.xml"

    audit_results=()
    local user_count=0
    local config_issues=0

    if [ "$config_status" = "Non-compliant" ]; then
        config_issues=1
    fi

    if [ ! -f "$users_xml_path" ]; then
        write_log "Error: $users_xml_path not found" 4
        config_issues=1
    else
        write_log "User Audit Results:" 4
        write_log "Username | Password Type | Compliance" 4
        write_log "---------|---------------|-----------" 4

        # Read the entire file
        local content
        content=$(cat "$users_xml_path" 2>/dev/null)
        if [ $? -ne 0 ]; then
            write_log "Error: Cannot read $users_xml_path" 4
            config_issues=1
        elif [ -z "$content" ]; then
            write_log "Error: $users_xml_path is empty" 4
            write_log "    No users found in $users_xml_path" 4
            config_issues=1
        else
            # Parse using grep and sed
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
                            elif [ "$credential_handler" = "None" ] || [ "$algorithm" != "SHA-256" ] || \
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
                            elif [ "$credential_handler" = "None" ] || [ "$algorithm" != "SHA-512" ] || \
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
                            elif [ "$tomcat_version" = "8.0" ] || [ "$tomcat_version" = "8.5" ]; then
                                if [ "$credential_handler" = "None" ] || \
                                   [[ ! "$algorithm" =~ ^(SHA-256|SHA-512)$ ]] || \
                                   [ "$iterations" -lt 10000 ] || [ "$salt_length" -lt 16 ]; then
                                    compliance_status="Non-compliant"
                                    issues+=("PBKDF2 requires compatible handler.")
                                else
                                    compliance_status="Compliant"
                                fi
                            else
                                if [ "$credential_handler" = "org.apache.catalina.realm.SecretKeyCredentialHandler" ] && \
                                   [ "$algorithm" = "PBKDF2WithHmacSHA512" ] && \
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

                        write_log "    $username | $password_type | $compliance_status" 4
                        for issue in "${issues[@]}"; do
                            write_log "        - $issue" 8
                        done

                        audit_results+=("$compliance_status")
                    fi
                done <<< "$user_lines"
            else
                write_log "    No users found in $users_xml_path" 4
                config_issues=1
            fi
        fi
    fi

    # Determine overall status
    local overall_secure=1
    if [ "$config_issues" -eq 1 ]; then
        overall_secure=0
    fi
    for result in "${audit_results[@]}"; do
        if [ "$result" = "Non-compliant" ]; then
            overall_secure=0
            break
        fi
    done

    write_log "==========================="
    write_log "Overall Status: $( [ "$overall_secure" -eq 1 ] && echo "Secure" || echo "Insecure" )"
    write_log "Audit completed"

    # Write single CSV line
    local timestamp="$exec_time"
    local combined_message=$(IFS="; "; echo "${log_messages[*]}")
    local log_entry="$timestamp,\"$combined_message\""
    if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
        echo "Warning: Cannot write to $LOG_FILE." >&2
        logger -t TomcatAudit "Warning: Cannot write to $LOG_FILE."
    fi
}

# Execute audit
audit_tomcat_config
