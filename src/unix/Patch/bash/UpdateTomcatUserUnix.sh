#!/bin/bash
# UpdateTomcatUserUnix.sh
# Processes existing users with plaintext passwords, generates compliant hashes, updates tomcat-users.xml and server.xml, and restarts Tomcat service

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

# Function to validate username
validate_username() {
    local username=$1
    # Username should be alphanumeric and may contain underscores
    if [[ ! $username =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo "Error: Invalid username format"
        return 1
    fi
    return 0
}

# Function to validate password
validate_password() {
    local password=$1
    # Password should be at least 8 characters
    if [ ${#password} -lt 8 ]; then
        echo "Error: Password must be at least 8 characters"
        return 1
    fi
    return 0
}

# Function to validate roles
validate_roles() {
    local roles=$1
    # Roles should be comma-separated and contain only valid role names
    local valid_roles="manager-gui,manager-script,manager-jmx,manager-status,admin-gui,admin-script"
    IFS=',' read -ra role_array <<< "$roles"
    for role in "${role_array[@]}"; do
        if [[ ! $valid_roles =~ (^|,)$role(,|$) ]]; then
            echo "Error: Invalid role: $role"
            return 1
        fi
    done
    return 0
}

# Function to update user
update_user() {
    local users_xml_path=$1
    local username=$2
    local password=$3
    local roles=$4
    local tomcat_version=$5
    local tomcat_bin=$6
    
    # Validate inputs
    if ! validate_username "$username"; then
        return 1
    fi
    if ! validate_password "$password"; then
        return 1
    fi
    if ! validate_roles "$roles"; then
        return 1
    fi
    
    # Generate password hash
    local hash_value=$(generate_password_hash "$tomcat_bin" "$password" "$tomcat_version")
    if [ -z "$hash_value" ]; then
        echo "Error: Failed to generate password hash"
        return 1
    fi
    
    # Check if user exists
    local user_exists
    user_exists=$(xmllint --xpath "//user[@username='$username']" "$users_xml_path" 2>/dev/null)
    
    if [ -n "$user_exists" ]; then
        # Update existing user
        sed -i "/<user.*username=\"$username\"/c\    <user username=\"$username\" password=\"$hash_value\" roles=\"$roles\"/>" "$users_xml_path"
    else
        # Add new user
        sed -i "/<\/tomcat-users>/i \    <user username=\"$username\" password=\"$hash_value\" roles=\"$roles\"/>" "$users_xml_path"
    fi
    
    return 0
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
    
    # Parse command line arguments
    local username=""
    local password=""
    local roles=""
    local custom_conf_path=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --username=*)
                username="${1#*=}"
                shift
                ;;
            --password=*)
                password="${1#*=}"
                shift
                ;;
            --roles=*)
                roles="${1#*=}"
                shift
                ;;
            --conf-path=*)
                custom_conf_path="${1#*=}"
                shift
                ;;
            *)
                echo "Error: Unknown option: $1"
                echo "Usage: $0 --username=USER --password=PASS --roles=ROLE1,ROLE2 [--conf-path=/path/to/conf]"
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [ -z "$username" ] || [ -z "$password" ] || [ -z "$roles" ]; then
        echo "Error: Missing required arguments"
        echo "Usage: $0 --username=USER --password=PASS --roles=ROLE1,ROLE2 [--conf-path=/path/to/conf]"
        exit 1
    fi
    
    # Get Tomcat configuration path
    local conf_path
    if [ -n "$custom_conf_path" ]; then
        conf_path="$custom_conf_path"
    elif [ -n "$CATALINA_HOME" ]; then
        conf_path="$CATALINA_HOME/conf"
    elif [ -n "$CATALINA_BASE" ]; then
        conf_path="$CATALINA_BASE/conf"
    else
        for path in "/opt/tomcat/conf" "/usr/local/tomcat/conf" "/var/lib/tomcat/conf" "/usr/share/tomcat/conf"; do
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
    
    # Update user
    local users_xml_path="$conf_path/tomcat-users.xml"
    if ! secure_parse_xml "$users_xml_path"; then
        echo "Error: Failed to parse $users_xml_path"
        exit 1
    fi
    
    if ! update_user "$users_xml_path" "$username" "$password" "$roles" "$tomcat_version" "$tomcat_home/bin"; then
        echo "Error: Failed to update user"
        exit 1
    fi
    
    if ! secure_write_xml "$users_xml_path"; then
        echo "Error: Failed to update $users_xml_path"
        exit 1
    fi
    
    # Restart Tomcat
    echo "Restarting Tomcat to apply changes"
    if ! manage_tomcat_service "$tomcat_home" "restart"; then
        echo "Error: Failed to restart Tomcat service"
        exit 1
    fi
    
    echo "User $username updated successfully"
    echo "Overall Status: Secure"
    
    # Log results
    local log_message="User: $username; Roles: $roles; Tomcat Version: $tomcat_version; Status: Updated"
    echo "$TIMESTAMP,\"$log_message\"" >> "$LOG_FILE"
}

# Execute main function
main "$@"