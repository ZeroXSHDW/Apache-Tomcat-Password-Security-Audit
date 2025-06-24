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
    printf "%s\n" "${log_message}" >&2
}

# Ensure log file has header
if [ ! -f "$LOG_FILE" ]; then
    if ! echo "Timestamp,Message" > "$LOG_FILE" 2>/dev/null; then
        printf "Warning: Cannot create %s. Logging to console only.\n" "$LOG_FILE" >&2
        logger -t TomcatAudit "Warning: Cannot create $LOG_FILE."
    fi
fi

# Function to check for running Tomcat processes and extract config path
check_tomcat_process() {
    write_log "Checking for running Tomcat processes..."
    local tomcat_pid
    tomcat_pid=$(pgrep -f "org.apache.catalina.startup.Bootstrap" 2>/dev/null)
    if [ -n "$tomcat_pid" ]; then
        write_log "Found running Tomcat process (PID: $tomcat_pid)" 2
        write_log "  - Check process details with: ps -ef | grep $tomcat_pid" 2
        # Attempt to extract CATALINA_HOME or CATALINA_BASE from process args
        local proc_args
        proc_args=$(ps -p "$tomcat_pid" -o args 2>/dev/null)
        local catalina_home
        catalina_home=$(echo "$proc_args" | grep -o -E '\-Dcatalina\.home=[^ ]+' | sed 's/-Dcatalina\.home=//')
        local catalina_base
        catalina_base=$(echo "$proc_args" | grep -o -E '\-Dcatalina\.base=[^ ]+' | sed 's/-Dcatalina\.base=//')
        if [ -n "$catalina_base" ] && [ -d "$catalina_base/conf" ] && [ -f "$catalina_base/conf/server.xml" ]; then
            write_log "  - Found CATALINA_BASE from process: $catalina_base/conf" 2
            echo "$catalina_base/conf"
        elif [ -n "$catalina_home" ] && [ -d "$catalina_home/conf" ] && [ -f "$catalina_home/conf/server.xml" ]; then
            write_log "  - Found CATALINA_HOME from process: $catalina_home/conf" 2
            echo "$catalina_home/conf"
        else
            write_log "  - Could not determine config path from process arguments" 2
        fi
        write_log "  - Tomcat may be running from an alternate installation" 2
    else
        write_log "No running Tomcat processes found" 2
        write_log "  - If Tomcat is installed, ensure it is running: sudo systemctl start tomcat" 2
    fi
}

# Function to detect Tomcat configuration path
get_tomcat_config_path() {
    local custom_conf_path="$1"
    local conf_path=""

    # Check custom path provided as argument
    if [ -n "$custom_conf_path" ]; then
        write_log "Checking custom configuration path: $custom_conf_path"
        if [ -d "$custom_conf_path" ] && [ -f "$custom_conf_path/server.xml" ] && [ -f "$custom_conf_path/tomcat-users.xml" ]; then
            conf_path="$custom_conf_path"
            write_log "Found valid Tomcat configuration at custom path: $conf_path"
        else
            write_log "ERROR: Invalid custom configuration path: $custom_conf_path" 2
            write_log "  - Missing server.xml or tomcat-users.xml" 2
            write_log "  - Verify path: ls -l $custom_conf_path" 2
            return 1
        fi
    fi

    # Check CATALINA_BASE
    if [ -z "$conf_path" ] && [ -n "${CATALINA_BASE}" ] && [ -d "${CATALINA_BASE}/conf" ] && [ -f "${CATALINA_BASE}/conf/server.xml" ] && [ -f "${CATALINA_BASE}/conf/tomcat-users.xml" ]; then
        write_log "Found Tomcat configuration at CATALINA_BASE: ${CATALINA_BASE}/conf"
        conf_path="${CATALINA_BASE}/conf"
    fi

    # Check CATALINA_HOME
    if [ -z "$conf_path" ] && [ -n "${CATALINA_HOME}" ] && [ -d "${CATALINA_HOME}/conf" ] && [ -f "${CATALINA_HOME}/conf/server.xml" ] && [ -f "${CATALINA_HOME}/conf/tomcat-users.xml" ]; then
        write_log "Found Tomcat configuration at CATALINA_HOME: ${CATALINA_HOME}/conf"
        conf_path="${CATALINA_HOME}/conf"
    fi

    # Check running process
    if [ -z "$conf_path" ]; then
        local process_conf_path
        process_conf_path=$(check_tomcat_process)
        if [ -n "$process_conf_path" ] && [ -d "$process_conf_path" ] && [ -f "$process_conf_path/server.xml" ] && [ -f "$process_conf_path/tomcat-users.xml" ]; then
            conf_path="$process_conf_path"
        fi
    fi

    # Infer CATALINA_HOME from catalina.sh
    if [ -z "$conf_path" ] && [ -z "$CATALINA_HOME" ]; then
        local catalina_script
        catalina_script=$(command -v catalina.sh 2>/dev/null)
        if [ -n "$catalina_script" ] && [ -f "$catalina_script" ]; then
            CATALINA_HOME=$(dirname "$(dirname "$catalina_script")")
            write_log "Inferred CATALINA_HOME from catalina.sh: $CATALINA_HOME"
            if [ -d "${CATALINA_HOME}/conf" ] && [ -f "${CATALINA_HOME}/conf/server.xml" ] && [ -f "${CATALINA_HOME}/conf/tomcat-users.xml" ]; then
                conf_path="${CATALINA_HOME}/conf"
            fi
        fi
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
            if [ -d "${path}" ] && [ -f "${path}/server.xml" ] && [ -f "${path}/tomcat-users.xml" ]; then
                write_log "Found Tomcat configuration at: ${path}"
                conf_path="${path}"
                break
            fi
        done
    fi

    # Fallback to find command
    if [ -z "$conf_path" ]; then
        write_log "No Tomcat configuration found in common paths, attempting to locate server.xml..."
        local found_path
        found_path=$(find / -type f -path "*/conf/server.xml" 2>/dev/null | head -n 1)
        if [ -n "$found_path" ]; then
            conf_path=$(dirname "$found_path")
            if [ -f "$conf_path/tomcat-users.xml" ]; then
                write_log "Found Tomcat configuration via find: ${conf_path}"
            else
                write_log "ERROR: Found server.xml but missing tomcat-users.xml at: ${conf_path}" 2
                conf_path=""
            fi
        fi
    fi

    if [ -z "$conf_path" ]; then
        write_log "ERROR: Could not locate Tomcat configuration directory."
        write_log "  - Ensure Tomcat is installed (e.g., sudo apt install tomcat)" 2
        write_log "  - Check for server.xml: sudo find / -name server.xml" 2
        write_log "  - Set CATALINA_HOME or CATALINA_BASE environment variables" 2
        write_log "  - Or specify a custom path: $0 /path/to/conf" 2
        return 1
    fi

    # Validate the path
    if [ ! -d "$conf_path" ] || [ ! -f "$conf_path/server.xml" ] || [ ! -f "$conf_path/tomcat-users.xml" ]; then
        write_log "ERROR: Invalid configuration directory: $conf_path"
        write_log "  - Missing server.xml or tomcat-users.xml" 2
        write_log "  - Verify path: ls -l $conf_path" 2
        return 1
    fi

    echo "$conf_path"
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
            case "$full_version" in
                7.0.*) version="7.0" ;;
                8.0.*) version="8.0" ;;
                8.5.*) version="8.5" ;;
                9.0.*) version="9.0" ;;
                10.0.*) version="10.0" ;;
                10.1.*) version="10.1" ;;
            esac
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
        case "$tomcat_home_lower" in
            *tomcat7*) version="7.0" ;;
            *tomcat8.5*) version="8.5" ;;
            *tomcat8*) version="8.0" ;;
            *tomcat9*) version="9.0" ;;
            *tomcat10.1*) version="10.1" ;;
            *tomcat10*) version="10.0" ;;
        esac
        [ "$version" != "unknown" ] && write_log "Version inferred from directory: $version"
    fi

    # Method 3: Check catalina.jar manifest
    if [ "$version" = "unknown" ] && [ -f "$catalina_jar" ] && command -v unzip >/dev/null; then
        write_log "Checking catalina.jar manifest for version..."
        manifest_version=$(unzip -p "$catalina_jar" META-INF/MANIFEST.MF 2>/dev/null | grep "Implementation-Version" | sed -n 's/.*Implementation-Version: \([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p')
        if [ -n "$manifest_version" ]; then
            case "$manifest_version" in
                7.0.*) version="7.0" ;;
                8.0.*) version="8.0" ;;
                8.5.*) version="8.5" ;;
                9.0.*) version="9.0" ;;
                10.0.*) version="10.0" ;;
                10.1.*) version="10.1" ;;
            esac
            write_log "Version found in catalina.jar manifest: $manifest_version ($version)"
        else
            write_log "No version found in catalina.jar manifest"
        fi
    elif [ ! -f "$catalina_jar" ]; then
        write_log "catalina.jar not found at $catalina_jar"
    fi

    # Fallback: Assume 7.0 with warning
    if [ "$version" = "unknown" ]; then
        version="7.0"
        write_log "WARNING: Could not determine Tomcat version at $tomcat_home, defaulting to 7.0"
        write_log "  - Ensure RELEASE-NOTES, catalina.jar, version.sh, or a Tomcat package is present" 2
        write_log "  - Manual verification recommended" 2
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
        write_log "  - Ensure Tomcat is installed correctly (e.g., sudo apt install tomcat)" 2
        write_log "  - Verify file exists: ls -l $server_xml_path" 2
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

# Validate Tomcat installation
validate_tomcat_installation() {
    local tomcat_home="$1"
    local required_files=("conf/server.xml" "conf/tomcat-users.xml")
    local optional_files=("RELEASE-NOTES" "lib/catalina.jar" "bin/version.sh")
    local missing_required=0

    write_log "Validating Tomcat installation at $tomcat_home"
    for file in "${required_files[@]}"; do
        local full_path="$tomcat_home/$file"
        if [ ! -f "$full_path" ]; then
            write_log "ERROR: Missing required file $full_path" 2
            write_log "  - Install Tomcat: sudo apt install tomcat (Kali/Debian)" 2
            write_log "  - Or download: https://tomcat.apache.org/download-90.cgi" 2
            write_log "  - Verify path: ls -l $full_path" 2
            missing_required=1
        elif [ ! -r "$full_path" ]; then
            write_log "ERROR: File $full_path exists but is not readable" 2
            write_log "  - Check permissions: ls -l $full_path" 2
            write_log "  - Fix permissions: sudo chmod 644 $full_path" 2
            missing_required=1
        fi
    done

    if [ $missing_required -eq 1 ]; then
        write_log "ERROR: Tomcat installation at $tomcat_home is incomplete" 2
        write_log "  - Required files (server.xml, tomcat-users.xml) are missing or unreadable" 2
        write_log "  - Check for other installations: sudo find / -name server.xml" 2
        write_log "  - Verify CATALINA_HOME ($CATALINA_HOME) and CATALINA_BASE ($CATALINA_BASE)" 2
        return 1
    fi

    local missing_optional=0
    for file in "${optional_files[@]}"; do
        if [ ! -f "$tomcat_home/$file" ]; then
            write_log "Warning: Missing optional file $tomcat_home/$file" 2
            missing_optional=1
        fi
    done

    if [ $missing_optional -eq 1 ]; then
        write_log "Warning: Some optional files are missing, version detection may be less accurate" 2
    fi

    write_log "Tomcat installation validation passed"
    return 0
}

# Function to check file ownership and permissions for root detection
check_file_ownership_and_permissions() {
    local file="$1"
    if [ -f "$file" ]; then
        local owner
        local perms
        owner=$(stat -c '%U' "$file" 2>/dev/null)
        perms=$(stat -c '%a' "$file" 2>/dev/null)
        if [ "$owner" != "root" ]; then
            write_log "WARNING: $file is not owned by root (owner: $owner)" 2
        else
            write_log "$file is owned by root" 2
        fi
        if [ "$perms" -gt 640 ]; then
            write_log "WARNING: $file has insecure permissions ($perms)" 2
        else
            write_log "$file permissions are secure ($perms)" 2
        fi
    else
        write_log "WARNING: $file does not exist" 2
    fi
}

# Function to check if Tomcat is running as root (two methods)
check_tomcat_running_as_root() {
    local tomcat_pids
    tomcat_pids=$(pgrep -f "org.apache.catalina.startup.Bootstrap" 2>/dev/null)
    local found_root=0
    # Method 1: ps user check
    if [ -n "$tomcat_pids" ]; then
        for pid in $tomcat_pids; do
            local proc_user
            proc_user=$(ps -o user= -p "$pid" 2>/dev/null | awk '{print $1}')
            if [ "$proc_user" = "root" ]; then
                write_log "WARNING: Tomcat process (PID $pid) is running as root! [ps method]" 2
                write_log "  - It is a security risk to run Tomcat as root. Use a dedicated non-root user." 2
                found_root=1
            fi
        done
    fi
    # Method 2: lsof check (process open files owned by root)
    if command -v lsof >/dev/null 2>&1 && [ -n "$tomcat_pids" ]; then
        for pid in $tomcat_pids; do
            if lsof -p "$pid" 2>/dev/null | awk '{print $3}' | grep -qw root; then
                write_log "WARNING: Tomcat process (PID $pid) has open files owned by root! [lsof method]" 2
                write_log "  - This may indicate Tomcat is running as root or has escalated privileges." 2
                found_root=1
            fi
        done
    fi
    if [ -z "$tomcat_pids" ]; then
        write_log "No running Tomcat processes found for root check." 2
    elif [ $found_root -eq 0 ]; then
        write_log "Tomcat process is not running as root (checked by both ps and lsof)." 2
    fi
}

# Main audit function
audit_tomcat_config() {
    local custom_conf_path="$1"

    # Check for sudo/root privileges
    if [ "$EUID" -ne 0 ]; then
        local timestamp=$(TZ=Asia/Kolkata date "+%Y-%m-%d %H:%M:%S")
        write_log "ERROR - This script must be run as root or with sudo"
        local combined_message=$(IFS="; "; echo "${log_messages[*]}")
        local log_entry="$timestamp,\"$combined_message\""
        if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
            printf "Error: Cannot write to %s.\n" "$LOG_FILE" >&2
            logger -t TomcatAudit "Error: Cannot write to $LOG_FILE."
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
    local conf_path
    conf_path=$(get_tomcat_config_path "$custom_conf_path")
    if [ $? -ne 0 ] || [ -z "$conf_path" ]; then
        local timestamp="$exec_time"
        local combined_message=$(IFS="; "; echo "${log_messages[*]}")
        local log_entry="$timestamp,\"$combined_message\""
        if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
            printf "Error: Cannot write to %s.\n" "$LOG_FILE" >&2
            logger -t TomcatAudit "Error: Cannot write to $LOG_FILE."
        fi
        exit 1
    fi
    write_log "Config Path: $conf_path"

    # Check if Tomcat is running as root
    check_tomcat_running_as_root

    # Always check file ownership and permissions for root detection
    check_file_ownership_and_permissions "$conf_path/server.xml"
    check_file_ownership_and_permissions "$conf_path/tomcat-users.xml"

    # Derive Tomcat home directory
    local tomcat_home
    tomcat_home=$(dirname "$conf_path")
    write_log "Tomcat Home: $tomcat_home"

    # Validate Tomcat installation
    validate_tomcat_installation "$tomcat_home"
    if [ $? -ne 0 ]; then
        local timestamp="$exec_time"
        local combined_message=$(IFS="; "; echo "${log_messages[*]}")
        local log_entry="$timestamp,\"$combined_message\""
        if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
            printf "Error: Cannot write to %s.\n" "$LOG_FILE" >&2
            logger -t TomcatAudit "Error: Cannot write to $LOG_FILE."
        fi
        exit 1
    fi

    # Detect Tomcat version
    local tomcat_version=$(detect_tomcat_version "$tomcat_home")
    if [ $? -ne 0 ]; then
        write_log "ERROR - Failed to detect Tomcat version due to invalid installation"
        local timestamp="$exec_time"
        local combined_message=$(IFS="; "; echo "${log_messages[*]}")
        local log_entry="$timestamp,\"$combined_message\""
        if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
            printf "Error: Cannot write to %s.\n" "$LOG_FILE" >&2
            logger -t TomcatAudit "Error: Cannot write to $LOG_FILE."
        fi
        exit 1
    fi
    write_log "Tomcat Version: $tomcat_version"

    # Audit server.xml
    local server_xml_path="$conf_path/server.xml"
    write_log "Auditing server.xml"
    read credential_handler algorithm iterations salt_length <<< $(audit_server_xml "$server_xml_path")
    if [ $? -ne 0 ]; then
        write_log "ERROR - Failed to audit server.xml"
        local timestamp="$exec_time"
        local combined_message=$(IFS="; "; echo "${log_messages[*]}")
        local log_entry="$timestamp,\"$combined_message\""
        if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
            printf "Error: Cannot write to %s.\n" "$LOG_FILE" >&2
            logger -t TomcatAudit "Error: Cannot write to $LOG_FILE."
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
        write_log "  - Ensure Tomcat is installed correctly (e.g., sudo apt install tomcat)" 4
        write_log "  - Verify file exists: ls -l $users_xml_path" 4
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
            write_log "  - Check permissions: ls -l $users_xml_path" 4
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
                                   [ "$iterations" -lt 16 ] || [ "$salt_length" -lt 16 ]; then
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
    write_log "Overall Status: $( [ "$overall_secure" == 1 ] && echo "Secure" || echo "Insecure" )"
    write_log "Audit completed"

    # Write single CSV line
    local timestamp="$exec_time"
    local combined_message=$(IFS="; "; echo "${log_messages[*]}")
    local log_entry="$timestamp,\"$combined_message)\""
    if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
        printf "Error: Cannot write to %s\n" "$LOG_FILE" >&2
        logger -t TomcatAudit "Error: Cannot write to $LOG_FILE."
    fi
}

# Parse command-line arguments
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [--custom-conf=/path/to/conf]" >&2
    exit 1
fi

custom_conf_path=""
if [ "$#" -eq 1 ]; then
    if [[ "$1" =~ ^--custom-conf=(.*)$ ]]; then
        custom_conf_path="${BASH_REMATCH[1]}"
    else
        echo "Usage: $0 [--custom-conf=/path/to/conf]" >&2
        exit 1
    fi
fi

# Execute audit with optional custom path
audit_tomcat_config "$custom_conf_path"
