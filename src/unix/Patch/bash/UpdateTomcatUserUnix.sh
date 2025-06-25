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
    echo "$TIMESTAMP,$msg" | tee -a "$LOG_FILE_PATH"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# --- 1. Locate Tomcat bin directory ---
find_tomcat_bin() {
    local bin_paths=(
        "/opt/tomcat/bin" "/usr/local/tomcat/bin" "/var/lib/tomcat7/bin" "/var/lib/tomcat8/bin" "/var/lib/tomcat9/bin" "/var/lib/tomcat10/bin"
        "/usr/share/tomcat/bin" "/usr/share/tomcat7/bin" "/usr/share/tomcat8/bin" "/usr/share/tomcat9/bin" "/usr/share/tomcat10/bin"
        "/etc/tomcat/bin" "/etc/tomcat7/bin" "/etc/tomcat8/bin" "/etc/tomcat9/bin" "/etc/tomcat10/bin"
    )
    for p in "${bin_paths[@]}"; do
        if [ -x "$p/digest.sh" ]; then
            echo "$p"
            return 0
        fi
    done
    # Try alternative versioned paths
    local alt_bin=$(find /opt /usr/local /var/lib /usr/share /etc -type d -name 'tomcat*' 2>/dev/null | grep '/bin$' | head -n1)
    if [ -n "$alt_bin" ] && [ -x "$alt_bin/digest.sh" ]; then
        echo "$alt_bin"
        return 0
    fi
    # Try systemd or process tracking
    local pid=$(pgrep -f 'org.apache.catalina.startup.Bootstrap' | head -n1)
    if [ -n "$pid" ]; then
        local proc_cwd="/proc/$pid/cwd"
        if [ -d "$proc_cwd/bin" ] && [ -x "$proc_cwd/bin/digest.sh" ]; then
            echo "$proc_cwd/bin"
            return 0
        fi
    fi
    # Try systemctl
    for svc in tomcat tomcat7 tomcat8 tomcat9 tomcat10; do
        local unit=$(systemctl show -p FragmentPath $svc.service 2>/dev/null | cut -d= -f2)
        if [ -n "$unit" ] && [ -f "$unit" ]; then
            local base_dir=$(dirname $(dirname "$unit"))
            if [ -x "$base_dir/bin/digest.sh" ]; then
                echo "$base_dir/bin"
                return 0
            fi
        fi
    done
    error_exit "Could not locate Tomcat bin directory with digest.sh."
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
    local bin_dir="$1"
    local ver=""
    if [ -f "$bin_dir/../RELEASE-NOTES" ]; then
        ver=$(grep -o 'Apache Tomcat Version [0-9]\+\.[0-9]\+\.[0-9]\+' "$bin_dir/../RELEASE-NOTES" | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    fi
    if [[ "$bin_dir" =~ tomcat7 ]]; then ver="7.0"; fi
    if [[ "$bin_dir" =~ tomcat8 ]]; then ver="8.5"; fi
    if [[ "$bin_dir" =~ tomcat9 ]]; then ver="9.0"; fi
    if [[ "$bin_dir" =~ tomcat10 ]]; then ver="10.0"; fi
    if [ -z "$ver" ]; then ver="8.5"; fi # fallback
    echo "$ver"
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

# --- 5. Update tomcat-users.xml for all users ---
update_all_users() {
    local users_xml="$1"; local bin_dir="$2"; local version="$3"
    local tmp_xml="${users_xml}.tmp"
    cp "$users_xml" "$tmp_xml"
    local users=( $(xmllint --xpath '//user/@username' "$users_xml" 2>/dev/null | sed -E 's/ username="([^"]*)"/\n\1/g' | grep -v '^$') )
    for user in "${users[@]}"; do
        local pw=$(xmllint --xpath "string(//user[@username='$user']/@password)" "$users_xml")
        local roles=$(xmllint --xpath "string(//user[@username='$user']/@roles)" "$users_xml")
        if [[ "$pw" =~ ^[0-9a-fA-F:]+$ ]]; then
            log "User $user already has a hash, skipping."
            continue
        fi
        local hash=$(generate_hash "$bin_dir" "$pw" "$version")
        log "User $user: password replaced with hash $hash"
        echo "User $user: password replaced with hash $hash"
        # Replace password in XML
        sed -i.bak "/<user.*username=\"$user\"/s/password=\"[^"]*\"/password=\"$hash\"/" "$tmp_xml"
    done
    mv "$tmp_xml" "$users_xml"
}

# --- 6. Update server.xml CredentialHandler ---
update_server_xml() {
    local server_xml="$1"; local version="$2"
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
    # Insert or update CredentialHandler in server.xml
    if grep -q '<CredentialHandler' "$server_xml"; then
        sed -i.bak "/<CredentialHandler/c\    $handler" "$server_xml"
    else
        # Insert inside <Realm ...UserDatabaseRealm...>
        sed -i.bak "/<Realm[^>]*UserDatabaseRealm[^>]*>/a \
    $handler" "$server_xml"
    fi
    log "server.xml CredentialHandler updated for Tomcat $version."
}

# --- 7. Restart Tomcat ---
restart_tomcat() {
    local bin_dir="$1"
    if command -v systemctl >/dev/null 2>&1; then
        for svc in tomcat tomcat7 tomcat8 tomcat9 tomcat10; do
            if systemctl is-active --quiet $svc 2>/dev/null; then
                systemctl restart $svc
                sleep 5
                log "Tomcat service $svc restarted."
                return 0
            fi
        done
    fi
    # Fallback: catalina.sh
    if [ -x "$bin_dir/catalina.sh" ]; then
        "$bin_dir/catalina.sh" stop || true
        sleep 5
        "$bin_dir/catalina.sh" start
        log "Tomcat restarted via catalina.sh."
        return 0
    fi
    error_exit "Could not restart Tomcat."
}

# --- 8. Main ---
main() {
    [ "$(id -u)" -eq 0 ] || error_exit "Run as root or with sudo."
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE_PATH"
    chmod 600 "$LOG_FILE_PATH"
    [ ! -f "$LOG_FILE" ] && echo "Timestamp,Message" > "$LOG_FILE"

    log "--- Tomcat User Patch Script Started ---"
    local bin_dir=$(find_tomcat_bin)
    log "Tomcat bin directory: $bin_dir"
    local conf_dir=$(find_tomcat_conf "$bin_dir")
    log "Tomcat conf directory: $conf_dir"
    local version=$(detect_tomcat_version "$bin_dir")
    log "Tomcat version: $version"
    local users_xml="$conf_dir/tomcat-users.xml"
    local server_xml="$conf_dir/server.xml"

    update_all_users "$users_xml" "$bin_dir" "$version"
    update_server_xml "$server_xml" "$version"
    restart_tomcat "$bin_dir"

    log "All users updated and server.xml patched."
    echo "SUCCESS: All users updated and server.xml patched."
}

main "$@"