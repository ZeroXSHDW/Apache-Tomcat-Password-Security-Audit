#!/usr/bin/env python3
# UpdateTomcatUserUnixPython.py
# Update Tomcat user credentials with secure password hashing

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
from typing import Optional, Tuple, List, Dict, Any

# Constants
LOG_FILE = "/tmp/TomcatManager.csv"
LOG_DIR = "/tmp"
LOG_FILE_PATH = os.path.join(LOG_DIR, "TomcatManager.log")
TIMESTAMP = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
HOSTNAME = socket.gethostname()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE_PATH),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class XMLHandler:
    """Handles XML operations securely"""
    
    @staticmethod
    def validate_xml_structure(xml_file: str) -> bool:
        """Validate XML structure and content"""
        try:
            if not os.path.exists(xml_file):
                logger.error(f"XML file {xml_file} not found")
                return False
                
            # Check for XML declaration
            with open(xml_file, 'r') as f:
                first_line = f.readline().strip()
                if not first_line.startswith('<?xml'):
                    logger.error(f"Invalid XML declaration in {xml_file}")
                    return False
            
            # Parse XML
            ET.parse(xml_file)
            return True
        except ET.ParseError as e:
            logger.error(f"Invalid XML structure in {xml_file}: {str(e)}")
            return False
        except Exception as e:
            logger.error(f"Error validating XML {xml_file}: {str(e)}")
            return False

    @staticmethod
    def secure_parse_xml(xml_file: str) -> Tuple[bool, Optional[ET.ElementTree]]:
        """Securely parse XML file with validation"""
        try:
            if not os.path.exists(xml_file):
                logger.error(f"XML file {xml_file} not found")
                return False, None
                
            if not os.access(xml_file, os.R_OK):
                logger.error(f"No read permission for {xml_file}")
                return False, None
                
            if not XMLHandler.validate_xml_structure(xml_file):
                return False, None
                
            tree = ET.parse(xml_file)
            return True, tree
        except Exception as e:
            logger.error(f"Error parsing XML {xml_file}: {str(e)}")
            return False, None

    @staticmethod
    def secure_write_xml(xml_file: str, tree: ET.ElementTree) -> bool:
        """Securely write XML file with backup"""
        try:
            # Create backup
            if os.path.exists(xml_file):
                backup_file = f"{xml_file}.bak.{int(time.time())}"
                shutil.copy2(xml_file, backup_file)
                os.chmod(backup_file, 0o600)
                logger.info(f"Created backup: {backup_file}")
            
            # Write to temporary file
            temp_file = f"{xml_file}.tmp"
            tree.write(temp_file, encoding='utf-8', xml_declaration=True)
            
            # Validate temporary file
            if not XMLHandler.validate_xml_structure(temp_file):
                os.remove(temp_file)
                return False
            
            # Move to final location
            shutil.move(temp_file, xml_file)
            os.chmod(xml_file, 0o600)
            return True
        except Exception as e:
            logger.error(f"Error writing XML {xml_file}: {str(e)}")
            if os.path.exists(temp_file):
                os.remove(temp_file)
            return False

class TomcatVersionDetector:
    """Detects Tomcat version from various sources"""
    
    @staticmethod
    def detect_version(tomcat_home: str) -> str:
        """Detect Tomcat version from RELEASE-NOTES or path"""
        version = "7.0"  # Default fallback
        
        # Check RELEASE-NOTES
        release_notes = os.path.join(tomcat_home, "RELEASE-NOTES")
        if os.path.exists(release_notes):
            try:
                with open(release_notes, 'r') as f:
                    content = f.read()
                    match = re.search(r"Apache Tomcat Version (\d+\.\d+\.\d+)", content)
                    if match:
                        full_version = match.group(1)
                        if full_version.startswith("7.0"): version = "7.0"
                        elif full_version.startswith("8.5"): version = "8.5"
                        elif full_version.startswith("9.0"): version = "9.0"
                        elif full_version.startswith("10.0"): version = "10.0"
                        elif full_version.startswith("10.1"): version = "10.1"
            except Exception as e:
                logger.warning(f"Error reading RELEASE-NOTES: {str(e)}")
        
        # Check path name
        tomcat_home_lower = tomcat_home.lower()
        if "tomcat7" in tomcat_home_lower: version = "7.0"
        elif "tomcat8" in tomcat_home_lower: version = "8.5"
        elif "tomcat9" in tomcat_home_lower: version = "9.0"
        elif "tomcat10" in tomcat_home_lower: version = "10.0"
        
        return version

class PasswordHandler:
    """Handles password operations securely"""
    
    HASH_PATTERNS = {
        "7.0": re.compile(r'^[0-9a-fA-F]{64}$'),
        "8.5": re.compile(r'^[0-9a-fA-F]{128}$'),
        "9.0": re.compile(r'^[0-9a-fA-F]+:[0-9a-fA-F]+$'),
        "10.0": re.compile(r'^[0-9a-fA-F]+:[0-9a-fA-F]+$'),
        "10.1": re.compile(r'^[0-9a-fA-F]+:[0-9a-fA-F]+$')
    }
    
    @staticmethod
    def validate_hash_format(hash_value: str, version: str) -> bool:
        """Validate hash format based on Tomcat version"""
        pattern = PasswordHandler.HASH_PATTERNS.get(version)
        if not pattern:
            logger.error(f"Unsupported Tomcat version: {version}")
            return False
        return bool(pattern.match(hash_value))

    @staticmethod
    def generate_password_hash(tomcat_bin: str, password: str, version: str) -> Optional[str]:
        """Generate password hash using digest.sh"""
        try:
            digest_script = os.path.join(tomcat_bin, "digest.sh")
            if not os.path.exists(digest_script) or not os.access(digest_script, os.X_OK):
                logger.error("digest.sh not found or not executable")
                return None
            
            # Set algorithm and parameters based on version
            algorithm = "SHA-256" if version == "7.0" else "SHA-512"
            iterations = None if version == "7.0" else "10000"
            salt_length = None if version == "7.0" else "16"
            
            # Build command
            cmd = [digest_script, "-a", algorithm]
            if iterations:
                cmd.extend(["-i", iterations])
            if salt_length:
                cmd.extend(["-s", salt_length])
            cmd.append(password)
            
            # Run digest.sh
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            hash_value = re.search(r'[0-9a-fA-F:]+$', result.stdout)
            
            if not hash_value:
                logger.error("Failed to generate hash")
                return None
                
            return hash_value.group(0)
        except subprocess.CalledProcessError as e:
            logger.error(f"Error running digest.sh: {str(e)}")
            return None
        except Exception as e:
            logger.error(f"Error generating hash: {str(e)}")
            return None

class ServiceManager:
    """Manages Tomcat service operations"""
    
    @staticmethod
    def get_service_name() -> Optional[str]:
        """Get active Tomcat service name"""
        for svc in ["tomcat", "tomcat7", "tomcat8", "tomcat9", "tomcat10"]:
            try:
                result = subprocess.run(
                    ["systemctl", "is-active", "--quiet", svc],
                    capture_output=True
                )
                if result.returncode == 0:
                    return svc
            except Exception:
                continue
        return None

    @staticmethod
    def manage_service(tomcat_home: str, action: str, timeout: int = 60) -> bool:
        """Manage Tomcat service (start/stop/restart)"""
        try:
            service_name = ServiceManager.get_service_name()
            
            if service_name:
                # Use systemd
                if action == "restart":
                    subprocess.run(["systemctl", "stop", service_name], check=True)
                    time.sleep(5)
                    subprocess.run(["systemctl", "start", service_name], check=True)
                else:
                    subprocess.run(["systemctl", action, service_name], check=True)
            else:
                # Use catalina.sh
                catalina_script = os.path.join(tomcat_home, "bin", "catalina.sh")
                if not os.path.exists(catalina_script) or not os.access(catalina_script, os.X_OK):
                    logger.error("catalina.sh not found or not executable")
                    return False
                
                if action == "restart":
                    subprocess.run([catalina_script, "stop"], check=True)
                    time.sleep(5)
                    subprocess.run([catalina_script, "start"], check=True)
                else:
                    subprocess.run([catalina_script, action], check=True)
            
            # Wait for service to be ready
            start_time = time.time()
            while time.time() - start_time < timeout:
                try:
                    with socket.create_connection(("localhost", 8080), timeout=1):
                        return True
                except (socket.timeout, socket.error):
                    time.sleep(1)
            
            logger.error("Service failed to start within timeout")
            return False
        except subprocess.CalledProcessError as e:
            logger.error(f"Error managing service: {str(e)}")
            return False
        except Exception as e:
            logger.error(f"Error managing service: {str(e)}")
            return False

class UserManager:
    """Manages Tomcat user operations"""
    
    VALID_ROLES = {
        "manager-gui", "manager-script", "manager-jmx", "manager-status",
        "admin-gui", "admin-script"
    }
    
    @staticmethod
    def validate_username(username: str) -> bool:
        """Validate username format"""
        if not re.match(r'^[a-zA-Z0-9_]+$', username):
            logger.error("Invalid username format")
            return False
        return True

    @staticmethod
    def validate_password(password: str) -> bool:
        """Validate password requirements"""
        if len(password) < 8:
            logger.error("Password must be at least 8 characters")
            return False
        return True

    @staticmethod
    def validate_roles(roles: str) -> bool:
        """Validate role names"""
        role_list = roles.split(',')
        for role in role_list:
            if role not in UserManager.VALID_ROLES:
                logger.error(f"Invalid role: {role}")
                return False
        return True

    @staticmethod
    def update_user(
        users_xml_path: str,
        username: str,
        password: str,
        roles: str,
        tomcat_version: str,
        tomcat_bin: str
    ) -> bool:
        """Update or create user in tomcat-users.xml"""
        try:
            # Validate inputs
            if not all([
                UserManager.validate_username(username),
                UserManager.validate_password(password),
                UserManager.validate_roles(roles)
            ]):
                return False
            
            # Generate password hash
            hash_value = PasswordHandler.generate_password_hash(
                tomcat_bin, password, tomcat_version
            )
            if not hash_value:
                return False
            
            # Parse XML
            success, tree = XMLHandler.secure_parse_xml(users_xml_path)
            if not success or not tree:
                return False
            
            root = tree.getroot()
            
            # Find existing user
            user = root.find(f".//user[@username='{username}']")
            
            if user is not None:
                # Update existing user
                user.set('password', hash_value)
                user.set('roles', roles)
            else:
                # Create new user
                new_user = ET.SubElement(root, 'user')
                new_user.set('username', username)
                new_user.set('password', hash_value)
                new_user.set('roles', roles)
            
            # Write changes
            return XMLHandler.secure_write_xml(users_xml_path, tree)
        except Exception as e:
            logger.error(f"Error updating user: {str(e)}")
            return False

def main():
    """Main function"""
    # Check root privileges
    if os.geteuid() != 0:
        logger.error("This script must be run as root or with sudo")
        sys.exit(1)
    
    # Create log directory
    os.makedirs(LOG_DIR, exist_ok=True)
    
    # Initialize log file
    if not os.path.exists(LOG_FILE):
        with open(LOG_FILE, 'w') as f:
            f.write("Timestamp,Message\n")
    
    # Parse arguments
    parser = argparse.ArgumentParser(description='Update Tomcat user credentials')
    parser.add_argument('--username', required=True, help='Username')
    parser.add_argument('--password', required=True, help='Password')
    parser.add_argument('--roles', required=True, help='Comma-separated roles')
    parser.add_argument('--conf-path', help='Custom Tomcat configuration path')
    args = parser.parse_args()
    
    # Get Tomcat configuration path
    conf_path = args.conf_path
    if not conf_path:
        if 'CATALINA_HOME' in os.environ:
            conf_path = os.path.join(os.environ['CATALINA_HOME'], 'conf')
        elif 'CATALINA_BASE' in os.environ:
            conf_path = os.path.join(os.environ['CATALINA_BASE'], 'conf')
        else:
            for path in [
                "/opt/tomcat/conf",
                "/usr/local/tomcat/conf",
                "/var/lib/tomcat/conf",
                "/usr/share/tomcat/conf"
            ]:
                if os.path.isdir(path) and os.path.exists(os.path.join(path, "server.xml")):
                    conf_path = path
                    break
    
    if not conf_path:
        logger.error("Could not locate Tomcat configuration directory")
        sys.exit(1)
    
    tomcat_home = os.path.dirname(conf_path)
    logger.info(f"Tomcat Home: {tomcat_home}")
    logger.info(f"Config Path: {conf_path}")
    
    # Detect Tomcat version
    tomcat_version = TomcatVersionDetector.detect_version(tomcat_home)
    logger.info(f"Tomcat Version: {tomcat_version}")
    
    # Update user
    users_xml_path = os.path.join(conf_path, "tomcat-users.xml")
    if not UserManager.update_user(
        users_xml_path,
        args.username,
        args.password,
        args.roles,
        tomcat_version,
        os.path.join(tomcat_home, "bin")
    ):
        logger.error("Failed to update user")
        sys.exit(1)
    
    # Restart Tomcat
    logger.info("Restarting Tomcat to apply changes")
    if not ServiceManager.manage_service(tomcat_home, "restart"):
        logger.error("Failed to restart Tomcat service")
        sys.exit(1)
    
    logger.info(f"User {args.username} updated successfully")
    logger.info("Overall Status: Secure")
    
    # Log results
    log_message = f"User: {args.username}; Roles: {args.roles}; Tomcat Version: {tomcat_version}; Status: Updated"
    with open(LOG_FILE, 'a') as f:
        f.write(f"{TIMESTAMP},\"{log_message}\"\n")

if __name__ == "__main__":
    main()