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

### Supported Tomcat Versions
| Version | Unix Support | Windows Support | Notes |
|---------|--------------|-----------------|-------|
| 7.0     | ✅           | ✅              | Supports `MessageDigestCredentialHandler` (MD5, SHA-1, SHA-256). |
| 8.5     | ✅           | ✅              | Adds SHA-512 and `NestedCredentialHandler` support. |
| 9.0     | ✅           | ✅              | Includes `SecretKeyCredentialHandler` for PBKDF2. |
| 10.0    | ✅           | ✅              | Supports `SecretKeyCredentialHandler` and `NestedCredentialHandler`. |
| 10.1    | ✅           | ✅              | Identical features to 10.0. |

## Architecture and boundaries

The auditor has separate local and remote surfaces with an explicit lab-only
test boundary:

| Surface | Boundary |
|---|---|
| `src/unix/Audit/` and `src/unix/Patch/` | Bash tools that inspect or explicitly patch a local Tomcat configuration; patch mode creates timestamped backups. |
| `src/windows/Audit/` and `src/windows/Patch/` | PowerShell tools for local Windows audit/patch and caller-supplied remote audit/update targets. Credentials are passed by the operator and are not stored by the repository. |
| `install/` | Optional lab setup and lifecycle helpers; do not use them as a production deployment mechanism. |
| `tests/unit/` and `tests/Audit/` | Self-contained helper tests and destructive lab harnesses. The full harness must run only against disposable Tomcat installations. |

The supported controls cover Tomcat credential handlers, password formats,
configuration permissions, backups, and redacted audit output. A compliant
result is not a complete host, application, or compliance assessment.

## Quick Start

### Prerequisites
- **Unix (Linux/macOS)**: Bash, Tomcat under a path such as `/opt/tomcat`, and sudo for audit/patch.
- **Windows**: PowerShell 5.1+, Tomcat installed, Administrator for patch; WinRM for remote audit.
- **Java**: Java 8 for Tomcat 7.0; Java 11+ for 8.5 / 9.0 / 10.x.

### Clone
```bash
git clone https://github.com/ZeroXSHDW/Apache-Tomcat-Password-Security-Audit ~/tomcat-audit
cd ~/tomcat-audit
```

### Fastest audit (Unix)
```bash
sudo ./src/unix/Audit/bash/CheckTomcatConfigUnixBash.sh
# optional custom conf:
sudo ./src/unix/Audit/bash/CheckTomcatConfigUnixBash.sh --custom-conf=/path/to/conf
```

### Fastest audit (Windows)
```powershell
.\src\windows\Audit\powershell\CheckTomcatConfigWin.ps1
```

### Optional Tomcat lab install
Install scripts under `install/` set up non-production Tomcat trees for testing. See [install/README.md](install/README.md).

### Security
See [SECURITY.md](SECURITY.md) for disclosure and safe-operation notes.

## Usage

### 1. Unix: Audit Local Configuration (Bash)
Run the Unix Bash auditing script to check compliance:
```bash
sudo ./src/unix/Audit/bash/CheckTomcatConfigUnixBash.sh
```
- **Output**: Logs to `/tmp/TomcatManager.csv`.
- **Example Output:**
```
Execution Time: 2025-06-26 14:12:11
Hostname: kali
===========================
Checking for running Tomcat processes...
  No running Tomcat processes found
Searching common Tomcat configuration paths...
Found Tomcat configuration via find: /opt/tomcat-8.5/conf
Config Path: /opt/tomcat-8.5/conf
  /opt/tomcat-8.5/conf/server.xml is owned by root
  /opt/tomcat-8.5/conf/server.xml permissions are secure (600)
  /opt/tomcat-8.5/conf/tomcat-users.xml is owned by root
  /opt/tomcat-8.5/conf/tomcat-users.xml permissions are secure (600)
Tomcat Home: /opt/tomcat-8.5
Validating Tomcat installation at /opt/tomcat-8.5
Tomcat installation validation passed
Tomcat Version: 8.5
Auditing server.xml
Server Configuration:
    - Tomcat 8.5 requires MessageDigestCredentialHandler with SHA-512, iterations >= 10000, saltLength >= 16
    - Recommendation: Configure MessageDigestCredentialHandler with algorithm='SHA-512', iterations='10000', saltLength='16'
  Status: Compliant for Tomcat 8.5
  Credential Handler: org.apache.catalina.realm.MessageDigestCredentialHandler
  Algorithm: SHA-512
  Iterations: 10000
  Salt Length: 16
Auditing tomcat-users.xml
    User Audit Results:
    Username | Password Type | Compliance
    ---------|---------------|-----------
        admin | Hash | Compliant
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
- **Example Output:**
```
2025-06-26 16:51:37,Created backup: /opt/tomcat/conf/server.xml.bak.20250626165137
─────────────────────────────
 Tomcat CredentialHandler Update
─────────────────────────────
• Before:
    (none found)
• After:
    <CredentialHandler className="org.apache.catalina.realm.SecretKeyCredentialHandler" algorithm="PBKDF2WithHmacSHA512" iterations="10000" saltLength="16" keyLength="256"/>
✅ CredentialHandler updated for Tomcat 10.1.
2025-06-26 16:51:37,Created backup: /opt/tomcat/conf/tomcat-users.xml.bak.20250626165137
─────────────────────────────
 Tomcat User Password Update
─────────────────────────────
✔ Updated user: tomcat
    • Old password:  [REDACTED]   (Plaintext, ❌ Non-compliant)
    • New password:  [REDACTED]   (Salted Hash, ✅ Compliant)
Finished updating users in /opt/tomcat/conf/tomcat-users.xml
```
- **Backups**: Before patching, backups are created for both `server.xml` and `tomcat-users.xml` with a unique timestamped suffix.
- **Credential hygiene**: Patch output and logs intentionally redact plaintext passwords and generated credential material.
- **Fail-closed versioning**: If the Unix patcher cannot identify a supported Tomcat version, it aborts before changing configuration; it never guesses a compatibility policy.

### 3. Windows: Audit, Patch, and Remote Audit

#### Local Audit
```powershell
.\src\windows\Audit\powershell\CheckTomcatConfigWin.ps1
```
- **Output**: Logs to `$env:LOCALAPPDATA\Temp\TomcatManager.csv` (e.g., `$env:LOCALAPPDATA\Temp`).
- **Example Output:**
```
Checking Apache Tomcat configuration security...
############################################################WIN-SERVER###########################################################
Execution Time: 2025-06-18 13:35:00
HOSTNAME: WIN-SERVER
===========================
Searching common Tomcat configuration paths...
Found Tomcat configuration at: C:\Program Files\Apache Software Foundation\Tomcat\conf
Config Path: C:\Program Files\Apache Software Foundation\Tomcat\conf
Tomcat Home: C:\Program Files\Apache Software Foundation\Tomcat
Detected Tomcat version from RELEASE-NOTES: 8.5.99
No Tomcat process found running as NT AUTHORITY\SYSTEM.
Validating Tomcat installation at C:\Program Files\Apache Software Foundation\Tomcat
Tomcat installation validation passed
Tomcat Version: 8.5.99
Auditing server.xml
Server Configuration:
    - Tomcat 8.5 requires MessageDigestCredentialHandler with SHA-512, iterations >= 10000, saltLength >= 16
    - Recommendation: Configure MessageDigestCredentialHandler with algorithm='SHA-512', iterations='10000', saltLength='16'
  Status: Compliant for Tomcat 8.5
  Credential Handler: org.apache.catalina.realm.MessageDigestCredentialHandler
  Algorithm: SHA-512
  Iterations: 10000
  Salt Length: 16
Auditing tomcat-users.xml
    User Audit Results:
    Username | Password Type | Compliance
    ---------|---------------|-----------
    admin    | Hash          | Compliant
===========================
Overall Status: Secure
Audit completed. Log: $env:LOCALAPPDATA\Temp\TomcatManager.csv
```

#### Local Patch
```powershell
.\src\windows\Patch\powershell\UpdateTomcatUserWin.ps1
```
- **Output**: Logs to `$env:LOCALAPPDATA\Temp\TomcatManager.csv` and console.
- **Example Output:**
```
Auto-detected TomcatHome: C:\tomcat
2025-06-26 16:51:37 - INFO - Java version: openjdk version "11.0.22" 2024-01-16
2025-06-26 16:51:37 - INFO - Using TomcatHome: C:\tomcat
2025-06-26 16:51:37 - INFO - Starting Tomcat configuration and user update
2025-06-26 16:51:37 - INFO - Administrative privileges confirmed
2025-06-26 16:51:37 - INFO - Detected Tomcat version: 10.1
2025-06-26 16:51:37 - INFO - Created or updated setenv.bat at C:\tomcat\bin\setenv.bat to set CATALINA_HOME.
2025-06-26 16:51:39 - INFO - Created backup: C:\tomcat\conf\server.xml.bak.20250626165139
2025-06-26 16:51:39 - INFO - Patched server.xml with correct CredentialHandler for Tomcat 10.1
2025-06-26 16:51:39 - INFO - Created backup: C:\tomcat\conf\tomcat-users.xml.bak.20250626165139
2025-06-26 16:51:39 - INFO - Hashing plaintext password for user tomcat using Tomcat 10.1
2025-06-26 16:51:41 - INFO - digest.bat completed; credential material omitted
2025-06-26 16:51:41 - INFO - Updated password for user tomcat
2025-06-26 16:51:41 - INFO - Successfully updated user hashes in tomcat-users.xml
2025-06-26 16:51:41 - INFO - Tomcat is not running. No restart will be performed.
2025-06-26 16:51:41 - INFO - Configuration update completed successfully
```
- **Backups**: Before patching, backups are created for both `server.xml` and `tomcat-users.xml` with a timestamp.

#### Remote Audit
```powershell
.\src\windows\Audit\powershell\Remote_CheckTomcatConfigWin.ps1 -ServerName WIN-SERVER -Credential $cred
```
- **Output**: Logs to `C:\Temp\TomcatConfigCheck.csv` on the client.
- **Example Output:**
```
[Client] Starting script execution at 2025-06-18 13:35:00.
[WIN-SERVER] Checking Apache Tomcat configuration security on WIN-SERVER...
[WIN-SERVER] ############################################################WIN-SERVER###########################################################
[WIN-SERVER] Execution Time: 2025-06-18 13:35:00
[WIN-SERVER] HOSTNAME: WIN-SERVER
[WIN-SERVER] ===========================
[WIN-SERVER] Searching common Tomcat configuration paths...
[WIN-SERVER] Found Tomcat configuration at: C:\Program Files\Apache Software Foundation\Tomcat\conf
[WIN-SERVER] Config Path: C:\Program Files\Apache Software Foundation\Tomcat\conf
[WIN-SERVER] Tomcat Home: C:\Program Files\Apache Software Foundation\Tomcat
[WIN-SERVER] Detected Tomcat version from RELEASE-NOTES: 8.5.99
[WIN-SERVER] No Tomcat process found running as NT AUTHORITY\SYSTEM.
[WIN-SERVER] Validating Tomcat installation at C:\Program Files\Apache Software Foundation\Tomcat
[WIN-SERVER] Tomcat installation validation passed
[WIN-SERVER] Tomcat Version: 8.5.99
[WIN-SERVER] Auditing server.xml
[WIN-SERVER] Server Configuration:
[WIN-SERVER]     - Tomcat 8.5 requires MessageDigestCredentialHandler with SHA-512, iterations >= 10000, saltLength >= 16
[WIN-SERVER]     - Recommendation: Configure MessageDigestCredentialHandler with algorithm='SHA-512', iterations='10000', saltLength='16'
[WIN-SERVER]   Status: Compliant for Tomcat 8.5
[WIN-SERVER]   Credential Handler: org.apache.catalina.realm.MessageDigestCredentialHandler
[WIN-SERVER]   Algorithm: SHA-512
[WIN-SERVER]   Iterations: 10000
[WIN-SERVER]   Salt Length: 16
[WIN-SERVER] Auditing tomcat-users.xml
[WIN-SERVER]     User Audit Results:
[WIN-SERVER]     Username | Password Type | Compliance
[WIN-SERVER]     ---------|---------------|-----------
[WIN-SERVER]     admin    | Hash          | Compliant
[WIN-SERVER] ===========================
[WIN-SERVER] Overall Status: Secure
[WIN-SERVER] Audit completed. Log: C:\Temp\TomcatConfigCheck.csv
```

## Example Output: Remote Tomcat User Update

Below is a sample output from running the remote Tomcat user update script. This demonstrates the logging, backup, password hashing, and completion messages you should expect:
```powershell
.\Remote_UpdateTomcatUserWin.ps1 -ServerName "WIN-E6DN4M5084M" -Credential (Get-Credential)
```
```powershell
PS <repo-root>> .\Remote_UpdateTomcatUserWin.ps1 -ServerName "WIN-E6DN4M5084M" -Credential (Get-Credential)

cmdlet Get-Credential at command pipeline position 1
Supply values for the following parameters:
Credential
[WIN-E6DN4M5084M] Starting remote Tomcat user update on WIN-E6DN4M5084M...
2025-06-27 07:34:47 - INFO - Auto-detected TomcatHome: C:\\tomcat
2025-06-27 07:34:48 - INFO - Java version: openjdk version "11.0.22" 2024-01-16
2025-06-27 07:34:48 - INFO - Using TomcatHome: C:\\tomcat
2025-06-27 07:34:48 - INFO - Starting Tomcat configuration and user update
2025-06-27 07:34:48 - INFO - Administrative privileges confirmed
2025-06-27 07:34:48 - INFO - Detected Tomcat version: 10.1
2025-06-27 07:34:48 - INFO - Created or updated setenv.bat at C:\\tomcat\bin\setenv.bat to set CATALINA_HOME.
2025-06-27 07:34:49 - INFO - Created backup: C:\\tomcat\conf\server.xml.bak.20250627073449
2025-06-27 07:34:49 - INFO - Patched server.xml with correct CredentialHandler for Tomcat 10.1
2025-06-27 07:34:49 - INFO - Created backup: C:\\tomcat\conf\tomcat-users.xml.bak.20250627073449
2025-06-27 07:34:49 - INFO - Hashing plaintext password for user tomcat using Tomcat 10.1
2025-06-27 07:34:49 - INFO - setenv.bat already sets CATALINA_HOME correctly.
2025-06-27 07:34:49 - INFO - Running digest.bat with credential arguments redacted
2025-06-27 07:34:50 - INFO - digest.bat completed; credential material omitted
2025-06-27 07:34:50 - INFO - Updated password for user tomcat
2025-06-27 07:34:50 - INFO - Successfully updated user hashes in tomcat-users.xml
2025-06-27 07:34:50 - INFO - Tomcat is not running. No restart will be performed.
2025-06-27 07:34:50 - INFO - Configuration update completed successfully
[WIN-E6DN4M5084M] True
[WIN-E6DN4M5084M] 2025-06-27 07:34:47 - INFO - Auto-detected TomcatHome: C:\\tomcat
[WIN-E6DN4M5084M] 2025-06-27 07:34:48 - INFO - Java version: openjdk version "11.0.22" 2024-01-16
[WIN-E6DN4M5084M] 2025-06-27 07:34:48 - INFO - Using TomcatHome: C:\\tomcat
[WIN-E6DN4M5084M] 2025-06-27 07:34:48 - INFO - Starting Tomcat configuration and user update
[WIN-E6DN4M5084M] 2025-06-27 07:34:48 - INFO - Administrative privileges confirmed
[WIN-E6DN4M5084M] 2025-06-27 07:34:48 - INFO - Detected Tomcat version: 10.1
[WIN-E6DN4M5084M] 2025-06-27 07:34:48 - INFO - Created or updated setenv.bat at C:\\tomcat\bin\setenv.bat to set CATALINA_HOME.
[WIN-E6DN4M5084M] 2025-06-27 07:34:49 - INFO - Created backup: C:\\tomcat\conf\server.xml.bak.20250627073449
[WIN-E6DN4M5084M] 2025-06-27 07:34:49 - INFO - Patched server.xml with correct CredentialHandler for Tomcat 10.1
[WIN-E6DN4M5084M] 2025-06-27 07:34:49 - INFO - Created backup: C:\\tomcat\conf\tomcat-users.xml.bak.20250627073449
[WIN-E6DN4M5084M] 2025-06-27 07:34:49 - INFO - Hashing plaintext password for user tomcat using Tomcat 10.1
[WIN-E6DN4M5084M] 2025-06-27 07:34:49 - INFO - setenv.bat already sets CATALINA_HOME correctly.
[WIN-E6DN4M5084M] 2025-06-27 07:34:49 - INFO - Running digest.bat with credential arguments redacted
[WIN-E6DN4M5084M] 2025-06-27 07:34:50 - INFO - digest.bat completed; credential material omitted
[WIN-E6DN4M5084M] 2025-06-27 07:34:50 - INFO - Updated password for user tomcat
[WIN-E6DN4M5084M] 2025-06-27 07:34:50 - INFO - Successfully updated user hashes in tomcat-users.xml
[WIN-E6DN4M5084M] 2025-06-27 07:34:50 - INFO - Tomcat is not running. No restart will be performed.
[WIN-E6DN4M5084M] 2025-06-27 07:34:50 - INFO - Configuration update completed successfully
PS <repo-root>>
```

## Windows Tomcat Audit JSON Output and Parsing

### Remote_CheckTomcatConfigWinJson.ps1
This script audits Apache Tomcat configuration on one or more remote Windows servers and outputs the results as a JSON array. It collects information such as Tomcat home, version, credential handler details, per-user compliance, overall status, and whether Tomcat is running as SYSTEM.

**Usage:**
```powershell
# Run the audit and output JSON to a file
./src/windows/Audit/powershell/Remote_CheckTomcatConfigWinJson.ps1 -ServerName "server1","server2" -Credential (Get-Credential) -TomcatConfPath "C:\Path\To\Tomcat\conf" > all_audit_results.txt
```

### Remote_ParseTomcatAuditJson.ps1
This script parses the output file(s) from Remote_CheckTomcatConfigWinJson.ps1, even if the file contains multiple concatenated JSON outputs. It combines all results into a single JSON array for further processing or reporting.

**Usage:**
```powershell
./src/windows/Audit/powershell/Remote_ParseTomcatAuditJson.ps1 -InputFile all_audit_results.txt
```

The output will be a single JSON array containing all parsed audit results from all servers.

---

## Command Line Parameters

Below are the command line parameters for each script. All scripts support optional parameters for custom Tomcat locations; Windows scripts may also accept service names or credentials.

### Unix Scripts

- **CheckTomcatConfigUnixBash.sh**
  - `--custom-conf=/path/to/conf` (optional): Use a custom Tomcat configuration directory (must contain `server.xml` and `tomcat-users.xml`).
  - **Usage:**
    ```bash
    sudo ./src/unix/Audit/bash/CheckTomcatConfigUnixBash.sh [--custom-conf=/path/to/conf]
    ```

- **UpdateTomcatUserUnix.sh**
  - `[optional-custom-conf-path]` (optional): Path to Tomcat `conf` directory (if not using default or auto-detected).
  - **Usage:**
    ```bash
    sudo ./src/unix/Patch/bash/UpdateTomcatUserUnix.sh [optional-custom-conf-path]
    ```

### Windows Scripts

- **CheckTomcatConfigWin.ps1**
  - `-TomcatConfPath <path>` (optional): Path to Tomcat `conf` directory (if not using default or auto-detected).
  - **Usage:**
    ```powershell
    .\src\windows\Audit\powershell\CheckTomcatConfigWin.ps1 [-TomcatConfPath <path>]
    ```

- **UpdateTomcatUserWin.ps1**
  - `-TomcatHome <path>` (optional): Path to Tomcat home directory (if not using default or auto-detected).
  - `-ServiceName <name>` (optional, default: `Tomcat101`): Name of the Tomcat Windows service to restart after patching.
  - **Usage:**
    ```powershell
    .\src\windows\Patch\powershell\UpdateTomcatUserWin.ps1 [-TomcatHome <path>] [-ServiceName <name>]
    ```

- **Remote_CheckTomcatConfigWin.ps1**
  - `-ServerName <server>` (required): One or more remote server names to audit.
  - `-TomcatConfPath <path>` (optional): Path to Tomcat `conf` directory on the remote server.
  - `-Credential <PSCredential>` (required): Credentials for remote connection (use `Get-Credential`).
  - **Usage:**
    ```powershell
    .\src\windows\Audit\powershell\Remote_CheckTomcatConfigWin.ps1 -ServerName WIN-SERVER -Credential $cred
    ```

- **Remote_UpdateTomcatUserWin.ps1**
  - `-ServerName <server>` (required): One or more remote server names to patch.
  - `-TomcatHome <path>` (optional): Path to Tomcat home directory on the remote server.
  - `-ServiceName <name>` (optional, default: `Tomcat101`): Name of the Tomcat Windows service to restart after patching.
  - `-Credential <PSCredential>` (required): Credentials for remote connection (use `Get-Credential`).
  - **Usage:**
    ```powershell
    .\src\windows\Patch\powershell\Remote_UpdateTomcatUserWin.ps1 -ServerName WIN-SERVER -Credential (Get-Credential)
    ```

- **TomcatManager.ps1**
  - `-Action <Install|Uninstall|Start|Stop|Status>` (required): Action to perform (install, uninstall, start, stop, or check status of Tomcat service).
  - `-TomcatVersion <version>` (optional): Tomcat version to install (e.g., `10.1.42`).
  - `-InstallDir <path>` (optional): Installation directory (default: `C:\tomcat`).
  - `-JavaHome <path>` (optional): Path to Java installation.
  - `-ServiceName <name>` (optional): Name for the Tomcat Windows service.
  - **Usage:**
    ```powershell
    .\install\windows\TomcatManager.ps1 -Action Install -TomcatVersion 10.1.42 -InstallDir C:\tomcat
    ```

## Verification

The safe CI-equivalent checks do not require a Tomcat service or credentials:

```bash
find src/unix install/unix -type f -name '*.sh' -exec bash -n {} +
python -m py_compile tests/Audit/unix/test_config_unix.py
python -m unittest discover -s tests/unit -v
git diff --check
```

The workflow also parses every PowerShell file on Windows. The complete audit
and patch lab harness is intentionally separate because it mutates disposable
Tomcat trees; it is never a substitute for the safe unit gate.

## Testing Framework

**WARNING**: The testing framework modifies system configurations, including `server.xml` and `tomcat-users.xml`, and installs/uninstalls Tomcat instances. It is **strictly for use in test labs** to verify that the auditing and patching scripts function correctly. **Do not use on production systems**, as it may disrupt services or cause data loss. Use only in controlled lab environments.

The testing framework validates the auditing and patching scripts by simulating various Tomcat configurations and password types to ensure they correctly identify and resolve compliance issues. It includes installation scripts to set up test environments.

### Run Tests
#### Unix (self-contained helpers — no Tomcat required)
```bash
python -m unittest discover -s tests/unit -v
```

#### Unix (full lab harness — requires installed Tomcat; mutates configs)
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

## Configuration reference and recommendations
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

## License

Licensed under the Apache 2.0 License. See [LICENSE](LICENSE).

## Contributing

Keep audit scripts safe, deterministic, and non-destructive by default. Run the documented PowerShell and unit checks before review and see [CONTRIBUTING.md](CONTRIBUTING.md).
