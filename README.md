# Apache Tomcat Password Security Auditor

![Tomcat Configuration Security Auditor Banner](assets/images/banner.jpg)

## Overview

**Apache Tomcat - Password Security Auditor Tool** is a set of tools designed to audit and patch Apache Tomcat user authentication configurations for compliance with **NIST 800-53 IA-5** and **CIS Tomcat Benchmark** standards. This repository includes scripts for both Unix (Linux/macOS) and Windows environments, enabling system administrators and security professionals to evaluate and secure password configurations across various Tomcat versions.

### Key Features
- **Automated Testing**: Scripts test multiple password types and credential handler configurations, modifying `server.xml` and `tomcat-users.xml` to simulate scenarios and validate compliance.
- **Manual Auditing**: Analyze existing configurations, reporting password types, credential handlers, and compliance status with actionable recommendations.
- **Automated Patching**: Convert plaintext passwords to compliant hashes, update configuration files, and restart Tomcat services.
- **Remote Auditing**: Support for auditing Tomcat configurations on remote Windows servers using PowerShell remoting.
- **Cross-Platform Support**: Bash scripts for Unix (Linux/macOS) and PowerShell scripts for Windows.
- **Backup and Restore**: Automatically back up and restore configuration files during auditing and patching to prevent data loss.
- **Detailed Logging**: Logs audit and patch results to platform-specific locations for traceability.
- **Compliance Reporting**: Identifies secure/insecure configurations and provides guidance for achieving compliance.

### Features
- Checks password types and credential handler configurations.
- Converts plaintext passwords to secure hashes (SHA-256, SHA-512, PBKDF2WithHmacSHA512) based on Tomcat version.
- Reports compliance status with actionable recommendations.
- Supports local and remote auditing on Windows, and local auditing/patching on Unix.
- Logs results for traceability (CSV for all platforms).
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
  - Bash shell.
  - Tomcat installed (e.g., `/opt/tomcat`).
  - Sudo permissions for auditing and patching.
- **Windows**:
  - PowerShell 5.1+ (included in Windows 10/11).
  - Tomcat installed (e.g., `C:\Program Files\Apache Software Foundation\Tomcat`).
  - Administrator privileges for auditing and patching.
  - PowerShell remoting enabled for remote auditing.
- **Java**: Java 8 for Tomcat 7.0; Java 11 for 8.5, 9.0, 10.0, 10.1.

### Secure Tomcat Installation (Recommended)

For automated, secure installation of Tomcat (all supported versions), use the install scripts provided in the `install/` directory. These scripts handle download, extraction, Java setup, secure user configuration, and service management for both Windows and Unix.

See [install/README.md](install/README.md) for full instructions and usage examples.

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
Run the Unix Bash auditing script to check compliance:
```bash
sudo ./src/unix/Audit/bash/CheckTomcatConfigUnixBash.sh
```
- **Output**: Logs to `/tmp/TomcatManager.csv`.
- **Example Output**:
```
07:05 PM IST, Tuesday, May 20, 2025
server01
===========================
Config Path: /opt/tomcat/conf
Checking for running Tomcat processes...
Found running Tomcat process (PID: 1234)
  - Check process details with: ps -ef | grep 1234
  - Found CATALINA_HOME from process: /opt/tomcat/conf
  - Tomcat may be running from an alternate installation
server.xml is owned by root
server.xml permissions are secure (0o640)
tomcat-users.xml is owned by root
tomcat-users.xml permissions are secure (0o640)
Tomcat Home: /opt/tomcat
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
Audit completed. Log: /tmp/TomcatManager.csv
```

### 2. Unix: Patch Local Configuration (Bash)
Run the Unix Bash patching script to convert plaintext passwords to compliant hashes and update configurations:
```bash
sudo ./src/unix/Patch/bash/UpdateTomcatUserUnix.sh
```
- **Output**: Logs to `/tmp/TomcatManager.csv`.
- **Example Output**:
```
Execution Time: 2025-06-18 13:58:00
Hostname: server01
===========================
Found valid Tomcat configuration at: /opt/tomcat/conf
Tomcat Home: /opt/tomcat
Config Path: /opt/tomcat/conf
Tomcat Version: 9.0
Reading /opt/tomcat/conf/tomcat-users.xml for users with plaintext passwords
Found 2 user(s) with plaintext passwords
  Processing user: testuser (Original plaintext password: [REDACTED])
  Generated Hash for testuser: hash1:salt1
  Processing user: admin (Original plaintext password: [REDACTED])
  Generated Hash for admin: hash2:salt2
Updating /opt/tomcat/conf/tomcat-users.xml with new hashes
Updating /opt/tomcat/conf/server.xml for compliance
Restarting Tomcat to apply changes
Compliance Status: Compliant with PBKDF2WithHmacSHA512, 10000 iterations, 16-byte salt (SecretKeyCredentialHandler)
===========================
Overall Status: Secure
Audit completed
```
- **Optional Custom Path**:
```bash
sudo ./src/unix/Patch/bash/UpdateTomcatUserUnix.sh --custom-conf=/opt/tomcat/conf
```

### 3. Windows: Audit, Patch, and Remote Audit

#### Local Audit
```powershell
.\src\windows\Audit\powershell\CheckTomcatConfigWin.ps1
```
- **Output**: Logs to `$env:LOCALAPPDATA\Temp\TomcatManager.csv` (e.g., `C:\Users\<User>\AppData\Local\Temp`).
- **Example Output**:
```
Checking Apache Tomcat configuration security...
##############################################################WIN-SERVER###############################################################
Execution Time: 2025-06-18 13:35:00
HOSTNAME: WIN-SERVER
===========================
Searching common Tomcat configuration paths...
Found Tomcat configuration at: C:\Program Files\Apache Software Foundation\Tomcat\conf
Config Path: C:\Program Files\Apache Software Foundation\Tomcat\conf
Tomcat Home: C:\Program Files\Apache Software Foundation\Tomcat
WARNING: Tomcat process (PID 1234) is running as NT AUTHORITY\SYSTEM. This is a security risk.
Validating Tomcat installation at C:\Program Files\Apache Software Foundation\Tomcat
Tomcat installation validation passed
Tomcat Version: 10.0
Auditing server.xml
Server Configuration:
    - Recommendation: Use PBKDF2WithHmacSHA512 or SHA-256 with at least 10,000 iterations and 16+ salt length.
    - Example: <CredentialHandler className='org.apache.catalina.realm.SecretKeyCredentialHandler' algorithm='PBKDF2WithHmacSHA512' iterations='10000' saltLength='16'/>
  Credential Handler: org.apache.catalina.realm.SecretKeyCredentialHandler
  Algorithm: PBKDF2WithHmacSHA512
  Iterations: 10000
  Salt Length: 16
  Status: Compliant
Auditing tomcat-users.xml
    User Audit Results:
    Username | Password Type | Compliance
    ---------|---------------|-----------
    testuser | Hashed_SHA256 | Compliant
===========================
Overall Status: Secure
Audit completed. Log: C:\Users\<User>\AppData\Local\Temp\TomcatManager.csv
```

#### Local Patch
```powershell
.\src\windows\Patch\powershell\UpdateTomcatUserWin.ps1
```
- **Output**: Logs to `$env:LOCALAPPDATA\Temp\TomcatManager.csv`.
- **Example Output**:
```
Execution Time: 2025-06-18 13:53:00
Hostname: WIN-SERVER
===========================
Found valid Tomcat configuration at: C:\Program Files\Apache Software Foundation\Tomcat\conf
Tomcat Home: C:\Program Files\Apache Software Foundation\Tomcat
Config Path: C:\Program Files\Apache Software Foundation\Tomcat\conf
Tomcat Version: 9.0
Found 2 user(s) with plaintext passwords
    Processing user: testuser (Original plaintext password: [REDACTED])
    Generated Hash for testuser: hash1:salt1
    Processing user: admin (Original plaintext password: [REDACTED])
    Generated Hash for admin: hash2:salt2
Updating C:\Program Files\Apache Software Foundation\Tomcat\conf\tomcat-users.xml with new hashes
Updating C:\Program Files\Apache Software Foundation\Tomcat\conf\server.xml for compliance
Restarting Tomcat to apply changes
Compliance Status: Compliant with PBKDF2WithHmacSHA512, 10000 iterations, 16-byte salt (SecretKeyCredentialHandler)
===========================
Overall Status: Secure
Audit completed
```
- **Optional Custom Path**:
```powershell
.\src\windows\Patch\powershell\UpdateTomcatUserWin.ps1 -TomcatConfPath "C:\Program Files\Apache Software Foundation\Tomcat\conf"
```

#### Remote Audit
```powershell
$cred = Get-Credential
.\src\windows\Audit\powershell\Remote_CheckTomcatConfigWin.ps1 -ServerName WIN-SERVER -Credential $cred
```
- **Output**: Logs to `C:\Temp\TomcatConfigCheck.csv` on the client.
- **Example Output**:
```
[Client] Starting script execution at 2025-06-18 13:35:00.
[WIN-SERVER] Checking Apache Tomcat configuration security on WIN-SERVER...
[WIN-SERVER] ##############################################################WIN-SERVER###############################################################
[WIN-SERVER] Execution Time: 2025-06-18 13:35:00
[WIN-SERVER] HOSTNAME: WIN-SERVER
[WIN-SERVER] ===========================
[WIN-SERVER] Searching common Tomcat configuration paths...
[WIN-SERVER] Found Tomcat configuration at: C:\Program Files\Apache Software Foundation\Tomcat\conf
[WIN-SERVER] Tomcat Home: C:\Program Files\Apache Software Foundation\Tomcat
[WIN-SERVER] WARNING: Tomcat process (PID 1234) is running as NT AUTHORITY\SYSTEM. This is a security risk.
[WIN-SERVER] Tomcat Version: 10.0
[WIN-SERVER] Auditing server.xml
[WIN-SERVER] Server Configuration:
[WIN-SERVER]     - Recommendation: Use PBKDF2WithHmacSHA512 or SHA-256 with at least 10,000 iterations and 16+ salt length.
[WIN-SERVER]     - Example: <CredentialHandler className='org.apache.catalina.realm.SecretKeyCredentialHandler' algorithm='PBKDF2WithHmacSHA512' iterations='10000' saltLength='16'/>
[WIN-SERVER]   Credential Handler: org.apache.catalina.realm.SecretKeyCredentialHandler
[WIN-SERVER]   Algorithm: PBKDF2WithHmacSHA512
[WIN-SERVER]   Iterations: 10000
[WIN-SERVER]   Salt Length: 16
[WIN-SERVER]   Status: Compliant
[WIN-SERVER] Auditing tomcat-users.xml
[WIN-SERVER]     User Audit Results:
[WIN-SERVER]     Username | Password Type | Compliance
[WIN-SERVER]     ---------|---------------|-----------
[WIN-SERVER]     testuser | Hashed_SHA256 | Compliant
[WIN-SERVER] ===========================
[WIN-SERVER] Overall Status: Secure
[WIN-SERVER] Audit completed. Log: C:\Temp\TomcatConfigCheck.csv
```
- **Log File Content (TomcatConfigCheck.csv)**:
```
Timestamp,Server,Message
2025-06-18 13:35:00,Windows-Server,[Windows-Server] Checking Apache Tomcat configuration security on Windows-Server...;[Windows-Server] Tomcat configuration directory located at C:\Program Files\Apache Software Foundation\Tomcat\conf;[Windows-Server] Detected Tomcat version 10.0 at C:\Program Files\Apache Software Foundation\Tomcat\conf;[Windows-Server] User 'testuser': Compliant;[Windows-Server] Overall Configuration: Secure;[Windows-Server] Audit completed
```
- **Multiple Servers**:
```powershell
$cred = Get-Credential
.\src\windows\Audit\powershell\Remote_CheckTomcatConfigWin.ps1 -ServerName Server1,Server2 -Credential $cred
```
- **Custom Path**:
```powershell
$cred = Get-Credential
.\src\windows\Audit\powershell\Remote_CheckTomcatConfigWin.ps1 -ServerName Windows-Server -TomcatConfPath "C:\Program Files\Apache Software Foundation\Tomcat\conf" -Credential $cred
```

## Testing Framework

**WARNING**: The testing framework modifies system configurations, including `server.xml` and `tomcat-users.xml`, and installs/uninstalls Tomcat instances. It is **strictly for use in test labs** to verify that the auditing and patching scripts function correctly. **Do not use on production systems**, as it may disrupt services or cause data loss. Use only in controlled lab environments.

The testing framework validates the auditing and patching scripts by simulating various Tomcat configurations and password types to ensure they correctly identify and resolve compliance issues. It includes installation scripts to set up test environments.

### Run Tests
#### Unix
```bash
sudo ./tests/Audit/unix/test_config_unix.py
```
- Logs to `~/TestTomcatConfig.log`.
- Tests 42 configurations per Tomcat version (7.0, 8.5, 9.0, 10.0, 10.1).

#### Windows
```powershell
.\tests\Audit\windows\test_config_win.ps1
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
│   │   ├── Audit/            # Auditing scripts
│   │   │   └── bash/        # Bash auditing scripts
│   │   │       └── CheckTomcatConfigUnixBash.sh
│   │   └── Patch/            # Patching scripts
│   │       └── bash/        # Bash patching scripts
│   │           └── UpdateTomcatUserUnix.sh
│   └── windows/              # Windows-specific scripts
│       ├── Audit/            # Auditing scripts
│       │   └── powershell/   # PowerShell auditing scripts
│       │       ├── CheckTomcatConfigWin.ps1
│       │       └── Remote_CheckTomcatConfigWin.ps1
│       └── Patch/            # Patching scripts
│           └── powershell/   # PowerShell patching scripts
│               └── UpdateTomcatUserWin.ps1
├── tests/                    # Test framework
│   └── Audit/                # Test scripts for auditing and patching
│       ├── unix/            # Unix test scripts
│       │   └── test_config_unix.py
│       └── windows/         # Windows test scripts
│           └── test_config_win.ps1
├── assets/                   # Static assets
│   └── images/               # Images and other media
│       └── banner.jpg
└── install/                  # Installation and management scripts
    ├── unix/                 # Unix installation and management
    │   └── tomcat_manager.sh
    └── windows/              # Windows installation and management
        └── TomcatManager.ps1
```

## License
Licensed under the Apache 2.0 License. See `docs/LICENSE` for details.