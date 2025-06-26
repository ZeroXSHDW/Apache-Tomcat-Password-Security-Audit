# Apache Tomcat Secure Install Scripts

This directory contains cross-platform installation scripts for Apache Tomcat, designed for secure, automated deployment and configuration. These scripts are compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark standards, and support all major Tomcat versions (7.0, 8.5, 9.0, 10.0, 10.1).

## Contents

- `windows/TomcatManager.ps1` — PowerShell script for Windows
- `unix/tomcat_manager.sh` — Bash script for Unix/Linux/macOS

## Features
- Automatically downloads and installs the latest patch for the specified Tomcat version
- Detects or installs Java as needed
- Configures secure admin user(s) with hashed passwords
- Optionally installs Tomcat as a service and configures firewall rules
- Robust error handling, logging, and backup of configuration files

---

## Windows: TomcatManager.ps1

**Usage:**
```powershell
# Run as Administrator in PowerShell
cd <repo-root>\install\windows

# Example: Install Tomcat 9.0 with a secure user
.\TomcatManager.ps1 -Version 9.0 -Username admin -Password MySecurePass! -Roles "manager,admin"
```

**Parameters:**
- `-InstallPath` — Installation directory (default: `C:\Program Files\Apache Software Foundation\Tomcat`)
- `-Version` — Tomcat major version (e.g., `7.0`, `8.5`, `9.0`, `10.0`, `10.1`)
- `-Username` — Admin username (default: `tomcat`)
- `-Password` — Admin password (default: `s3cret`)
- `-Roles` — Comma-separated roles (default: `manager,admin`)
- `-InstallService` — Install as Windows service (default: enabled)
- `-ConfigureFirewall` — Add firewall rule for port 8080 (default: enabled)

**What it does:**
- Downloads the latest available patch for the specified Tomcat version
- Installs Java if not found
- Extracts Tomcat, configures the admin user with a secure hash, and installs as a service
- Adds a firewall rule for port 8080
- Logs actions to `$env:TEMP\TomcatManager.log`

**Example Output:**
```
[INFO] Installing Tomcat 9.0.85 to C:\Program Files\Apache Software Foundation\Tomcat
[INFO] Java detected: C:\Program Files\AdoptOpenJDK\jdk-11.0.11.9-hotspot\bin\java.exe
[INFO] Downloading Tomcat 9.0.85...
[INFO] Extracting Tomcat...
[INFO] Configuring admin user with secure hash...
[INFO] Installing Tomcat as a Windows service...
[INFO] Adding firewall rule for port 8080...
[INFO] Installation complete. Tomcat service started.
[INFO] CredentialHandler: org.apache.catalina.realm.MessageDigestCredentialHandler (SHA-512, 10000 iterations, 16 salt)
[INFO] User Accounts:
  Username | Roles         | Password Type | Compliance
  -------- | ------------ | -------------| ----------
  admin    | manager,admin| Hash         | Compliant
```

---

## Unix: tomcat_manager.sh

**Usage:**
```bash
# Run as root or with sudo
cd <repo-root>/install/unix

# Example: Install Tomcat 9.0 with a secure user
sudo ./tomcat_manager.sh -v 9.0 -u admin -w MySecurePass! -r manager,admin
```

**Options:**
- `-p, --path` — Installation path (default: `/opt/tomcat`)
- `-v, --version` — Tomcat major version (e.g., `7.0`, `8.5`, `9.0`, `10.0`, `10.1`)
- `-u, --username` — Admin username (default: `tomcat`)
- `-w, --password` — Admin password (default: `s3cret`)
- `-r, --roles` — Comma-separated roles (default: `manager,admin`)
- `-s, --no-service` — Skip service installation
- `-f, --no-firewall` — Skip firewall configuration

**What it does:**
- Downloads and extracts the latest patch for the specified Tomcat version
- Installs Java if not found
- Configures secure admin user(s) with hashed passwords
- Optionally installs as a systemd service and configures firewall
- Logs actions to `~/TomcatManager.log`

**Example Output:**
```
─────────────────────────────
 Tomcat CredentialHandler Update
─────────────────────────────
• Before:
    (none found)
• After:
    <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-512" iterations="10000" saltLength="16"/>
✅ CredentialHandler updated for Tomcat 8.5.
─────────────────────────────
 Tomcat User Password Update
─────────────────────────────
✔ Updated user: admin
    • Old password:  MySecurePass!   (Plaintext, ❌ Non-compliant)
    • New password:  [HASHED]   (Hash, ✅ Compliant)
─────────────────────────────
 Tomcat User & Credential Audit
─────────────────────────────
Tomcat Version: 8.5

CredentialHandler:
  Status: Compliant
  Handler: org.apache.catalina.realm.MessageDigestCredentialHandler
  Algorithm: SHA-512
  Iterations: 10000
  Salt Length: 16

User Accounts:
  Username      | Roles           | Password Type   | Compliance
  ------------- | --------------- | --------------- | -----------
  admin         | manager,admin   | Hash            | Compliant
─────────────────────────────
All users updated and server.xml patched.
```

---

## Log Files
- **Windows:** `$env:TEMP\TomcatManager.log` and `$env:TEMP\TomcatManager.csv`
- **Unix:** `~/TomcatManager.log` and `/tmp/TomcatManager.csv`

---

## Troubleshooting
- **Permissions:** Always run as Administrator (Windows) or with sudo/root (Unix).
- **Java Not Found:** The script will attempt to install Java if missing, but you may need to install it manually on some systems.
- **Firewall/Service Issues:** Use the `--no-firewall` or `--no-service` options if you do not want these configured.
- **Log Files:** Check the log files for detailed error messages if something fails.

---

For more details, see the main [README.md](../README.md) in the project root. 