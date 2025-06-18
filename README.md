# Apache Tomcat Password Security Auditor

![Tomcat Configuration Security Auditor Banner](assets/images/banner.jpg)

## Overview

**Apache Tomcat - Password Security Auditor Tool** is a set of tools designed to audit Apache Tomcat user authentication configurations for compliance with **NIST 800-53 IA-5** and **CIS Tomcat Benchmark** standards. This repository includes scripts for both Unix (Linux/macOS) and Windows environments, enabling system administrators and security professionals to evaluate password security across various Tomcat versions.

### Key Features
- **Automated Testing**: Scripts test multiple password types and credential handler configurations, modifying `server.xml` and `tomcat-users.xml` to simulate scenarios and validate compliance.
- **Manual Auditing**: Analyze existing configurations, reporting password types, credential handlers, and compliance status with actionable recommendations.
- **Remote Auditing**: Support for auditing Tomcat configurations on remote Windows servers using PowerShell remoting.
- **Cross-Platform Support**: Bash and Python-based scripts for Unix (Linux/macOS) and PowerShell scripts for Windows.
- **Backup and Restore**: Automatically back up and restore configuration files during testing to prevent data loss.
- **Detailed Logging**: Logs audit and test results to platform-specific locations for traceability.
- **Compliance Reporting**: Identifies secure/insecure configurations and provides guidance for achieving compliance.

### Features
- Checks password types and credential handler configurations.
- Reports compliance status with actionable recommendations.
- Supports local and remote auditing on Windows, and local auditing on Unix.
- Logs results for traceability (CSV for Windows, text for Unix).
- Compatible with Tomcat 7.0, 8.5, 9.0, 10.0, and 10.1.

### Supported Tomcat Versions
| Version | Unix Support | Windows Support | Notes |
|---------|--------------|-----------------|-------|
| 7.0     | ✅           | ✅              | Supports `MessageDigestCredentialHandler` (MD5, SHA-1, SHA-256). |
| 8.5     | ✅           | ✅              | Adds SHA-512 and `NestedCredentialHandler` support. |
| 9.0     | ✅           | ✅              | Includes `SecretKeyCredentialHandler` for PBKDF2. |
| 10.0    | ✅           | ✅              | Supports `SecretKeyCredentialHandler` and `NestedCredentialHandler`. |
| 10.1    | ✅           | ✅              | Identical features to 10.0. |

## Quick Start

### Prerequisites
- **Unix (Linux/macOS)**:
  - Bash or Python 3.6+.
  - Tomcat installed (e.g., `/opt/tomcat`).
  - Sudo permissions for auditing.
- **Windows**:
  - PowerShell 5.1+ (included in Windows 10/11).
  - Tomcat installed (e.g., `C:\tomcat`).
  - Administrator privileges for auditing.
  - PowerShell remoting enabled for remote auditing.
- **Java**: Java 8 for Tomcat 7.0; Java 11 for 8.5, 9.0, 10.0, 10.1.

### Clone Repository
```bash
git clone https://github.com/ZeroXSHDW/Apache-Tomcat-Password-Security-Audit ~/tomcat-audit
cd ~/tomcat-audit
```
For Windows:
```powershell
git clone https://github.com/ZeroXSHDW/Apache-Tomcat-Password-Security-Audit C:\Users\<User>\tomcat-audit
cd C:\Users\<User>\tomcat-audit
```

## Usage

### 1. Unix: Audit Local Configuration (Bash)
Run the Unix Bash auditing script:
```bash
sudo ./CheckTomcatConfigUnixBash.sh
```
- **Output**: Logs to `/tmp/TomcatManager.log`.
- **Example Output**:
```
07:05 PM IST, Tuesday, May 20, 2025
server01
===========================
Config Path: /opt/tomcat/conf
Tomcat Version: 9.0
Auditing server.xml
Server Configuration:
  Status: Compliant for Tomcat 9.0
  Credential Handler: org.apache.catalina.realm.SecretKeyCredentialHandler
  Algorithm: PBKDF2WithHmacSHA512
  Iterations: 10000
  Salt Length: 16
Auditing tomcat-users.xml
User Audit Results:
Username | Password Type | Compliance
---------|---------------|-----------
    testuser | Salted_PBKDF2 | Compliant
===========================
Overall Status: Secure
Audit completed. Log: /tmp/TomcatManager.log
```

### 2. Unix: Audit Local Configuration (Python)
Run the Unix Python auditing script:
```bash
sudo ./CheckTomcatConfigUnixPython.py
```
- **Output**: Logs to `/tmp/TomcatManager.log`.
- **Example Output**:
```
07:05 PM IST, Tuesday, May 20, 2025
server01
===========================
Config Path: /opt/tomcat/conf
Tomcat Version: 9.0
Auditing server.xml
Server Configuration:
  Status: Compliant for Tomcat 9.0
  Credential Handler: org.apache.catalina.realm.SecretKeyCredentialHandler
  Algorithm: PBKDF2WithHmacSHA512
  Iterations: 10000
  Salt Length: 16
Auditing tomcat-users.xml
User Audit Results:
Username | Password Type | Compliance
---------|---------------|-----------
    testuser | Salted_PBKDF2 | Compliant
===========================
Overall Status: Secure
Audit completed. Log: /tmp/TomcatManager.log
```

### 3. Windows: Audit Local Configuration
Run the Windows auditing script:
```powershell
.\CheckTomcatConfigWin.ps1
```
- **Output**: Logs to `$env:LOCALAPPDATA\Temp\TestTomcatConfig.csv` (e.g., `C:\Users\<User>\AppData\Local\Temp`).
- **Example Output**:
```
Checking Apache Tomcat configuration security...
Tomcat configuration directory located at C:\Program Files\Apache Software Foundation\Tomcat 10.0\conf
Detected Tomcat version 10.0 at C:\Program Files\Apache Software Foundation\Tomcat 10.0\conf
User 'testuser': Compliant
Overall Configuration: Secure
Audit completed
```
- **Log File Content (TestTomcatConfig.csv)**:
```
Timestamp,Message
2025-05-20 17:35:00,Checking Apache Tomcat configuration security...;Tomcat configuration directory located at C:\Program Files\Apache Software Foundation\Tomcat 10.0\conf;Detected Tomcat version 10.0 at C:\Program Files\Apache Software Foundation\Tomcat 10.0\conf;User 'testuser': Compliant;Overall Configuration: Secure;Audit completed
```

### 4. Windows: Audit Remote Configuration
Run the remote auditing script:
```powershell
$cred = Get-Credential
.\Remote_CheckTomcatConfigWin.ps1 -ServerName Windows-Server -Credential $cred
```
- **Output**: Logs to `C:\Temp\TomcatConfigCheck.csv`.
- **Example Output**:
```
[Client] Starting script execution at 2025-05-20 17:35:00.
[Windows-Server] Checking Apache Tomcat configuration security on Windows-Server...
[Windows-Server] Tomcat configuration directory located at C:\Program Files\Apache Software Foundation\Tomcat 10.0\conf
[Windows-Server] Detected Tomcat version 10.0 at C:\Program Files\Apache Software Foundation\Tomcat 10.0\conf
[Windows-Server] User 'testuser': Compliant
[Windows-Server] Overall Configuration: Secure
[Windows-Server] Audit completed
```
- **Log File Content (TomcatConfigCheck.csv)**:
```
Timestamp,Server,Message
2025-05-20 17:35:00,Windows-Server,[Windows-Server] Checking Apache Tomcat configuration security on Windows-Server...;[Windows-Server] Tomcat configuration directory located at C:\Program Files\Apache Software Foundation\Tomcat 10.0\conf;[Windows-Server] Detected Tomcat version 10.0 at C:\Program Files\Apache Software Foundation\Tomcat 10.0\conf;[Windows-Server] User 'testuser': Compliant;[Windows-Server] Overall Configuration: Secure;[Windows-Server] Audit completed
```
- **Multiple Servers**:
```powershell
$cred = Get-Credential
.\Remote_CheckTomcatConfigWin.ps1 -ServerName Server1,Server2 -Credential $cred
```
- **Custom Path** (optional):
```powershell
$cred = Get-Credential
.\彼此:.\Remote_CheckTomcatConfigWin.ps1 -ServerName Windows-Server -TomcatConfPath "C:\tomcat\conf" -Credential $cred
```

## Testing Framework

**WARNING**: The testing framework modifies system configurations, including `server.xml` and `tomcat-users.xml`, and installs/uninstalls Tomcat instances. It is **strictly for use in test labs** to verify that the auditing scripts function correctly. **Do not use on production systems**, as it may disrupt services or cause data loss. Use only in controlled lab environments.

The testing framework validates the auditing scripts by simulating various Tomcat configurations and password types to ensure they correctly identify compliance issues. It includes installation scripts to set up test environments.

### Installation for Testing
Use these commands to install Tomcat for testing the auditing scripts. These are optional and only needed for validation.

#### Unix
Install Tomcat:
```bash
sudo ./tomcat_manager.sh install 9    # Install Tomcat 9.0
```
Uninstall Tomcat:
```bash
sudo ./tomcat_manager.sh uninstall
```
Install dependencies:
```bash
sudo apt install python3 openjdk-11-jdk  # Ubuntu/Debian/Kali
sudo yum install python3 java-11-openjdk-devel  # CentOS/RHEL
```

#### Windows
Install Tomcat:
```powershell
.\TomcatManager.ps1 install 9    # Install Tomcat 9.0
```
Uninstall Tomcat:
```powershell
.\TomcatManager.ps1 uninstall
```
Install Java (if needed):
- Download Java 11 from `https://adoptium.net/`.
- Set `JAVA_HOME`:
```powershell
[Environment]::SetEnvironmentVariable("JAVA_HOME", "C:\Program Files\Java\jdk-11", "Machine")
```

### Run Tests
#### Unix
```bash
sudo ./test_config_unix.py
```
- Logs to `~/TestTomcatConfig.log`.
- Tests 42 configurations per Tomcat version (7.0, 8.5, 9.0, 10.0, 10.1).

#### Windows
```powershell
.\test_config_win.ps1
```
- Logs to `$env:LOCALAPPDATA\Temp\TestTomcatConfig.log`.
- Tests 15–42 configurations per Tomcat version.

## Configuration Recommendations
For optimal compliance:
- **Tomcat 7.0**: Use `MessageDigestCredentialHandler` with SHA-256.
- **Tomcat 8.5**: Use `MessageDigestCredentialHandler` with SHA-512, ≥10,000 iterations, ≥16-byte salt.
- **Tomcat 9.0/10.0/10.1**: Use `SecretKeyCredentialHandler` with PBKDF2WithHmacSHA512, ≥10,000 iterations, ≥16-byte salt.

Example `server.xml` (Tomcat 9.0+):
```xml
<Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
  <CredentialHandler className="org.apache.catalina.realm.SecretKeyCredentialHandler"
                    algorithm="PBKDF2WithHmacSHA512"
                    iterations="10000"
                    saltLength="16"
                    keyLength="256"/>
</Realm>
```

Example `tomcat-users.xml`:
```xml
<tomcat-users>
  <user username="testuser" password="4b6f7e8c9d0a1b2c3d4e5f60718293a4:1234567890abcdef" roles="manager"/>
</tomcat-users>
```
## Directory Descriptions

```
Apache-Tomcat-Password-Security-Audit/
├── docs/                      # Documentation
│   ├── README.md             # Main documentation
│   └── LICENSE               # License file
├── src/                      # Source code
│   ├── unix/                 # Unix-specific scripts
│   │   ├── scripts/         # Unix shell scripts
│   │   └── python/          # Unix Python scripts
│   ├── windows/             # Windows-specific scripts
│   │   ├── powershell/      # PowerShell scripts
│   │   └── batch/          # Batch scripts
│   └── common/              # Common utilities
├── tests/                    # Test framework
│   ├── unix/                # Unix tests
│   └── windows/             # Windows tests
├── assets/                   # Static assets
│   └── images/              # Images and other media
└── install/                  # Installation and management scripts
    ├── unix/                # Unix installation and management
    └── windows/             # Windows installation and management
```

## Directory Descriptions

- **docs/**: Contains all project documentation including the main README and LICENSE files
- **src/**: Contains all source code organized by platform
  - **unix/**: Unix-specific scripts and utilities
  - **windows/**: Windows-specific scripts and utilities
  - **common/**: Shared utilities used across platforms
- **tests/**: Contains all test files organized by platform
- **assets/**: Contains static assets like images
- **install/**: Contains installation and management scripts for different platforms

## Troubleshooting
- **Tomcat Not Found**:
  - Verify installation path (e.g., `/opt/tomcat` or `C:\tomcat`).
  - Ensure `server.xml` and `tomcat-users.xml` exist in the `conf` directory.
- **Unix Permissions**:
  - Run with `sudo`.
  - Check write access to `/tmp` and Tomcat’s `conf` directory.
- **Windows Permissions**:
  - Run PowerShell as Administrator.
  - Ensure write access to `$env:LOCALAPPDATA\Temp` and `C:\Temp`.
- **Remote Auditing**:
  - Enable PowerShell remoting:
    ```powershell
    Enable-PSRemoting -Force
    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value "Server-IP" -Concatenate -Force
    ```
  - Test connectivity:
    ```powershell
    Test-WSMan Server-IP
    ```
- **Java Issues**:
  - Verify Java version:
    ```bash
    java -version
    ```
    ```powershell
    java -version
    ```

## License
Licensed under the Apache 2.0 License. See `LICENSE` for details.
