#!/usr/bin/env python3
# test_config_unix.py
# Automated testing for CheckTomcatConfigUnix.py across Tomcat 7.0, 8.5, 9.0, 10.0, and 10.1

import os
import sys
import shutil
import subprocess
import xml.etree.ElementTree as ET
import re

# Log setup
log_file = os.path.expanduser("~/TestTomcatConfig.log")
backup_dir = "/tmp/TomcatConfigBackup"

def write_log(message, indent=0, marker=""):
    """
    Write a log message with indentation and marker, without timestamps.
    indent: Number of indentation levels (each level is two spaces).
    marker: Prefix marker (e.g., '-', '  -', '    -') for specific lines.
    """
    indent_spaces = "  " * indent
    log_message = f"{indent_spaces}{marker}{message}"
    try:
        with open(log_file, "a") as f:
            f.write(log_message + "\n")
    except PermissionError:
        print(f"Warning: Cannot write to {log_file}. Logging to console only.", file=sys.stderr)
    print(log_message)

# Function to detect Tomcat path
def get_tomcat_config_path():
    catalina_home = os.getenv("CATALINA_HOME")
    if catalina_home:
        conf_path = os.path.join(catalina_home, "conf")
        if os.path.exists(conf_path) and os.path.exists(os.path.join(conf_path, "server.xml")):
            return conf_path
    possible_paths = [
        "/opt/tomcat/conf",
        "/usr/local/tomcat/conf",
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

# Detect Tomcat version
def detect_tomcat_version(tomcat_home):
    version_file = os.path.join(tomcat_home, "RELEASE-NOTES")
    if os.path.exists(version_file):
        try:
            with open(version_file, "r") as f:
                content = f.read()
                match = re.search(r"Apache Tomcat Version\s+([0-9]+\.[0-9]+\.[0-9]+)", content)
                if match:
                    version = match.group(1)
                    if version.startswith("7.0"): return "7.0"
                    elif version.startswith("8.5"): return "8.5"
                    elif version.startswith("9.0"): return "9.0"
                    elif version.startswith("10.0"): return "10.0"
                    elif version.startswith("10.1"): return "10.1"
        except Exception as e:
            write_log(f"Error reading {version_file}: {str(e)}")
    # Check directory name
    if "tomcat7" in tomcat_home.lower(): return "7.0"
    if "tomcat8" in tomcat_home.lower(): return "8.5"
    if "tomcat9" in tomcat_home.lower(): return "9.0"
    if "tomcat10" in tomcat_home.lower(): return "10.0"
    # Check server.xml for version clues
    server_xml = os.path.join(tomcat_home, "conf/server.xml")
    if os.path.exists(server_xml):
        try:
            with open(server_xml, "r") as f:
                content = f.read()
                if "org.apache.catalina.startup.VersionLoggerListener" in content:
                    if "tomcat10" in tomcat_home.lower() or "10." in content: return "10.0"
                    elif "9." in content: return "9.0"
                    elif "8." in content: return "8.5"
                    elif "7." in content: return "7.0"
        except Exception as e:
            write_log(f"Error reading {server_xml}: {str(e)}")
    write_log(f"Warning: Could not determine Tomcat version at {tomcat_home}, defaulting to 7.0")
    return "7.0"

# Backup configuration files
def backup_configs(conf_path):
    os.makedirs(backup_dir, exist_ok=True)
    for file in ["server.xml", "tomcat-users.xml"]:
        src = os.path.join(conf_path, file)
        dst = os.path.join(backup_dir, file)
        if os.path.exists(src):
            shutil.copy2(src, dst)
        else:
            write_log(f"Warning: {src} not found for backup")

# Restore configuration files
def restore_configs(conf_path):
    for file in ["server.xml", "tomcat-users.xml"]:
        src = os.path.join(backup_dir, file)
        dst = os.path.join(conf_path, file)
        if os.path.exists(src):
            shutil.copy2(src, dst)
        else:
            write_log(f"Warning: {src} not found for restore")

# Modify server.xml
def modify_server_xml(conf_path, handler_config):
    server_xml = os.path.join(conf_path, "server.xml")
    try:
        tree = ET.parse(server_xml)
        root = tree.getroot()
        realm = root.find(".//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
        if realm is None:
            realm = root.find(".//Realm[@className='org.apache.catalina.realm.MemoryRealm']")
        if realm is None:
            write_log(f"Error: No UserDatabaseRealm or MemoryRealm found in {server_xml}")
            return False

        # Remove existing CredentialHandler
        for ch in realm.findall("CredentialHandler"):
            realm.remove(ch)

        # Add new CredentialHandler if specified
        if handler_config:
            ch = ET.SubElement(realm, "CredentialHandler")
            for key, value in handler_config.items():
                ch.set(key, value)

        tree.write(server_xml, encoding="UTF-8", xml_declaration=True)
        write_log(f"Modified server.xml: {handler_config}")
        return True
    except Exception as e:
        write_log(f"Error modifying server.xml: {str(e)}")
        return False

# Modify tomcat-users.xml
def modify_users_xml(conf_path, password, password_type):
    users_xml = os.path.join(conf_path, "tomcat-users.xml")
    try:
        tree = ET.parse(users_xml)
        root = tree.getroot()
        # Clear existing users
        for user in root.findall(".//user"):
            root.remove(user)
        # Add test user
        user = ET.SubElement(root, "user")
        user.set("username", "testuser")
        user.set("password", password)
        user.set("roles", "manager")
        tree.write(users_xml, encoding="UTF-8", xml_declaration=True)
        write_log(f"Modified tomcat-users.xml: Set password for testuser to {password_type} ({password})")
        return True
    except Exception as e:
        write_log(f"Error modifying tomcat-users.xml: {str(e)}")
        return False

# Run CheckTomcatConfigUnix.py and capture output
def run_check_script():
    try:
        result = subprocess.run(["python3", "CheckTomcatConfigUnix.py"], capture_output=True, text=True)
        return result.stdout.strip()
    except Exception as e:
        write_log(f"Error running CheckTomcatConfigUnix.py: {str(e)}")
        return ""

# Define test cases
TEST_CASES = {
    "7.0": {
        "server_configs": [
            {"name": "NoCredentialHandler", "config": None},
            {"name": "MessageDigest_MD5", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "MD5"}},
            {"name": "MessageDigest_SHA1", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "SHA-1"}},
            {"name": "MessageDigest_SHA256", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "SHA-256", "iterations": "10000", "saltLength": "16"}},
            {"name": "MessageDigest_SHA512", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "SHA-512", "iterations": "10000", "saltLength": "16"}},
            {"name": "NestedCredentialHandler", "config": {"className": "org.apache.catalina.realm.NestedCredentialHandler"}}
        ],
        "passwords": [
            {"type": "Plaintext", "value": "s3cret"},
            {"type": "Hashed_MD5", "value": "5ebe2294ecd0e0f08eab7690d2a6ee69"},
            {"type": "Hashed_SHA1", "value": "e5e9fa1ba31ecd1ae84f75caaa474f3a663f05f4"},
            {"type": "Hashed_SHA256", "value": "2bb80d537b1da3e38bd30361aa855686bde0eacd7162fef6a25fe97bf527a25b"},
            {"type": "Hashed_SHA512", "value": "ee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db27ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff"},
            {"type": "Salted_MD5", "value": "5ebe2294ecd0e0f08eab7690d2a6ee69:1234567890abcdef"},
            {"type": "Salted_PBKDF2", "value": "4b6f7e8c9d0a1b2c3d4e5f60718293a4:1234567890abcdef"}
        ]
    },
    "8.5": {
        "server_configs": [
            {"name": "NoCredentialHandler", "config": None},
            {"name": "MessageDigest_MD5", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "MD5"}},
            {"name": "MessageDigest_SHA1", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "SHA-1"}},
            {"name": "MessageDigest_SHA256", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "SHA-256", "iterations": "10000", "saltLength": "16"}},
            {"name": "MessageDigest_SHA512", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "SHA-512", "iterations": "10000", "saltLength": "16"}},
            {"name": "NestedCredentialHandler", "config": {"className": "org.apache.catalina.realm.NestedCredentialHandler"}}
        ],
        "passwords": [
            {"type": "Plaintext", "value": "s3cret"},
            {"type": "Hashed_MD5", "value": "5ebe2294ecd0e0f08eab7690d2a6ee69"},
            {"type": "Hashed_SHA1", "value": "e5e9fa1ba31ecd1ae84f75caaa474f3a663f05f4"},
            {"type": "Hashed_SHA256", "value": "2bb80d537b1da3e38bd30361aa855686bde0eacd7162fef6a25fe97bf527a25b"},
            {"type": "Hashed_SHA512", "value": "ee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db27ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff"},
            {"type": "Salted_MD5", "value": "5ebe2294ecd0e0f08eab7690d2a6ee69:1234567890abcdef"},
            {"type": "Salted_PBKDF2", "value": "4b6f7e8c9d0a1b2c3d4e5f60718293a4:1234567890abcdef"}
        ]
    },
    "9.0": {
        "server_configs": [
            {"name": "NoCredentialHandler", "config": None},
            {"name": "MessageDigest_MD5", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "MD5"}},
            {"name": "MessageDigest_SHA256", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "SHA-256", "iterations": "10000", "saltLength": "16"}},
            {"name": "MessageDigest_SHA512", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "SHA-512", "iterations": "10000", "saltLength": "16"}},
            {"name": "NestedCredentialHandler", "config": {"className": "org.apache.catalina.realm.NestedCredentialHandler"}},
            {"name": "SecretKey_PBKDF2", "config": {"className": "org.apache.catalina.realm.SecretKeyCredentialHandler", "algorithm": "PBKDF2WithHmacSHA512", "iterations": "10000", "saltLength": "16", "keyLength": "256"}}
        ],
        "passwords": [
            {"type": "Plaintext", "value": "s3cret"},
            {"type": "Hashed_MD5", "value": "5ebe2294ecd0e0f08eab7690d2a6ee69"},
            {"type": "Hashed_SHA1", "value": "e5e9fa1ba31ecd1ae84f75caaa474f3a663f05f4"},
            {"type": "Hashed_SHA256", "value": "2bb80d537b1da3e38bd30361aa855686bde0eacd7162fef6a25fe97bf527a25b"},
            {"type": "Hashed_SHA512", "value": "ee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db27ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff"},
            {"type": "Salted_MD5", "value": "5ebe2294ecd0e0f08eab7690d2a6ee69:1234567890abcdef"},
            {"type": "Salted_PBKDF2", "value": "4b6f7e8c9d0a1b2c3d4e5f60718293a4:1234567890abcdef"}
        ]
    },
    "10.0": {
        "server_configs": [
            {"name": "NoCredentialHandler", "config": None},
            {"name": "MessageDigest_MD5", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "MD5"}},
            {"name": "MessageDigest_SHA256", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "SHA-256", "iterations": "10000", "saltLength": "16"}},
            {"name": "MessageDigest_SHA512", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "SHA-512", "iterations": "10000", "saltLength": "16"}},
            {"name": "NestedCredentialHandler", "config": {"className": "org.apache.catalina.realm.NestedCredentialHandler"}},
            {"name": "SecretKey_PBKDF2", "config": {"className": "org.apache.catalina.realm.SecretKeyCredentialHandler", "algorithm": "PBKDF2WithHmacSHA512", "iterations": "10000", "saltLength": "16", "keyLength": "256"}}
        ],
        "passwords": [
            {"type": "Plaintext", "value": "s3cret"},
            {"type": "Hashed_MD5", "value": "5ebe2294ecd0e0f08eab7690d2a6ee69"},
            {"type": "Hashed_SHA1", "value": "e5e9fa1ba31ecd1ae84f75caaa474f3a663f05f4"},
            {"type": "Hashed_SHA256", "value": "2bb80d537b1da3e38bd30361aa855686bde0eacd7162fef6a25fe97bf527a25b"},
            {"type": "Hashed_SHA512", "value": "ee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db27ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff"},
            {"type": "Salted_MD5", "value": "5ebe2294ecd0e0f08eab7690d2a6ee69:1234567890abcdef"},
            {"type": "Salted_PBKDF2", "value": "4b6f7e8c9d0a1b2c3d4e5f60718293a4:1234567890abcdef"}
        ]
    },
    "10.1": {
        "server_configs": [
            {"name": "NoCredentialHandler", "config": None},
            {"name": "MessageDigest_MD5", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "MD5"}},
            {"name": "MessageDigest_SHA256", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "SHA-256", "iterations": "10000", "saltLength": "16"}},
            {"name": "MessageDigest_SHA512", "config": {"className": "org.apache.catalina.realm.MessageDigestCredentialHandler", "algorithm": "SHA-512", "iterations": "10000", "saltLength": "16"}},
            {"name": "NestedCredentialHandler", "config": {"className": "org.apache.catalina.realm.NestedCredentialHandler"}},
            {"name": "SecretKey_PBKDF2", "config": {"className": "org.apache.catalina.realm SecretKeyCredentialHandler", "algorithm": "PBKDF2WithHmacSHA512", "iterations": "10000", "saltLength": "16", "keyLength": "256"}}
        ],
        "passwords": [
            {"type": "Plaintext", "value": "s3cret"},
            {"type": "Hashed_MD5", "value": "5ebe2294ecd0e0f08eab7690d2a6ee69"},
            {"type": "Hashed_SHA1", "value": "e5e9fa1ba31ecd1ae84f75caaa474f3a663f05f4"},
            {"type": "Hashed_SHA256", "value": "2bb80d537b1da3e38bd30361aa855686bde0eacd7162fef6a25fe97bf527a25b"},
            {"type": "Hashed_SHA512", "value": "ee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db27ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff"},
            {"type": "Salted_MD5", "value": "5ebe2294ecd0e0f08eab7690d2a6ee69:1234567890abcdef"},
            {"type": "Salted_PBKDF2", "value": "4b6f7e8c9d0a1b2c3d4e5f60718293a4:1234567890abcdef"}
        ]
    }
}

# Expected output patterns
EXPECTED_OUTPUTS = {
    "Plaintext": {
        "pattern": r"User 'testuser': Plaintext password \(insecure\).*Parameter: Password Type = Plaintext \[FAIL\].*Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark.*Plaintext passwords detected",
        "pass": False
    },
    "Hashed_MD5": {
        "pattern": r"User 'testuser': Hashed_MD5 password \(insecure\).*Parameter: Password Type = Hashed_MD5 \[FAIL\].*Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark.*Weak password hashing \(Hashed_MD5\)",
        "pass": False
    },
    "Hashed_SHA1": {
        "pattern": r"User 'testuser': Hashed_SHA1 password \(insecure\).*Parameter: Password Type = Hashed_SHA1 \[FAIL\].*Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark.*Weak password hashing \(SHA-1\)",
        "pass": False
    },
    "Hashed_SHA256": {
        "default": {
            "pattern": r"User 'testuser': Hashed_SHA256 password \(secure\).*Parameter: Password Type = Hashed_SHA256 \[PASS\].*Parameter: Algorithm = SHA-256 \[PASS\].*Parameter: Iterations = 10000 \[PASS\].*Parameter: Salt Length = 16 \[PASS\].*Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark",
            "pass": True
        },
        "non_compliant": {
            "pattern": r"User 'testuser': Hashed_SHA256 password \(secure\).*Parameter: Password Type = Hashed_SHA256 \[PASS\].*Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark.*Hashed_SHA256 passwords should use salt and iterations",
            "pass": False
        }
    },
    "Hashed_SHA512": {
        "default": {
            "pattern": r"User 'testuser': Hashed_SHA512 password \(secure\).*Parameter: Password Type = Hashed_SHA512 \[PASS\].*Parameter: Algorithm = SHA-512 \[PASS\].*Parameter: Iterations = 10000 \[PASS\].*Parameter: Salt Length = 16 \[PASS\].*Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark",
            "pass": True
        },
        "non_compliant": {
            "pattern": r"User 'testuser': Hashed_SHA512 password \(secure\).*Parameter: Password Type = Hashed_SHA512 \[PASS\].*Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark.*Hashed_SHA512 passwords should use salt and iterations",
            "pass": False
        }
    },
    "Salted_MD5": {
        "pattern": r"User 'testuser': Salted_MD5 password \(insecure\).*Parameter: Password Type = Salted_MD5 \[FAIL\].*Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark.*Weak password hashing \(Salted_MD5\)",
        "pass": False
    },
    "Salted_PBKDF2": {
        "9.0_10.0_10.1": {
            "pattern": r"User 'testuser': Salted_PBKDF2 password \(secure\).*Parameter: Password Type = Salted_PBKDF2 \[PASS\].*Parameter: CredentialHandler = org.apache.catalina.realm.SecretKeyCredentialHandler \[PASS\].*Parameter: Algorithm = PBKDF2WithHmacSHA512 \[PASS\].*Parameter: Iterations = 10000 \[PASS\].*Parameter: Salt Length = 16 \[PASS\].*Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark",
            "pass": True
        },
        "non_compliant": {
            "pattern": r"User 'testuser': Salted_PBKDF2 password \(secure\).*Parameter: Password Type = Salted_PBKDF2 \[PASS\].*Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark.*Salted_PBKDF2 requires SecretKeyCredentialHandler with PBKDF2",
            "pass": False
        }
    }
}

# Main testing logic
def run_tests():
    write_log("Starting tests for CheckTomcatConfigUnix.py...")
    
    # Verify CheckTomcatConfigUnix.py exists
    if not os.path.exists("CheckTomcatConfigUnix.py"):
        write_log("Error: CheckTomcatConfigUnix.py not found in current directory")
        sys.exit(1)
    write_log("Verified file exists: ./CheckTomcatConfigUnix.py")

    # Clear log file
    try:
        open(log_file, "w").close()
    except PermissionError:
        write_log(f"Warning: Cannot clear {log_file}. Continuing with existing log.")

    # Find Tomcat configuration
    conf_path = get_tomcat_config_path()
    if not conf_path:
        write_log("Error: No Tomcat configuration directory found")
        sys.exit(1)
    tomcat_version = detect_tomcat_version(os.path.dirname(conf_path))
    write_log(f"Found Tomcat at {conf_path}, version: {tomcat_version}")

    # Handle unknown version
    if tomcat_version == "Unknown":
        write_log("Warning: Could not determine Tomcat version. Defaulting to 7.0 for testing.")
        tomcat_version = "7.0"

    # Backup original files
    write_log(f"Backed up original files to {backup_dir}")
    backup_configs(conf_path)

    total_tests = 0
    passed_tests = 0

    # Run tests for the detected version
    if tomcat_version not in TEST_CASES:
        write_log(f"Error: Unsupported Tomcat version {tomcat_version}. Supported versions: 7.0, 8.5, 9.0, 10.0, 10.1")
        sys.exit(1)

    for server_config in TEST_CASES[tomcat_version]["server_configs"]:
        for password in TEST_CASES[tomcat_version]["passwords"]:
            test_name = f"{tomcat_version}_{server_config['name']}_{password['type']}"
            total_tests += 1

            write_log(f"Test: {test_name}", indent=1)
            write_log(f"Description: Testing {password['type']} password with {server_config['name']} CredentialHandler", indent=2)

            # Modify server.xml
            if not modify_server_xml(conf_path, server_config["config"]):
                write_log("Result: SKIPPED (failed to modify server.xml)", indent=2)
                continue

            # Modify tomcat-users.xml
            if not modify_users_xml(conf_path, password["value"], password["type"]):
                write_log("Result: SKIPPED (failed to modify tomcat-users.xml)", indent=2)
                continue

            # Run check script
            output = run_check_script()
            write_log("Actual output:", indent=2)
            write_log(output, indent=3)

            # Determine expected output
            expected = EXPECTED_OUTPUTS[password["type"]]
            if password["type"] in ["Hashed_SHA256", "Hashed_SHA512"]:
                expected_pattern = expected["default"]["pattern"] if server_config["name"] in ["MessageDigest_SHA256", "MessageDigest_SHA512"] and tomcat_version not in ["7.0", "8.5"] else expected["non_compliant"]["pattern"]
                expected_pass = server_config["name"] in ["MessageDigest_SHA256", "MessageDigest_SHA512"] and tomcat_version not in ["7.0", "8.5"]
            elif password["type"] == "Salted_PBKDF2":
                expected_pattern = expected["9.0_10.0_10.1"]["pattern"] if server_config["name"] == "SecretKey_PBKDF2" and tomcat_version in ["9.0", "10.0", "10.1"] else expected["non_compliant"]["pattern"]
                expected_pass = server_config["name"] == "SecretKey_PBKDF2" and tomcat_version in ["9.0", "10.0", "10.1"]
            else:
                expected_pattern = expected["pattern"]
                expected_pass = expected["pass"]

            # Check result
            if re.search(expected_pattern, output, re.DOTALL):
                write_log("Result: PASSED", indent=2)
                passed_tests += 1 if expected_pass else 0
            else:
                write_log("Result: FAILED (output does not match expected pattern)", indent=2)

    # Restore original configuration
    write_log("Restored original configuration files")
    restore_configs(conf_path)

    # Summarize results
    write_log("Test Summary:", indent=1)
    write_log(f"Total tests run: {total_tests}", indent=2)
    write_log(f"Tests passed: {passed_tests}", indent=2)
    write_log(f"Tests failed: {total_tests - passed_tests}", indent=2)
    write_log("All tests completed")

if __name__ == "__main__":
    run_tests()
