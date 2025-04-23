#!/usr/bin/env python3
import os
import xml.etree.ElementTree as ET
import re
import logging
import sys
from pathlib import Path

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

# Password type detection regex
PASSWORD_PATTERNS = {
    "Plaintext": r"^[a-zA-Z0-9!@#$%^&*()_+]{1,100}$",
    "Hashed_MD5": r"^[0-9a-f]{32}$",
    "Hashed_SHA1": r"^[0-9a-f]{40}$",
    "Hashed_SHA256": r"^[0-9a-f]{64}$",
    "Hashed_SHA512": r"^[0-9a-f]{128}$",
    "Salted_MD5": r"^[0-9a-f]{32}:[0-9a-f]{16}$",
    "Salted_PBKDF2": r"^[0-9a-f]{32}:[0-9a-f]{16}$"
}

# Compliance requirements
COMPLIANCE_STANDARDS = {
    "NIST_800_53_IA_5": {
        "Plaintext": False,
        "Hashed_MD5": False,
        "Hashed_SHA1": False,
        "Hashed_SHA256": True,  # Requires proper CredentialHandler
        "Hashed_SHA512": True,  # Requires proper CredentialHandler
        "Salted_MD5": False,
        "Salted_PBKDF2": True
    },
    "CIS_Tomcat_Benchmark": {
        "Plaintext": False,
        "Hashed_MD5": False,
        "Hashed_SHA1": False,
        "Hashed_SHA256": True,  # Requires iterations >= 10,000, salt >= 16 bytes
        "Hashed_SHA512": True,  # Requires iterations >= 10,000, salt >= 16 bytes
        "Salted_MD5": False,
        "Salted_PBKDF2": True   # Requires iterations >= 10,000, salt >= 16 bytes
    }
}

def detect_tomcat_version(conf_dir):
    """Detect Tomcat version from context.xml or default to Unknown."""
    context_xml = os.path.join(conf_dir, "context.xml")
    try:
        tree = ET.parse(context_xml)
        root = tree.getroot()
        version = root.get("version", "Unknown")
        if "7.0" in version:
            return "7.0"
        elif "8.5" in version:
            return "8.5"
        elif "9.0" in version:
            return "9.0"
        return "Unknown"
    except (FileNotFoundError, ET.ParseError):
        logger.warning("Could not determine Tomcat version from context.xml")
        return "Unknown"

def parse_credential_handler(server_xml):
    """Parse CredentialHandler from server.xml."""
    try:
        tree = ET.parse(server_xml)
        root = tree.getroot()
        realm = root.find(".//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
        if realm is None:
            logger.info("No UserDatabaseRealm found in server.xml")
            return None, {}
        handler = realm.find(".//CredentialHandler")
        if handler is None:
            logger.info("No CredentialHandler found in Realm")
            return None, {}
        class_name = handler.get("className", "Unknown")
        attributes = {
            "algorithm": handler.get("algorithm", "None"),
            "iterations": handler.get("iterations", "0"),
            "saltLength": handler.get("saltLength", "0"),
            "keyLength": handler.get("keyLength", "0")
        }
        return class_name, attributes
    except (FileNotFoundError, ET.ParseError) as e:
        logger.error(f"Error parsing server.xml: {e}")
        print(f"ERROR: Failed to parse {server_xml}. Check permissions and file integrity.")
        sys.exit(1)

def detect_password_type(password):
    """Detect password type based on regex patterns."""
    for ptype, pattern in PASSWORD_PATTERNS.items():
        if re.match(pattern, password):
            return ptype
    return "Unknown"

def check_compliance(password_type, handler_class, attributes, tomcat_version):
    """Check compliance with NIST 800-53 IA-5 and CIS Tomcat Benchmark."""
    results = []
    is_secure = True

    # Basic compliance check
    for standard, rules in COMPLIANCE_STANDARDS.items():
        compliant = rules.get(password_type, False)
        details = []
        if not compliant:
            details.append(f"{password_type} is non-compliant with {standard}")
            is_secure = False
        elif password_type in ["Hashed_SHA256", "Hashed_SHA512", "Salted_PBKDF2"]:
            if tomcat_version == "7.0" and password_type in ["Hashed_SHA512", "Salted_PBKDF2"]:
                compliant = False
                details.append(f"{password_type} not supported in Tomcat 7.0")
                is_secure = False
            elif handler_class is None:
                compliant = False
                details.append("No CredentialHandler defined")
                is_secure = False
            else:
                # Check iterations and salt length for advanced hashes
                iterations = int(attributes.get("iterations", "0"))
                salt_length = int(attributes.get("saltLength", "0"))
                if iterations < 10000:
                    compliant = False
                    details.append(f"Iterations ({iterations}) < 10,000")
                    is_secure = False
                if salt_length < 16:
                    compliant = False
                    details.append(f"Salt length ({salt_length}) < 16 bytes")
                    is_secure = False
                if password_type == "Salted_PBKDF2" and attributes.get("algorithm") != "PBKDF2WithHmacSHA512":
                    compliant = False
                    details.append(f"Algorithm ({attributes.get('algorithm')}) not PBKDF2WithHmacSHA512")
                    is_secure = False
        results.append((standard, compliant, details))
    return results, is_secure

def audit_users(tomcat_users_xml, handler_class, attributes, tomcat_version):
    """Audit users in tomcat-users.xml."""
    try:
        tree = ET.parse(tomcat_users_xml)
        root = tree.getroot()
        users = root.findall(".//user")
        if not users:
            logger.info("No users defined in tomcat-users.xml")
            print("  No users defined in tomcat-users.xml")
            print("    - Status: Compliant (no passwords to evaluate)")
            return True

        overall_secure = True
        for user in users:
            username = user.get("username", "Unknown")
            password = user.get("password", "")
            password_type = detect_password_type(password)
            logger.info(f"User {username}: Detected password type {password_type}")

            print(f"  - User '{username}': {password_type} password ({'secure' if password_type in ['Hashed_SHA256', 'Hashed_SHA512', 'Salted_PBKDF2'] else 'insecure'})")
            print(f"    - Parameter: Password Type = {password_type} [{'PASS' if password_type in ['Hashed_SHA256', 'Hashed_SHA512', 'Salted_PBKDF2'] else 'FAIL'}]")
            print(f"    - Parameter: CredentialHandler = {handler_class or 'None'} [{'PASS' if handler_class else 'FAIL'}]")

            if handler_class:
                for attr_name, attr_value in attributes.items():
                    status = "PASS" if (attr_name == "algorithm" and attr_value in ["SHA-256", "SHA-512", "PBKDF2WithHmacSHA512"]) or \
                                     (attr_name == "iterations" and int(attr_value) >= 10000) or \
                                     (attr_name == "saltLength" and int(attr_value) >= 16) else "FAIL"
                    print(f"    - Parameter: {attr_name.capitalize()} = {attr_value} [{status}]")

            compliance_results, is_secure = check_compliance(password_type, handler_class, attributes, tomcat_version)
            for standard, compliant, details in compliance_results:
                status = "Compliant" if compliant else "Non-compliant"
                print(f"    - Status: {status} with {standard}")
                for detail in details:
                    print(f"      - {detail}")
                    logger.warning(f"User {username}: {detail}")

            if not is_secure:
                overall_secure = False

        return overall_secure
    except (FileNotFoundError, ET.ParseError) as e:
        logger.error(f"Error parsing tomcat-users.xml: {e}")
        print(f"ERROR: Failed to parse {tomcat_users_xml}. Check permissions and file integrity.")
        sys.exit(1)

def main():
    """Main function to audit Tomcat configuration."""
    print("Checking Apache Tomcat configuration security...")
    logger.info("Starting Tomcat configuration audit")

    if not os.path.exists(TOMCAT_CONF_DIR):
        logger.error(f"Tomcat configuration directory {TOMCAT_CONF_DIR} not found")
        print(f"ERROR: Tomcat configuration directory {TOMCAT_CONF_DIR} not found.")
        sys.exit(1)

    tomcat_version = detect_tomcat_version(TOMCAT_CONF_DIR)
    print(f"Detected Tomcat version {tomcat_version} at {TOMCAT_CONF_DIR}")
    logger.info(f"Detected Tomcat version {tomcat_version}")

    print(f"  Auditing server.xml at {SERVER_XML}")
    handler_class, attributes = parse_credential_handler(SERVER_XML)
    logger.info(f"CredentialHandler: {handler_class}, Attributes: {attributes}")

    print(f"  Auditing tomcat-users.xml at {TOMCAT_USERS_XML}")
    overall_secure = audit_users(TOMCAT_USERS_XML, handler_class, attributes, tomcat_version)

    print(f"Overall Configuration: {'Secure' if overall_secure else 'Insecure'}")
    if not overall_secure:
        print("Recommendations:")
        if tomcat_version == "7.0":
            print("  - Use MessageDigestCredentialHandler with SHA-256 (strongest available for 7.0)")
        else:
            print("  - Use SecretKeyCredentialHandler with PBKDF2WithHmacSHA512, iterations >= 10,000, salt length >= 16 bytes")
        print("  - Remove plaintext, MD5, SHA-1, or unsalted passwords")
        print("  - Update tomcat-users.xml to use secure password hashes")
    logger.info(f"Overall Configuration: {'Secure' if overall_secure else 'Insecure'}")
    print("Audit completed")

if __name__ == "__main__":
    main()
