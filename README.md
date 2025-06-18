# Apache Tomcat Password Security Auditor

![Tomcat Configuration Security Auditor Banner](assets/images/banner.jpg)

## Overview

**Apache Tomcat - Password Security Auditor Tool** is a set of tools designed to audit and patch Apache Tomcat user authentication configurations for compliance with **NIST 800-53 IA-5** and **CIS Tomcat Benchmark** standards. This repository includes scripts for both Unix (Linux/macOS) and Windows environments, enabling system administrators and security professionals to evaluate and secure password configurations across various Tomcat versions.

### Key Features
- **Automated Testing**: Scripts test multiple password types and credential handler configurations, modifying `server.xml` and `tomcat-users.xml` to simulate scenarios and validate compliance.
- **Manual Auditing**: Analyze existing configurations, reporting password types, credential handlers, and compliance status with actionable recommendations.
- **Automated Patching**: Convert plaintext passwords to compliant hashes, update configuration files, and restart Tomcat services.
- **Remote Auditing**: Support for auditing Tomcat configurations on remote Windows servers using PowerShell remoting.
- **Cross-Platform Support**: Bash and Python-based scripts for Unix (Linux/macOS) and PowerShell scripts for Windows.
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
  - Bash or Python 3.6+.
  - Tomcat installed (e.g., `/opt/tomcat`).
  - Sudo permissions for auditing and patching.
- **Windows**:
  - PowerShell 5.1+ (included in Windows 10/11).
  - Tomcat installed (e.g., `C:\Program Files\Apache Software Foundation\Tomcat`).
  - Administrator privileges for auditing and patching.
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

### 2. Unix: Audit Local Configuration (Python)
Run the Unix Python auditing script to check compliance:
```bash
sudo ./src/unix/Audit/python/CheckTomcatConfigUnixPython.py
```
- **Output**: Logs to `/tmp/TomcatManager.csv`.
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
Audit completed. Log: /tmp/TomcatManager.csv
```

### 3. Unix: Patch Local Configuration (Bash)
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

### 4. Unix: Patch Local Configuration (Python)
Run the Unix Python patching script to convert plaintext passwords to compliant hashes and update configurations:
```bash
sudo ./src/unix/Patch/python/UpdateTomcatUserUnixPython.py
```
- **Output**: Logs to `/tmp/TomcatManager.csv`.
- **Example Output**: Same as the Bash patching script above.
- **Optional Custom Path**:
```bash
sudo ./src/unix/Patch/python/UpdateTomcatUserUnixPython.py --custom-conf=/opt/tomcat/conf
```

### 5. Windows: Audit Local Configuration
Run the Windows auditing script to check compliance:
```powershell
.\src\windows\Audit\powershell\CheckTomcatConfigWin.ps1
```
- **Output**: Logs to `$env:LOCALAPPDATA\Temp\TomcatManager.csv` (e.g., `C:\Users\<User>\AppData\Local\Temp`).
- **Example Output**:
```
Checking Apache Tomcat configuration security...
Tomcat configuration directory located at C:\Program Files\Apache Software Foundation\Tomcat\conf
Detected Tomcat version 10.0 at C:\Program Files\Apache Software Foundation\Tomcat\conf
User 'testuser': Compliant
Overall Configuration: Secure
Audit completed
```
- **Log File Content (TomcatManager.csv)**:
```
Timestamp,Message
2025-06-18 13:35:00,Checking Apache Tomcat configuration security...;Tomcat configuration directory located at C:\Program Files\Apache Software Foundation\Tomcat\conf;Detected Tomcat version 10.0 at C:\Program Files\Apache Software Foundation\Tomcat\conf;User 'testuser': Compliant;Overall Configuration: Secure;Audit completed
```

### 6. Windows: Patch Local Configuration
Run the Windows patching script to convert plaintext passwords to compliant hashes and update configurations:
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

### 7. Windows: Audit Remote Configuration
Run the remote auditing script to check compliance on remote Windows servers:
```powershell
$cred = Get-Credential
.\src\windows\Audit\powershell\Remote_CheckTomcatConfigWin.ps1 -ServerName Windows-Server -Credential $cred
```
- **Output**: Logs to `C:\Temp\TomcatConfigCheck.csv`.
- **Example Output**:
```
[Client] Starting script execution at 2025-06-18 13:35:00
[Windows-Server] Checking Apache Tomcat configuration security on Windows-Server...
[Windows-Server] Tomcat configuration directory located at C:\Program Files\Apache Software Foundation\Tomcat\conf
[Windows-Server] Detected Tomcat version 10.0 at C:\Program Files\Apache Software Foundation\Tomcat\conf
[Windows-Server] User 'testuser': Compliant
[Windows-Server] Overall Configuration: Secure
[Windows-Server] Audit completed
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

### Installation for Testing
Use these commands to install Tomcat for testing the auditing and patching scripts. These are optional and only needed for validation.

#### Unix
Install Tomcat:
```bash
sudo ./install/unix/tomcat_manager.sh install 9    # Install Tomcat 9.0
```
Uninstall Tomcat:
```bash
sudo ./install/unix/tomcat_manager.sh uninstall
```
Install dependencies:
```bash
sudo apt install python3 openjdk-11-jdk  # Ubuntu/Debian/Kali
sudo yum install python3 java-11-openjdk-devel  # CentOS/RHEL
```

#### Windows
Install Tomcat:
```powershell
.\install\windows\TomcatManager.ps1 install 9    # Install Tomcat 9.0
```
Uninstall Tomcat:
```powershell
.\install\windows\TomcatManager.ps1 uninstall
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
│   │   │   ├── bash/        # Bash auditing scripts
│   │   │   │   └── CheckTomcatConfigUnixBash.sh
│   │   │   └── python/      # Python auditing scripts
│   │   │       └── CheckTomcatConfigUnixPython.py
│   │   └── Patch/            # Patching scripts
│   │       ├── bash/        # Bash patching scripts
│   │       │   └── UpdateTomcatUserUnix.sh
│   │       └── python/      # Python patching scripts
│   │           └── UpdateTomcatUserUnixPython.py
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

## Troubleshooting
- **Tomcat Not Found**:
  - Verify installation path (e.g., `/opt/tomcat` or `C:\Program Files\Apache Software Foundation\Tomcat`).
  - Ensure `server.xml`, `tomcat-users.xml`, and `digest.sh`/`digest.bat` exist in the `conf` and `bin` directories.
- **Unix Permissions**:
  - Run with `sudo`.
  - Check write access to `/tmp` and Tomcat’s `conf` directory:
    ```bash
    sudo chmod 644 /opt/tomcat/conf/*
    ```
- **Windows Permissions**:
  - Run PowerShell as Administrator.
  - Ensure write access to `$env:LOCALAPPDATA\Temp` and `C:\Temp`:
    ```powershell
    icacls "C:\Program Files\Apache Software Foundation\Tomcat\conf" /grant Administrators:F
    ```
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
  - Verify Java version and `JAVA_HOME`:
    ```bash
    java -version
    echo $JAVA_HOME
    ```
    ```powershell
    java -version
    $env:JAVA_HOME
    ```
  - Set `JAVA_HOME` if needed:
    ```bash
    export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
    ```
    ```powershell
    [Environment]::SetEnvironmentVariable("JAVA_HOME", "C:\Program Files\Java\jdk-11", "Machine")
    ```
- **Log Security**:
  - Ensure log files (`/tmp/TomcatManager.csv`, `$env:LOCALAPPDATA\Temp\TomcatManager.csv`) and backups are secured:
    ```bash
    sudo chmod 600 /tmp/TomcatManager.csv
    ```
  - Move logs to a secure location if needed (e.g., `/var/log/tomcat-audit` or `C:\ProgramData\TomcatAudit`).

## License
Licensed under the Apache 2.0 License. See `docs/LICENSE` for details.