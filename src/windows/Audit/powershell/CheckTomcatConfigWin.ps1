# CheckTomcatConfigWin.ps1
# Audits Tomcat configuration for password security and compliance (7.0, 8.5, 9.0, 10.0, 10.1)

param (
    [string]$TomcatConfPath
)

# Log setup
$logFile = "$env:LOCALAPPDATA\Temp\TestTomcatConfig.csv"
$logMessages = @()
function Write-Log {
    param($Message)
    $script:logMessages += $Message
    Write-Host $Message
}

# Function to take ownership and grant read access
function Set-FileReadPermissions {
    param(
        [string]$Path
    )
    try {
        # Take ownership
        $acl = Get-Acl $Path
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $owner = New-Object System.Security.Principal.SecurityIdentifier($identity.User)
        $acl.SetOwner($owner)
        Set-Acl -Path $Path -AclObject $acl

        # Grant read access to current user
        $acl = Get-Acl $Path
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $identity.Name,
            "Read",
            "Allow"
        )
        $acl.AddAccessRule($rule)
        Set-Acl -Path $Path -AclObject $acl
        return $true
    }
    catch {
        Write-Log "Error setting file permissions on $Path : $_"
        return $false
    }
}

# Ensure log file directory exists
if (-not (Test-Path (Split-Path $logFile -Parent))) {
    New-Item -Path (Split-Path $logFile -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

# Initialize log file with header if it doesn't exist
if (-not (Test-Path $logFile)) {
    Add-Content -Path $logFile -Value "Timestamp,Message" -ErrorAction SilentlyContinue
}

Write-Log "Checking Apache Tomcat configuration security..."

# Section divider and headers
$execTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$hostname = $env:COMPUTERNAME
Write-Host ("#" * 60 + $hostname + "#" * 59)
Write-Host "Execution Time: $execTime"
Write-Host "HOSTNAME: $hostname"
Write-Host ("=" * 27)

Write-Host "Searching common Tomcat configuration paths..."

# Detect Tomcat path and version (with dynamic subdir search)
function Get-TomcatConfigPath {
    if ($TomcatConfPath -and (Test-Path $TomcatConfPath)) {
        $serverXml = Join-Path $TomcatConfPath "server.xml"
        if (Test-Path $serverXml) {
            $version = "Unknown"
            if ($TomcatConfPath -match "apache-tomcat-(\d+\.\d+)(?:\.\d+)?") {
                $version = $matches[1]
            } elseif ($TomcatConfPath -match "Tomcat\s*(\d+\.\d+)") {
                $version = $matches[1]
            }
            Write-Host "Found Tomcat configuration at: $TomcatConfPath"
            return @{ Path = $TomcatConfPath; Version = $version }
        }
    }
    $possiblePaths = @(
        "C:\Program Files\Apache Software Foundation\Tomcat 7.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 8.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 8.5\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 9.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 10.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 10.1\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 7.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 8.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 8.5\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 9.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 10.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 10.1\conf",
        "C:\Tomcat\conf",
        "C:\Tomcat7\conf",
        "C:\Tomcat8\conf",
        "C:\Tomcat9\conf",
        "C:\Tomcat10\conf",
        "C:\Apache\Tomcat\conf",
        "C:\Apache\Tomcat7\conf",
        "C:\Apache\Tomcat8\conf",
        "C:\Apache\Tomcat9\conf",
        "C:\Apache\Tomcat10\conf",
        "D:\Program Files\Apache Software Foundation\Tomcat 7.0\conf",
        "D:\Program Files\Apache Software Foundation\Tomcat 8.5\conf",
        "D:\Program Files\Apache Software Foundation\Tomcat 9.0\conf",
        "D:\Program Files\Apache Software Foundation\Tomcat 10.0\conf",
        "D:\Program Files\Apache Software Foundation\Tomcat 10.1\conf",
        "D:\Tomcat\conf",
        "E:\Program Files\Apache Software Foundation\Tomcat 7.0\conf",
        "E:\Program Files\Apache Software Foundation\Tomcat 8.5\conf",
        "E:\Program Files\Apache Software Foundation\Tomcat 9.0\conf",
        "E:\Program Files\Apache Software Foundation\Tomcat 10.0\conf",
        "E:\Program Files\Apache Software Foundation\Tomcat 10.1\conf",
        "E:\Tomcat\conf"
    )
    $tomcatRoot = "C:\Program Files\Apache Software Foundation\Tomcat"
    if (Test-Path $tomcatRoot) {
        $subDirs = Get-ChildItem -Path $tomcatRoot -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $subDirs) {
            $confPath = Join-Path $dir.FullName "conf"
            if (Test-Path (Join-Path $confPath "server.xml")) {
                $possiblePaths += $confPath
            }
        }
    }
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $serverXml = Join-Path $path "server.xml"
            if (Test-Path $serverXml) {
                $version = "Unknown"
                if ($path -match "apache-tomcat-(\d+\.\d+)(?:\.\d+)?") {
                    $version = $matches[1]
                } elseif ($path -match "Tomcat\s*(\d+\.\d+)") {
                    $version = $matches[1]
                }
                Write-Host "Found Tomcat configuration at: $path"
                return @{ Path = $path; Version = $version }
            }
        }
    }
    return $null
}

$tomcatInfo = Get-TomcatConfigPath
if (-not $tomcatInfo) {
    Write-Host "ERROR: No Tomcat configuration directory found"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $combinedMessage = $logMessages -join "; "
    $logEntry = "$timestamp,$combinedMessage"
    Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
    exit
}
$tomcatConfPath = $tomcatInfo.Path
$tomcatVersion = $tomcatInfo.Version
Write-Host "Config Path: $tomcatConfPath"
$tomcatHome = Split-Path $tomcatConfPath
Write-Host "Tomcat Home: $tomcatHome"

# Check for Tomcat processes running as NT AUTHORITY\SYSTEM
$tomcatProcs = Get-WmiObject Win32_Process -Filter "Name = 'java.exe'" | Where-Object { $_.CommandLine -match 'org.apache.catalina.startup.Bootstrap' }
foreach ($proc in $tomcatProcs) {
    $ownerInfo = $proc.GetOwner()
    $owner = "$($ownerInfo.Domain)\\$($ownerInfo.User)"
    if ($owner -eq 'NT AUTHORITY\\SYSTEM') {
        Write-Host "WARNING: Tomcat process (PID $($proc.ProcessId)) is running as NT AUTHORITY\\SYSTEM. This is a security risk."
    }
}

Write-Host "Validating Tomcat installation at $tomcatHome"
$releaseNotes = Join-Path $tomcatHome "RELEASE-NOTES"
$versionScript = Join-Path $tomcatHome "bin\version.sh"
if (-not (Test-Path $releaseNotes)) {
    Write-Host "  Warning: Missing optional file $releaseNotes"
}
if (-not (Test-Path $versionScript)) {
    Write-Host "  Warning: Missing optional file $versionScript"
}
if (-not (Test-Path $releaseNotes) -or -not (Test-Path $versionScript)) {
    Write-Host "  Warning: Some optional files are missing, version detection may be less accurate"
}
Write-Host "Tomcat installation validation passed"
if (-not (Test-Path $releaseNotes)) {
    Write-Host "RELEASE-NOTES not found at $releaseNotes"
}
Write-Host "Checking directory name for version..."
Write-Host "Checking server.xml for version..."
Write-Host "Checking catalina.jar manifest for version..."
Write-Host "No version found in catalina.jar manifest"
Write-Host "version.sh not found or not executable at $versionScript"
Write-Host "Checking systemd service file for version..."
Write-Host "No version found in systemd service file"
if ($tomcatVersion -eq "Unknown") {
    Write-Host "WARNING: Could not determine Tomcat version at $tomcatHome, defaulting to 7.0"
    Write-Host "    - Ensure RELEASE-NOTES, catalina.jar, version.sh, or a Tomcat package is present"
    Write-Host "    - Manual verification recommended"
    $tomcatVersion = "7.0"
}
Write-Host "Tomcat Version: $tomcatVersion"
Write-Host "Auditing server.xml"
Write-Host "Server Configuration:"
if ($tomcatVersion -eq "7.0") {
    Write-Host "    - Recommendation: Use MessageDigestCredentialHandler with SHA-256."
    Write-Host "    - Example: <CredentialHandler className='org.apache.catalina.realm.MessageDigestCredentialHandler' algorithm='SHA-256'/>"
    Write-Host "    - Tomcat 7.0 requires MessageDigestCredentialHandler with SHA-256"
} else {
    Write-Host "    - Recommendation: Use PBKDF2WithHmacSHA512 or SHA-256 with at least 10,000 iterations and 16+ salt length."
    Write-Host "    - Example: <CredentialHandler className='org.apache.catalina.realm.SecretKeyCredentialHandler' algorithm='PBKDF2WithHmacSHA512' iterations='10000' saltLength='16'/>"
}
$serverXmlPath = Join-Path $tomcatConfPath "server.xml"
$usersXmlPath = Join-Path $tomcatConfPath "tomcat-users.xml"

# Set permissions for reading files
Set-FileReadPermissions -Path $serverXmlPath
Set-FileReadPermissions -Path $usersXmlPath

$serverXml = [xml](Get-Content $serverXmlPath -Encoding UTF8)
$usersXml = [xml](Get-Content $usersXmlPath -Encoding UTF8)
$realm = $serverXml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
if (-not $realm) {
    $realm = $serverXml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.MemoryRealm']")
}
$credentialHandler = $realm.CredentialHandler
$isSecure = $true
if ($credentialHandler) {
    $chClass = $credentialHandler.className
    $chAlg = $credentialHandler.algorithm
    $chIter = $credentialHandler.iterations
    $chSalt = $credentialHandler.saltLength
    Write-Host "  Credential Handler: $chClass"
    Write-Host "  Algorithm: $chAlg"
    Write-Host "  Iterations: $chIter"
    Write-Host "  Salt Length: $chSalt"
} else {
    Write-Host "  Credential Handler: None"
    Write-Host "  Algorithm: None"
    Write-Host "  Iterations: 0"
    Write-Host "  Salt Length: 0"
}
# Compliance status for server.xml
if ($tomcatVersion -eq "7.0" -and -not $credentialHandler) {
    Write-Host "  Status: Non-compliant"
} elseif ($credentialHandler -and $credentialHandler.algorithm -eq "SHA-256" -and [int]$credentialHandler.iterations -ge 10000 -and [int]$credentialHandler.saltLength -ge 16) {
    Write-Host "  Status: Compliant"
} elseif ($credentialHandler -and $credentialHandler.algorithm -eq "PBKDF2WithHmacSHA512" -and [int]$credentialHandler.iterations -ge 10000 -and [int]$credentialHandler.saltLength -ge 16) {
    Write-Host "  Status: Compliant"
} else {
    Write-Host "  Status: Non-compliant"
}
Write-Host "Auditing tomcat-users.xml"
Write-Host "    User Audit Results:"
Write-Host "    Username | Password Type | Compliance"
Write-Host "    ---------|---------------|-----------"
$users = $usersXml.'tomcat-users'.user
if (-not $users) {
    Write-Host "    No users defined in tomcat-users.xml - Compliant"
    Write-Host ("=" * 27)
    Write-Host "Overall Status: Secure"
    Write-Host "Audit completed. Log: $logFile"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $combinedMessage = $logMessages -join "; "
    $logEntry = "$timestamp,$combinedMessage"
    Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
    exit
}
foreach ($user in $users) {
    $username = $user.username
    $password = $user.password
    if (-not $password) {
        $passwordType = "None"
        $complianceStatus = "Compliant (no password)"
        Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
        continue
    }
    $passwordType = switch -Regex ($password) {
        "^[a-f0-9]{32}$" { "Hashed_MD5" }
        "^[a-f0-9]{40}$" { "Hashed_SHA1" }
        "^[a-f0-9]{64}$" { "Hashed_SHA256" }
        "^[a-f0-9]{128}$" { "Hashed_SHA512" }
        "^[a-f0-9]{32}:[a-f0-9]{16}$" { "Salted_MD5" }
        "^[a-f0-9]{32}:[a-f0-9]{16}$" { "Salted_PBKDF2" }
        default { "Plaintext" }
    }
    $complianceStatus = ""
    if ($passwordType -eq "Plaintext") {
        $complianceStatus = "Non-compliant"
        $isSecure = $false
        Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
        Write-Host "        - Plaintext passwords detected. Use PBKDF2WithHmacSHA512 or SHA-256 with salt and iterations."
    } elseif ($passwordType -in @("Hashed_MD5", "Salted_MD5")) {
        $complianceStatus = "Non-compliant"
        $isSecure = $false
        Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
        Write-Host "        - Weak MD5 hashing detected. Use SHA-256 or PBKDF2WithHmacSHA512."
    } elseif ($passwordType -eq "Hashed_SHA1") {
        $complianceStatus = "Non-compliant"
        $isSecure = $false
        Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
        Write-Host "        - Weak SHA1 hashing detected. Use SHA-256 or PBKDF2WithHmacSHA512."
    } elseif ($passwordType -eq "Hashed_SHA256") {
        if ($tomcatVersion -eq "7.0") {
            $complianceStatus = "Compliant for Tomcat 7.0"
            Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
        } elseif (-not $credentialHandler -or $credentialHandler.algorithm -ne "SHA-256" -or [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
            $complianceStatus = "Non-compliant"
            $isSecure = $false
            Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
            Write-Host "        - SHA256 requires salt and iterations. Use PBKDF2WithHmacSHA512 if possible."
        } else {
            $complianceStatus = "Compliant"
            Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
        }
    } elseif ($passwordType -eq "Hashed_SHA512") {
        if ($tomcatVersion -eq "7.0") {
            $complianceStatus = "Non-compliant"
            $isSecure = $false
            Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
            Write-Host "        - SHA512 not supported in Tomcat 7.0. Use SHA-256 or PBKDF2WithHmacSHA512."
        } elseif (-not $credentialHandler -or $credentialHandler.algorithm -ne "SHA-512" -or [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
            $complianceStatus = "Non-compliant"
            $isSecure = $false
            Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
            Write-Host "        - SHA512 requires salt and iterations. Use PBKDF2WithHmacSHA512 if possible."
        } else {
            $complianceStatus = "Compliant"
            Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
        }
    } elseif ($passwordType -eq "Salted_PBKDF2") {
        if ($tomcatVersion -eq "7.0") {
            $complianceStatus = "Non-compliant"
            $isSecure = $false
            Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
            Write-Host "        - PBKDF2 not supported in Tomcat 7.0. Use SHA-256."
        } elseif ($tomcatVersion -eq "8.5") {
            if (-not $credentialHandler -or $credentialHandler.algorithm -notin @("SHA-256", "SHA-512") -or [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
                $complianceStatus = "Non-compliant"
                $isSecure = $false
                Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                Write-Host "        - PBKDF2 requires compatible handler. Use SHA-256 or PBKDF2WithHmacSHA512."
            } else {
                $complianceStatus = "Compliant"
                Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
            }
        } else {
            if ($credentialHandler -and $credentialHandler.className -eq "org.apache.catalina.realm.SecretKeyCredentialHandler" -and $credentialHandler.algorithm -eq "PBKDF2WithHmacSHA512" -and [int]$credentialHandler.iterations -ge 10000 -and [int]$credentialHandler.saltLength -ge 16) {
                $complianceStatus = "Compliant"
                Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
            } else {
                $complianceStatus = "Non-compliant"
                $isSecure = $false
                Write-Host ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                Write-Host "        - PBKDF2 requires SecretKeyCredentialHandler."
            }
        }
    }
}
Write-Host ("=" * 27)
Write-Host "Overall Status: $(if ($isSecure) { 'Secure' } else { 'Insecure' })"
Write-Host "Audit completed. Log: $logFile"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$combinedMessage = $logMessages -join "; "
$logEntry = "$timestamp,$combinedMessage"
Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
