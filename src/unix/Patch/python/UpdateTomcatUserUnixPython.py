#!/usr/bin/env python3
# UpdateTomcatUserUnixPython.py
# Processes existing users with plaintext passwords, generates compliant hashes, updates tomcat-users.xml and server.xml, and restarts Tomcat service

import os
import re
import sys
import subprocess
import datetime
import socket
import xml.etree.ElementTree as ET
import shutil
import time
from pathlib import Path

# Log setup
LOG_FILE = "/tmp/TomcatManager.csv"
log_messages = []

def write_log(message, indent=0):
    """
    Store a log message in memory and print to console with indentation.
    indent: Number of indentation levels (each level is two spaces).
    """
    indent_spaces = "  " * indent
    log_message = f"{indent_spaces}{message}"
    log_messages.append(log_message)
    print(log_message, file=sys.stderr)

# Ensure log file has header and secure permissions
if not os.path.exists(LOG_FILE):
    try:
        with open(LOG_FILE, "w") as f:
            f.write("Timestamp,Message\n")
        os.chmod(LOG_FILE, 0o600)
    except (PermissionError, OSError):
        write_log(f"Warning: Cannot create {LOG_FILE}. Logging to console only.", indent=2)

def get_tomcat_config_path(custom_conf_path=None):
    """Locate Tomcat configuration directory."""
    conf_path = None
    default_path = "/mnt/f/Koger/apps/apache-tomcat-7.0.94"

    # Check default path
    write_log(f"Checking default configuration path: {default_path}")
    if (os.path.isdir(f"{default_path}/conf") and
        os.path.isfile(f"{default_path}/conf/server.xml") and
        os.path.isfile(f"{default_path}/conf/tomcat-users.xml") and
        os.path.isfile(f"{default_path}/bin/digest.sh")):
        conf_path = f"{default_path}/conf"
        write_log(f"Found valid Tomcat configuration at default path: {conf_path}")

    # Check custom path
    if not conf_path and custom_conf_path:
        write_log(f"Checking custom configuration path: {custom_conf_path}")
        if (os.path.isdir(custom_conf_path) and
            os.path.isfile(f"{custom_conf_path}/server.xml") and
            os.path.isfile(f"{custom_conf_path}/tomcat-users.xml") and
            os.path.isfile(f"{os.path.dirname(custom_conf_path)}/bin/digest.sh")):
            conf_path = custom_conf_path
            write_log(f"Found valid Tomcat configuration at custom path: {conf_path}")
        else:
            write_log(f"ERROR: Invalid custom configuration path: {custom_conf_path}", indent=2)

    # Check environment variables
    if not conf_path and "CATALINA_BASE" in os.environ:
        base = os.environ["CATALINA_BASE"]
        if (os.path.isdir(f"{base}/conf") and
            os.path.isfile(f"{base}/conf/server.xml") and
            os.path.isfile(f"{base}/conf/tomcat-users.xml") and
            os.path.isfile(f"{base}/bin/digest.sh")):
            conf_path = f"{base}/conf"
            write_log(f"Found Tomcat configuration at CATALINA_BASE: {conf_path}")

    if not conf_path and "CATALINA_HOME" in os.environ:
        home = os.environ["CATALINA_HOME"]
        if (os.path.isdir(f"{home}/conf") and
            os.path.isfile(f"{home}/conf/server.xml") and
            os.path.isfile(f"{home}/conf/tomcat-users.xml") and
            os.path.isfile(f"{home}/bin/digest.sh")):
            conf_path = f"{home}/conf"
            write_log(f"Found Tomcat configuration at CATALINA_HOME: {conf_path}")

    # Search common paths
    if not conf_path:
        write_log("Searching common Tomcat configuration paths...")
        possible_paths = [
            "/opt/tomcat/conf",
            "/usr/local/tomcat/conf",
            "/var/lib/tomcat7/conf",
            "/var/lib/tomcat8/conf",
            "/var/lib/tomcat9/conf",
            "/var/lib/tomcat10/conf",
            "/usr/share/tomcat/conf",
            "/usr/share/tomcat7/conf",
            "/usr/share/tomcat8/conf",
            "/usr/share/tomcat9/conf",
            "/usr/share/tomcat10/conf",
            "/etc/tomcat/conf",
            "/etc/tomcat7/conf",
            "/etc/tomcat8/conf",
            "/etc/tomcat9/conf",
            "/etc/tomcat10/conf"
        ]
        for path in possible_paths:
            if (os.path.isdir(path) and
                os.path.isfile(f"{path}/server.xml") and
                os.path.isfile(f"{path}/tomcat-users.xml") and
                os.path.isfile(f"{os.path.dirname(path)}/bin/digest.sh")):
                conf_path = path
                write_log(f"Found Tomcat configuration at: {path}")
                break

    if not conf_path:
        write_log("ERROR: Could not locate Tomcat configuration directory.")
        write_log("  - Ensure Tomcat is installed and digest.sh exists", indent=2)
        return None

    return conf_path

def detect_tomcat_version(tomcat_home):
    """Detect Tomcat version from RELEASE-NOTES or default to 7.0."""
    version_file = os.path.join(tomcat_home, "RELEASE-NOTES")
    version = "7.0"  # Default

    if os.path.isfile(version_file):
        try:
            with open(version_file, "r") as f:
                content = f.read()
                match = re.search(r"Apache Tomcat Version\s+([0-9]+\.[0-9]+\.[0-9]+)", content)
                if match:
                    full_version = match.group(1)
                    if full_version.startswith("7.0"): version = "7.0"
                    elif full_version.startswith("8.0"): version = "8.0"
                    elif full_version.startswith("8.5"): version = "8.5"
                    elif full_version.startswith("9.0"): version = "9.0"
                    elif full_version.startswith("10.0"): version = "10.0"
                    elif full_version.startswith("10.1"): version = "10.1"
                    write_log(f"Version found in RELEASE-NOTES: {full_version} ({version})")
        except Exception as e:
            write_log(f"Warning: Error reading {version_file}: {str(e)}", indent=2)
    else:
        write_log("Warning: RELEASE-NOTES not found, defaulting to version 7.0", indent=2)

    return version

def generate_password_hash(tomcat_bin, password, tomcat_version):
    """Generate compliant hash using digest.sh."""
    digest_script = os.path.join(tomcat_bin, "digest.sh")
    algorithm = ""
    iterations = ""
    salt_length = ""

    # Set algorithm and parameters based on Tomcat version
    if tomcat_version == "7.0":
        algorithm = "SHA-256"
    elif tomcat_version == "8.5":
        algorithm = "SHA-512"
        iterations = "10000"
        salt_length = "16"
    elif tomcat_version in ["9.0", "10.0", "10.1"]:
        algorithm = "PBKDF2WithHmacSHA512"
        iterations = "10000"
        salt_length = "16"
    else:
        write_log(f"ERROR: Unsupported Tomcat version: {tomcat_version}", indent=2)
        return None

    if not (os.path.isfile(digest_script) and os.access(digest_script, os.X_OK)):
        write_log(f"ERROR: digest.sh not found or not executable at {digest_script}", indent=2)
        return None

    # Verify JAVA_HOME
    if "JAVA_HOME" not in os.environ:
        write_log("ERROR: JAVA_HOME is not set, required for digest.sh", indent=2)
        return None

    # Run digest.sh
    try:
        cmd = [digest_script, "-a", algorithm]
        if tomcat_version != "7.0":
            cmd.extend(["-i", iterations, "-s", salt_length])
        cmd.append(password)
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            write_log("ERROR: Failed to generate hash using digest.sh", indent=2)
            return None

        # Extract hash
        match = re.search(r'[0-9a-fA-F:]+', result.stdout)
        if not match:
            write_log("ERROR: Failed to parse hash from digest.sh output", indent=2)
            return None
        return match.group(0)
    except Exception as e:
        write_log(f"ERROR: Failed to generate hash: {str(e)}", indent=2)
        return None

def get_plaintext_users(users_xml_path):
    """Extract users with plaintext passwords from tomcat-users.xml."""
    if not os.path.isfile(users_xml_path):
        write_log(f"ERROR: {users_xml_path} not found", indent=2)
        return None

    if os.path.getsize(users_xml_path) == 0:
        write_log(f"WARNING: {users_xml_path} is empty", indent=2)
        return []

    try:
        with open(users_xml_path, "r", encoding="utf-8") as f:
            content = f.read()
        users = []
        user_pattern = re.compile(r'<user[^>]*username="([^"]+)"[^>]*password="([^"]+)"[^>]*>')
        for match in user_pattern.finditer(content):
            username = match.group(1)
            password = match.group(2)
            # Check if password is plaintext (not a hash)
            if not re.match(r'^[0-9a-fA-F:]+$', password) or not re.match(
                r'^[0-9a-fA-F]{32}$|^[0-9a-fA-F]{40}$|^[0-9a-fA-F]{64}$|^[0-9a-fA-F]{128}$|^[0-9a-fA-F]+:[0-9a-fA-F]+$',
                password):
                users.append({"username": username, "password": password})
        if not users:
            write_log(f"No users with plaintext passwords found in {users_xml_path}", indent=2)
        return users
    except Exception as e:
        write_log(f"ERROR: Failed to read {users_xml_path}: {str(e)}", indent=2)
        return None

def update_tomcat_users_xml(users_xml_path, user_pairs):
    """Update tomcat-users.xml with new hashes."""
    backup_path = f"{users_xml_path}.bak.{datetime.datetime.now().strftime('%Y%m%d%H%M%S')}"
    try:
        shutil.copy2(users_xml_path, backup_path)
        os.chmod(backup_path, 0o600)
        write_log(f"Backed up {users_xml_path} to {backup_path}")
    except Exception as e:
        write_log(f"ERROR: Failed to backup {users_xml_path}: {str(e)}", indent=2)
        return False

    try:
        tree = ET.parse(users_xml_path)
        root = tree.getroot()
        for pair in user_pairs:
            username = pair["username"]
            hash_value = pair["hash"]
            for user in root.findall(".//user"):
                if user.get("username") == username:
                    user.set("password", hash_value)
                    write_log(f"Updated user {username} with new hash in {users_xml_path}")
        tree.write(users_xml_path)
        # Basic XML validation
        with open(users_xml_path, "r", encoding="utf-8") as f:
            if "</tomcat-users>" not in f.read():
                raise ValueError("Invalid XML")
        return True
    except Exception as e:
        write_log(f"ERROR: Failed to update {users_xml_path}: {str(e)}", indent=2)
        shutil.copy2(backup_path, users_xml_path)
        write_log(f"Restored {users_xml_path} from backup")
        return False

def update_server_xml(server_xml_path, tomcat_version):
    """Configure server.xml for compliance."""
    backup_path = f"{server_xml_path}.bak.{datetime.datetime.now().strftime('%Y%m%d%H%M%S')}"
    try:
        shutil.copy2(server_xml_path, backup_path)
        os.chmod(backup_path, 0o600)
        write_log(f"Backed up {server_xml_path} to {backup_path}")
    except Exception as e:
        write_log(f"ERROR: Failed to backup {server_xml_path}: {str(e)}", indent=2)
        return False

    try:
        tree = ET.parse(server_xml_path)
        root = tree.getroot()
        realm = root.find(".//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
        if not realm:
            engine = root.find(".//Engine")
            realm = ET.SubElement(engine, "Realm", className="org.apache.catalina.realm.UserDatabaseRealm", resourceName="UserDatabase")
            write_log(f"Added new Realm to {server_xml_path}")

        # Remove existing CredentialHandler
        for ch in realm.findall("CredentialHandler"):
            realm.remove(ch)

        # Add new CredentialHandler
        ch = ET.SubElement(realm, "CredentialHandler")
        if tomcat_version == "7.0":
            ch.set("className", "org.apache.catalina.realm.MessageDigestCredentialHandler")
            ch.set("algorithm", "SHA-256")
        elif tomcat_version == "8.5":
            ch.set("className", "org.apache.catalina.realm.MessageDigestCredentialHandler")
            ch.set("algorithm", "SHA-512")
            ch.set("iterations", "10000")
            ch.set("saltLength", "16")
        elif tomcat_version in ["9.0", "10.0", "10.1"]:
            ch.set("className", "org.apache.catalina.realm.SecretKeyCredentialHandler")
            ch.set("algorithm", "PBKDF2WithHmacSHA512")
            ch.set("iterations", "10000")
            ch.set("saltLength", "16")
            ch.set("keyLength", "256")
        else:
            write_log(f"ERROR: Unsupported Tomcat version: {tomcat_version}", indent=2)
            return False

        tree.write(server_xml_path)
        # Basic XML validation
        with open(server_xml_path, "r", encoding="utf-8") as f:
            if "</Server>" not in f.read():
                raise ValueError("Invalid XML")
        write_log(f"Updated Realm configuration in {server_xml_path}")
        return True
    except Exception as e:
        write_log(f"ERROR: Failed to update {server_xml_path}: {str(e)}", indent=2)
        shutil.copy2(backup_path, server_xml_path)
        write_log(f"Restored {server_xml_path} from backup")
        return False

def restart_tomcat_service(tomcat_home):
    """Restart Tomcat service."""
    service_name = None
    for svc in ["tomcat", "tomcat7", "tomcat8", "tomcat9", "tomcat10"]:
        try:
            result = subprocess.run(["systemctl", "is-active", svc], capture_output=True, text=True)
            if result.returncode == 0:
                service_name = svc
                break
        except subprocess.CalledProcessError:
            continue

    if service_name:
        write_log(f"Restarting Tomcat service: {service_name}")
        try:
            subprocess.run(["systemctl", "restart", service_name], check=True, capture_output=True)
            time.sleep(5)
            result = subprocess.run(["systemctl", "is-active", service_name], capture_output=True, text=True)
            if result.returncode != 0:
                write_log(f"ERROR: Tomcat service {service_name} failed to start", indent=2)
                return False
            write_log(f"Tomcat service {service_name} restarted successfully")
            return True
        except subprocess.CalledProcessError as e:
            write_log(f"ERROR: Failed to restart Tomcat service {service_name}: {str(e)}", indent=2)
            return False
    else:
        catalina_script = os.path.join(tomcat_home, "bin/catalina.sh")
        if os.path.isfile(catalina_script) and os.access(catalina_script, os.X_OK):
            write_log("No systemd service found, using catalina.sh to restart")
            try:
                subprocess.run([catalina_script, "stop"], capture_output=True, check=True)
                time.sleep(5)
                subprocess.run([catalina_script, "start"], capture_output=True, check=True)
                time.sleep(5)
                result = subprocess.run(["pgrep", "-f", "org.apache.catalina.startup.Bootstrap"], capture_output=True)
                if result.returncode != 0:
                    write_log("ERROR: Tomcat failed to start via catalina.sh", indent=2)
                    return False
                write_log("Tomcat restarted successfully via catalina.sh")
                return True
            except subprocess.CalledProcessError as e:
                write_log(f"ERROR: Failed to restart Tomcat using catalina.sh: {str(e)}", indent=2)
                return False
        else:
            write_log("ERROR: No Tomcat service or catalina.sh found", indent=2)
            return False

def main():
    """Main function to execute the audit and update process."""
    if os.geteuid() != 0:
        write_log("ERROR: This script must be run as root or with sudo")
        sys.exit(1)

    # Parse arguments
    custom_conf_path = None
    for arg in sys.argv[1:]:
        if arg.startswith("--custom-conf="):
            custom_conf_path = arg.split("=", 1)[1]
        else:
            write_log(f"ERROR: Unknown argument: {arg}")
            sys.exit(1)

    exec_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    hostname = socket.gethostname()
    write_log(f"Execution Time: {exec_time}")
    write_log(f"Hostname: {hostname}")
    write_log("===========================")

    conf_path = get_tomcat_config_path(custom_conf_path)
    if not conf_path:
        combined_message = "; ".join(log_messages)
        log_entry = f"{exec_time},\"{combined_message}\""
        try:
            with open(LOG_FILE, "a") as f:
                f.write(log_entry + "\n")
        except PermissionError:
            write_log(f"Error: Cannot write to {LOG_FILE}")
        sys.exit(1)

    tomcat_home = os.path.dirname(conf_path)
    write_log(f"Tomcat Home: {tomcat_home}")
    write_log(f"Config Path: {conf_path}")

    tomcat_version = detect_tomcat_version(tomcat_home)
    write_log(f"Tomcat Version: {tomcat_version}")

    users_xml_path = os.path.join(conf_path, "tomcat-users.xml")
    write_log(f"Reading {users_xml_path} for users with plaintext passwords")
    plaintext_users = get_plaintext_users(users_xml_path)
    if plaintext_users is None:
        combined_message = "; ".join(log_messages)
        log_entry = f"{exec_time},\"{combined_message}\""
        try:
            with open(LOG_FILE, "a") as f:
                f.write(log_entry + "\n")
        except PermissionError:
            write_log(f"Error: Cannot write to {LOG_FILE}")
        sys.exit(1)

    if not plaintext_users:
        write_log("No plaintext passwords to update")
        write_log(f"Updating {users_xml_path} for compliance only")
    else:
        write_log(f"Found {len(plaintext_users)} user(s) with plaintext passwords")

    updated_users = []
    for user in plaintext_users:
        username = user["username"]
        password = user["password"]
        write_log(f"Processing user: {username} (Original plaintext password: [REDACTED])", indent=2)
        hash_value = generate_password_hash(tomcat_home + "/bin", password, tomcat_version)
        if not hash_value:
            combined_message = "; ".join(log_messages)
            log_entry = f"{exec_time},\"{combined_message}\""
            try:
                with open(LOG_FILE, "a") as f:
                    f.write(log_entry + "\n")
            except PermissionError:
                write_log(f"Error: Cannot write to {LOG_FILE}")
            sys.exit(1)
        write_log(f"Generated Hash for {username}: {hash_value}", indent=2)
        updated_users.append({"username": username, "hash": hash_value})

    if updated_users:
        write_log(f"Updating {users_xml_path} with new hashes")
        if not update_tomcat_users_xml(users_xml_path, updated_users):
            combined_message = "; ".join(log_messages)
            log_entry = f"{exec_time},\"{combined_message}\""
            try:
                with open(LOG_FILE, "a") as f:
                    f.write(log_entry + "\n")
            except PermissionError:
                write_log(f"Error: Cannot write to {LOG_FILE}")
            sys.exit(1)

    server_xml_path = os.path.join(conf_path, "server.xml")
    write_log(f"Updating {server_xml_path} for compliance")
    if not update_server_xml(server_xml_path, tomcat_version):
        combined_message = "; ".join(log_messages)
        log_entry = f"{exec_time},\"{combined_message}\""
        try:
            with open(LOG_FILE, "a") as f:
                f.write(log_entry + "\n")
            except PermissionError:
                write_log(f"Error: Cannot write to {LOG_FILE}")
        sys.exit(1)

    write_log("Restarting Tomcat to apply changes")
    if not restart_tomcat_service(tomcat_home):
        combined_message = "; ".join(log_messages)
        log_entry = f"{exec_time},\"{combined_message}\""
        try:
            with open(LOG_FILE, "a") as f:
                f.write(log_entry + "\n")
        except PermissionError:
            write_log(f"Error: Cannot write to {LOG_FILE}")
        sys.exit(1)

    compliance_status = {
        "7.0": "Compliant with SHA-256 (MessageDigestCredentialHandler)",
        "8.5": "Compliant with SHA-512, 10000 iterations, 16-byte salt (MessageDigestCredentialHandler)",
        "9.0": "Compliant with PBKDF2WithHmacSHA512, 10000 iterations, 16-byte salt (SecretKeyCredentialHandler)",
        "10.0": "Compliant with PBKDF2WithHmacSHA512, 10000 iterations, 16-byte salt (SecretKeyCredentialHandler)",
        "10.1": "Compliant with PBKDF2WithHmacSHA512, 10000 iterations, 16-byte salt (SecretKeyCredentialHandler)"
    }.get(tomcat_version, "Unknown compliance status")
    write_log(f"Compliance Status: {compliance_status}")
    write_log("===========================")
    write_log("Overall Status: Secure")
    write_log("Audit completed")

    combined_message = "; ".join(log_messages)
    log_entry = f"{exec_time},\"{combined_message}\""
    try:
        with open(LOG_FILE, "a") as f:
            f.write(log_entry + "\n")
    except PermissionError:
        write_log(f"Error: Cannot write to {LOG_FILE}")

if __name__ == "__main__":
    main()