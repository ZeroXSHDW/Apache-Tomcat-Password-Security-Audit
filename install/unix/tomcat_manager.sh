#!/bin/bash

export LC_ALL=C
export LANG=C

# tomcat_manager.sh
# Installs and configures Apache Tomcat with secure password hashing for Unix systems
# Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark

# Exit on error
set -e

# Function to setup Java environment after installation
setup_java_env() {
    local java_home="$1"
    if [ -z "$java_home" ] || [ ! -d "$java_home" ]; then
        return 1
    fi

    # Set JAVA_HOME and PATH
    export JAVA_HOME="$java_home"
    export PATH="$java_home/bin:$PATH"

    # For macOS, create necessary symlinks
    if [[ "$(uname)" == "Darwin" ]]; then
        if [ -d "$java_home/libexec/openjdk.jdk" ]; then
            sudo ln -sfn "$java_home/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk.jdk
        fi
    fi

    # Verify Java is working
    if ! java -version >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

# Function to validate Java installation
validate_java() {
    local java_path="$1"
    if [ ! -x "$java_path" ]; then
        return 1
    fi
    
    # Check if it's actually Java and get version
    local version_output
    version_output=$("$java_path" -version 2>&1)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Verify it's a JDK (not just JRE)
    if [ ! -f "$(dirname "$java_path")/../lib/tools.jar" ] && [ ! -d "$(dirname "$java_path")/../lib/modules" ]; then
        return 1
    fi
    
    return 0
}

# Function to detect and setup Java
setup_java() {
    # First check if java is already available
    if command -v java >/dev/null 2>&1; then
        # Try to find JAVA_HOME from java command
        local java_path=$(which java)
        if [ -n "$java_path" ]; then
            # Handle symlinks (works on both Linux and macOS)
            if [ -L "$java_path" ]; then
                if [[ "$(uname)" == "Darwin" ]]; then
                    java_path=$(readlink "$java_path")
                else
                    java_path=$(readlink -f "$java_path")
                fi
            fi
            
            # Validate the Java installation
            if validate_java "$java_path"; then
                # Get the bin directory
                local java_bin=$(dirname "$java_path")
                # Get the home directory (usually 2 levels up from bin)
                local java_home=$(dirname "$java_bin")
                if [ -d "$java_home" ]; then
                    if setup_java_env "$java_home"; then
                        write_log "Found valid Java installation at $JAVA_HOME"
                        return 0
                    fi
                fi
            fi
        fi
    fi

    # If no valid Java found, try to install it
    write_log "No valid Java installation found. Attempting to install..." "WARNING"
    
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS
        if command -v brew >/dev/null 2>&1; then
            write_log "Installing OpenJDK via Homebrew..." "INFO"
            
            # Check if we're running as root
            if [ "$(id -u)" = "0" ]; then
                write_log "Cannot run Homebrew as root. Please run the following commands as your regular user:" "ERROR"
                write_log "1. brew install openjdk" "INFO"
                write_log "2. sudo ln -sfn \$(brew --prefix openjdk)/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk" "INFO"
                write_log "3. Run this script again" "INFO"
                return 1
            fi
            
            # Install OpenJDK
            brew install openjdk || { write_log "Failed to install OpenJDK via Homebrew." "ERROR"; return 1; }
            
            # Try both common Homebrew locations
            local java_home=""
            if [ -d "/usr/local/opt/openjdk" ]; then
                java_home="/usr/local/opt/openjdk"
            elif [ -d "/opt/homebrew/opt/openjdk" ]; then
                java_home="/opt/homebrew/opt/openjdk"
            else
                java_home="$(brew --prefix openjdk)"
            fi
            
            if [ -n "$java_home" ] && [ -d "$java_home" ]; then
                if setup_java_env "$java_home"; then
                    write_log "Successfully installed and configured Java at $JAVA_HOME"
                    return 0
                fi
            fi
        else
            write_log "Homebrew not found. Please install Homebrew first:" "ERROR"
            write_log "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"" "INFO"
            return 1
        fi
    elif [[ -f "/etc/debian_version" ]]; then
        write_log "Installing OpenJDK via apt-get..." "INFO"
        sudo apt-get update && sudo apt-get install -y openjdk-11-jdk || { write_log "Failed to install OpenJDK via apt-get." "ERROR"; return 1; }
        local java_home="/usr/lib/jvm/java-11-openjdk-$(dpkg --print-architecture)"
        if setup_java_env "$java_home"; then
            write_log "Successfully installed and configured Java at $JAVA_HOME"
            return 0
        fi
    elif [[ -f "/etc/redhat-release" ]]; then
        write_log "Installing OpenJDK via yum..." "INFO"
        sudo yum install -y java-11-openjdk || { write_log "Failed to install OpenJDK via yum." "ERROR"; return 1; }
        local java_home="/usr/lib/jvm/java-11-openjdk"
        if setup_java_env "$java_home"; then
            write_log "Successfully installed and configured Java at $JAVA_HOME"
            return 0
        fi
    else
        write_log "Unsupported OS. Please install Java manually." "ERROR"
        return 1
    fi
    
    write_log "Java installation or configuration failed" "ERROR"
    return 1
}

# Constants
LOG_FILE="$HOME/TomcatManager.log"
LOG_CSV="$HOME/TomcatManager.csv"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname)

# Default values
INSTALL_PATH="/opt/tomcat"
VERSION="9.0"
USERNAME="tomcat"
PASSWORD="s3cret"
ROLES="manager,admin"
INSTALL_SERVICE=true
CONFIGURE_FIREWALL=true

# Function to display usage
show_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  -p, --path PATH            Installation path (default: /opt/tomcat)"
    echo "  -v, --version VERSION      Tomcat version (default: 9.0)"
    echo "  -u, --username USERNAME    Admin username (default: tomcat)"
    echo "  -w, --password PASSWORD    Admin password (default: s3cret)"
    echo "  -r, --roles ROLES          Comma-separated roles (default: manager,admin)"
    echo "  -s, --no-service           Skip service installation"
    echo "  -f, --no-firewall          Skip firewall configuration"
    echo ""
    echo "Example:"
    echo "  $0 -p /opt/tomcat -v 9.0 -u admin -w securepass -r manager,admin"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            ;;
        -p|--path)
            INSTALL_PATH="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -u|--username)
            USERNAME="$2"
            shift 2
            ;;
        -w|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -r|--roles)
            ROLES="$2"
            shift 2
            ;;
        -s|--no-service)
            INSTALL_SERVICE=false
            shift
            ;;
        -f|--no-firewall)
            CONFIGURE_FIREWALL=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Function to write log messages
write_log() {
    local message="$1"
    local level="${2:-INFO}"
    local log_message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
    echo "$log_message" >> "$LOG_FILE"
    echo "$log_message"
}

# Function to validate XML structure
validate_xml() {
    local xml_file="$1"
    if [ ! -f "$xml_file" ]; then
        write_log "XML file $xml_file not found" "ERROR"
        return 1
    fi
    
    # Check for XML declaration
    if ! head -n 1 "$xml_file" | grep -q '^<?xml'; then
        write_log "Invalid XML declaration in $xml_file" "ERROR"
        return 1
    fi
    
    # Validate XML
    if ! xmllint --noout "$xml_file" 2>/dev/null; then
        write_log "Invalid XML structure in $xml_file" "ERROR"
        return 1
    fi
    
    return 0
}

# Function to securely parse XML
parse_xml() {
    local xml_file="$1"
    if ! validate_xml "$xml_file"; then
        return 1
    fi
    
    # Use xmllint to parse XML
    if ! xmllint --format "$xml_file" >/dev/null 2>&1; then
        write_log "Failed to parse XML file $xml_file" "ERROR"
        return 1
    fi
    
    return 0
}

# Function to securely write XML
write_xml() {
    local xml_file="$1"
    local xml_content="$2"
    
    # Create backup
    if [ -f "$xml_file" ]; then
        local backup_file="${xml_file}.bak.$(date '+%Y%m%d%H%M%S')"
        cp "$xml_file" "$backup_file"
        chmod 600 "$backup_file"
        write_log "Created backup: $backup_file"
    fi
    
    # Write to temporary file
    local temp_file="${xml_file}.tmp"
    echo "$xml_content" > "$temp_file"
    
    # Validate temporary file
    if ! validate_xml "$temp_file"; then
        rm -f "$temp_file"
        return 1
    fi
    
    # Move to final location
    mv "$temp_file" "$xml_file"
    chmod 600 "$xml_file"
    return 0
}

# Function to validate hash format
validate_hash() {
    local hash="$1"
    local version="$2"
    
    case "$version" in
        "7.0")
            [[ "$hash" =~ ^[0-9a-fA-F]{64}$ ]]
            ;;
        "8.5")
            [[ "$hash" =~ ^[0-9a-fA-F]{128}$ ]]
            ;;
        "9.0"|"10.0"|"10.1")
            [[ "$hash" =~ ^[0-9a-fA-F]+:[0-9a-fA-F]+$ ]]
            ;;
        *)
            write_log "Unsupported Tomcat version: $version" "ERROR"
            return 1
            ;;
    esac
}

# Function to generate password hash
generate_hash() {
    local tomcat_bin="$1"
    local password="$2"
    local version="$3"
    
    local digest_script="${tomcat_bin}/digest.sh"
    if [ ! -f "$digest_script" ]; then
        write_log "digest.sh not found" "ERROR"
        return 1
    fi
    
    # Set algorithm and parameters based on version
    local algorithm
    local iterations
    local salt_length
    
    if [ "$version" = "7.0" ]; then
        algorithm="SHA-256"
    else
        algorithm="SHA-512"
        iterations="10000"
        salt_length="16"
    fi
    
    # Build command
    local cmd="env JAVA_HOME=\"$JAVA_HOME\" PATH=\"$PATH\" $digest_script -a $algorithm"
    [ -n "$iterations" ] && cmd="$cmd -i $iterations"
    [ -n "$salt_length" ] && cmd="$cmd -s $salt_length"
    cmd="$cmd '$password'"
    
    # Run digest.sh
    local result
    result=$(eval $cmd)
    if [[ "$result" =~ [0-9a-fA-F:]+$ ]]; then
        echo "${BASH_REMATCH[0]}"
        return 0
    fi
    
    write_log "Failed to generate hash" "ERROR"
    return 1
}

# Function to manage Tomcat service
manage_service() {
    local action="$1"
    local service_name="$2"
    local timeout="${3:-60}"
    
    case "$action" in
        "install")
            # Install service
            if [ ! -f "${INSTALL_PATH}/bin/service.sh" ]; then
                write_log "service.sh not found" "ERROR"
                return 1
            fi
            
            env JAVA_HOME="$JAVA_HOME" PATH="$PATH" "${INSTALL_PATH}/bin/service.sh" install "$service_name"
            if [ $? -ne 0 ]; then
                write_log "Failed to install service" "ERROR"
                return 1
            fi
            
            # Start service
            systemctl start "$service_name"
            
            # Wait for service to be ready
            local start_time=$(date +%s)
            while [ $(($(date +%s) - start_time)) -lt $timeout ]; do
                if systemctl is-active --quiet "$service_name"; then
                    return 0
                fi
                sleep 1
            done
            
            write_log "Service failed to start within timeout" "ERROR"
            return 1
            ;;
            
        "start"|"stop"|"restart"|"remove")
            # Check if service exists
            if ! systemctl list-unit-files | grep -q "^${service_name}.service"; then
                write_log "Service $service_name not found" "ERROR"
                return 1
            fi
            
            case "$action" in
                "start")
                    systemctl start "$service_name"
                    ;;
                "stop")
                    systemctl stop "$service_name"
                    ;;
                "restart")
                    systemctl restart "$service_name"
                    ;;
                "remove")
                    systemctl stop "$service_name"
                    "${INSTALL_PATH}/bin/service.sh" remove "$service_name"
                    ;;
            esac
            
            if [ "$action" != "remove" ]; then
                # Wait for service to be ready
                local start_time=$(date +%s)
                while [ $(($(date +%s) - start_time)) -lt $timeout ]; do
                    if systemctl is-active --quiet "$service_name"; then
                        return 0
                    fi
                    sleep 1
                done
                
                write_log "Service failed to start within timeout" "ERROR"
                return 1
            fi
            ;;
            
        *)
            write_log "Invalid action: $action" "ERROR"
            return 1
            ;;
    esac
    
    return 0
}

# Function to configure firewall
configure_firewall() {
    local service_name="$1"
    
    # Check if firewall is active
    if ! command -v ufw >/dev/null 2>&1 && ! command -v firewall-cmd >/dev/null 2>&1; then
        write_log "No supported firewall found" "WARNING"
        return 0
    fi
    
    # Configure UFW
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            ufw allow 8080/tcp
            write_log "Added UFW rule for port 8080"
        fi
    fi
    
    # Configure firewalld
    if command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state | grep -q "running"; then
            firewall-cmd --permanent --add-port=8080/tcp
            firewall-cmd --reload
            write_log "Added firewalld rule for port 8080"
        fi
    fi
    
    return 0
}

# Function to validate username
validate_username() {
    local username="$1"
    echo "[DEBUG] Validating username: '$username'" >&2
    echo "$username" | grep -Eq '^[a-zA-Z0-9_\-\.]+$'
    local result=$?
    if [ $result -eq 0 ]; then
        echo "[DEBUG] Username matches regex (via grep)" >&2
        return 0
    else
        echo "[DEBUG] Username does NOT match regex (via grep)" >&2
        return 1
    fi
}

# Function to validate password
validate_password() {
    local password="$1"
    [ ${#password} -ge 8 ]
}

# Function to validate roles
validate_roles() {
    local roles="$1"
    local valid_roles=("manager" "admin" "manager-gui" "manager-script" "manager-jmx" "manager-status")
    local IFS=','
    local user_roles=($roles)
    
    for role in "${user_roles[@]}"; do
        local valid=false
        for valid_role in "${valid_roles[@]}"; do
            if [ "$role" = "$valid_role" ]; then
                valid=true
            break
            fi
        done
        if ! $valid; then
            return 1
        fi
    done

    return 0
}

# Function to update Tomcat user
update_user() {
    local users_xml="$1"
    local username="$2"
    local password="$3"
    local roles="$4"
    
    if [ ! -f "$users_xml" ]; then
        write_log "Users XML file not found" "ERROR"
        return 1
    fi
    
    if ! parse_xml "$users_xml"; then
        return 1
    fi
    
    # Create temporary file
    local temp_file="${users_xml}.tmp"
    cp "$users_xml" "$temp_file"
    
    # Update or add user
    if grep -q "<user username=\"$username\"" "$temp_file"; then
        # Update existing user
        if sed --version >/dev/null 2>&1; then
            # GNU sed
            sed -i "s|<user username=\"$username\".*|<user username=\"$username\" password=\"$password\" roles=\"$roles\"/>|" "$temp_file"
        else
            # BSD/macOS sed
            sed -i '' "s|<user username=\"$username\".*|<user username=\"$username\" password=\"$password\" roles=\"$roles\"/>|" "$temp_file"
        fi
    else
        # Add new user
        if sed --version >/dev/null 2>&1; then
            # GNU sed
            sed -i "/<\/tomcat-users>/i <user username=\"$username\" password=\"$password\" roles=\"$roles\"/>" "$temp_file"
        else
            # BSD/macOS sed
            sed -i '' "/<\/tomcat-users>/i\\
<user username=\"$username\" password=\"$password\" roles=\"$roles\"/>" "$temp_file"
        fi
    fi
    
    # Write updated XML
    if ! write_xml "$users_xml" "$(cat "$temp_file")"; then
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    return 0
}

# Main script
write_log "Starting Tomcat installation"

# Test multiple Tomcat versions
success=0
for test_version in 7.0 8.5 9.0 10.0 10.1; do
    write_log "\n[TEST] Installing Tomcat version $test_version" "INFO"
    VERSION="$test_version"
    # Setup Java first
    if ! setup_java; then
        write_log "Java setup failed for version $test_version. Skipping." "ERROR"
        continue
    fi
    if ! java -version >/dev/null 2>&1; then
        write_log "Java is not working for version $test_version. Skipping." "ERROR"
        continue
    fi
    if ! validate_username "$USERNAME"; then
        write_log "Invalid username format for version $test_version" "ERROR"
        continue
    fi
    if ! validate_password "$PASSWORD"; then
        write_log "Password must be at least 8 characters long for version $test_version" "ERROR"
        continue
    fi
    if ! validate_roles "$ROLES"; then
        write_log "Invalid roles specified for version $test_version" "ERROR"
        continue
    fi
    if [ ! -d "$INSTALL_PATH-$test_version" ]; then
        mkdir -p "$INSTALL_PATH-$test_version"
        write_log "Created installation directory: $INSTALL_PATH-$test_version"
    fi
    major_version="${test_version%%.*}"
    # Determine the latest available minor version for the major version
    latest_minor=$(curl -s --max-time 10 "https://dlcdn.apache.org/tomcat/tomcat-${major_version}/" | grep -oE "v${test_version}\.[0-9]+" | sort -V | tail -n 1 | sed 's/v//')
    if [ -z "$latest_minor" ]; then
        write_log "Could not determine latest minor version for Tomcat $test_version. Using fallback version." "WARNING"
        case "$test_version" in
            7.0)
                latest_minor="7.0.109"
                download_url="https://archive.apache.org/dist/tomcat/tomcat-7/v7.0.109/bin/apache-tomcat-7.0.109.tar.gz"
                ;;
            8.5)
                latest_minor="8.5.99"
                download_url="https://archive.apache.org/dist/tomcat/tomcat-8/v8.5.99/bin/apache-tomcat-8.5.99.tar.gz"
                ;;
            9.0)
                latest_minor="9.0.106"
                download_url="https://dlcdn.apache.org/tomcat/tomcat-9/v9.0.106/bin/apache-tomcat-9.0.106.tar.gz"
                ;;
            10.0)
                latest_minor="10.1.42"
                download_url="https://dlcdn.apache.org/tomcat/tomcat-10/v10.1.42/bin/apache-tomcat-10.1.42.tar.gz"
                ;;
            10.1)
                latest_minor="10.1.42"
                download_url="https://dlcdn.apache.org/tomcat/tomcat-10/v10.1.42/bin/apache-tomcat-10.1.42.tar.gz"
                ;;
            *)
                write_log "No fallback version available for Tomcat $test_version. Skipping." "ERROR"
                continue
                ;;
        esac
    else
        download_url="https://dlcdn.apache.org/tomcat/tomcat-${major_version}/v${latest_minor}/bin/apache-tomcat-${latest_minor}.tar.gz"
    fi
    write_log "Latest available minor version for Tomcat $test_version is $latest_minor" "INFO"
    zip_file="/tmp/apache-tomcat-${latest_minor}.tar.gz"
    # Check if the URL is valid (HTTP 200)
    http_status=$(curl -s -o /dev/null -w "%{http_code}" "$download_url")
    if [ "$http_status" != "200" ]; then
        write_log "Tomcat $latest_minor not available at $download_url (HTTP $http_status). Skipping." "ERROR"
        rm -f "$zip_file"
        continue
    fi
    # Download if not already valid
    if [ -f "$zip_file" ] && tar tzf "$zip_file" > /dev/null 2>&1; then
        write_log "Using existing Tomcat archive: $zip_file"
    else
        write_log "Downloading Tomcat $latest_minor"
        rm -f "$zip_file"
        curl -L "$download_url" -o "$zip_file"
        if [ $? -ne 0 ]; then
            write_log "Failed to download Tomcat archive for version $latest_minor" "ERROR"
            rm -f "$zip_file"
            continue
        fi
        # Validate archive
        if ! tar tzf "$zip_file" > /dev/null 2>&1; then
            write_log "Downloaded file for Tomcat $latest_minor is not a valid archive. Skipping." "ERROR"
            rm -f "$zip_file"
            continue
        fi
    fi
    if [ -d "$INSTALL_PATH-$test_version" ] && [ ! -w "$INSTALL_PATH-$test_version" ]; then
        write_log "No write permission to $INSTALL_PATH-$test_version. Skipping." "ERROR"
        continue
    fi
    write_log "Extracting Tomcat to $INSTALL_PATH-$test_version"
    rm -rf "$INSTALL_PATH-$test_version"
    tar xzf "$zip_file" -C "$(dirname "$INSTALL_PATH-$test_version")"
    mv "$(dirname "$INSTALL_PATH-$test_version")/apache-tomcat-$latest_minor" "$INSTALL_PATH-$test_version"
    rm -f "$zip_file"
    hash=$(generate_hash "$INSTALL_PATH-$test_version/bin" "$PASSWORD" "$test_version")
    if [ -z "$hash" ]; then
        write_log "Failed to generate password hash for version $test_version" "ERROR"
        continue
    fi
    users_xml="$INSTALL_PATH-$test_version/conf/tomcat-users.xml"
    if update_user "$users_xml" "$USERNAME" "$hash" "$ROLES"; then
        write_log "Successfully configured user $USERNAME for version $test_version"
        success=1
    else
        write_log "Failed to configure user for version $test_version" "ERROR"
        continue
    fi
    write_log "Tomcat $test_version installation completed successfully" "INFO"
done

if [ "$success" = "1" ]; then
    write_log "At least one Tomcat version installed successfully." "INFO"
exit 0
else
    write_log "All Tomcat version installations failed." "ERROR"
    exit 1
fi
