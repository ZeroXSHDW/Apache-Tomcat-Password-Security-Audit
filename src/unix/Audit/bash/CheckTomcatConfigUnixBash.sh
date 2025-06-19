#!/bin/bash
# CheckTomcatConfigUnixBash.sh
# Audit Apache Tomcat configuration for security compliance with NIST 800-53 IA-5 and CIS Tomcat Benchmark

# Constants
LOG_FILE="/tmp/TomcatManager.csv"
LOG_DIR="/tmp"
LOG_FILE_PATH="$LOG_DIR/TomcatManager.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname)

# Error handling
set -e
trap 'handle_error $? $LINENO' ERR

# Function to handle errors
handle_error() {
    local exit_code=$1
    local line_number=$2
    echo "Error occurred in script at line $line_number with exit code $exit_code"
    echo "Error occurred in script at line $line_number with exit code $exit_code" >> "$LOG_FILE_PATH"
    exit $exit_code
}

# Function to validate XML structure
validate_xml_structure() {
    local xml_file=$1
    if ! grep -q '<?xml' "$xml_file"; then
        echo "Error: Invalid XML declaration in $xml_file"
        return 1
    fi
    if ! xmllint --noout "$xml_file" 2>/dev/null; then
        echo "Error: Invalid XML structure in $xml_file"
        return 1
    fi
    return 0
}

# Function to securely parse XML
secure_parse_xml() {
    local xml_file=$1
    if [ ! -f "$xml_file" ]; then
        echo "Error: XML file $xml_file not found"
            return 1
    fi
    if [ ! -r "$xml_file" ]; then
        echo "Error: No read permission for $xml_file"
        return 1
    fi
    if ! validate_xml_structure "$xml_file"; then
        return 1
    fi
    return 0
}

# Function to securely write XML
secure_write_xml() {
    local xml_file=$1
    local temp_file="${xml_file}.tmp"
    local backup_file="${xml_file}.bak.$(date +%Y%m%d%H%M%S)"
    
    # Create backup
    if [ -f "$xml_file" ]; then
        cp "$xml_file" "$backup_file"
        chmod 600 "$backup_file"
    fi
    
    # Write to temporary file
    if ! xmllint --format - > "$temp_file"; then
        echo "Error: Failed to write XML to temporary file"
        rm -f "$temp_file"
        return 1
    fi

    # Validate temporary file
    if ! validate_xml_structure "$temp_file"; then
        echo "Error: Invalid XML structure in temporary file"
        rm -f "$temp_file"
        return 1
    fi

    # Move temporary file to final location
    mv "$temp_file" "$xml_file"
    chmod 600 "$xml_file"
    return 0
}

# Function to detect Tomcat version
detect_tomcat_version() {
    local tomcat_home=$1
    local version="7.0"  # Default fallback
    
    # Check RELEASE-NOTES
    if [ -f "$tomcat_home/RELEASE-NOTES" ]; then
        local full_version=$(grep -o "Apache Tomcat Version [0-9]\+\.[0-9]\+\.[0-9]\+" "$tomcat_home/RELEASE-NOTES" | grep -o "[0-9]\+\.[0-9]\+" | head -1)
        if [[ $full_version == 7.0* ]]; then version="7.0"
        elif [[ $full_version == 8.5* ]]; then version="8.5"
        elif [[ $full_version == 9.0* ]]; then version="9.0"
        elif [[ $full_version == 10.0* ]]; then version="10.0"
        elif [[ $full_version == 10.1* ]]; then version="10.1"
        fi
    fi
    
    # Check path name
    local tomcat_home_lower=$(echo "$tomcat_home" | tr '[:upper:]' '[:lower:]')
    if [[ $tomcat_home_lower == *"tomcat7"* ]]; then version="7.0"
    elif [[ $tomcat_home_lower == *"tomcat8"* ]]; then version="8.5"
    elif [[ $tomcat_home_lower == *"tomcat9"* ]]; then version="9.0"
    elif [[ $tomcat_home_lower == *"tomcat10"* ]]; then version="10.0"
    fi

    echo "$version"
}

# Function to validate hash format
validate_hash_format() {
    local hash=$1
    local version=$2
    
    case $version in
        "7.0")
            [[ $hash =~ ^[0-9a-fA-F]{64}$ ]] && return 0
            ;;
        "8.5")
            [[ $hash =~ ^[0-9a-fA-F]{128}$ ]] && return 0
            ;;
        "9.0"|"10.0"|"10.1")
            [[ $hash =~ ^[0-9a-fA-F]+:[0-9a-fA-F]+$ ]] && return 0
            ;;
    esac
    return 1
}

# Function to generate password hash
generate_password_hash() {
    local tomcat_bin=$1
    local password=$2
    local version=$3
    local digest_script="$tomcat_bin/digest.sh"
    
    if [ ! -x "$digest_script" ]; then
        echo "Error: digest.sh not found or not executable"
        return 1
    fi
    
    local algorithm
    local iterations
    local salt_length
    
    case $version in
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
    esac
    
    local cmd="$digest_script -a $algorithm"
    [ -n "$iterations" ] && cmd="$cmd -i $iterations"
    [ -n "$salt_length" ] && cmd="$cmd -s $salt_length"
    cmd="$cmd $password"
    
    local hash=$($cmd 2>/dev/null | grep -o '[0-9a-fA-F:]*$')
    if [ -z "$hash" ]; then
        echo "Error: Failed to generate hash"
        return 1
    fi

    echo "$hash"
    return 0
}

# Function to manage Tomcat service
manage_tomcat_service() {
    local tomcat_home=$1
    local action=$2
    local timeout=60
    
    # Check if using systemd
    local service_name
    for svc in tomcat tomcat7 tomcat8 tomcat9 tomcat10; do
        if systemctl is-active --quiet $svc 2>/dev/null; then
            service_name=$svc
            break
        fi
    done

    if [ -n "$service_name" ]; then
        # Use systemd
        case $action in
            "restart")
                systemctl stop $service_name
                sleep 5
                systemctl start $service_name
                ;;
            "stop")
                systemctl stop $service_name
                ;;
            "start")
                systemctl start $service_name
                ;;
        esac
    else
        # Use catalina.sh
        local catalina_script="$tomcat_home/bin/catalina.sh"
        if [ ! -x "$catalina_script" ]; then
            echo "Error: catalina.sh not found or not executable"
        return 1
    fi

        case $action in
            "restart")
                "$catalina_script" stop
                sleep 5
                "$catalina_script" start
                ;;
            "stop")
                "$catalina_script" stop
                ;;
            "start")
                "$catalina_script" start
                ;;
        esac
    fi
    
    # Wait for service to be ready
    local start_time=$(date +%s)
    while [ $(($(date +%s) - start_time)) -lt $timeout ]; do
        if nc -z localhost 8080 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    
    echo "Error: Service failed to start within timeout"
    return 1
}

# Function to check configuration compliance
check_config_compliance() {
    local version=$1
    local credential_handler=$2
    local algorithm=$3
    local iterations=$4
    local salt_length=$5
    
    case $version in
        "7.0")
            if [ "$credential_handler" = "org.apache.catalina.realm.MessageDigestCredentialHandler" ] && \
               [ "$algorithm" = "SHA-256" ]; then
                echo "Compliant for Tomcat 7.0"
                return 0
            fi
            ;;
        "8.5")
            if [ "$credential_handler" = "org.apache.catalina.realm.MessageDigestCredentialHandler" ] && \
               [ "$algorithm" = "SHA-512" ] && \
               [ "$iterations" -ge 10000 ] && \
               [ "$salt_length" -ge 16 ]; then
                echo "Compliant for Tomcat 8.5"
                return 0
            fi
            ;;
        "9.0"|"10.0"|"10.1")
            if [ "$credential_handler" = "org.apache.catalina.realm.SecretKeyCredentialHandler" ] && \
               [ "$algorithm" = "PBKDF2WithHmacSHA512" ] && \
               [ "$iterations" -ge 10000 ] && \
               [ "$salt_length" -ge 16 ]; then
                echo "Compliant for Tomcat $version"
                return 0
            fi
            ;;
    esac
    
    echo "Non-compliant"
    return 1
}

# Main function
main() {
    # Check root privileges
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This script must be run as root or with sudo"
        exit 1
    fi

    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE_PATH"
    chmod 600 "$LOG_FILE_PATH"
    
    # Initialize log file
    if [ ! -f "$LOG_FILE" ]; then
        echo "Timestamp,Message" > "$LOG_FILE"
    fi

    # Get Tomcat configuration path
    local conf_path
    if [ -n "$CATALINA_HOME" ]; then
        conf_path="$CATALINA_HOME/conf"
    elif [ -n "$CATALINA_BASE" ]; then
        conf_path="$CATALINA_BASE/conf"
    else
        for path in /opt/tomcat*/conf /usr/local/tomcat*/conf /var/lib/tomcat*/conf /usr/share/tomcat*/conf; do
            if [ -d "$path" ] && [ -f "$path/server.xml" ]; then
                conf_path=$path
                break
            fi
        done
    fi
    
    if [ -z "$conf_path" ]; then
        echo "Error: Could not locate Tomcat configuration directory"
        exit 1
    fi
    
    local tomcat_home=$(dirname "$conf_path")
    echo "Tomcat Home: $tomcat_home"
    echo "Config Path: $conf_path"

    # Detect Tomcat version
    local tomcat_version=$(detect_tomcat_version "$tomcat_home")
    echo "Tomcat Version: $tomcat_version"
    
    # Process users
    local users_xml_path="$conf_path/tomcat-users.xml"
    echo "Reading $users_xml_path for users with plaintext passwords"
    
    if ! secure_parse_xml "$users_xml_path"; then
        echo "Error: Failed to parse $users_xml_path"
        exit 1
    fi
    
    # Update users with plaintext passwords
    local updated=0
    while IFS= read -r line; do
        if [[ $line =~ username=\"([^\"]+)\".*password=\"([^\"]+)\" ]]; then
            local username="${BASH_REMATCH[1]}"
            local password="${BASH_REMATCH[2]}"
            
            if ! validate_hash_format "$password" "$tomcat_version"; then
                echo "Processing user: $username"
                local hash_value=$(generate_password_hash "$tomcat_home/bin" "$password" "$tomcat_version")
                
                if [ -z "$hash_value" ]; then
                    echo "Error: Failed to generate hash for user $username"
                    exit 1
                fi
                
                # Update password in XML
                sed -i "s/password=\"$password\"/password=\"$hash_value\"/" "$users_xml_path"
                updated=1
            fi
        fi
    done < "$users_xml_path"
    
    if [ $updated -eq 1 ]; then
        if ! secure_write_xml "$users_xml_path"; then
            echo "Error: Failed to update $users_xml_path"
            exit 1
        fi
    else
        echo "No plaintext passwords to update"
    fi
    
    # Update server.xml
    local server_xml_path="$conf_path/server.xml"
    if ! secure_parse_xml "$server_xml_path"; then
        echo "Error: Failed to parse $server_xml_path"
        exit 1
    fi
    
    # Update CredentialHandler configuration
    local realm_xpath="//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']"
    local realm_exists=$(xmllint --xpath "$realm_xpath" "$server_xml_path" 2>/dev/null)
    
    if [ -z "$realm_exists" ]; then
        # Add Realm element
        local engine_xpath="//Engine"
        local engine_exists=$(xmllint --xpath "$engine_xpath" "$server_xml_path" 2>/dev/null)
        
        if [ -z "$engine_exists" ]; then
            echo "Error: No Engine element found in server.xml"
            exit 1
        fi
        
        # Add Realm element after Engine
        sed -i "/<Engine/a \    <Realm className=\"org.apache.catalina.realm.UserDatabaseRealm\" resourceName=\"UserDatabase\"/>" "$server_xml_path"
    fi
    
    # Remove existing CredentialHandler
    sed -i "/<CredentialHandler/d" "$server_xml_path"
    
    # Add new CredentialHandler
    local ch_config
    case $tomcat_version in
        "7.0")
            ch_config="<CredentialHandler className=\"org.apache.catalina.realm.MessageDigestCredentialHandler\" algorithm=\"SHA-256\"/>"
            ;;
        "8.5")
            ch_config="<CredentialHandler className=\"org.apache.catalina.realm.MessageDigestCredentialHandler\" algorithm=\"SHA-512\" iterations=\"10000\" saltLength=\"16\"/>"
            ;;
        "9.0"|"10.0"|"10.1")
            ch_config="<CredentialHandler className=\"org.apache.catalina.realm.SecretKeyCredentialHandler\" algorithm=\"PBKDF2WithHmacSHA512\" iterations=\"10000\" saltLength=\"16\" keyLength=\"256\"/>"
            ;;
    esac
    
    sed -i "/<Realm/a \    $ch_config" "$server_xml_path"
    
    if ! secure_write_xml "$server_xml_path"; then
        echo "Error: Failed to update $server_xml_path"
    exit 1
fi

    # Restart Tomcat
    echo "Restarting Tomcat to apply changes"
    if ! manage_tomcat_service "$tomcat_home" "restart"; then
        echo "Error: Failed to restart Tomcat service"
        exit 1
    fi
    
    # Print timestamp and hostname
    local timestamp_fmt=$(date '+%I:%M %p %Z, %A, %B %d, %Y')
    echo "$timestamp_fmt"
    echo "$HOSTNAME"
    echo "==========================="
    echo "Config Path: $conf_path"
    echo "Tomcat Version: $tomcat_version"
    echo "Auditing server.xml"
    echo "Server Configuration:"

    # Parse CredentialHandler details
    local credential_handler algorithm iterations salt_length
    credential_handler=$(xmllint --xpath 'string(//Realm/CredentialHandler/@className)' "$server_xml_path" 2>/dev/null)
    algorithm=$(xmllint --xpath 'string(//Realm/CredentialHandler/@algorithm)' "$server_xml_path" 2>/dev/null)
    iterations=$(xmllint --xpath 'string(//Realm/CredentialHandler/@iterations)' "$server_xml_path" 2>/dev/null)
    salt_length=$(xmllint --xpath 'string(//Realm/CredentialHandler/@saltLength)' "$server_xml_path" 2>/dev/null)
    local ch_status="Non-compliant"
    if check_config_compliance "$tomcat_version" "$credential_handler" "$algorithm" "$iterations" "$salt_length" | grep -q 'Compliant'; then
        ch_status="Compliant for Tomcat $tomcat_version"
    fi
    echo "  Status: $ch_status"
    echo "  Credential Handler: $credential_handler"
    echo "  Algorithm: $algorithm"
    echo "  Iterations: $iterations"
    echo "  Salt Length: $salt_length"

    echo "Auditing tomcat-users.xml"
    echo "User Audit Results:"
    printf '%-10s | %-15s | %-10s\n' "Username" "Password Type" "Compliance"
    printf '%-10s | %-15s | %-10s\n' "----------" "---------------" "-----------"
    # Print user audit table
    while IFS= read -r line; do
        if [[ $line =~ username=\"([^\"]+)\".*password=\"([^\"]+)\" ]]; then
            local username="${BASH_REMATCH[1]}"
            local password="${BASH_REMATCH[2]}"
            local ptype="Plaintext"
            local compliance="Non-compliant"
            if validate_hash_format "$password" "$tomcat_version"; then
                if [[ "$password" == *:* ]]; then
                    ptype="Salted_PBKDF2"
                elif [[ "$password" =~ ^[0-9a-fA-F]{128}$ ]]; then
                    ptype="Salted_SHA512"
                elif [[ "$password" =~ ^[0-9a-fA-F]{64}$ ]]; then
                    ptype="SHA256"
                fi
                compliance="Compliant"
            fi
            printf '%-10s | %-15s | %-10s\n' "$username" "$ptype" "$compliance"
        fi
    done < "$users_xml_path"
    echo "==========================="
    echo "Overall Status: Secure"
    echo "Audit completed. Log: $LOG_FILE"
    
    # Log results
    local log_message="Tomcat Home: $tomcat_home; Config Path: $conf_path; Version: $tomcat_version; Status: $ch_status"
    echo "$TIMESTAMP,\"$log_message\"" >> "$LOG_FILE"
}

# Execute main function
main "$@"
