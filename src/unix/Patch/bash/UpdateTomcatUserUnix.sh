#!/bin/bash
# UpdateTomcatUserUnix.sh
# Processes existing users with plaintext passwords, generates compliant hashes, updates tomcat-users.xml and server.xml, and restarts Tomcat service

# Log setup
LOG_FILE="/tmp/TomcatManager.csv"
log_messages=()

write_log() {
    local message="$1"
    local indent=${2:-0}
    local indent_spaces=$(printf "%${indent}s" | tr ' ' ' ')
    local log_message="${indent_spaces}${message}"
    
    log_messages+=("$log_message")
    printf "%s\n" "${log_message}" >&2
}

# Ensure log file has header and secure permissions
if [ ! -f "$LOG_FILE" ]; then
    if ! echo "Timestamp,Message" > "$LOG_FILE" 2>/dev/null; then
        write_log "Warning: Cannot create $LOG_FILE. Logging to console only."
    else
        chmod 600 "$LOG_FILE" 2>/dev/null || write_log "Warning: Cannot set permissions on $LOG_FILE"
    fi
fi

# Function to detect Tomcat configuration path
get_tomcat_config_path() {
    local custom_conf_path="$1"
    local conf_path=""

    # Check custom path (Windows path adjusted for Unix mount)
    default_path="/mnt/f/Koger/apps/apache-tomcat-7.0.94"
    write_log "Checking default configuration path: $default_path"
    if [ -d "$default_path/conf" ] && [ -f "$default_path/conf/server.xml" ] && [ -f "$default_path/conf/tomcat-users.xml" ] && [ -f "$default_path/bin/digest.sh" ]; then
        conf_path="$default_path/conf"
        write_log "Found valid Tomcat configuration at default path: $conf_path"
    fi

    # Check custom path provided as argument
    if [ -z "$conf_path" ] && [ -n "$custom_conf_path" ]; then
        write_log "Checking custom configuration path: $custom_conf_path"
        if [ -d "$custom_conf_path" ] && [ -f "$custom_conf_path/server.xml" ] && [ -f "$custom_conf_path/tomcat-users.xml" ] && [ -f "$(dirname "$custom_conf_path")/bin/digest.sh" ]; then
            conf_path="$custom_conf_path"
            write_log "Found valid Tomcat configuration at custom path: $conf_path"
        else
            write_log "ERROR: Invalid custom configuration path: $custom_conf_path" 2
            return 1
        fi
    fi

    # Check environment variables
    if [ -z "$conf_path" ] && [ -n "${CATALINA_BASE}" ] && [ -d "${CATALINA_BASE}/conf" ] && [ -f "${CATALINA_BASE}/conf/server.xml" ] && [ -f "${CATALINA_BASE}/conf/tomcat-users.xml" ] && [ -f "${CATALINA_BASE}/bin/digest.sh" ]; then
        conf_path="${CATALINA_BASE}/conf"
        write_log "Found Tomcat configuration at CATALINA_BASE: $conf_path"
    fi

    if [ -z "$conf_path" ] && [ -n "${CATALINA_HOME}" ] && [ -d "${CATALINA_HOME}/conf" ] && [ -f "${CATALINA_HOME}/conf/server.xml" ] && [ -f "${CATALINA_HOME}/conf/tomcat-users.xml" ] && [ -f "${CATALINA_HOME}/bin/digest.sh" ]; then
        conf_path="${CATALINA_HOME}/conf"
        write_log "Found Tomcat configuration at CATALINA_HOME: $conf_path"
    fi

    # Search common paths
    if [ -z "$conf_path" ]; then
        write_log "Searching common Tomcat configuration paths..."
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
            if [ -d "${path}" ] && [ -f "${path}/server.xml" ] && [ -f "${path}/tomcat-users.xml" ] && [ -f "$(dirname "${path}")/bin/digest.sh" ]; then
                conf_path="${path}"
                write_log "Found Tomcat configuration at: ${path}"
                break
            fi
        done
    fi

    if [ -z "$conf_path" ]; then
        write_log "ERROR: Could not locate Tomcat configuration directory."
        write_log "  - Ensure Tomcat is installed and digest.sh exists" 2
        return 1
    fi

    echo "$conf_path"
}

# Detect Tomcat version
detect_tomcat_version() {
    local tomcat_home="$1"
    local version_file="${tomcat_home}/RELEASE-NOTES"
    local version="7.0"  # Default for compatibility

    if [ -f "$version_file" ]; then
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
        fi
    else
        write_log "Warning: RELEASE-NOTES not found, defaulting to version 7.0"
    fi

    echo "$version"
}

# Generate password hash using digest.sh
generate_password_hash() {
    local tomcat_bin="$1"
    local password="$2"
    local tomcat_version="$3"
    local digest_script="$tomcat_bin/digest.sh"
    local algorithm=""
    local iterations=""
    local salt_length=""

    # Set algorithm and parameters based on Tomcat version
    case "$tomcat_version" in
        "7.0")
            algorithm="SHA-256"
            ;;
        "8.5")
            algorithm="SHA-512"
            iterations="10000"
            salt_length="16"
            ;;
        "9.0"|"10.0"|"10.1")
            algorithm="PBKDF2WithHmacSHA512"
            iterations="10000"
            salt_length="16"
            ;;
        *)
            write_log "ERROR: Unsupported Tomcat version: $tomcat_version" 2
            return 1
            ;;
    esac

    if [ ! -x "$digest_script" ]; then
        write_log "ERROR: digest.sh not found or not executable at $digest_script" 2
        return 1
    fi

    # Verify JAVA_HOME is set
    if [ -z "$JAVA_HOME" ]; then
        write_log "ERROR: JAVA_HOME is not set, required for digest.sh" 2
        return 1
    fi

    # Run digest.sh with appropriate algorithm
    local hash_output
    if [ "$tomcat_version" = "7.0" ]; then
        hash_output=$("$digest_script" -a "$algorithm" "$password" 2>/dev/null)
    else
        hash_output=$("$digest_script" -a "$algorithm" -i "$iterations" -s "$salt_length" "$password" 2>/dev/null)
    fi

    if [ $? -ne 0 ]; then
        write_log "ERROR: Failed to generate hash for password using digest.sh" 2
        return 1
    fi

    # Extract hash
    local hash
    hash=$(echo "$hash_output" | grep -oE '[0-9a-fA-F:]+' | head -n 1)
    if [ -z "$hash" ]; then
        write_log "ERROR: Failed to parse hash from digest.sh output" 2
        return 1
    fi

    echo "$hash"
}

# Read users with plaintext passwords from tomcat-users.xml
get_plaintext_users() {
    local users_xml_path="$1"
    local users=()

    if [ ! -f "$users_xml_path" ]; then
        write_log "ERROR: $users_xml_path not found" 2
        return 1
    fi

    if [ ! -s "$users_xml_path" ]; then
        write_log "WARNING: $users_xml_path is empty" 2
        return 0
    fi

    local content
    content=$(cat "$users_xml_path" 2>/dev/null)
    if [ $? -ne 0 ]; then
        write_log "ERROR: Cannot read $users_xml_path" 2
        return 1
    fi

    # Parse users with plaintext passwords (not matching hash formats)
    while IFS= read -r user_line; do
        if [[ "$user_line" =~ username=\"([^\"]+)\"[^>]*password=\"([^\"]+)\" ]]; then
            local username="${BASH_REMATCH[1]}"
            local password="${BASH_REMATCH[2]}"
            # Check if password is not a hash (plaintext if it contains non-hex characters or doesn't match hash formats)
            if ! [[ "$password" =~ ^[0-9a-fA-F:]+$ ]] || \
               ! [[ "$password" =~ ^[0-9a-fA-F]{32}$|^[0-9a-fA-F]{40}$|^[0-9a-fA-F]{64}$|^[0-9a-fA-F]{128}$|^[0-9a-fA-F]+:[0-9a-fA-F]+$ ]]; then
                users+=("$username:$password")
            fi
        fi
    done <<< "$(echo "$content" | grep '<user')"

    if [ ${#users[@]} -eq 0 ]; then
        write_log "No users with plaintext passwords found in $users_xml_path" 2
        return 0
    fi

    for user in "${users[@]}"; do
        echo "$user"
    done
}

# Update tomcat-users.xml with new hashes
update_tomcat_users_xml() {
    local users_xml_path="$1"
    shift
    local user_pairs=("$@")
    local backup_path="${users_xml_path}.bak.$(date +%Y%m%d%H%M%S)"

    # Backup existing file
    if ! cp "$users_xml_path" "$backup_path" 2>/dev/null; then
        write_log "ERROR: Failed to backup $users_xml_path" 2
        return 1
    fi
    write_log "Backed up $users_xml_path to $backup_path"
    chmod 600 "$backup_path" 2>/dev/null || write_log "Warning: Cannot set permissions on $backup_path"

    # Read content
    local content
    content=$(cat "$users_xml_path" 2>/dev/null)
    if [ $? -ne 0 ]; then
        write_log "ERROR: Cannot read $users_xml_path" 2
        return 1
    fi

    local new_content="$content"
    for pair in "${user_pairs[@]}"; do
        local username="${pair%%:*}"
        local hash="${pair#*:}"
        # Escape special characters in hash for sed
        hash=$(echo "$hash" | sed 's/[&/]/\\&/g')
        # Update user password
        new_content=$(echo "$new_content" | sed "s/\(username=\"$username\"[^>]*password=\"\)[^\"]*\"/\1$hash\"/")
        write_log "Updated user $username with new hash in $users_xml_path"
    done

    # Write updated content
    if ! echo "$new_content" > "$users_xml_path" 2>/dev/null; then
        write_log "ERROR: Failed to write updated $users_xml_path" 2
        cp "$backup_path" "$users_xml_path"
        write_log "Restored $users_xml_path from backup"
        return 1
    fi

    # Validate XML (basic check)
    if ! grep -q "</tomcat-users>" "$users_xml_path"; then
        write_log "ERROR: Updated $users_xml_path is not valid XML" 2
        cp "$backup_path" "$users_xml_path"
        write_log "Restored $users_xml_path from backup"
        return 1
    fi

    return 0
}

# Update server.xml for compliance
update_server_xml() {
    local server_xml_path="$1"
    local tomcat_version="$2"
    local backup_path="${server_xml_path}.bak.$(date +%Y%m%d%H%M%S)"

    # Backup existing file
    if ! cp "$server_xml_path" "$backup_path" 2>/dev/null; then
        write_log "ERROR: Failed to backup $server_xml_path" 2
        return 1
    fi
    write_log "Backed up $server_xml_path to $backup_path"
    chmod 600 "$backup_path" 2>/dev/null || write_log "Warning: Cannot set permissions on $backup_path"

    # Read content
    local content
    content=$(cat "$server_xml_path" 2>/dev/null)
    if [ $? -ne 0 ]; then
        write_log "ERROR: Cannot read $server_xml_path" 2
        return 1
    fi

    # Define Realm configuration based on Tomcat version
    local new_realm=""
    case "$tomcat_version" in
        "7.0")
            new_realm='        <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
          <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-256"/>
        </Realm>'
            ;;
        "8.5")
            new_realm='        <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
          <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-512" iterations="10000" saltLength="16"/>
        </Realm>'
            ;;
        "9.0"|"10.0"|"10.1")
            new_realm='        <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
          <CredentialHandler className="org.apache.catalina.realm.SecretKeyCredentialHandler" algorithm="PBKDF2WithHmacSHA512" iterations="10000" saltLength="16" keyLength="256"/>
        </Realm>'
            ;;
        *)
            write_log "ERROR: Unsupported Tomcat version: $tomcat_version" 2
            return 1
            ;;
    esac

    # Check for existing Realm
    local realm_line
    realm_line=$(echo "$content" | grep "org.apache.catalina.realm.UserDatabaseRealm")
    local new_content
    if [ -n "$realm_line" ]; then
        # Update existing Realm (replace entire Realm block)
        new_content=$(echo "$content" | sed -E "s|<Realm[^>]*className=\"org.apache.catalina.realm.UserDatabaseRealm\"[^>]*>.*?</Realm>|$new_realm|")
        write_log "Updated Realm configuration in $server_xml_path"
    else
        # Add new Realm inside Server/Service/Engine
        new_content=$(echo "$content" | sed "/<Engine[^>]*>/a$new_realm")
        write_log "Added Realm configuration to $server_xml_path"
    fi

    # Write updated content
    if ! echo "$new_content" > "$server_xml_path" 2>/dev/null; then
        write_log "ERROR: Failed to write updated $server_xml_path" 2
        cp "$backup_path" "$server_xml_path"
        write_log "Restored $server_xml_path from backup"
        return 1
    fi

    # Validate XML (basic check)
    if ! grep -q "</Server>" "$server_xml_path"; then
        write_log "ERROR: Updated $server_xml_path is not valid XML" 2
        cp "$backup_path" "$server_xml_path"
        write_log "Restored $server_xml_path from backup"
        return 1
    fi

    return 0
}

# Restart Tomcat service
restart_tomcat_service() {
    local tomcat_home="$1"
    local service_name=""

    # Try to detect service name
    for svc in tomcat tomcat7 tomcat8 tomcat9 tomcat10; do
        if systemctl is-active "$svc" >/dev/null 2>&1; then
            service_name="$svc"
            break
        fi
    done

    if [ -n "$service_name" ]; then
        write_log "Restarting Tomcat service: $service_name"
        if ! systemctl restart "$service_name" 2>/dev/null; then
            write_log "ERROR: Failed to restart Tomcat service $service_name" 2
            return 1
        fi
        # Wait and check status
        sleep 5
        if ! systemctl is-active "$service_name" >/dev/null 2>&1; then
            write_log "ERROR: Tomcat service $service_name failed to start" 2
            return 1
        fi
        write_log "Tomcat service $service_name restarted successfully"
    else
        # Fallback to catalina.sh
        local catalina_script="$tomcat_home/bin/catalina.sh"
        if [ -x "$catalina_script" ]; then
            write_log "No systemd service found, using catalina.sh to restart"
            "$catalina_script" stop >/dev/null 2>&1
            sleep 5
            "$catalina_script" start >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                write_log "ERROR: Failed to restart Tomcat using catalina.sh" 2
                return 1
            fi
            # Wait and check for running process
            sleep 5
            if ! pgrep -f "org.apache.catalina.startup.Bootstrap" >/dev/null; then
                write_log "ERROR: Tomcat failed to start via catalina.sh" 2
                return 1
            fi
            write_log "Tomcat restarted successfully via catalina.sh"
        else
            write_log "ERROR: No Tomcat service or catalina.sh found" 2
            return 1
        fi
    fi

    return 0
}

# Main function
main() {
    # Check for root privileges
    if [ "$EUID" -ne 0 ]; then
        write_log "ERROR: This script must be run as root or with sudo"
        exit 1
    fi

    # Parse arguments
    local custom_conf_path=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --custom-conf=*) custom_conf_path="${1#*=}" ;;
            *) write_log "ERROR: Unknown argument: $1"; exit 1 ;;
        esac
        shift
    done

    # Get execution time and hostname
    local exec_time=$(TZ=Asia/Kolkata date "+%Y-%m-%d %H:%M:%S")
    local hostname=$(hostname)
    write_log "Execution Time: $exec_time"
    write_log "Hostname: $hostname"
    write_log "==========================="

    # Get Tomcat configuration path
    local conf_path
    conf_path=$(get_tomcat_config_path "$custom_conf_path")
    if [ $? -ne 0 ] || [ -z "$conf_path" ]; then
        write_log "ERROR: Failed to locate Tomcat configuration"
        local combined_message=$(IFS="; "; echo "${log_messages[*]}")
        local log_entry="$exec_time,\"$combined_message\""
        echo "$log_entry" >> "$LOG_FILE" 2>/dev/null || write_log "Error: Cannot write to $LOG_FILE"
        exit 1
    fi
    local tomcat_home=$(dirname "$conf_path")
    write_log "Tomcat Home: $tomcat_home"
    write_log "Config Path: $conf_path"

    # Detect Tomcat version
    local tomcat_version
    tomcat_version=$(detect_tomcat_version "$tomcat_home")
    write_log "Tomcat Version: $tomcat_version"

    # Get users with plaintext passwords
    local users_xml_path="$conf_path/tomcat-users.xml"
    write_log "Reading $users_xml_path for users with plaintext passwords"
    local plaintext_users
    plaintext_users=($(get_plaintext_users "$users_xml_path"))
    if [ $? -ne 0 ]; then
        write_log "ERROR: Failed to read users from $users_xml_path"
        local combined_message=$(IFS="; "; echo "${log_messages[*]}")
        local log_entry="$exec_time,\"$combined_message\""
        echo "$log_entry" >> "$LOG_FILE" 2>/dev/null || write_log "Error: Cannot write to $LOG_FILE"
        exit 1
    fi

    if [ ${#plaintext_users[@]} -eq 0 ]; then
        write_log "No plaintext passwords to update"
        write_log "Updating $users_xml_path for compliance only"
    else
        write_log "Found ${#plaintext_users[@]} user(s) with plaintext passwords"
    fi

    # Generate new hashes for plaintext users
    local updated_users=()
    for user in "${plaintext_users[@]}"; do
        local username="${user%%:*}"
        local password="${user#*:}"
        write_log "Processing user: $username (Original plaintext password: [REDACTED])" # Redact plaintext password in logs
        local hash
        hash=$(generate_password_hash "$tomcat_home/bin" "$password" "$tomcat_version")
        if [ $? -ne 0 ]; then
            write_log "ERROR: Failed to generate hash for user $username" 2
            local combined_message=$(IFS="; "; echo "${log_messages[*]}")
            local log_entry="$exec_time,\"$combined_message\""
            echo "$log_entry" >> "$LOG_FILE" 2>/dev/null || write_log "Error: Cannot write to $LOG_FILE"
            exit 1
        fi
        write_log "Generated Hash for $username: $hash"
        updated_users+=("$username:$hash")
    done

    # Update tomcat-users.xml with new hashes
    if [ ${#updated_users[@]} -gt 0 ]; then
        write_log "Updating $users_xml_path with new hashes"
        update_tomcat_users_xml "$users_xml_path" "${updated_users[@]}"
        if [ $? -ne 0 ]; then
            write_log "ERROR: Failed to update $users_xml_path"
            local combined_message=$(IFS="; "; echo "${log_messages[*]}")
            local log_entry="$exec_time,\"$combined_message\""
            echo "$log_entry" >> "$LOG_FILE" 2>/dev/null || write_log "Error: Cannot write to $LOG_FILE"
            exit 1
        fi
    fi

    # Update server.xml
    local server_xml_path="$conf_path/server.xml"
    write_log "Updating $server_xml_path for compliance"
    update_server_xml "$server_xml_path" "$tomcat_version"
    if [ $? -ne 0 ]; then
        write_log "ERROR: Failed to update $server_xml_path"
        local combined_message=$(IFS="; "; echo "${log_messages[*]}")
        local log_entry="$exec_time,\"$combined_message\""
        echo "$log_entry" >> "$LOG_FILE" 2>/dev/null || write_log "Error: Cannot write to $LOG_FILE"
        exit 1
    fi

    # Restart Tomcat
    write_log "Restarting Tomcat to apply changes"
    restart_tomcat_service "$tomcat_home"
    if [ $? -ne 0 ]; then
        write_log "ERROR: Failed to restart Tomcat"
        local combined_message=$(IFS="; "; echo "${log_messages[*]}")
        local log_entry="$exec_time,\"$combined_message\""
        echo "$log_entry" >> "$LOG_FILE" 2>/dev/null || write_log "Error: Cannot write to $LOG_FILE"
        exit 1
    fi

    # Log compliance status
    local compliance_status
    case "$tomcat_version" in
        "7.0") compliance_status="Compliant with SHA-256 (MessageDigestCredentialHandler)" ;;
        "8.5") compliance_status="Compliant with SHA-512, 10000 iterations, 16-byte salt (MessageDigestCredentialHandler)" ;;
        "9.0"|"10.0"|"10.1") compliance_status="Compliant with PBKDF2WithHmacSHA512, 10000 iterations, 16-byte salt (SecretKeyCredentialHandler)" ;;
    esac
    write_log "Compliance Status: $compliance_status"
    write_log "==========================="
    write_log "Overall Status: Secure"
    write_log "Audit completed"

    # Write to CSV
    local combined_message=$(IFS="; "; echo "${log_messages[*]}")
    local log_entry="$exec_time,\"$combined_message\""
    if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
        write_log "Error: Cannot write to $LOG_FILE"
    fi
}

# Execute main function
main "$@"