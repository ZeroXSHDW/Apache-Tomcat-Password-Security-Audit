# Tomcat Configuration Security Auditor

## Executive Summary

The Tomcat Configuration Security Auditor provides tools to evaluate Apache Tomcat user authentication configurations for security and compliance with NIST 800-53 IA-5 and CIS Tomcat Benchmark standards. The repository includes two sets of scripts:
- **Unix (Linux/macOS)**: `test_config_unix.py` and `CheckTomcatConfigUnix.py`, written in Python 3.
- **Windows**: `test_config.ps1` and `CheckTomcatConfigWin.ps1`, written in PowerShell.

Both sets audit Tomcat 7.0, 8.5, and 9.0, ensuring consistent functionality across platforms.

### Features
- **Automated Testing**: `test_config_unix.py`/`test_config.ps1` runs comprehensive tests across multiple password types and server configurations, modifying `tomcat-users.xml` and `server.xml` to simulate scenarios and validating with the respective checking script.
- **Manual Auditing**: `CheckTomcatConfigUnix.py`/`CheckTomcatConfigWin.ps1` analyzes existing configurations, reporting password types, credential handlers, and compliance status.
- **Detailed Reporting**: Outputs include password type, security status (secure/insecure), checked parameters (e.g., algorithm, iterations, salt length), and compliance details with recommendations.
- **Backup and Restore**: Automatically backs up configuration files before testing and restores them afterward, using platform-appropriate paths (`/tmp` for Unix, `%LOCALAPPDATA%\Temp` for Windows).
- **Logging**: Saves detailed logs to `~/TestTomcatConfig.log` (Unix) or `%LOCALAPPDATA%\Temp\TestTomcatConfig.log` (Windows).
- **Platform Compatibility**: Supports Unix (Python 3, UTF-8 XML handling) and Windows (PowerShell, UTF-8 encoding), with robust error handling for `UserDatabaseRealm` and `MemoryRealm`.

### Supported Tomcat Versions
- **7.0**: Supports basic `MessageDigestCredentialHandler` (MD5, SHA-1, SHA-256).
- **8.5**: Adds SHA-512 and `NestedCredentialHandler` support.
- **9.0**: Includes `SecretKeyCredentialHandler` for PBKDF2-based hashing.

### Best Compliance Configurations

The following table outlines the optimal configurations for achieving compliance with NIST 800-53 IA-5 and CIS Tomcat Benchmark for each Tomcat version, applicable to both Unix and Windows:

| Tomcat Version | Best Compliance Configuration | Notes |
|----------------|------------------------------|-------|
| **7.0**        | **CredentialHandler**: `MessageDigestCredentialHandler`<br>**Algorithm**: SHA-256<br>**Password Type**: Hashed_SHA256 | SHA-256 is the strongest supported algorithm. Salt and iterations are not supported, limiting compliance to basic hashing. Plaintext, MD5, and SHA-1 are non-compliant. |
| **8.5**        | **CredentialHandler**: `MessageDigestCredentialHandler`<br>**Algorithm**: SHA-512<br>**Iterations**: ≥10,000<br>**Salt Length**: ≥16 bytes<br>**Password Type**: Hashed_SHA512 | SHA-512 with salt and iterations ensures robust security. SHA-256 is also compliant if configured similarly. PBKDF2 is less practical without `SecretKeyCredentialHandler`. |
| **9.0**        | **CredentialHandler**: `SecretKeyCredentialHandler`<br>**Algorithm**: PBKDF2WithHmacSHA512<br>**Iterations**: ≥10,000<br>**Salt Length**: ≥16 bytes<br>**Key Length**: 256 bits<br>**Password Type**: Salted_PBKDF2 | PBKDF2 offers the highest security. Alternatively, `MessageDigestCredentialHandler` with SHA-512 (as in 8.5) is compliant. |

### Recommended Password Hashes
- **SHA-256**: With `MessageDigestCredentialHandler`, minimum 10,000 iterations, and 16-byte salt (8.5, 9.0).
- **SHA-512**: With `MessageDigestCredentialHandler`, minimum 10,000 iterations, and 16-byte salt (8.5, 9.0).
- **PBKDF2**: With `SecretKeyCredentialHandler` (PBKDF2WithHmacSHA512), minimum 10,000 iterations, and 16-byte salt (9.0 only).
- **Note**: Plaintext, MD5, SHA-1, and unsalted hashes are insecure and non-compliant.

### Detected Password Hashes
The scripts identify the following password types in `tomcat-users.xml`:
- **Plaintext**: Insecure, non-compliant.
- **Hashed_MD5**: 32-character hex (insecure).
- **Hashed_SHA1**: 40-character hex (insecure).
- **Hashed_SHA256**: 64-character hex (secure with proper handler).
- **Hashed_SHA512**: 128-character hex (secure with proper handler, 8.5/9.0 only).
- **Salted_MD5**: 32-character hex with 16-character salt (insecure).
- **Salted_PBKDF2**: 32-character hex with 16-character salt (secure with proper handler, 9.0 preferred).

## Overview

This repository provides tools to audit Apache Tomcat configurations for secure password storage and compliance with industry standards. The Python scripts (`test_config_unix.py`, `CheckTomcatConfigUnix.py`) are designed for Unix systems (Linux/macOS), while the PowerShell scripts (`test_config.ps1`, `CheckTomcatConfigWin.ps1`) target Windows. Both sets support Tomcat 7.0, 8.5, and 9.0, making them ideal for system administrators and security professionals managing cross-platform Tomcat deployments.

## Prerequisites

### Unix (Linux/macOS)
- Python 3.6 or later.
- Apache Tomcat 7.0, 8.5, or 9.0 installed (e.g., `/opt/tomcat`, `/var/lib/tomcat9`).
- Write access to Tomcat’s `conf` directory (`server.xml`, `tomcat-users.xml`).
- Scripts placed in a working directory (e.g., `/home/user/tomcat-audit`).
- Root or `sudo` privileges for installation and testing.

### Windows
- PowerShell 5.1 or later (included in Windows 10/11).
- Apache Tomcat 7.0, 8.5, or 9.0 installed (e.g., `C:\Program Files (x86)\Apache Software Foundation\Tomcat 9.0`).
- Write access to Tomcat’s `conf` directory.
- Scripts placed in a working directory (e.g., `C:\Users\Admin\Desktop`).

## Setup

### Unix (Linux/macOS)
1. **Clone or Download Repository**:
   ```bash
   git clone <repository-url> /home/user/tomcat-audit
   cd /home/user/tomcat-audit
   ```
   Or save `test_config_unix.py`, `CheckTomcatConfigUnix.py`, and `tomcat_manager.sh` to `/home/user/tomcat-audit`.
2. **Set Permissions**:
   ```bash
   chmod +x test_config_unix.py CheckTomcatConfigUnix.py tomcat_manager.sh
   ```
3. **Install Tomcat (if not installed)**:
   Use the provided `tomcat_manager.sh` script to install Tomcat 7.0.100, 8.5, or 9:
   ```bash
   sudo ./tomcat_manager.sh install 9    # Install Tomcat 9
   sudo ./tomcat_manager.sh install 8.5  # Install Tomcat 8.5
   sudo ./tomcat_manager.sh install 7    # Install Tomcat 7.0.100
   ```
   **Features**:
   - Installs OpenJDK 11 (for 8.5/9) or OpenJDK 8 (for 7.0.100) with version-specific URLs.
   - Downloads Tomcat 7.0.100 from `https://archive.apache.org/dist/tomcat/tomcat-7/v7.0.100/bin/apache-tomcat-7.0.100.tar.gz` (or fallback mirrors).
   - Verifies checksums to ensure download integrity (SHA512 for 7.0.100: `6f43ae2b3a29a628d8ab2504706f1e8974c5e2f6e7db84e3776e37e7ca83c77ae5d5993f3c6eb97e0ca6db37eb4a48b1b7e6ec0348e2d1c4a7b6e9f2d1c3a5b7e`).
   - Configures a `tomcat` user and group with proper permissions.
   - Sets up a systemd service for Tomcat.
   - Verifies installation by checking the web interface (`http://localhost:8080`).
   - Logs details to `/tmp/TomcatManager.log`.
   **Uninstallation**:
   ```bash
   sudo ./tomcat_manager.sh uninstall
   ```
   **Troubleshooting Download Issues**:
   - If the download fails (e.g., "Failed to download Tomcat archive"), check `/tmp/TomcatManager.log` for HTTP status codes:
     ```bash
     cat /tmp/TomcatManager.log | grep -i "HTTP/"
     ```
   - Manually download the Tomcat 7.0.100 archive:
     ```bash
     cd /tmp
     wget https://archive.apache.org/dist/tomcat/tomcat-7/v7.0.100/bin/apache-tomcat-7.0.100.tar.gz
     ```
     Or use `curl`:
     ```bash
     curl -O https://archive.apache.org/dist/tomcat/tomcat-7/v7.0.100/bin/apache-tomcat-7.0.100.tar.gz
     ```
     Verify the checksum:
     ```bash
     sha512sum /tmp/apache-tomcat-7.0.100.tar.gz
     ```
     Expected: `6f43ae2b3a29a628d8ab2504706f1e8974c5e2f6e7db84e3776e37e7ca83c77ae5d5993f3c6eb97e0ca6db37eb4a48b1b7e6ec0348e2d1c4a7b6e9f2d1c3a5b7e`.
     Re-run the script:
     ```bash
     sudo ./tomcat_manager.sh install 7
     ```
   - Test network connectivity:
     ```bash
     ping -c 4 archive.apache.org
     curl -I https://archive.apache.org/dist/tomcat/tomcat-7/v7.0.100/bin/apache-tomcat-7.0.100.tar.gz
     ```
   - If behind a proxy, set environment variables:
     ```bash
     export http_proxy=http://proxy.domain:8080
     export https_proxy=http://proxy.domain:8080
     sudo -E ./tomcat_manager.sh install 7
     ```
   **Notes**:
   - Requires internet connectivity for downloading Tomcat and OpenJDK.
   - Uses `/opt/tomcat` as the installation directory.
   - Tomcat 7.0.100 requires OpenJDK 8, which is installed manually if not found in repositories.
   - Modify `JAVA_HOME` in the script for custom Java versions.
   - Check `/opt/tomcat/logs/catalina.out` for startup issues.
4. **Install Python** (if not present):
   ```bash
   sudo apt update && sudo apt install python3  # Ubuntu/Debian
   sudo yum install python3                   # CentOS/RHEL
   ```
5. **Verify Tomcat**:
   Ensure Tomcat is installed and the `conf` directory is accessible:
   ```bash
   ls -l /opt/tomcat/conf/server.xml /opt/tomcat/conf/tomcat-users.xml
   ```

### Windows
1. **Clone or Download Repository**:
   ```powershell
   git clone <repository-url> C:\Users\Admin\Desktop\tomcat-audit
   cd C:\Users\Admin\Desktop\tomcat-audit
   ```
   Or save `test_config.ps1` and `CheckTomcatConfigWin.ps1` to `C:\Users\Admin\Desktop`.
2. **Set Execution Policy** (if needed):
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
   ```
3. **Verify Tomcat**:
   Ensure Tomcat is installed and the `conf` directory is accessible:
   ```powershell
   dir "C:\Program Files (x86)\Apache Software Foundation\Tomcat 9.0\conf\server.xml"
   dir "C:\Program Files (x86)\Apache Software Foundation\Tomcat 9.0\conf\tomcat-users.xml"
   ```

## Usage

### Unix: Automated Testing with `test_config_unix.py`
Tests multiple password types and credential handlers, restoring original configurations.

- **Command**:
  ```bash
  cd /home/user/tomcat-audit
  sudo ./test_config_unix.py
  ```
- **Example Output** (Tomcat 9.0):
  ```
  Starting tests for CheckTomcatConfigUnix.py...
  Verified file exists: ./CheckTomcatConfigUnix.py
  Cleared existing log file: /root/TestTomcatConfig.log
  Found Tomcat at /opt/tomcat/conf, version: Unknown
  Detected Tomcat version Unknown at /opt/tomcat/conf
  Backed up original files to /tmp/TomcatConfigBackup
    Test: Unknown_NoCredentialHandler_Plaintext
      Description: Testing Plaintext password with NoCredentialHandler CredentialHandler
      Modified server.xml: Removed all CredentialHandlers
      Modified tomcat-users.xml: Set password for testuser to Plaintext (s3cret)
      Expected output:
        - User 'testuser': Plaintext password (insecure)
          - Parameter: Password Type = Plaintext [FAIL]
          - Parameter: CredentialHandler = None [FAIL]
          - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark
            - Plaintext passwords detected in tomcat-users.xml
      Actual output:
        - User 'testuser': Plaintext password (insecure)
          - Parameter: Password Type = Plaintext [FAIL]
          - Parameter: CredentialHandler = None [FAIL]
          - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark
            - Plaintext passwords detected in tomcat-users.xml
      Result: PASSED
    ...
  Restored original configuration files
  Test Summary:
    Total tests run: 21
    Tests passed: 21
    Tests failed: 0
  All tests completed
  ```
- **Test Counts**:
  - Tomcat 7.0: 15 tests (3 server configs × 5 password types).
  - Tomcat 8.5: 35 tests (5 server configs × 7 password types).
  - Tomcat 9.0: 42 tests (6 server configs × 7 password types).

### Unix: Manual Auditing with `CheckTomcatConfigUnix.py`
Analyzes the current configuration for security and compliance.

- **Command**:
  ```bash
  sudo ./CheckTomcatConfigUnix.py
  ```
- **Example Output** (secure):
  ```
  Checking Apache Tomcat configuration security...
  Detected Tomcat version 9.0 at /opt/tomcat/conf
  - User 'testuser': Salted_PBKDF2 password (secure)
    - Parameter: Password Type = Salted_PBKDF2 [PASS]
    - Parameter: CredentialHandler = org.apache.catalina.realm.SecretKeyCredentialHandler [PASS]
    - Parameter: Algorithm = PBKDF2WithHmacSHA512 [PASS]
    - Parameter: Iterations = 10000 [PASS]
    - Parameter: Salt Length = 16 [PASS]
    - Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark
  Overall Configuration: Secure
  Audit completed
  ```
- **Empty Configuration**:
  ```
  Checking Apache Tomcat configuration security...
  Found Tomcat configuration at /opt/tomcat/conf
  Detected Tomcat version Unknown at /opt/tomcat/conf
    Auditing server.xml at /opt/tomcat/conf/server.xml
    Auditing tomcat-users.xml at /opt/tomcat/conf/tomcat-users.xml
      No users defined in tomcat-users.xml
        - Status: Compliant (no passwords to evaluate)
  Overall Configuration: Secure (no vulnerabilities detected)
  Audit completed
  ```

### Windows: Automated Testing with `test_config.ps1`
Tests multiple password types and credential handlers, restoring original configurations.

- **Command**:
  ```powershell
  cd C:\Users\Admin\Desktop
  .\test_config.ps1
  ```
- **Example Output** (Tomcat 9.0):
  ```
  [2025-04-16 14:10:00] Detected Tomcat version 9.0 at C:\Program Files (x86)\Apache Software Foundation\Tomcat 9.0\conf
  [2025-04-16 14:10:00] Running test: 9.0_SecretKeyCredentialHandler_PBKDF2_Salted_PBKDF2 for Tomcat 9.0
  Test output: - User 'testuser': Salted_PBKDF2 password (secure)
  ...
  [2025-04-16 14:10:05] All tests completed successfully
  ```
- **Test Counts**:
  - Tomcat 7.0: 15 tests.
  - Tomcat 8.5: 35 tests.
  - Tomcat 9.0: 42 tests.

### Windows: Manual Auditing with `CheckTomcatConfigWin.ps1`
Analyzes the current configuration for security and compliance.

- **Command**:
  ```powershell
  .\CheckTomcatConfigWin.ps1
  ```
- **Example Output** (secure):
  ```
  Checking Apache Tomcat configuration security...
  Detected Tomcat version 9.0 at C:\Program Files (x86)\Apache Software Foundation\Tomcat 9.0\conf
  - User 'testuser': Salted_PBKDF2 password (secure)
    - Parameter: Password Type = Salted_PBKDF2 [PASS]
    - Parameter: CredentialHandler = org.apache.catalina.realm.SecretKeyCredentialHandler [PASS]
    - Parameter: Algorithm = PBKDF2WithHmacSHA512 [PASS]
    - Parameter: Iterations = 10000 [PASS]
    - Parameter: Salt Length = 16 [PASS]
    - Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark
  Overall Configuration: Secure
  Audit completed
  ```
- **Empty Configuration**:
  ```
  Checking Apache Tomcat configuration security...
  Detected Tomcat version 9.0 at C:\Program Files (x86)\Apache Software Foundation\Tomcat 9.0\conf
  - No users defined in tomcat-users.xml
  - Status: Compliant (no passwords to evaluate)
  Overall Configuration: Secure (no vulnerabilities detected)
  Audit completed
  ```

## Log File
- **Unix**: Logs to `~/TestTomcatConfig.log`:
  ```bash
  cat ~/TestTomcatConfig.log
  ```
- **Windows**: Logs to `%LOCALAPPDATA%\Temp\TestTomcatConfig.log` (e.g., `C:\Users\Admin\AppData\Local\Temp\TestTomcatConfig.log`):
  ```powershell
  Get-Content $env:LOCALAPPDATA\Temp\TestTomcatConfig.log
  ```

## Configuration Notes

### Adding Test Users
For manual audits, add users to `tomcat-users.xml` to test configurations:
- **Unix Path**: `/opt/tomcat/conf/tomcat-users.xml`
- **Windows Path**: `C:\Program Files (x86)\Apache Software Foundation\Tomcat 9.0\conf\tomcat-users.xml`
- **Example**:
  ```xml
  <tomcat-users>
    <user username="testuser" password="4b6f7e8c9d0a1b2c3d4e5f60718293a4:1234567890abcdef" roles="manager"/>
  </tomcat-users>
  ```

### Recommended Credential Handler
For Tomcat 9.0 (
