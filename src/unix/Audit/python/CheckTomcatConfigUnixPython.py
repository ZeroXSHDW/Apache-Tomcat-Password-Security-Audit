#!/usr/bin/env python3
# CheckTomcatConfigUnixPython.py
# Audit Apache Tomcat configuration for security compliance with NIST 800-53 IA-5 and CIS Tomcat Benchmark

import os
import sys
import re
import datetime
import socket
import xml.etree.ElementTree as ET
import logging
from logging.handlers import RotatingFileHandler
import platform
import subprocess
import time
from pathlib import Path
import shutil
import stat

class TomcatConfigManager:
    """Manages Tomcat configuration across different platforms."""
    
    def __init__(self):
        self.platform = platform.system().lower()
        self.path_separator = '\\' if self.platform == 'windows' else '/'
        self.logger = self._setup_logging()
        
    def _setup_logging(self):
        """Setup secure logging with rotation."""
        log_file = "/tmp/TomcatManager.log"
        logger = logging.getLogger('tomcat_audit')
        logger.setLevel(logging.INFO)
        
        # File handler with rotation
        handler = RotatingFileHandler(
            log_file,
            maxBytes=10*1024*1024,  # 10MB
            backupCount=5
        )
        
        # Format
        formatter = logging.Formatter(
            '%(asctime)s - %(levelname)s - %(message)s'
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        
        # Set secure permissions
        if os.path.exists(log_file):
            os.chmod(log_file, 0o600)
            
        return logger
        
    def get_config_path(self, custom_conf_path=None):
        """Get Tomcat configuration path based on platform."""
        if custom_conf_path:
            return self._validate_custom_path(custom_conf_path)
            
        # Check environment variables
        for env_var in ['CATALINA_HOME', 'CATALINA_BASE']:
            if env_var in os.environ:
                path = os.path.join(os.environ[env_var], 'conf')
                if self._validate_config_path(path):
                    return path
                    
        # Check common paths
        common_paths = self._get_common_paths()
        for path in common_paths:
            if self._validate_config_path(path):
                return path
                
        return None
        
    def _validate_custom_path(self, path):
        """Validate custom configuration path."""
        if not path or not isinstance(path, str):
            self.logger.error("Invalid configuration path")
            return None
            
        # Prevent path traversal
        if '..' in path or path.startswith('/'):
            self.logger.error("Invalid path format")
            return None
            
        return path if self._validate_config_path(path) else None
        
    def _validate_config_path(self, path):
        """Validate configuration path has required files."""
        required_files = ['server.xml', 'tomcat-users.xml']
        try:
            for file in required_files:
                file_path = os.path.join(path, file)
                if not os.path.isfile(file_path):
                    return False
                # Verify file permissions
                if not os.access(file_path, os.R_OK):
                    self.logger.error(f"No read permission for {file_path}")
                    return False
            return True
        except Exception as e:
            self.logger.error(f"Error validating path {path}: {str(e)}")
            return False
            
    def _get_common_paths(self):
        """Get common Tomcat configuration paths based on platform."""
        if self.platform == 'windows':
            return [
                r"C:\Program Files\Apache Software Foundation\Tomcat\conf",
                r"C:\Program Files (x86)\Apache Software Foundation\Tomcat\conf",
                r"C:\Tomcat\conf"
            ]
        else:
            return [
                "/opt/tomcat/conf",
                "/usr/local/tomcat/conf",
                "/var/lib/tomcat/conf",
                "/usr/share/tomcat/conf"
            ]

class XMLHandler:
    """Handles XML operations securely."""
    
    def __init__(self, logger):
        self.logger = logger
        
    def validate_xml_structure(self, xml_content):
        """Validate XML structure and content."""
        try:
            # Basic XML structure validation
            if not xml_content.strip().startswith('<?xml'):
                raise ValueError("Invalid XML declaration")
                
            # Parse XML to validate structure
            try:
                tree = ET.fromstring(xml_content)
            except ET.ParseError as e:
                raise ValueError(f"XML parsing error: {str(e)}")
                
            return True
        except Exception as e:
            self.logger.error(f"XML validation failed: {str(e)}")
            return False
            
    def secure_parse_xml(self, file_path):
        """Securely parse XML file with validation."""
        try:
            # Read file with proper encoding
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
                
            # Validate XML structure
            if not self.validate_xml_structure(content):
                raise ValueError("Invalid XML structure")
                
            # Parse XML
            tree = ET.parse(file_path)
            root = tree.getroot()
            
            return tree, root
        except Exception as e:
            self.logger.error(f"Error parsing XML file {file_path}: {str(e)}")
            return None, None
            
    def secure_write_xml(self, tree, file_path):
        """Securely write XML file with backup."""
        backup_path = f"{file_path}.bak.{datetime.datetime.now().strftime('%Y%m%d%H%M%S')}"
        try:
            # Create backup
            if os.path.exists(file_path):
                shutil.copy2(file_path, backup_path)
                os.chmod(backup_path, 0o600)
                
            # Write XML with proper formatting
            tree.write(file_path, encoding='utf-8', xml_declaration=True)
            
            # Verify written file
            if not self.validate_xml_structure(open(file_path, 'r', encoding='utf-8').read()):
                raise ValueError("XML validation failed after write")
                
            # Set secure permissions
            os.chmod(file_path, 0o600)
            
            return True
        except Exception as e:
            self.logger.error(f"Error writing XML file {file_path}: {str(e)}")
            # Restore from backup if available
            if os.path.exists(backup_path):
                shutil.copy2(backup_path, file_path)
                os.chmod(file_path, 0o600)
            return False

class PasswordHandler:
    """Handles password operations securely."""
    
    def __init__(self, logger):
        self.logger = logger
        self.hash_patterns = {
            "7.0": r'^[0-9a-fA-F]{64}$',
            "8.5": r'^[0-9a-fA-F]{128}$',
            "9.0": r'^[0-9a-fA-F]+:[0-9a-fA-F]+$',
            "10.0": r'^[0-9a-fA-F]+:[0-9a-fA-F]+$',
            "10.1": r'^[0-9a-fA-F]+:[0-9a-fA-F]+$'
        }
        
    def generate_and_validate_hash(self, tomcat_bin, password, tomcat_version):
        """Generate and validate password hash."""
        try:
            # Generate hash
            hash_value = self._generate_hash(tomcat_bin, password, tomcat_version)
            if not hash_value:
                raise ValueError("Hash generation failed")
                
            # Validate hash format
            if not self._validate_hash_format(hash_value, tomcat_version):
                raise ValueError(f"Invalid hash format for Tomcat {tomcat_version}")
                
            return hash_value
        except Exception as e:
            self.logger.error(f"Error generating/validating hash: {str(e)}")
            return None
            
    def _generate_hash(self, tomcat_bin, password, tomcat_version):
        """Generate password hash using digest.sh."""
        digest_script = os.path.join(tomcat_bin, "digest.sh")
        
        # Verify digest script exists and is executable
        if not (os.path.isfile(digest_script) and os.access(digest_script, os.X_OK)):
            self.logger.error(f"digest.sh not found or not executable at {digest_script}")
            return None
            
        # Set algorithm and parameters based on Tomcat version
        algorithm, iterations, salt_length = self._get_hash_parameters(tomcat_version)
        
        try:
            # Run digest.sh
            cmd = [digest_script, "-a", algorithm]
            if tomcat_version != "7.0":
                cmd.extend(["-i", iterations, "-s", salt_length])
            cmd.append(password)
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if result.returncode != 0:
                self.logger.error(f"digest.sh failed: {result.stderr}")
                return None
                
            # Extract hash
            match = re.search(r'[0-9a-fA-F:]+', result.stdout)
            if not match:
                self.logger.error("Failed to parse hash from digest.sh output")
                return None
                
            return match.group(0)
        except subprocess.TimeoutExpired:
            self.logger.error("digest.sh timed out")
            return None
        except Exception as e:
            self.logger.error(f"Error running digest.sh: {str(e)}")
            return None
            
    def _validate_hash_format(self, hash_value, tomcat_version):
        """Validate hash format."""
        pattern = self.hash_patterns.get(tomcat_version)
        if not pattern:
            self.logger.error(f"Unsupported Tomcat version: {tomcat_version}")
            return False
            
        return bool(re.match(pattern, hash_value))
        
    def _get_hash_parameters(self, tomcat_version):
        """Get hash parameters based on Tomcat version."""
        if tomcat_version == "7.0":
            return "SHA-256", None, None
        elif tomcat_version == "8.5":
            return "SHA-512", "10000", "16"
        else:  # 9.0, 10.0, 10.1
            return "PBKDF2WithHmacSHA512", "10000", "16"

class ServiceManager:
    """Manages Tomcat service operations."""
    
    def __init__(self, logger):
        self.logger = logger
        
    def restart_service(self, tomcat_home, timeout=60):
        """Restart Tomcat service with verification."""
        service_name = self._get_service_name()
        if service_name:
            return self._restart_systemd_service(service_name, timeout)
        else:
            return self._restart_catalina_service(tomcat_home, timeout)
            
    def _get_service_name(self):
        """Get Tomcat service name."""
        for svc in ["tomcat", "tomcat7", "tomcat8", "tomcat9", "tomcat10"]:
            try:
                result = subprocess.run(["systemctl", "is-active", svc],
                                     capture_output=True, text=True)
                if result.returncode == 0:
                    return svc
            except subprocess.CalledProcessError:
                continue
        return None
        
    def _restart_systemd_service(self, service_name, timeout):
        """Restart Tomcat service using systemd."""
        try:
            # Stop service
            subprocess.run(["systemctl", "stop", service_name],
                         check=True, capture_output=True)
            
            # Wait for service to stop
            if not self._wait_for_service_status(service_name, "inactive", timeout/2):
                self.logger.error(f"Service {service_name} failed to stop")
                return False
                
            # Start service
            subprocess.run(["systemctl", "start", service_name],
                         check=True, capture_output=True)
            
            # Wait for service to start
            if not self._wait_for_service_status(service_name, "active", timeout/2):
                self.logger.error(f"Service {service_name} failed to start")
                return False
                
            # Verify service health
            if not self._verify_service_health():
                self.logger.error(f"Service {service_name} health check failed")
                return False
                
            return True
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Error managing service {service_name}: {str(e)}")
            return False
            
    def _restart_catalina_service(self, tomcat_home, timeout):
        """Restart Tomcat service using catalina.sh."""
        catalina_script = os.path.join(tomcat_home, "bin/catalina.sh")
        if not (os.path.isfile(catalina_script) and os.access(catalina_script, os.X_OK)):
            self.logger.error("catalina.sh not found or not executable")
            return False
            
        try:
            # Stop service
            subprocess.run([catalina_script, "stop"],
                         check=True, capture_output=True)
            
            # Wait for service to stop
            if not self._wait_for_process_stop(timeout/2):
                self.logger.error("Tomcat process failed to stop")
                return False
                
            # Start service
            subprocess.run([catalina_script, "start"],
                         check=True, capture_output=True)
            
            # Wait for service to start
            if not self._wait_for_process_start(timeout/2):
                self.logger.error("Tomcat process failed to start")
                return False
                
            # Verify service health
            if not self._verify_service_health():
                self.logger.error("Tomcat service health check failed")
                return False
                
            return True
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Error managing Tomcat service: {str(e)}")
            return False
            
    def _wait_for_service_status(self, service_name, status, timeout):
        """Wait for service to reach specified status."""
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                result = subprocess.run(["systemctl", "is-active", service_name],
                                     capture_output=True, text=True)
                if result.stdout.strip() == status:
                    return True
            except subprocess.CalledProcessError:
                pass
            time.sleep(1)
        return False
        
    def _wait_for_process_stop(self, timeout):
        """Wait for Tomcat process to stop."""
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                result = subprocess.run(["pgrep", "-f", "org.apache.catalina.startup.Bootstrap"],
                                     capture_output=True)
                if result.returncode != 0:
                    return True
            except subprocess.CalledProcessError:
                pass
            time.sleep(1)
        return False
        
    def _wait_for_process_start(self, timeout):
        """Wait for Tomcat process to start."""
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                result = subprocess.run(["pgrep", "-f", "org.apache.catalina.startup.Bootstrap"],
                                     capture_output=True)
                if result.returncode == 0:
                    return True
            except subprocess.CalledProcessError:
                pass
            time.sleep(1)
        return False
        
    def _verify_service_health(self, timeout=30):
        """Verify Tomcat service is healthy."""
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                # Try to connect to Tomcat
                import socket
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                result = sock.connect_ex(('127.0.0.1', 8080))
                sock.close()
                if result == 0:
                    return True
            except:
                pass
            time.sleep(1)
        return False

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
    print(log_message)

# Ensure log file has header
if not os.path.exists(LOG_FILE):
    try:
        with open(LOG_FILE, "w") as f:
            f.write("Timestamp,Message\n")
    except PermissionError:
        print(f"Warning: Cannot create {LOG_FILE}. Logging to console only.", file=sys.stderr)

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
            issues.append("Tomcat 7.0 requires MessageDigestCredentialHandler with SHA-256")
            issues.append("Recommendation: Configure MessageDigestCredentialHandler with algorithm='SHA-256'")
    elif tomcat_version == "8.5":
        if (credential_handler == "org.apache.catalina.realm.MessageDigestCredentialHandler" and 
            algorithm == "SHA-512" and iterations >= 10000 and salt_length >= 16):
            config_status = "Compliant for Tomcat 8.5"
        else:
            issues.append("Tomcat 8.5 requires MessageDigestCredentialHandler with SHA-512, iterations >= 10000, saltLength >= 16")
            issues.append("Recommendation: Configure MessageDigestCredentialHandler with algorithm='SHA-512', iterations='10000', saltLength='16'")
    else:  # Tomcat 9.0, 10.0, 10.1
        if (credential_handler == "org.apache.catalina.realm.SecretKeyCredentialHandler" and 
            algorithm == "PBKDF2WithHmacSHA512" and iterations >= 10000 and salt_length >= 16):
            config_status = f"Compliant for Tomcat {tomcat_version}"
        else:
            issues.append(f"Tomcat {tomcat_version} requires SecretKeyCredentialHandler with PBKDF2WithHmacSHA512, iterations >= 10000, saltLength >= 16")
            issues.append("Recommendation: Configure SecretKeyCredentialHandler with algorithm='PBKDF2WithHmacSHA512', iterations='10000', saltLength='16'")
    return config_status, issues

# Audit server.xml
def audit_server_xml(server_xml_path):
    if not os.path.isfile(server_xml_path):
        write_log(f"Error: {server_xml_path} not found")
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
        write_log(f"Error: {users_xml_path} not found")
        return results
    try:
        with open(users_xml_path, "r") as f:
            content = f.read()
        write_log("User Audit Results:")
        write_log("Username | Password Type | Compliance")
        write_log("---------|---------------|-----------")
        user_pattern = re.compile(r'<user[^>]*username="([^"]+)"[^>]*password="([^"]+)"[^>]*>')
        for match in user_pattern.finditer(content):
            user_count += 1
            username = match.group(1) if match.group(1) else "Unknown"
            password = match.group(2) if match.group(2) else ""
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
                write_log(issue, indent=4)
            results.append({"status": compliance_status})
        if user_count == 0:
            write_log("    No users found in tomcat-users.xml", indent=2)
    except Exception as e:
        write_log(f"Error reading {users_xml_path}: {str(e)}")
    return results

def check_tomcat_running_as_root():
    """Check if any Tomcat process is running as root, and if lsof is available, check open files owned by root."""
    try:
        # Find Tomcat PIDs
        result = subprocess.run(["pgrep", "-f", "org.apache.catalina.startup.Bootstrap"], capture_output=True, text=True)
        tomcat_pids = result.stdout.strip().split() if result.returncode == 0 else []
        found_root = False
        if tomcat_pids:
            for pid in tomcat_pids:
                # Check process user
                try:
                    proc_user = subprocess.check_output(["ps", "-o", "user=", "-p", pid], text=True).strip()
                    if proc_user == "root":
                        write_log(f"WARNING: Tomcat process (PID {pid}) is running as root! [ps method]", 2)
                        write_log("  - It is a security risk to run Tomcat as root. Use a dedicated non-root user.", 2)
                        found_root = True
                except Exception:
                    continue
            # lsof check
            if shutil.which("lsof"):
                for pid in tomcat_pids:
                    try:
                        lsof_out = subprocess.check_output(["lsof", "-p", pid], text=True)
                        for line in lsof_out.splitlines():
                            parts = line.split()
                            if len(parts) > 2 and parts[2] == "root":
                                write_log(f"WARNING: Tomcat process (PID {pid}) has open files owned by root! [lsof method]", 2)
                                write_log("  - This may indicate Tomcat is running as root or has escalated privileges.", 2)
                                found_root = True
                                break
                    except Exception:
                        continue
            if not found_root:
                write_log("Tomcat process is not running as root (checked by both ps and lsof).", 2)
        else:
            write_log("No running Tomcat processes found for root check.", 2)
    except Exception as e:
        write_log(f"Error checking Tomcat root status: {e}", 2)

def check_file_ownership_and_permissions(file_path):
    """Check if file is owned by root and has secure permissions."""
    if os.path.isfile(file_path):
        st = os.stat(file_path)
        owner = st.st_uid
        perms = stat.S_IMODE(st.st_mode)
        try:
            import pwd
            owner_name = pwd.getpwuid(owner).pw_name
        except Exception:
            owner_name = str(owner)
        if owner_name != "root":
            write_log(f"WARNING: {file_path} is not owned by root (owner: {owner_name})", 2)
        else:
            write_log(f"{file_path} is owned by root", 2)
        if perms > 0o640:
            write_log(f"WARNING: {file_path} has insecure permissions ({oct(perms)})", 2)
        else:
            write_log(f"{file_path} permissions are secure ({oct(perms)})", 2)
    else:
        write_log(f"WARNING: {file_path} does not exist", 2)

# Main audit function
def audit_tomcat_config():
    # Check for sudo/root privileges
    if os.geteuid() != 0:
        timestamp = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=5, minutes=30))).strftime("%Y-%m-%d %H:%M:%S")
        write_log("ERROR - This script must be run as root or with sudo")
        combined_message = "; ".join(log_messages)
        log_entry = f"{timestamp},\"{combined_message}\""
        try:
            with open(LOG_FILE, "a") as f:
                f.write(log_entry + "\n")
        except PermissionError:
            print(f"Warning: Cannot write to {LOG_FILE}.", file=sys.stderr)
        sys.exit(1)

    # Write execution time and hostname
    exec_time = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=5, minutes=30))).strftime("%Y-%m-%d %H:%M:%S")
    hostname = socket.gethostname()
    write_log(f"Execution Time: {exec_time}")
    write_log(f"Hostname: {hostname}")
    write_log("===========================")

    conf_path = get_tomcat_config_path()
    if not conf_path:
        write_log("ERROR - No Tomcat configuration directory found")
        return
    write_log(f"Config Path: {conf_path}")

    # Check if Tomcat is running as root
    check_tomcat_running_as_root()

    # Always check file ownership and permissions for root detection
    check_file_ownership_and_permissions(os.path.join(conf_path, "server.xml"))
    check_file_ownership_and_permissions(os.path.join(conf_path, "tomcat-users.xml"))

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
    write_log("Audit completed")

    # Write single CSV line
    timestamp = exec_time
    combined_message = "; ".join(log_messages)
    log_entry = f"{timestamp},\"{combined_message}\""
    try:
        with open(LOG_FILE, "a") as f:
            f.write(log_entry + "\n")
    except PermissionError:
        print(f"Warning: Cannot write to {LOG_FILE}.", file=sys.stderr)

def main():
    """Main function to execute the audit and update process."""
    try:
        # Check root privileges
        if os.geteuid() != 0:
            raise PermissionError("This script must be run as root or with sudo")

        # Initialize managers
        config_manager = TomcatConfigManager()
        xml_handler = XMLHandler(config_manager.logger)
        password_handler = PasswordHandler(config_manager.logger)
        service_manager = ServiceManager(config_manager.logger)

        # Parse arguments
        custom_conf_path = None
        for arg in sys.argv[1:]:
            if arg.startswith("--custom-conf="):
                custom_conf_path = arg.split("=", 1)[1]
            else:
                config_manager.logger.error(f"Unknown argument: {arg}")
                sys.exit(1)

        # Get configuration path
        conf_path = config_manager.get_config_path(custom_conf_path)
        if not conf_path:
            config_manager.logger.error("Could not locate Tomcat configuration directory")
            sys.exit(1)

        tomcat_home = os.path.dirname(conf_path)
        config_manager.logger.info(f"Tomcat Home: {tomcat_home}")
        config_manager.logger.info(f"Config Path: {conf_path}")

        # Detect Tomcat version
        tomcat_version = detect_tomcat_version(tomcat_home)
        config_manager.logger.info(f"Tomcat Version: {tomcat_version}")

        # Process users
        users_xml_path = os.path.join(conf_path, "tomcat-users.xml")
        config_manager.logger.info(f"Reading {users_xml_path} for users with plaintext passwords")
        
        # Parse users XML
        tree, root = xml_handler.secure_parse_xml(users_xml_path)
        if not tree or not root:
            config_manager.logger.error(f"Failed to parse {users_xml_path}")
            sys.exit(1)

        # Get plaintext users
        plaintext_users = []
        for user in root.findall(".//user"):
            username = user.get("username")
            password = user.get("password")
            if password and not password_handler._validate_hash_format(password, tomcat_version):
                plaintext_users.append({"username": username, "password": password})

        if not plaintext_users:
            config_manager.logger.info("No plaintext passwords to update")
        else:
            config_manager.logger.info(f"Found {len(plaintext_users)} user(s) with plaintext passwords")

        # Update users
        updated_users = []
        for user in plaintext_users:
            username = user["username"]
            password = user["password"]
            config_manager.logger.info(f"Processing user: {username}")
            
            hash_value = password_handler.generate_and_validate_hash(
                os.path.join(tomcat_home, "bin"),
                password,
                tomcat_version
            )
            
            if not hash_value:
                config_manager.logger.error(f"Failed to generate hash for user {username}")
                sys.exit(1)
                
            config_manager.logger.info(f"Generated hash for {username}")
            updated_users.append({"username": username, "hash": hash_value})

        # Update configuration files
        if updated_users:
            # Update users XML
            for user in root.findall(".//user"):
                username = user.get("username")
                for updated_user in updated_users:
                    if updated_user["username"] == username:
                        user.set("password", updated_user["hash"])
                        break

            if not xml_handler.secure_write_xml(tree, users_xml_path):
                config_manager.logger.error(f"Failed to update {users_xml_path}")
                sys.exit(1)

        # Update server XML
        server_xml_path = os.path.join(conf_path, "server.xml")
        tree, root = xml_handler.secure_parse_xml(server_xml_path)
        if not tree or not root:
            config_manager.logger.error(f"Failed to parse {server_xml_path}")
            sys.exit(1)

        # Update server configuration
        realm = root.find(".//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
        if not realm:
            engine = root.find(".//Engine")
            if not engine:
                config_manager.logger.error("No Engine element found in server.xml")
                sys.exit(1)
            realm = ET.SubElement(engine, "Realm",
                                className="org.apache.catalina.realm.UserDatabaseRealm",
                                resourceName="UserDatabase")

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
        else:  # 9.0, 10.0, 10.1
            ch.set("className", "org.apache.catalina.realm.SecretKeyCredentialHandler")
            ch.set("algorithm", "PBKDF2WithHmacSHA512")
            ch.set("iterations", "10000")
            ch.set("saltLength", "16")
            ch.set("keyLength", "256")

        if not xml_handler.secure_write_xml(tree, server_xml_path):
            config_manager.logger.error(f"Failed to update {server_xml_path}")
            sys.exit(1)

        # Restart service
        config_manager.logger.info("Restarting Tomcat to apply changes")
        if not service_manager.restart_service(tomcat_home):
            config_manager.logger.error("Failed to restart Tomcat service")
            sys.exit(1)

        # Report compliance status
        compliance_status = {
            "7.0": "Compliant with SHA-256 (MessageDigestCredentialHandler)",
            "8.5": "Compliant with SHA-512, 10000 iterations, 16-byte salt (MessageDigestCredentialHandler)",
            "9.0": "Compliant with PBKDF2WithHmacSHA512, 10000 iterations, 16-byte salt (SecretKeyCredentialHandler)",
            "10.0": "Compliant with PBKDF2WithHmacSHA512, 10000 iterations, 16-byte salt (SecretKeyCredentialHandler)",
            "10.1": "Compliant with PBKDF2WithHmacSHA512, 10000 iterations, 16-byte salt (SecretKeyCredentialHandler)"
        }.get(tomcat_version, "Unknown compliance status")
        
        config_manager.logger.info(f"Compliance Status: {compliance_status}")
        config_manager.logger.info("Overall Status: Secure")
        config_manager.logger.info("Audit completed")

    except Exception as e:
        config_manager.logger.error(f"Error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
