#!/usr/bin/env python3
# test_config_unix.py
# Tests CheckTomcatConfigUnix.py for various Tomcat configurations (7.0, 8.0, 8.5, 9.0, 10.0)

import os
import sys
import shutil
import subprocess
import xml.etree.ElementTree as ET
import re
import time

# Log setup
log_file = os.path.expanduser("~/TestTomcatConfig.log")

def write_log(message, indent=0, marker=""):
    indent_spaces = "  " * indent
    log_message = f"{indent_spaces}{marker}{message}"
    try:
        with open(log_file, "a") as f:
            f.write(log_message + "\n")
    except PermissionError:
        print(f"Warning: Cannot write to {log_file}. Logging to console only.", file=sys.stderr)
    print(log_message)

write_log("Starting tests for CheckTomcatConfigUnix.py...")

# Verify script exists
if not os.path.exists("./CheckTomcatConfigUnix.py"):
    write_log("Error: CheckTomcatConfigUnix.py not found")
    sys.exit(1)
write_log("Verified file exists: ./CheckTomcatConfigUnix.py")

# Clear existing log
if os.path.exists(log_file):
    try:
        open(log_file, 'w').close()
        write_log(f"Cleared existing log file: {log_file}")
    except PermissionError:
        write_log(f"Warning: Cannot clear {log_file}. Continuing...")

# Function to detect Tomcat path and version
def get_tomcat_config_path():
    catalina_home = os.getenv("CATALINA_HOME")
    if catalina_home:
        conf_path = os.path.join(catalina_home, "conf")
        if os.path.exists(conf_path) and os.path.exists(os.path.join(conf_path, "server.xml")):
            return conf_path
    possible_paths = [
        "/usr/local/tomcat/conf",
        "/opt/tomcat/conf",
        "/var/lib/tomcat7/conf",
        "/var/lib/tomcat8/conf",
        "/var/lib/tomcat9/conf",
        "/var/lib/tomcat10/conf",
        "/usr/share/tomcat7/conf",
        "/usr/share/tomcat8/conf",
        "/usr/share/tomcat9/conf",
        "/usr/share/tomcat10/conf"
    ]
    for path in possible_paths:
        if os.path.exists(path) and os.path.exists(os.path.join(path, "server.xml")):
            return path
    return None

def detect_tomcat_version(tomcat_home):
    version_file = os.path.join(tomcat_home, "RELEASE-NOTES")
    if os.path.exists(version_file):
        with open(version_file, "r") as f:
            for line in f:
                if line.startswith("Apache Tomcat Version"):
                    version = line.split()[-1]
                    if version.startswith("7."):
                        return "7.0"
                    elif version.startswith("8.0"):
                        return "8.0"
                    elif version.startswith("8."):
                        return "8.5"
                    elif version.startswith("9."):
                        return "9.0"
                    elif version.startswith("10."):
                        return "10.0"
    if "tomcat7" in tomcat_home.lower():
        return "7.0"
    elif "tomcat8" in tomcat_home.lower():
        return "8.5" if "tomcat8.5" in tomcat_home.lower() else "8.0"
    elif "tomcat9" in tomcat_home.lower():
        return "9.0"
    elif "tomcat10" in tomcat_home.lower():
        return "10.0"
    return "Unknown"

# Detect Tomcat installation
tomcat_conf_path = get_tomcat_config_path()
if not tomcat_conf_path:
    write_log("Error: No Tomcat configuration directory found")
    sys.exit(1)
tomcat_version = detect_tomcat_version(os.path.dirname(tomcat_conf_path))
write_log(f"Found Tomcat at {tomcat_conf_path}, version: {tomcat_version}")

# Backup directory
backup_dir = "/tmp/TomcatConfigBackup"
if not os.path.exists(backup_dir):
    os.makedirs(backup_dir)

# Define test cases
password_tests = [
    "Plaintext",
    "Hashed_MD5",
    "Hashed_SHA1",
    "Hashed_SHA256",
    "Hashed_SHA512",
    "Salted_MD5",
    "Salted_PBKDF2"
]

server_tests = [
    "NoCredentialHandler",
    "MessageDigestCredentialHandler_MD5",
    "MessageDigestCredentialHandler_SHA256"
]
if tomcat_version in ["8.0", "8.5", "9.0", "10.0"]:
    server_tests.append("MessageDigestCredentialHandler_SHA512")
    server_tests.append("NestedCredentialHandler")
if tomcat_version in ["9.0", "10.0"]:
    server_tests.append("SecretKeyCredentialHandler_PBKDF2")
if tomcat_version == "7.0":
    write_log("Limiting tests for Tomcat 7.0: Excluding SHA-512, NestedCredentialHandler, and SecretKeyCredentialHandler")

# Password examples
password_values = {
    "Plaintext": "s3cret",
    "Hashed_MD5": "5ebe2294ecd0e0f08eab7690d2a6ee69",
    "Hashed_SHA1": "e5e9fa1ba31ecd1ae84f75caaa474f3a663f05f4",
    "Hashed_SHA256": "94f9b6c88f1b2b3b3363b7f4174480c1b3913b8200cb0a50f2974f2bc90bc774",
    "Hashed_SHA512": "eede1e3b1840e3a3c2283ff623e3db6b4d8abfad6bded83fd36f9db08e7c3f2c2df0b5b7e6c9c0d1ebfe7e3b3c3d8b0e7f9d0c1f7e6b4c3b2a1f0e9d8c7b6a5f",
    "Salted_MD5": "8208b5051cdd2b35cfba7f0b70b57e7f:1234567890abcdef",
    "Salted_PBKDF2": "4b6f7e8c9d0a1b2c3d4e5f60718293a4:1234567890abcdef"
}

# Server configurations
server_configs = {
    "NoCredentialHandler": "",
    "MessageDigestCredentialHandler_MD5": '<CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="MD5"/>',
    "MessageDigestCredentialHandler_SHA256": '<CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-256" iterations="10000" saltLength="16"/>',
    "MessageDigestCredentialHandler_SHA512": '<CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-512" iterations="10000" saltLength="16"/>',
    "NestedCredentialHandler": '<CredentialHandler className="org.apache.catalina.realm.NestedCredentialHandler"><CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-256"/></CredentialHandler>',
    "SecretKeyCredentialHandler_PBKDF2": '<CredentialHandler className="org.apache.catalina.realm.SecretKeyCredentialHandler" algorithm="PBKDF2WithHmacSHA512" iterations="10000" saltLength="16" keyLength="256"/>'
}

# Backup original files
server_xml = os.path.join(tomcat_conf_path, "server.xml")
users_xml = os.path.join(tomcat_conf_path, "tomcat-users.xml")
shutil.copy(server_xml, os.path.join(backup_dir, "server.xml.bak"))
shutil.copy(users_xml, os.path.join(backup_dir, "tomcat-users.xml.bak"))
write_log(f"Backed up original files to {backup_dir}")

# Run tests
test_count = 0
passed_tests = 0
failed_tests = 0

for server_test in server_tests:
    for password_test in password_tests:
        if password_test == "Hashed_SHA512" and tomcat_version in ["7.0", "8.0"]:
            write_log(f"Skipping Hashed_SHA512 for Tomcat {tomcat_version} (not supported)")
            continue
        if password_test == "Salted_PBKDF2" and tomcat_version in ["7.0", "8.0"]:
            write_log(f"Skipping Salted_PBKDF2 for Tomcat {tomcat_version} (not supported)")
            continue
        if password_test == "Salted_PBKDF2" and server_test == "SecretKeyCredentialHandler_PBKDF2" and tomcat_version not in ["9.0", "10.0"]:
            write_log(f"Skipping Salted_PBKDF2 with SecretKeyCredentialHandler for Tomcat {tomcat_version} (not supported)")
            continue
        test_count += 1
        test_name = f"{tomcat_version}_{server_test}_{password_test}"
        write_log(f"Test: {test_name}", indent=1)
        write_log(f"Description: Testing {password_test} password with {server_test} CredentialHandler", indent=2)

        # Modify server.xml
        tree = ET.parse(server_xml)
        root = tree.getroot()
        realm = root.find(".//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
        if realm is None:
            realm = root.find(".//Realm[@className='org.apache.catalina.realm.MemoryRealm']")
        if server_test == "NoCredentialHandler":
            if realm.find("CredentialHandler") is not None:
                realm.remove(realm.find("CredentialHandler"))
        else:
            new_handler = ET.fromstring(server_configs[server_test])
            existing_handler = realm.find("CredentialHandler")
            if existing_handler is not None:
                realm.remove(existing_handler)
            realm.append(new_handler)
        tree.write(server_xml)
        write_log(f"Modified server.xml: {'Removed all CredentialHandlers' if server_test == 'NoCredentialHandler' else f'Set {server_test}'}", indent=2)

        # Modify tomcat-users.xml
        users_tree = ET.parse(users_xml)
        users_root = users_tree.getroot()
        user = users_root.find(".//user[@username='testuser']")
        if user is None:
            user = ET.Element("user")
            user.set("username", "testuser")
            user.set("roles", "manager")
            users_root.append(user)
        user.set("password", password_values[password_test])
        users_tree.write(users_xml)
        write_log(f"Modified tomcat-users.xml: Set password for testuser to {password_test} ({password_values[password_test]})", indent=2)

        # Run CheckTomcatConfigUnix.py
        result = subprocess.run(["python3", "./CheckTomcatConfigUnix.py"], capture_output=True, text=True)
        output = result.stdout
        write_log("Actual output:", indent=2)
        for line in output.split("\n"):
            write_log(line, indent=3)
        
        # Simplified pass/fail check (actual implementation would compare expected output)
        expected_status = "Compliant" if password_test in ["Hashed_SHA256", "Hashed_SHA512", "Salted_PBKDF2"] and server_test in ["MessageDigestCredentialHandler_SHA256", "MessageDigestCredentialHandler_SHA512", "SecretKeyCredentialHandler_PBKDF2"] and tomcat_version not in ["7.0", "8.0"] else "Non-compliant"
        if expected_status in output:
            write_log("Result: PASSED", indent=2)
            passed_tests += 1
        else:
            write_log("Result: FAILED", indent=2)
            failed_tests += 1

# Restore original files
shutil.copy(os.path.join(backup_dir, "server.xml.bak"), server_xml)
shutil.copy(os.path.join(backup_dir, "tomcat-users.xml.bak"), users_xml)
write_log("Restored original configuration files")

# Test summary
write_log("Test Summary:")
write_log(f"Total tests run: {test_count}")
write_log(f"Tests passed: {passed_tests}")
write_log(f"Tests failed: {failed_tests}")
write_log("All tests completed")
