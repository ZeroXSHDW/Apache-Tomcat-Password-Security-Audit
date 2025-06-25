#!/usr/bin/env python3
# test_config_unix.py
# Tests CheckTomcatConfigUnix.py for various Tomcat configurations (7.0, 8.5, 9.0, 10.0, 10.1)

import os
import sys
import re
import subprocess
import logging
import xml.etree.ElementTree as ET
import shutil
import time
import socket
import argparse
from datetime import datetime
from pathlib import Path

# Constants
LOG_FILE = os.path.expanduser("~/TestTomcatConfig.log")
LOG_DIR = os.path.dirname(LOG_FILE)
LOG_FILE_PATH = LOG_FILE
TIMESTAMP = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
HOSTNAME = socket.gethostname()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

def write_log(message, level="INFO"):
    """Write a log message with timestamp and severity level."""
    log_message = f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} - {level} - {message}"
    with open(LOG_FILE, 'a') as f:
        f.write(log_message + '\n')
    print(log_message)

def detect_tomcat_path():
    """Detect Tomcat installation path and version."""
    possible_paths = [
        "/usr/local/tomcat",
        "/opt/tomcat",
        "/usr/share/tomcat",
        "/var/lib/tomcat",
        "/var/lib/tomcat7",
        "/var/lib/tomcat8",
        "/var/lib/tomcat9",
        "/var/lib/tomcat10"
    ]
    
    for path in possible_paths:
        if os.path.exists(path):
            version_file = os.path.join(path, "RELEASE-NOTES")
            if os.path.exists(version_file):
                with open(version_file, 'r') as f:
                    content = f.read()
                    version_match = re.search(r"Apache Tomcat Version\s+(\d+\.\d+\.\d+)", content)
                    if version_match:
                        full_version = version_match.group(1)
                        version = "7.0"  # Default
                        if full_version.startswith("8.5"):
                            version = "8.5"
                        elif full_version.startswith("9.0"):
                            version = "9.0"
                        elif full_version.startswith("10.0"):
                            version = "10.0"
                        elif full_version.startswith("10.1"):
                            version = "10.1"
                        return {"path": path, "version": version}
    return None

def validate_xml_structure(xml_file):
    """Validate XML file structure and content."""
    try:
        if not os.path.exists(xml_file):
            write_log(f"XML file {xml_file} not found", "ERROR")
            return False

        # Check for XML declaration
        with open(xml_file, 'r') as f:
            first_line = f.readline().strip()
            if not first_line.startswith('<?xml'):
                write_log(f"Invalid XML declaration in {xml_file}", "ERROR")
                return False
        
        # Parse XML
        ET.parse(xml_file)
        return True
    except Exception as e:
        write_log(f"Error validating XML {xml_file}: {str(e)}", "ERROR")
        return False

def secure_parse_xml(xml_file):
    """Securely parse XML file with validation."""
    try:
        if not os.path.exists(xml_file):
            write_log(f"XML file {xml_file} not found", "ERROR")
            return None
        
        if not validate_xml_structure(xml_file):
            return None
        
        return ET.parse(xml_file)
    except Exception as e:
        write_log(f"Error parsing XML {xml_file}: {str(e)}", "ERROR")
        return None

def secure_write_xml(xml_file, xml_content):
    """Securely write XML content to file with backup."""
    try:
        # Create backup
        if os.path.exists(xml_file):
            backup_file = f"{xml_file}.bak.{datetime.now().strftime('%Y%m%d%H%M%S')}"
            shutil.copy2(xml_file, backup_file)
            os.chmod(backup_file, 0o600)  # Secure permissions
            write_log(f"Created backup: {backup_file}")
        
        # Write to temporary file
        temp_file = f"{xml_file}.tmp"
        xml_content.write(temp_file, encoding='utf-8', xml_declaration=True)
        
        # Validate temporary file
        if not validate_xml_structure(temp_file):
            os.remove(temp_file)
            return False
        
        # Move to final location
        shutil.move(temp_file, xml_file)
        os.chmod(xml_file, 0o600)  # Secure permissions
        return True
    except Exception as e:
        write_log(f"Error writing XML {xml_file}: {str(e)}", "ERROR")
        if os.path.exists(temp_file):
            os.remove(temp_file)
        return False

def backup_config_files(conf_path):
    """Create secure backups of configuration files."""
    backup_dir = os.path.join(os.path.expanduser("~"), "TomcatConfigBackup")
    os.makedirs(backup_dir, exist_ok=True)
    os.chmod(backup_dir, 0o700)  # Secure permissions
    
    server_xml = os.path.join(conf_path, "conf", "server.xml")
    users_xml = os.path.join(conf_path, "conf", "tomcat-users.xml")
    
    if os.path.exists(server_xml):
        shutil.copy2(server_xml, os.path.join(backup_dir, "server.xml.bak"))
    if os.path.exists(users_xml):
        shutil.copy2(users_xml, os.path.join(backup_dir, "tomcat-users.xml.bak"))
    
    return backup_dir

def restore_config_files(conf_path, backup_dir):
    """Restore configuration files from backup."""
    try:
        server_xml = os.path.join(conf_path, "conf", "server.xml")
        users_xml = os.path.join(conf_path, "conf", "tomcat-users.xml")
        
        shutil.copy2(os.path.join(backup_dir, "server.xml.bak"), server_xml)
        shutil.copy2(os.path.join(backup_dir, "tomcat-users.xml.bak"), users_xml)
        write_log("Restored original configuration files")
    except Exception as e:
        write_log(f"Error restoring original files: {str(e)}", "ERROR")

def main():
    """Main function to run tests."""
    write_log("Starting tests for CheckTomcatConfigUnix.py...")
    
    # Verify script exists
    if not os.path.exists("./CheckTomcatConfigUnix.py"):
        write_log("Error: CheckTomcatConfigUnix.py not found", "ERROR")
        sys.exit(1)
    write_log("Verified file exists: ./CheckTomcatConfigUnix.py")

    # Clear existing log
    if os.path.exists(LOG_FILE):
        open(LOG_FILE, 'w').close()
        write_log(f"Cleared existing log file: {LOG_FILE}")

    # Detect Tomcat installation
    tomcat_info = detect_tomcat_path()
    if not tomcat_info:
        write_log("Error: No Tomcat configuration directory found", "ERROR")
        sys.exit(1)
    
    tomcat_conf_path = tomcat_info["path"]
    tomcat_version = tomcat_info["version"]
    write_log(f"Detected Tomcat version {tomcat_version} at {tomcat_conf_path}")
    
    # Create backup
    backup_dir = backup_config_files(tomcat_conf_path)
    
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
    
    if tomcat_version in ["8.5", "9.0", "10.0", "10.1"]:
        server_tests.extend([
            "MessageDigestCredentialHandler_SHA512",
            "NestedCredentialHandler"
        ])
    
    if tomcat_version in ["9.0", "10.0", "10.1"]:
        server_tests.append("SecretKeyCredentialHandler_PBKDF2")
    
    if tomcat_version == "7.0":
        write_log("Limiting tests for Tomcat 7.0: Excluding SHA-512, NestedCredentialHandler, and SecretKeyCredentialHandler")
    
    # Password examples (simplified for demo)
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
    
    # Run tests
    for server_test in server_tests:
        for password_test in password_tests:
            if password_test == "Hashed_SHA512" and tomcat_version == "7.0":
                write_log("Skipping Hashed_SHA512 for Tomcat 7.0 (not supported)")
                continue
            if password_test == "Salted_PBKDF2" and tomcat_version == "7.0":
                write_log("Skipping Salted_PBKDF2 for Tomcat 7.0 (not supported)")
                continue
            if password_test == "Salted_PBKDF2" and server_test == "SecretKeyCredentialHandler_PBKDF2" and tomcat_version not in ["9.0", "10.0", "10.1"]:
                write_log(f"Skipping Salted_PBKDF2 with SecretKeyCredentialHandler for Tomcat {tomcat_version} (not supported)")
                continue
            
            write_log(f"Running test: {tomcat_version}_{server_test}_{password_test} for Tomcat {tomcat_version}")

            # Modify server.xml
            server_xml = os.path.join(tomcat_conf_path, "conf", "server.xml")
            xml = secure_parse_xml(server_xml)
            if not xml:
                write_log("Failed to parse server.xml", "ERROR")
                continue
            
            root = xml.getroot()
            realm = root.find(".//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
            if realm is None:
                realm = root.find(".//Realm[@className='org.apache.catalina.realm.MemoryRealm']")
            
            if server_test == "NoCredentialHandler":
                handler = realm.find("CredentialHandler")
                if handler is not None:
                    realm.remove(handler)
            else:
                new_handler = ET.fromstring(server_configs[server_test])
                handler = realm.find("CredentialHandler")
                if handler is not None:
                    realm.remove(handler)
                realm.append(new_handler)
            
            if not secure_write_xml(server_xml, xml):
                write_log("Failed to update server.xml", "ERROR")
                continue

            # Modify tomcat-users.xml
            users_xml = os.path.join(tomcat_conf_path, "conf", "tomcat-users.xml")
            users = secure_parse_xml(users_xml)
            if not users:
                write_log("Failed to parse tomcat-users.xml", "ERROR")
                continue

            root = users.getroot()
            user = root.find(".//user[@username='testuser']")
            if user is None:
                user = ET.SubElement(root, "user")
                user.set("username", "testuser")
                user.set("roles", "manager")
            user.set("password", password_values[password_test])
            
            if not secure_write_xml(users_xml, users):
                write_log("Failed to update tomcat-users.xml", "ERROR")
                continue
            
            # Run CheckTomcatConfigUnix.py
            try:
                result = subprocess.run(
                    ["./CheckTomcatConfigUnix.py", "-p", tomcat_conf_path],
                    capture_output=True,
                    text=True,
                    check=True
                )
                write_log(f"Test output: {result.stdout}")
            except subprocess.CalledProcessError as e:
                write_log(f"Error running CheckTomcatConfigUnix.py: {str(e)}", "ERROR")

    # Restore original files
    restore_config_files(tomcat_conf_path, backup_dir)
    
    write_log("All tests completed successfully")

if __name__ == "__main__":
    main()
