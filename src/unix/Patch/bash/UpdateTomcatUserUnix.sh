#!/bin/bash
# UpdateTomcatUserUnix.sh
# Patch and update all Tomcat users with secure password hashes and update server.xml CredentialHandler

set -euo pipefail

# --- Config ---
LOG_FILE="/tmp/TomcatManager.csv"
LOG_DIR="/tmp"
LOG_FILE_PATH="$LOG_DIR/TomcatManager.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname)

# --- Helper Functions ---
log() {
    local msg="$1"
    echo "$TIMESTAMP,$msg" | tee -a "$LOG_FILE_PATH" >&2
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# --- 1. Locate Tomcat bin and conf directories ---
find_tomcat_bin_and_conf() {
    local search_parents=(/opt /usr/local /var/lib /usr/share /etc)
    for parent in "${search_parents[@]}"; do
        while IFS= read -r digest; do
            if [ -x "$digest" ]; then
                local bin_dir=$(dirname "$digest")
                # Search upwards for conf directory
                local dir="$bin_dir"
                while [ "$dir" != "/" ]; do
                    if [ -d "$dir/conf" ] && [ -f "$dir/conf/server.xml" ] && [ -f "$dir/conf/tomcat-users.xml" ]; then
                        log "Found Tomcat bin: $bin_dir"
                        log "Found Tomcat conf: $dir/conf"
                        echo "$bin_dir|$dir/conf"
                        return 0
                    fi
                    dir=$(dirname "$dir")
                done
            fi
        done < <(find "$parent" -type f -name digest.sh 2>/dev/null)
    done
    error_exit "Could not locate Tomcat bin directory with digest.sh and valid conf."
}

# --- 2. Locate tomcat-users.xml and server.xml ---
find_tomcat_conf() {
    local bin_dir="$1"
    local conf_dir=$(dirname "$bin_dir")/conf
    if [ -f "$conf_dir/tomcat-users.xml" ] && [ -f "$conf_dir/server.xml" ]; then
        echo "$conf_dir"
        return 0
    fi
    # Try parent directories
    conf_dir=$(dirname $(dirname "$bin_dir"))/conf
    if [ -f "$conf_dir/tomcat-users.xml" ] && [ -f "$conf_dir/server.xml" ]; then
        echo "$conf_dir"
        return 0
    fi
    error_exit "Could not locate tomcat-users.xml and server.xml."
}

# --- 3. Detect Tomcat version ---
detect_tomcat_version() {
    local tomcat_home="$1"
    local version_file="${tomcat_home}/RELEASE-NOTES"
    local catalina_jar="${tomcat_home}/lib/catalina.jar"
    local version="unknown"
    local full_version=""

    # Method 1: Check RELEASE-NOTES
    if [ -f "$version_file" ]; then
        log "Checking RELEASE-NOTES for version..."
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
            log "Version found in RELEASE-NOTES: $full_version ($version)"
        else
            log "No version found in RELEASE-NOTES"
        fi
    else
        log "RELEASE-NOTES not found at $version_file"
    fi

    # Method 2: Check directory name
    if [ "$version" = "unknown" ]; then
        log "Checking directory name for version..."
        tomcat_home_lower=$(echo "$tomcat_home" | tr '[:upper:]' '[:lower:]')
        case "$tomcat_home_lower" in
            *tomcat7*) version="7.0" ;;
            *tomcat8.5*) version="8.5" ;;
            *tomcat8*) version="8.0" ;;
            *tomcat9*) version="9.0" ;;
            *tomcat10.1*) version="10.1" ;;
            *tomcat10*) version="10.0" ;;
        esac
        [ "$version" != "unknown" ] && log "Version inferred from directory: $version"
    fi

    # Method 3: Check catalina.jar manifest
    if [ "$version" = "unknown" ] && [ -f "$catalina_jar" ] && command -v unzip >/dev/null; then
        log "Checking catalina.jar manifest for version..."
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
            log "Version found in catalina.jar manifest: $manifest_version ($version)"
        else
            log "No version found in catalina.jar manifest"
        fi
    elif [ ! -f "$catalina_jar" ]; then
        log "catalina.jar not found at $catalina_jar"
    fi

    # Fallback: Error if version is unknown
    if [ "$version" = "unknown" ]; then
        log "ERROR: Could not determine Tomcat version at $tomcat_home. Defaulting to 8.5." 2
        version="8.5"
    fi

    echo "$version"
}

# --- 4. Generate password hash ---
generate_hash() {
    local bin_dir="$1"; local password="$2"; local version="$3"
    local digest="$bin_dir/digest.sh"
    local algo iterations salt
    case "$version" in
        7.0) algo="SHA-256";;
        8.5) algo="SHA-512"; iterations="-i 10000"; salt="-s 16";;
        9.0|10.0|10.1) algo="PBKDF2WithHmacSHA512"; iterations="-i 10000"; salt="-s 16";;
        *) algo="SHA-512"; iterations="-i 10000"; salt="-s 16";;
    esac
    local cmd="$digest -a $algo ${iterations:-} ${salt:-} $password"
    local hash=$($cmd 2>/dev/null | grep -o '[0-9a-fA-F:]*$')
    if [ -z "$hash" ]; then error_exit "Failed to generate hash for $password"; fi
    echo "$hash"
}

# Helper: Extract CredentialHandler block from server.xml
extract_credential_handler() {
    local server_xml="$1"
    awk '/<CredentialHandler/,/\/?>/' "$server_xml" | tr '\n' ' ' | sed 's/^ *//;s/ *$//'
}

# Helper: Print all users and their password type
print_users_info() {
    local users_xml="$1"
    echo "Current Tomcat Users:"
    local tmpfile=$(mktemp)
    grep -E '^[[:space:]]*<user ' "$users_xml" | while read -r line; do
        local username=$(echo "$line" | sed -n 's/.*username="\([^"]*\)".*/\1/p')
        local roles=$(echo "$line" | sed -n 's/.*roles="\([^"]*\)".*/\1/p')
        local password=$(echo "$line" | sed -n 's/.*password="\([^"]*\)".*/\1/p')
        local type="Plaintext"
        if [[ "$password" =~ ^[0-9a-fA-F:]+$ ]]; then
            if [[ "$password" =~ : ]]; then
                type="Salted Hash"
            else
                type="Hash"
            fi
        fi
        echo "  - $username (roles: $roles, password type: $type)"
        echo 1 >> "$tmpfile"
    done
    local user_count=$(wc -l < "$tmpfile")
    rm -f "$tmpfile"
    if [ "$user_count" -eq 0 ]; then
        echo "[WARNING] No active users found in $users_xml."
    fi
}

# Helper: Print user compliance report
print_user_compliance_report() {
    local users_xml="$1"
    echo "User Compliance Report:"
    local tmpfile=$(mktemp)
    grep -E '^[[:space:]]*<user ' "$users_xml" | while read -r line; do
        local username=$(echo "$line" | sed -n 's/.*username="\([^"]*\)".*/\1/p')
        local roles=$(echo "$line" | sed -n 's/.*roles="\([^"]*\)".*/\1/p')
        local password=$(echo "$line" | sed -n 's/.*password="\([^"]*\)".*/\1/p')
        local type="Plaintext"
        if [[ "$password" =~ ^[0-9a-fA-F:]+$ ]]; then
            if [[ "$password" =~ : ]]; then
                type="Salted Hash"
            else
                type="Hash"
            fi
        fi
        echo "$username,$roles,$type"
        echo 1 >> "$tmpfile"
    done
    local user_count=$(wc -l < "$tmpfile")
    rm -f "$tmpfile"
    if [ "$user_count" -eq 0 ]; then
        echo "[WARNING] No active users found in $users_xml."
    fi
}

# --- 5. Update tomcat-users.xml for all users ---
update_all_users() {
    local users_xml="$1"; local bin_dir="$2"; local version="$3"
    local tmp_xml="${users_xml}.tmp"
    cp "$users_xml" "$tmp_xml"
    local header_printed=0
    local any_updated=0
    local csv_file="/tmp/TomcatManager.csv"
    local csv_header="Timestamp,Username,OldType,NewType,Compliance"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    [ ! -f "$csv_file" ] && echo "$csv_header" > "$csv_file"
    grep -E '^[[:space:]]*<user ' "$users_xml" | grep -v '^[[:space:]]*<!--' | while read -r line; do
        local username=$(echo "$line" | sed -n 's/.*username="\([^"]*\)".*/\1/p')
        local pw=$(echo "$line" | sed -n 's/.*password="\([^"]*\)".*/\1/p')
        local old_type="Plaintext"
        local new_type compliance
        if [[ "$pw" =~ ^[0-9a-fA-F:]+$ ]]; then
            if [[ "$pw" =~ : ]]; then
                old_type="Salted Hash"
            else
                old_type="Hash"
            fi
        fi
        if [ "$old_type" = "Plaintext" ]; then
            if [ $header_printed -eq 0 ]; then
                echo "─────────────────────────────"
                echo " Tomcat User Password Update"
                echo "─────────────────────────────"
                header_printed=1
            fi
            any_updated=1
            local hash=$(generate_hash "$bin_dir" "$pw" "$version")
            new_type="Hash"
            if [[ "$hash" =~ : ]]; then
                new_type="Salted Hash"
            fi
            compliance="Compliant"
            echo "✔ Updated user: $username"
            echo "    • Old password:  $pw   (Plaintext, ❌ Non-compliant)"
            echo "    • New password:  $hash   ($new_type, ✅ Compliant)"
            echo
            echo "$timestamp,$username,Plaintext,$new_type,$compliance" >> "$csv_file"
            sed "/<user.*username=\"$username\"/s#password=\"[^\"]*\"#password=\"$hash\"#" "$tmp_xml" > "${tmp_xml}.new" && mv "${tmp_xml}.new" "$tmp_xml"
        fi
    done
    mv "$tmp_xml" "$users_xml"
    if [ "$header_printed" -eq 0 ]; then
        echo "─────────────────────────────"
        echo " Tomcat User Password Update"
        echo "─────────────────────────────"
        echo "No plaintext user passwords found to update."
    fi
}

# --- 6. Update server.xml CredentialHandler ---
update_server_xml() {
    local server_xml="$1"; local version="$2"
    local before_block after_block
    before_block=$(awk '/<CredentialHandler/{flag=1} flag; /\/>/{flag=0}' "$server_xml" | tr '\n' ' ' | sed 's/^ *//;s/ *$//')
    [ -z "$before_block" ] && before_block="(none found)"
    local handler=""
    case "$version" in
        7.0)
            handler='<CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-256"/>'
            ;;
        8.5)
            handler='<CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-512" iterations="10000" saltLength="16"/>'
            ;;
        9.0|10.0|10.1)
            handler='<CredentialHandler className="org.apache.catalina.realm.SecretKeyCredentialHandler" algorithm="PBKDF2WithHmacSHA512" iterations="10000" saltLength="16" keyLength="256"/>'
            ;;
        *)
            handler='<CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-512" iterations="10000" saltLength="16"/>'
            ;;
    esac
    if grep -q '<CredentialHandler' "$server_xml"; then
        sed "/<CredentialHandler/c\    $handler" "$server_xml" > "${server_xml}.new" && mv "${server_xml}.new" "$server_xml"
    else
        # Find the self-closing UserDatabaseRealm line and preserve all attributes
        local realm_line
        realm_line=$(grep -E '<Realm[^>]*UserDatabaseRealm[^>]*/>' "$server_xml")
        if [ -n "$realm_line" ]; then
            # Extract attributes (everything between <Realm and />)
            local attrs
            attrs=$(echo "$realm_line" | sed -E 's#<Realm (.*)/>#\1#')
            local open_realm="<Realm $attrs>"
            local close_realm="</Realm>"
            awk -v rl="$realm_line" -v orl="$open_realm" -v ch="$handler" -v crl="$close_realm" '
                {if ($0 ~ rl) {print orl; print "    " ch; print crl} else {print $0}}
            ' "$server_xml" > "${server_xml}.new" && mv "${server_xml}.new" "$server_xml"
        else
            sed "/<Realm[^>]*UserDatabaseRealm[^>]*>/a \
    $handler" "$server_xml" > "${server_xml}.new" && mv "${server_xml}.new" "$server_xml"
        fi
    fi
    after_block=$(awk '/<CredentialHandler/{flag=1} flag; /\/>/{flag=0}' "$server_xml" | tr '\n' ' ' | sed 's/^ *//;s/ *$//')
    [ -z "$after_block" ] && after_block="(none found)"
    echo "─────────────────────────────"
    echo " Tomcat CredentialHandler Update"
    echo "─────────────────────────────"
    echo "• Before:"
    echo "    $before_block"
    echo "• After:"
    echo "    $after_block"
    if [ "$before_block" != "$after_block" ]; then
        echo "✅ CredentialHandler updated for Tomcat $version."
    else
        if [ "$before_block" = "(none found)" ]; then
            echo "⚠️  No CredentialHandler found or updated."
        else
            echo "No CredentialHandler update needed; already compliant."
        fi
    fi
}

# --- 7. Restart Tomcat ---
restart_tomcat() {
    local bin_dir="$1"
    log "Restarting Tomcat via catalina.sh."
    "$bin_dir/catalina.sh" stop >/dev/null 2>&1
    sleep 2
    "$bin_dir/catalina.sh" start >/dev/null 2>&1
    log "Tomcat restarted via catalina.sh."
}

# --- 8. Main ---
main() {
    [ "$(id -u)" -eq 0 ] || error_exit "Run as root or with sudo."
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE_PATH"
    chmod 600 "$LOG_FILE_PATH"
    [ ! -f "$LOG_FILE" ] && echo "Timestamp,Message" > "$LOG_FILE"
    local custom_conf_path=""
    if [ $# -ge 1 ]; then
        custom_conf_path="$1"
    fi
    local conf_dir
    conf_dir=$(get_tomcat_config_path "$custom_conf_path")
    local users_xml="$conf_dir/tomcat-users.xml"
    local server_xml="$conf_dir/server.xml"
    local bin_dir=$(dirname "$conf_dir")/bin
    local tomcat_home=$(dirname "$bin_dir")
    local version=$(detect_tomcat_version "$tomcat_home")
    update_server_xml "$server_xml" "$version"
    update_all_users "$users_xml" "$bin_dir" "$version"
    print_compliance_summary "$version" "$server_xml" "$users_xml"
    restart_tomcat "$bin_dir" >/dev/null
}

print_compliance_summary() {
    local version="$1"
    local server_xml="$2"
    local users_xml="$3"
    local ch_line
    ch_line=$(awk '/<CredentialHandler/{flag=1} flag; /\/>/{flag=0}' "$server_xml" | tr '\n' ' ')
    local handler algorithm iterations salt_length
    handler=$(echo "$ch_line" | grep -o 'className="[^\"]*"' | sed 's/className="\([^"]*\)"/\1/')
    algorithm=$(echo "$ch_line" | grep -o 'algorithm="[^\"]*"' | sed 's/algorithm="\([^"]*\)"/\1/')
    iterations=$(echo "$ch_line" | grep -o 'iterations="[0-9]*"' | sed 's/iterations="\([0-9]*\)"/\1/')
    salt_length=$(echo "$ch_line" | grep -o 'saltLength="[0-9]*"' | sed 's/saltLength="\([0-9]*\)"/\1/')
    [ -z "$handler" ] && handler="(none)"
    [ -z "$algorithm" ] && algorithm="(none)"
    [ -z "$iterations" ] && iterations="(none)"
    [ -z "$salt_length" ] && salt_length="(none)"
    local ch_compliance="Non-compliant"
    if [[ "$handler" == *SecretKeyCredentialHandler* && "$algorithm" == *PBKDF2WithHmacSHA512* && "$iterations" -ge 10000 && "$salt_length" -ge 16 ]]; then
        ch_compliance="Compliant"
    fi
    echo "─────────────────────────────"
    echo " Tomcat User & Credential Audit"
    echo "─────────────────────────────"
    echo "Tomcat Version: $version"
    echo
    echo "CredentialHandler:"
    echo "  Status: $ch_compliance"
    echo "  Handler: $handler"
    echo "  Algorithm: $algorithm"
    echo "  Iterations: $iterations"
    echo "  Salt Length: $salt_length"
    echo
    echo "User Accounts:"
    printf "  %-13s | %-15s | %-15s | %-10s\n" "Username" "Roles" "Password Type" "Compliance"
    printf "  %-13s | %-15s | %-15s | %-10s\n" "-------------" "---------------" "---------------" "-----------"
    grep -E '^[[:space:]]*<user ' "$users_xml" | grep -v '^[[:space:]]*<!--' | while read -r line; do
        local username roles password type compliance
        username=$(echo "$line" | sed -n 's/.*username="\([^"]*\)".*/\1/p')
        roles=$(echo "$line" | sed -n 's/.*roles="\([^"]*\)".*/\1/p')
        password=$(echo "$line" | sed -n 's/.*password="\([^"]*\)".*/\1/p')
        type="Plaintext"
        compliance="Non-compliant"
        if [[ "$password" =~ ^[0-9a-fA-F:]+$ ]]; then
            if [[ "$password" =~ : ]]; then
                type="Salted Hash"
            else
                type="Hash"
            fi
            compliance="Compliant"
        fi
        printf "  %-13s | %-15s | %-15s | %-10s\n" "$username" "$roles" "$type" "$compliance"
    done
    echo
    echo "─────────────────────────────"
    echo "All users updated and server.xml patched."
}

get_tomcat_config_path() {
    local custom_conf_path="$1"
    local conf_path=""
    # Check custom path provided as argument
    if [ -n "$custom_conf_path" ]; then
        if [ -d "$custom_conf_path" ] && [ -f "$custom_conf_path/server.xml" ] && [ -f "$custom_conf_path/tomcat-users.xml" ]; then
            conf_path="$custom_conf_path"
        else
            echo "ERROR: Invalid custom configuration path: $custom_conf_path" >&2
            exit 1
        fi
    fi
    # Check CATALINA_BASE
    if [ -z "$conf_path" ] && [ -n "${CATALINA_BASE:-}" ] && [ -d "${CATALINA_BASE}/conf" ] && [ -f "${CATALINA_BASE}/conf/server.xml" ] && [ -f "${CATALINA_BASE}/conf/tomcat-users.xml" ]; then
        conf_path="${CATALINA_BASE}/conf"
    fi
    # Check CATALINA_HOME
    if [ -z "$conf_path" ] && [ -n "${CATALINA_HOME:-}" ] && [ -d "${CATALINA_HOME}/conf" ] && [ -f "${CATALINA_HOME}/conf/server.xml" ] && [ -f "${CATALINA_HOME}/conf/tomcat-users.xml" ]; then
        conf_path="${CATALINA_HOME}/conf"
    fi
    # Check running process
    if [ -z "$conf_path" ]; then
        local tomcat_pid
        tomcat_pid=$(pgrep -f "org.apache.catalina.startup.Bootstrap" 2>/dev/null)
        if [ -n "$tomcat_pid" ]; then
            local proc_args
            proc_args=$(ps -p "$tomcat_pid" -o args 2>/dev/null)
            local catalina_home
            catalina_home=$(echo "$proc_args" | grep -o -E '\-Dcatalina\.home=[^ ]+' | sed 's/-Dcatalina\.home=//')
            local catalina_base
            catalina_base=$(echo "$proc_args" | grep -o -E '\-Dcatalina\.base=[^ ]+' | sed 's/-Dcatalina\.base=//')
            if [ -n "$catalina_base" ] && [ -d "$catalina_base/conf" ] && [ -f "$catalina_base/conf/server.xml" ]; then
                conf_path="$catalina_base/conf"
            elif [ -n "$catalina_home" ] && [ -d "$catalina_home/conf" ] && [ -f "$catalina_home/conf/server.xml" ]; then
                conf_path="$catalina_home/conf"
            fi
        fi
    fi
    # Infer CATALINA_HOME from catalina.sh
    if [ -z "$conf_path" ] && [ -z "${CATALINA_HOME:-}" ]; then
        local catalina_script
        catalina_script=$(command -v catalina.sh 2>/dev/null)
        if [ -n "$catalina_script" ] && [ -f "$catalina_script" ]; then
            CATALINA_HOME=$(dirname "$(dirname "$catalina_script")")
            if [ -d "${CATALINA_HOME}/conf" ] && [ -f "${CATALINA_HOME}/conf/server.xml" ] && [ -f "${CATALINA_HOME}/conf/tomcat-users.xml" ]; then
                conf_path="${CATALINA_HOME}/conf"
            fi
        fi
    fi
    # Search common paths
    if [ -z "$conf_path" ]; then
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
            if [ -d "$path" ] && [ -f "$path/server.xml" ] && [ -f "$path/tomcat-users.xml" ]; then
                conf_path="$path"
                break
            fi
        done
    fi
    # Fallback to find command
    if [ -z "$conf_path" ]; then
        local found_path
        found_path=$(find / -type f -path "*/conf/server.xml" 2>/dev/null | head -n 1)
        if [ -n "$found_path" ]; then
            conf_path=$(dirname "$found_path")
            if [ ! -f "$conf_path/tomcat-users.xml" ]; then
                conf_path=""
            fi
        fi
    fi
    if [ -z "$conf_path" ]; then
        echo "ERROR: Could not locate Tomcat configuration directory (server.xml and tomcat-users.xml)." >&2
        exit 1
    fi
    echo "$conf_path"
}

main "$@"