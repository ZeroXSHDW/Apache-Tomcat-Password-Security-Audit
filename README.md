# Apache Tomcat Password Security Auditor

![Tomcat Configuration Security Auditor Banner](assets/banner.jpg)

## Overview

The **Apache Tomcat Password Security Auditor** is a set of tools to audit Tomcat user authentication configurations for compliance with **NIST 800-53 IA-5** and **CIS Tomcat Benchmark** standards. It helps system administrators and security professionals ensure secure password configurations across Tomcat versions 7.0, 8.5, 9.0, 10.0, and 10.1.

### Key Scripts
- **CheckTomcatConfigUnix.py**: Audits Tomcat configurations on Unix (Linux/macOS) systems.
- **CheckTomcatConfigWin.ps1**: Audits Tomcat configurations on local Windows systems.
- **Remote_CheckTomcatConfigWin.ps1**: Audits Tomcat configurations on remote Windows servers via PowerShell remoting.

### Features
- Checks password types and credential handler configurations.
- Reports compliance status with actionable recommendations.
- Supports local and remote auditing on Windows, and local auditing on Unix.
- Logs results for traceability (CSV for Windows, text for Unix).
- Compatible with Tomcat 7.0, 8.5, 9.0, 10.0, and 10.1.

## Quick Start

### Prerequisites
- **Unix (Linux/macOS)**:
  - Python 3.6+.
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
git clone <repository-url> ~/tomcat-audit
cd ~/tomcat-audit
```
For Windows:
```powershell
git clone <repository-url> C:\Users\<User>\tomcat-audit
cd C:\Users\<User>\tomcat-audit
```

## Usage

### 1. Unix: Audit Local Configuration
Run the Unix auditing script:
```bash
sudo ./CheckTomcatConfigUnix.py
```
- **Output**: Logs to `/tmp/TomcatManager.log`.
- **Example**:
  ```
  Checking Apache Tomcat configuration security...
  Tomcat configuration directory located at /opt/tomcat/conf
  Detected Tomcat version 9.0 at /opt/tomcat/conf
  User 'testuser': Compliant
  Overall Configuration: Secure
  Audit completed
  ```

### 2. Windows: Audit Local Configuration
Run the Windows auditing script:
```powershell
.\CheckTomcatConfigWin.ps1
```
- **Output**: Logs to `$env:LOCALAPPDATA\Temp\TestTomcatConfig.csv` (e.g., `C:\Users\<User>\AppData\Local\Temp`).
- **Example**:
  ```
  Checking Apache Tomcat configuration security...
  Tomcat configuration directory located at C:\tomcat\conf
  Detected Tomcat version 10.0 at C:\tomcat\conf
  User 'testuser': Compliant
  Overall Configuration: Secure
  Audit completed
  ```

### 3. Windows: Audit Remote Configuration
Run the remote auditing script:
```powershell
$cred = Get-Credential
.\Remote_CheckTomcatConfigWin.ps1 -ServerName Windows-Server -Credential $cred
```
- **Output**: Logs to `C:\Temp\TomcatConfigCheck.csv`.
- **Example**:
  ```
  [Windows-Server] Checking Apache Tomcat configuration security on Windows-Server...
  [Windows-Server] Tomcat configuration directory located at C:\Program Files\Apache Software Foundation\Tomcat 10.0\conf
  [Windows-Server] Detected Tomcat version 10.0 at C:\Program Files\Apache Software Foundation\Tomcat 10.0\conf
  [Windows-Server] User 'testuser': Compliant
  [Windows-Server] Overall Configuration: Secure
  [Windows-Server] Audit completed
  ```
- **Multiple Servers**:
  ```powershell
  $cred = Get-Credential
  .\Remote_CheckTomcatConfigWin.ps1 -ServerName Server1,Server2 -Credential $cred
  ```
- **Custom Path** (optional):
  ```powershell
  $cred = Get-Credential
  .\Remote_CheckTomcatConfigWin.ps1 -ServerName Windows-Server -TomcatConfPath "C:\tomcat\conf" -Credential $cred
  ```

## Testing Framework
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
