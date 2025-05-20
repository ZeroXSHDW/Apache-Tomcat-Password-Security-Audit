#!/usr/bin/env python3
# CheckTomcatConfigUnix.py
# Audit Apache Tomcat configuration for security compliance with NIST 800-53 IA-5 and CIS Tomcat Benchmark

import os
import sys
import xml.etree.ElementTree as ET
import re
import datetime
import socket

# Log setup
LOG_FILE = "/tmp/TomcatManager.log"

def write_log(message, indent=0):
    """
    Write a log message with indentation to both file and console.
    indent: Number of indentation levels (each level is two spaces).
    """
    indent_spaces = "  " * indent
    log_message = f"{indent_spaces}{message}"
    try:
        with open(LOG_FILE, "a") as f:
            f.write(log_message + "\n")
    except PermissionError:
        print(f"Warning: Cannot write to {LOG_FILE}. Logging to console only.", file=sys.stderr)
    print(log_message)

# Function to detect Tomcat path
def get_tomcat_config_path():
    catalina_home = os.getenv("CATALINA_HOME")
    if catalina_home:
        conf_path = os.path.join(catalina_home, "conf")
        if os.path.isdir(conf_path) and os.path.isfile(os.path.join(conf_path, "server.xml")):
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
        if os.path.isdir(path) and os.path.isfile(os.path.join(path, "server.xml")):
            return path
    return None

# Detect Tomcat version
def detect_tomcat_version(tomcat_home):
    version_file = os.path.join(tomcat_home, "RELEASE-NOTES")
    version = "7.0"  # Default fallback
    if os.path.isfile(version_file):
        try:
            with open(version_file, "r") as f:
                content = f.read()
                match = re.search(r"Apache Tomcat Version\s+([0-9]+\.[0-9]+\.[0-9]+)", content)
                if match:
                    full_version = match.group(1)
                    if full_version.startswith("7.0"): return "7.0"
                    elif full_version.startswith("8.5"): return "8.5"
                    elif full_version.startswith("9.0"): return "9.0"
                    elif full_version.startswith("10.0"): return "10.0"
                    elif full_version.startswith("10.1"): return "10.1"
        except Exception as e:
            write_log(f"Error reading {version_file}: {str(e)}")
    tomcat_home_lower = tomcat_home.lower()
    if "tomcat7" in tomcat_home_lower: return "7.0"
    elif "tomcat8" in tomcat_home_lower: return "8.5"
    elif "tomcat9" in tomcat_home_lower: return "9.0"
    elif "tomcat10" in tomcat_home_lower: return "10.0"
    server_xml = os.path.join(tomcat_home, "conf/server.xml")
    if os.path.isfile(server_xml):
        try:
            with open(server_xml, "r") as f:
                content = f.read()
                if "org.apache.catalina.startup.VersionLoggerListener" in content:
                    if "tomcat10" in tomcat_home_lower or "10." in content: return "10.0"
                    elif "9." in content: return "9.0"
                    elif "8." in content: return "8.5"
                    elif "7." in content: return "7.0"
        except Exception as e:
            write_log(f"Error reading {server_xml}: {str(e)}")
    write_log(f"Warning: Could not determine Tomcat version at {tomcat_home}, defaulting to 7.0")
    return version

# Detect password type
def detect_password_type(password):
    if not re.match(r"^[0-9a-fA-F:]+$", password):
        return "Plaintext", False
    if ":" in password:
        hash_part, _ = password.split(":", 1)
        if len(hash_part) == 32 and re.match(r"^[0-9a-fA-F]{32}$", hash_part):
            return "Salted_MD5", False
        if len(hash_part) >= 32 and re.match(r"^[0-9a-fA-F]+$", hash_part):
            return "Salted_PBKDF2", True
        return "Unknown", False
    if len(password) == 32 and re.match(r"^[0-9a-fA-F]{32}$", password):
        return "Hashed_MD5", False
    if len(password) == 40 and re.match(r"^[0-9a-fA-F]{40}$", password):
        return "Hashed_SHA1", False
    if len(password) == 64 and re.match(r"^[0-9a-fA-F]{64}$", password):
        return "Hashed_SHA256", True
    if len(password) == 128 and re.match(r"^[0-9a-fA-F]{128}$", password):
        return "Hashed_SHA512", True
    return "Unknown", False

# Check configuration compliance
def check_config_compliance(tomcat_version, credential_handler, algorithm, iterations, salt_length):
    config_status = "Non-compliant"
    issues = []
    if tomcat_version == "7.0":
        if credential_handler == "org.apache.catalina.realm.MessageDigestCredentialHandler" and algorithm == "SHA-256":
            config_status = "Compliant for Tomcat 7.0"
        else:
            issues.append(f"Tomcat 7.0 requires MessageDigestCredentialHandler with SHA-256")
            issues.append(f"Recommendation: Configure MessageDigestCredentialHandler with algorithm='SHA-256'")
    elif tomcat_version == "8.5":
        if (credential_handler == "org.apache.catalina.realm.MessageDigestCredentialHandler" and 
            algorithm == "SHA-512" and iterations >= 10000 and salt_length >= 16):
            config_status = "Compliant for Tomcat 8.5"
        else:
            issues.append(f"Tomcat 8.5 requires MessageDigestCredentialHandler with SHA-512, iterations >= 10000, saltLength >= 16")
            issues.append(f"Recommendation: Configure MessageDigestCredentialHandler with algorithm='SHA-512', iterations='10000', saltLength='16'")
    else:  # Tomcat 9.0, 10.0, 10.1
        if (credential_handler == "org.apache.catalina.realm.SecretKeyCredentialHandler" and 
            algorithm == "PBKDF2WithHmacSHA512" and iterations >= 10000 and salt_length >= 16):
            config_status = "Compliant for Tomcat {tomcat_version}"
        else:
            issues.append(f"Tomcat {tomcat_version} requires SecretKeyCredentialHandler with PBKDF2WithHmacSHA512, iterations >= 10000, saltLength >= 16")
            issues.append(f"Recommendation: Configure SecretKeyCredentialHandler with algorithm='PBKDF2WithHmacSHA512', iterations='10000', saltLength='16'")
    return config_status, issues

# Audit server.xml
def audit_server_xml(server_xml_path):
    if not os.path.isfile(server_xml_path):
        write_log(f"Error: {server_xml_path} not found", indent=0)
        return "None", "None", 0, 0
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
def audit_users_xml(users_xml_path, credential_handler, handler_algorithm, iterations, salt_length, tomcat_version):
    results = []
    user_count = 0
    if not os.path.isfile(users_xml_path):
        write_log(f"Error: {users_xml_path} not found", indent=0)
        return results
    try:
        tree = ET.parse(users_xml_path)
        root = tree.getroot()
        write_log("User Audit Results:", indent=0)
        write_log("Username | Password Type | Compliance", indent=0)
        write_log("---------|---------------|-----------", indent=0)
        for user in root.findall(".//user"):
            user_count += 1
            username = user.get("username", "Unknown")
            password = user.get("password", "")
            password_type, is_secure = detect_password_type(password)
            compliance_status = "Non-compliant"
            issues = []
            if password_type == "Plaintext":
                issues.append("Plaintext passwords detected. Use salted SHA-256 or PBKDF2.")
            elif password_type in ["Hashed_MD5", "Salted_MD5"]:
                issues.append("Weak MD5 hashing detected. Use SHA-256 or PBKDF2.")
            elif password_type == "Hashed_SHA1":
                issues.append("Weak SHA1 hashing detected. Use SHA-256 or PBKDF2.")
            elif password_type == "Hashed_SHA256":
                if tomcat_version == "7.0":
                    compliance_status = "Compliant"
                elif (credential_handler == "None" or handler_algorithm != "SHA-256" or 
                      iterations < 10000 or salt_length < 16):
                    issues.append("SHA256 requires salt and iterations.")
                else:
                    compliance_status = "Compliant"
            elif password_type == "Hashed_SHA512":
                if tomcat_version == "7.0":
                    issues.append("SHA512 not supported in Tomcat 7.0. Use SHA-256.")
                elif (credential_handler == "None" or handler_algorithm != "SHA-512" or 
                      iterations < 10000 or salt_length < 16):
                    issues.append("SHA512 requires salt and iterations.")
                else:
                    compliance_status = "Compliant"
            elif password_type == "Salted_PBKDF2":
                if tomcat_version == "7.0":
                    issues.append("PBKDF2 not supported in Tomcat 7.0. Use SHA-256.")
                elif tomcat_version == "8.5":
                    if (credential_handler == "None" or 
                        handler_algorithm not in ["SHA-256", "SHA-512"] or 
                        iterations < 10000 or salt_length < 16):
                        issues.append("PBKDF2 requires compatible handler.")
                    else:
                        compliance_status = "Compliant"
                else:
                    if (credential_handler == "org.apache.catalina.realm.SecretKeyCredentialHandler" and 
                        handler_algorithm == "PBKDF2WithHmacSHA512" and 
                        iterations >= 10000 and salt_length >= 16):
                        compliance_status = "Compliant"
                    else:
                        issues.append("PBKDF2 requires SecretKeyCredentialHandler.")
            else:
                issues.append(f"Unknown password type: {password_type}.")
            write_log(f"    {username} | {password_type} | {compliance_status}", indent=2)
            for issue in issues:
                write_log(f"{issue}", indent=4)
            results.append({"status": compliance_status})
        if user_count == 0:
            write_log("    No users found in tomcat-users.xml", indent=2)
    except Exception as e:
        write_log(f"Error parsing {users_xml_path}: {str(e)}")
    return results

# Main audit function
def audit_tomcat_config():
    # Clear log file first
    try:
        open(LOG_FILE, "w").close()
    except PermissionError:
        print(f"Warning: Cannot clear {LOG_FILE}. Continuing with existing log.", file=sys.stderr)

    # Write execution time and hostname
    exec_time = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=5, minutes=30))).strftime("%I:%M %p IST, %A, %B %d, %Y")
    hostname = socket.gethostname()
    write_log(exec_time)
    write_log(hostname)
    write_log("===========================")

    conf_path = get_tomcat_config_path()
    if not conf_path:
        write_log("Error: No Tomcat configuration directory found")
        sys.exit(1)
    write_log(f"Config Path: {conf_path}")

    tomcat_version = detect_tomcat_version(os.path.dirname(conf_path))
    write_log(f"Tomcat Version: {tomcat_version}")

    server_xml_path = os.path.join(conf_path, "server.xml")
    write_log("Auditing server.xml")
    credential_handler, algorithm, iterations, salt_length = audit_server_xml(server_xml_path)

    write_log("Server Configuration:")
    config_status, issues = check_config_compliance(tomcat_version, credential_handler, algorithm, iterations, salt_length)
    for issue in issues:
        write_log(issue, indent=2)
    write_log(f"  Status: {config_status}")
    write_log(f"  Credential Handler: {credential_handler}")
    write_log(f"  Algorithm: {algorithm}")
    write_log(f"  Iterations: {iterations}")
    write_log(f"  Salt Length: {salt_length}")

    users_xml_path = os.path.join(conf_path, "tomcat-users.xml")
    write_log("Auditing tomcat-users.xml")
    audit_results = audit_users_xml(users_xml_path, credential_handler, algorithm, iterations, salt_length, tomcat_version)

    overall_secure = True
    if config_status == "Non-compliant" or not audit_results:
        overall_secure = False
    else:
        for result in audit_results:
            if result["status"] == "Non-compliant":
                overall_secure = False
                break

    write_log("===========================")
    write_log(f"Overall Status: {'Secure' if overall_secure else 'Insecure'}")
    write_log(f"Audit completed. Log: {LOG_FILE}")

if __name__ == "__main__":
    audit_tomcat_config()
