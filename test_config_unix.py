#!/usr/bin/env python3
import os
import shutil
import subprocess
import xml.etree.ElementTree as ET
import logging
from pathlib import Path
from datetime import datetime

# Setup logging
log_file = Path.home() / "TestTomcatConfig.log"
logging.basicConfig(
    filename=log_file,
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger(__name__)

# Tomcat configuration paths
TOMCAT_CONF_DIR = "/opt/tomcat/conf"
SERVER_XML = os.path.join(TOMCAT_CONF_DIR, "server.xml")
TOMCAT_USERS_XML = os.path.join(TOMCAT_CONF_DIR, "tomcat-users.xml")
BACKUP_DIR = "/tmp/TomcatConfigBackup"

# Test configurations for Tomcat 7.0
TEST_CONFIGS_7_0 = [
    {
        "name": "NoCredentialHandler_Plaintext",
        "server_xml": {"credential_handler": None},
        "tomcat_users_xml": {"username": "testuser", "password": "s3cret", "roles": "manager"},
        "expected": {
            "password_type": "Plaintext",
            "secure": False,
            "output": [
                "User 'testuser': Plaintext password (insecure)",
                "Parameter: Password Type = Plaintext [FAIL]",
                "Parameter: CredentialHandler = None [FAIL]",
                "Non-compliant with NIST_800_53_IA_5",
                "Non-compliant with CIS_Tomcat_Benchmark",
                "Plaintext passwords detected"
            ]
        }
    },
    {
        "name": "MessageDigest_MD5",
        "server_xml": {
            "credential_handler": {
                "className": "org.apache.catalina.realm.MessageDigestCredentialHandler",
                "algorithm": "MD5"
            }
        },
        "tomcat_users_xml": {"username": "testuser", "password": "d41d8cd98f00b204e9800998ecf8427e", "roles": "manager"},
        "expected": {
            "password_type": "Hashed_MD5",
            "secure": False,
            "output": [
                "User 'testuser': Hashed_MD5 password (insecure)",
                "Parameter: Password Type = Hashed_MD5 [FAIL]",
                "Parameter: CredentialHandler = org.apache.catalina.realm.MessageDigestCredentialHandler [PASS]",
                "Parameter: Algorithm = MD5 [FAIL]",
                "Non-compliant with NIST_800_53_IA_5",
                "Non-compliant with CIS_Tomcat_Benchmark"
            ]
        }
    },
    {
        "name": "MessageDigest_SHA1",
        "server_xml": {
            "credential_handler": {
                "className": "org.apache.catalina.realm.MessageDigestCredentialHandler",
                "algorithm": "SHA-1"
            }
        },
        "tomcat_users_xml": {"username": "testuser", "password": "da39a3ee5e6b4b0d3255bfef95601890afd80709", "roles": "manager"},
        "expected": {
            "password_type": "Hashed_SHA1",
            "secure": False,
            "output": [
                "User 'testuser': Hashed_SHA1 password (insecure)",
                "Parameter: Password Type = Hashed_SHA1 [FAIL]",
                "Parameter: CredentialHandler = org.apache.catalina.realm.MessageDigestCredentialHandler [PASS]",
                "Parameter: Algorithm = SHA-1 [FAIL]",
                "Non-compliant with NIST_800_53_IA_5",
                "Non-compliant with CIS_Tomcat_Benchmark"
            ]
        }
    },
    {
        "name": "MessageDigest_SHA256",
        "server_xml": {
            "credential_handler": {
                "className": "org.apache.catalina.realm.MessageDigestCredentialHandler",
                "algorithm": "SHA-256"
            }
        },
        "tomcat_users_xml": {"username": "testuser", "password": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "roles": "manager"},
        "expected": {
            "password_type": "Hashed_SHA256",
            "secure": True,
            "output": [
                "User 'testuser': Hashed_SHA256 password (secure)",
                "Parameter: Password Type = Hashed_SHA256 [PASS]",
                "Parameter: CredentialHandler = org.apache.catalina.realm.MessageDigestCredentialHandler [PASS]",
                "Parameter: Algorithm = SHA-256 [PASS]",
                "Compliant with NIST_800_53_IA_5",
                "Compliant with CIS_Tomcat_Benchmark"
            ]
        }
    },
    {
        "name": "NoCredentialHandler_Salted_MD5",
        "server_xml": {"credential_handler": None},
        "tomcat_users_xml": {"username": "testuser", "password": "d41d8cd98f00b204e9800998ecf8427e:1234567890abcdef", "roles": "manager"},
        "expected": {
            "password_type": "Salted_MD5",
            "secure": False,
            "output": [
                "User 'testuser': Salted_MD5 password (insecure)",
                "Parameter: Password Type = Salted_MD5 [FAIL]",
                "Parameter: CredentialHandler = None [FAIL]",
                "Non-compliant with NIST_800_53_IA_5",
                "Non-compliant with CIS_Tomcat_Benchmark"
            ]
        }
    }
]

def setup_backup():
    """Create backup directory and copy original configuration files."""
    os.makedirs(BACKUP_DIR, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_server = os.path.join(BACKUP_DIR, f"server_{timestamp}.xml")
    backup_users = os.path.join(BACKUP_DIR, f"tomcat-users_{timestamp}.xml")
    try:
        shutil.copy2(SERVER_XML, backup_server)
        shutil.copy2(TOMCAT_USERS_XML, backup_users)
        logger.info(f"Backed up configuration files to {BACKUP_DIR}")
        print(f"Backed up original files to {BACKUP_DIR}")
        return backup_server, backup_users
    except (FileNotFoundError, PermissionError) as e:
        logger.error(f"Backup failed: {e}")
        print(f"ERROR: Failed to backup configuration files: {e}")
        sys.exit(1)

def restore_config(backup_server, backup_users):
    """Restore original configuration files from backup."""
    try:
        shutil.copy2(backup_server, SERVER_XML)
        shutil.copy2(backup_users, TOMCAT_USERS_XML)
        logger.info("Restored original configuration files")
        print("Restored original configuration files")
    except (FileNotFoundError, PermissionError) as e:
        logger.error(f"Restore failed: {e}")
        print(f"ERROR: Failed to restore configuration files: {e}")
        sys.exit(1)

def modify_server_xml(config):
    """Modify server.xml with specified CredentialHandler."""
    try:
        tree = ET.parse(SERVER_XML)
        root = tree.getroot()
        realm = root.find(".//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
        if realm is None:
            logger.error("No UserDatabaseRealm found in server.xml")
            print("ERROR: No UserDatabaseRealm found in server.xml")
            sys.exit(1)

        # Remove existing CredentialHandler
        for handler in realm.findall("CredentialHandler"):
            realm.remove(handler)

        # Add new CredentialHandler if specified
        if config["server_xml"]["credential_handler"]:
            handler = ET.SubElement(realm, "CredentialHandler")
            for key, value in config["server_xml"]["credential_handler"].items():
                handler.set(key, value)
            logger.info(f"Modified server.xml: Added CredentialHandler {config['server_xml']['credential_handler']}")
            print(f"Modified server.xml: Added CredentialHandler {config['server_xml']['credential_handler']}")
        else:
            logger.info("Modified server.xml: Removed all CredentialHandlers")
            print("Modified server.xml: Removed all CredentialHandlers")

        tree.write(SERVER_XML)
    except (FileNotFoundError, ET.ParseError, PermissionError) as e:
        logger.error(f"Failed to modify server.xml: {e}")
        print(f"ERROR: Failed to modify server.xml: {e}")
        sys.exit(1)

def modify_tomcat_users_xml(config):
    """Modify tomcat-users.xml with specified user and password."""
    try:
        tree = ET.parse(TOMCAT_USERS_XML)
        root = tree.getroot()
        # Clear existing users
        for user in root.findall("user"):
            root.remove(user)
        # Add test user
        user = ET.SubElement(root, "user")
        user.set("username", config["tomcat_users_xml"]["username"])
        user.set("password", config["tomcat_users_xml"]["password"])
        user.set("roles", config["tomcat_users_xml"]["roles"])
        logger.info(f"Modified tomcat-users.xml: Added user {config['tomcat_users_xml']['username']} with password {config['tomcat_users_xml']['password']}")
        print(f"Modified tomcat-users.xml: Set password for {config['tomcat_users_xml']['username']}")
        tree.write(TOMCAT_USERS_XML)
    except (FileNotFoundError, ET.ParseError, PermissionError) as e:
        logger.error(f"Failed to modify tomcat-users.xml: {e}")
        print(f"ERROR: Failed to modify tomcat-users.xml: {e}")
        sys.exit(1)

def run_check_script():
    """Run CheckTomcatConfigUnix.py and capture output."""
    try:
        result = subprocess.run(
            ["./CheckTomcatConfigUnix.py"],
            capture_output=True,
            text=True,
            check=True
        )
        logger.info("Ran CheckTomcatConfigUnix.py successfully")
        return result.stdout.splitlines()
    except subprocess.CalledProcessError as e:
        logger.error(f"CheckTomcatConfigUnix.py failed: {e.stderr}")
        print(f"ERROR: CheckTomcatConfigUnix.py failed: {e.stderr}")
        sys.exit(1)

def verify_test_output(test_config, actual_output):
    """Verify that actual output matches expected output."""
    expected = test_config["expected"]["output"]
    passed = True
    for expected_line in expected:
        if not any(expected_line in line for line in actual_output):
            logger.warning(f"Test {test_config['name']}: Expected line not found: {expected_line}")
            print(f"      Expected line not found: {expected_line}")
            passed = False
    return passed

def main():
    """Main function to run tests."""
    print("Starting tests for CheckTomcatConfigUnix.py...")
    logger.info("Starting tests for CheckTomcatConfigUnix.py")

    # Verify CheckTomcatConfigUnix.py exists
    if not os.path.exists("./CheckTomcatConfigUnix.py"):
        logger.error("CheckTomcatConfigUnix.py not found in current directory")
        print("ERROR: CheckTomcatConfigUnix.py not found in current directory")
        sys.exit(1)
    print("Verified file exists: ./CheckTomcatConfigUnix.py")

    # Clear existing log file
    if os.path.exists(log_file):
        os.remove(log_file)
        print(f"Cleared existing log file: {log_file}")
        logger.info(f"Cleared existing log file: {log_file}")

    # Verify Tomcat configuration directory
    if not os.path.exists(TOMCAT_CONF_DIR):
        logger.error(f"Tomcat configuration directory {TOMCAT_CONF_DIR} not found")
        print(f"ERROR: Tomcat configuration directory {TOMCAT_CONF_DIR} not found")
        sys.exit(1)
    print(f"Found Tomcat at {TOMCAT_CONF_DIR}, version: Unknown")

    # Backup original configuration
    backup_server, backup_users = setup_backup()

    try:
        total_tests = len(TEST_CONFIGS_7_0)
        passed_tests = 0

        for test_config in TEST_CONFIGS_7_0:
            print(f"  Test: {test_config['name']}")
            logger.info(f"Running test: {test_config['name']}")
            print(f"    Description: Testing {test_config['expected']['password_type']} password with {test_config['name'].split('_')[0]} CredentialHandler")

            # Modify configuration files
            modify_server_xml(test_config)
            modify_tomcat_users_xml(test_config)

            # Run check script
            actual_output = run_check_script()

            # Verify output
            print("    Expected output:")
            for line in test_config["expected"]["output"]:
                print(f"      - {line}")
            print("    Actual output:")
            for line in actual_output:
                print(f"      - {line.strip()}")

            if verify_test_output(test_config, actual_output):
                print("    Result: PASSED")
                passed_tests += 1
            else:
                print("    Result: FAILED")
            logger.info(f"Test {test_config['name']}: {'PASSED' if verify_test_output(test_config, actual_output) else 'FAILED'}")

        # Print test summary
        print("Test Summary:")
        print(f"  Total tests run: {total_tests}")
        print(f"  Tests passed: {passed_tests}")
        print(f"  Tests failed: {total_tests - passed_tests}")
        logger.info(f"Test Summary: Total={total_tests}, Passed={passed_tests}, Failed={total_tests - passed_tests}")

    finally:
        # Restore original configuration
        restore_config(backup_server, backup_users)

    print("All tests completed")
    logger.info("All tests completed")

if __name__ == "__main__":
    main()
