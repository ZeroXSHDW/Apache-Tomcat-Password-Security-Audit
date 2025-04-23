#!/usr/bin/env python3
# CheckTomcatConfigUnix.py
# Audit Apache Tomcat configuration for security compliance with NIST 800-53 IA-5 and CIS Tomcat Benchmark

import os
import sys
import xml.etree.ElementTree as ET
import re

# Log setup
log_file = "/tmp/TomcatManager.log"

def write_log(message, indent=0):
    """
    Write a log message with indentation to both file and console.
    indent: Number of indentation levels (each level is two spaces).
    """
    indent_spaces = "  " * indent
    log_message = f"{indent_spaces}{message}"
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

# Detect password type
def detect_password_type(password):
    """
    Determine the password type based on its format and length.
    Returns a tuple: (type, is_secure).
    """
    # Plaintext: No specific format, typically short and non-hex
    if not re.match(r"^[0-9a-fA-F:]+$", password):
        return "Plaintext", False
    
    # Check for salted format (hash:salt)
    if ":" in password:
        hash_part, salt = password.split(":", 1)
        # Salted_MD5: 32-char hex hash
        if len(hash_part) == 32 and re.match(r"^[0-9a-fA-F]{32}$", hash_part):
            return "Salted_MD5", False
        # Salted_PBKDF2: Typically longer hash, depends on handler
        if len(hash_part) >= 32 and re.match(r"^[0-9a-fA-F]+$", hash_part):
            return "Salted_PBKDF2", True
        return "Unknown", False
    
    # Unsalted hashes
    # Hashed_MD5: 32-char hex
    if len(password) == 32 and re.match(r"^[0-9a-fA-F]{32}$", password):
        return "Hashed_MD5", False
    # Hashed_SHA1: 40-char hex
    if len(password) == 40 and re.match(r"^[0-9a-fA-F]{40}$", password):
        return "Hashed_SHA1", False
    # Hashed_SHA256: 64-char hex
    if len(password) == 64 and re.match(r"^[0-9a-fA-F]{64}$", password):
        return "Hashed_SHA256", True
    # Hashed_SHA512: 128-char hex
    if len(password) == 128 and re.match(r"^[0-9a-fA-F]{128}$", password):
        return "Hashed_SHA512", True
    
    return "Unknown", False

# Audit server.xml
def audit_server_xml(server_xml_path):
    """
    Audit server.xml for CredentialHandler configuration.
    Returns: (credential_handler, algorithm, iterations, salt_length)
    """
    try:
        tree = ET.parse(server_xml_path)
        root = tree.getroot()
        realm = root.find(".//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
        if realm is None:
            realm = root.find(".//Realm[@className='org.apache.catalina.realm.MemoryRealm']")
        if realm is None:
            return "None", "None", 0, 0

        ch = realm.find("CredentialHandler")
        if ch is None:
            return "None", "None", 0, 0

        class_name = ch.get("className", "Unknown")
        algorithm = ch.get("algorithm", "None")
        iterations = int(ch.get("iterations", "0"))
        salt_length = int(ch.get("saltLength", "0"))
        return class_name, algorithm, iterations, salt_length
    except Exception as e:
        write_log(f"Error parsing {server_xml_path}: {str(e)}")
        return "None", "None", 0, 0

# Audit tomcat-users.xml
def audit_users_xml(users_xml_path, credential_handler, handler_algorithm, iterations, salt_length):
    """
    Audit tomcat-users.xml for user password security.
    Returns: List of audit results for each user.
    """
    results = []
    try:
        tree = ET.parse(users_xml_path)
        root = tree.getroot()
        for user in root.findall(".//user"):
            username = user.get("username", "Unknown")
            password = user.get("password", "")
            password_type, is_secure = detect_password_type(password)
            
            audit_result = {
                "username": username,
                "password_type": password_type,
                "is_secure": is_secure,
                "parameters": [],
                "status": "Non-compliant",
                "issues": []
            }

            # Parameter checks
            audit_result["parameters"].append(f"Password Type = {password_type} [{'PASS' if is_secure else 'FAIL'}]")
            audit_result["parameters"].append(f"CredentialHandler = {credential_handler} [{'PASS' if credential_handler != 'None' else 'FAIL'}]")
            audit_result["parameters"].append(f"Algorithm = {handler_algorithm} [{'PASS' if handler_algorithm in ['SHA-256', 'SHA-512', 'PBKDF2WithHmacSHA512'] else 'FAIL'}]")
            audit_result["parameters"].append(f"Iterations = {iterations} [{'PASS' if iterations >= 10000 else 'FAIL'}]")
            audit_result["parameters"].append(f"Salt Length = {salt_length} [{'PASS' if salt_length >= 16 else 'FAIL'}]")

            # Compliance checks
            if password_type == "Plaintext":
                audit_result["issues"].append("Plaintext passwords detected in tomcat-users.xml")
                audit_result["issues"].append("Recommendation: Use salted and iterated passwords (e.g., SHA-256 or PBKDF2)")
            elif password_type in ["Hashed_MD5", "Hashed_SHA1", "Salted_MD5"]:
                audit_result["issues"].append(f"Weak password hashing ({password_type}) detected")
                audit_result["issues"].append("Recommendation: Use SHA-256, SHA-512, or PBKDF2")
            elif password_type in ["Hashed_SHA256", "Hashed_SHA512"]:
                if credential_handler == "org.apache.catalina.realm.MessageDigestCredentialHandler" and handler_algorithm == password_type.split("_")[1] and iterations >= 10000 and salt_length >= 16:
                    audit_result["status"] = "Compliant"
                else:
                    audit_result["issues"].append(f"{password_type} passwords should use salt and iterations")
                    audit_result["issues"].append("Recommendation: Configure MessageDigestCredentialHandler with saltLength >= 16 and iterations >= 10000")
            elif password_type == "Salted_PBKDF2":
                if (credential_handler == "org.apache.catalina.realm.SecretKeyCredentialHandler" and 
                    handler_algorithm == "PBKDF2WithHmacSHA512" and 
                    iterations >= 10000 and 
                    salt_length >= 16):
                    audit_result["status"] = "Compliant"
                else:
                    audit_result["issues"].append("Salted_PBKDF2 requires SecretKeyCredentialHandler with PBKDF2")
                    audit_result["issues"].append("Recommendation: Configure SecretKeyCredentialHandler with PBKDF2, saltLength >= 16, iterations >= 10000")
            else:
                audit_result["issues"].append(f"Unknown password type detected: {password_type}")
                audit_result["issues"].append("Recommendation: Use a supported secure hashing algorithm")

            results.append(audit_result)
    except Exception as e:
        write_log(f"Error parsing {users_xml_path}: {str(e)}")
    return results

# Main audit function
def audit_tomcat_config():
    write_log("Checking Apache Tomcat configuration security...")

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
    write_log(f"Found Tomcat configuration at {conf_path}")

    tomcat_version = detect_tomcat_version(os.path.dirname(conf_path))
    write_log(f"Detected Tomcat version {tomcat_version} at {conf_path}")

    # Audit server.xml
    server_xml_path = os.path.join(conf_path, "server.xml")
    write_log(f"Auditing server.xml at {server_xml_path}")
    credential_handler, algorithm, iterations, salt_length = audit_server_xml(server_xml_path)

    # Audit tomcat-users.xml
    users_xml_path = os.path.join(conf_path, "tomcat-users.xml")
    write_log(f"Auditing tomcat-users.xml at {users_xml_path}")
    audit_results = audit_users_xml(users_xml_path, credential_handler, algorithm, iterations, salt_length)

    # Process audit results
    overall_secure = True
    for result in audit_results:
        write_log(f"- User '{result['username']}': {result['password_type']} password ({'secure' if result['is_secure'] else 'insecure'})", indent=1)
        for param in result["parameters"]:
            write_log(param, indent=2, marker="- ")
        write_log(f"- Status: {result['status']} with NIST 800-53 IA-5 and CIS Tomcat Benchmark", indent=2)
        for issue in result["issues"]:
            write_log(issue, indent=3, marker="- ")
        if result["status"] == "Non-compliant":
            overall_secure = False

    # Overall status
    write_log(f"Overall Configuration: {'Secure' if overall_secure else 'Insecure'}")
    write_log("Audit completed")

if __name__ == "__main__":
    audit_tomcat_config()
