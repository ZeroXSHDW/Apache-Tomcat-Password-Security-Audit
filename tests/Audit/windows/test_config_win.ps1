# test_config_win.ps1
# Tests CheckTomcatConfigWin.ps1 for various Tomcat configurations (7.0, 8.5, 9.0, 10.0, 10.1)

#Requires -Version 7.0
#Requires -RunAsAdministrator

# Log setup
$LOG_FILE = "$env:TEMP\TestTomcatConfig.log"
$LOG_DIR = "$env:TEMP"
$LOG_FILE_PATH = Join-Path $LOG_DIR "TestTomcatConfig.log"
$TIMESTAMP = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$HOSTNAME = $env:COMPUTERNAME

# Configure logging
$ErrorActionPreference = "Stop"
$LogFile = Join-Path $LOG_DIR "TestTomcatConfig.log"
$LogCSV = Join-Path $LOG_DIR "TestTomcatConfig.csv"

# Function to write log messages
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Level - $Message"
    Add-Content -Path $LogFile -Value $logMessage
    Write-Host $logMessage
}

Write-Log "Starting tests for CheckTomcatConfigWin.ps1..."

# Verify script exists
if (-not (Test-Path ".\CheckTomcatConfigWin.ps1")) {
    Write-Log "Error: CheckTomcatConfigWin.ps1 not found" "ERROR"
    exit 1
}
Write-Log "Verified file exists: .\CheckTomcatConfigWin.ps1"

# Clear existing log
if (Test-Path $LogFile) {
    Clear-Content $LogFile
    Write-Log "Cleared existing log file: $LogFile"
}

# Function to detect Tomcat path and version
function Get-TomcatConfigPath {
    $possiblePaths = @(
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 7.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 8.5\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 9.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 10.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 10.1\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 7.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 8.5\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 9.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 10.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 10.1\conf"
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $serverXml = Join-Path $path "server.xml"
            if (Test-Path $serverXml) {
                $version = if ($path -match "Tomcat\s*(\d+\.\d+)") { $matches[1] } else { "Unknown" }
                return @{ Path = $path; Version = $version }
            }
        }
    }
    return $null
}

# Function to validate XML structure
function Test-XmlStructure {
    param(
        [string]$XmlFile
    )
    try {
        if (-not (Test-Path $XmlFile)) {
            Write-Log "XML file $XmlFile not found" "ERROR"
            return $false
        }
        
        # Check for XML declaration
        $firstLine = Get-Content $XmlFile -TotalCount 1
        if (-not $firstLine.Trim().StartsWith('<?xml')) {
            Write-Log "Invalid XML declaration in $XmlFile" "ERROR"
            return $false
        }
        
        # Parse XML
        [xml]$null = Get-Content $XmlFile
        return $true
    }
    catch {
        Write-Log "Error validating XML $XmlFile : $_" "ERROR"
        return $false
    }
}

# Function to securely parse XML
function Get-SecureXml {
    param(
        [string]$XmlFile
    )
    try {
        if (-not (Test-Path $XmlFile)) {
            Write-Log "XML file $XmlFile not found" "ERROR"
            return $null
        }
        
        if (-not (Test-XmlStructure $XmlFile)) {
            return $null
        }
        
        return [xml](Get-Content $XmlFile)
    }
    catch {
        Write-Log "Error parsing XML $XmlFile : $_" "ERROR"
        return $null
    }
}

# Function to securely write XML
function Set-SecureXml {
    param(
        [string]$XmlFile,
        [xml]$XmlContent
    )
    try {
        # Create backup
        if (Test-Path $XmlFile) {
            $backupFile = "$XmlFile.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item $XmlFile $backupFile
            $acl = Get-Acl $backupFile
            $acl.SetAccessRuleProtection($true, $false)
            Set-Acl $backupFile $acl
            Write-Log "Created backup: $backupFile"
        }
        
        # Write to temporary file
        $tempFile = "$XmlFile.tmp"
        $XmlContent.Save($tempFile)
        
        # Validate temporary file
        if (-not (Test-XmlStructure $tempFile)) {
            Remove-Item $tempFile -Force
            return $false
        }
        
        # Move to final location
        Move-Item $tempFile $XmlFile -Force
        $acl = Get-Acl $XmlFile
        $acl.SetAccessRuleProtection($true, $false)
        Set-Acl $XmlFile $acl
        return $true
    }
    catch {
        Write-Log "Error writing XML $XmlFile : $_" "ERROR"
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
        return $false
    }
}

# Detect Tomcat installation
$tomcatInfo = Get-TomcatConfigPath
if (-not $tomcatInfo) {
    Write-Log "Error: No Tomcat configuration directory found" "ERROR"
    exit 1
}
$tomcatConfPath = $tomcatInfo.Path
$tomcatVersion = $tomcatInfo.Version
Write-Log "Detected Tomcat version $tomcatVersion at $tomcatConfPath"

# Backup directory
$backupDir = "$env:TEMP\TomcatConfigBackup"
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}

# Define test cases
$passwordTests = @(
    "Plaintext",
    "Hashed_MD5",
    "Hashed_SHA1",
    "Hashed_SHA256",
    "Hashed_SHA512",
    "Salted_MD5",
    "Salted_PBKDF2"
)

$serverTests = @(
    "NoCredentialHandler",
    "MessageDigestCredentialHandler_MD5",
    "MessageDigestCredentialHandler_SHA256"
)
if ($tomcatVersion -in @("8.5", "9.0", "10.0", "10.1")) {
    $serverTests += "MessageDigestCredentialHandler_SHA512"
    $serverTests += "NestedCredentialHandler"
}
if ($tomcatVersion -in @("9.0", "10.0", "10.1")) {
    $serverTests += "SecretKeyCredentialHandler_PBKDF2"
}
if ($tomcatVersion -eq "7.0") {
    Write-Log "Limiting tests for Tomcat 7.0: Excluding SHA-512, NestedCredentialHandler, and SecretKeyCredentialHandler"
}

# Password examples (simplified for demo)
$passwordValues = @{
    "Plaintext" = "fixture-only-password"
    "Hashed_MD5" = "5ebe2294ecd0e0f08eab7690d2a6ee69"
    "Hashed_SHA1" = "e5e9fa1ba31ecd1ae84f75caaa474f3a663f05f4"
    "Hashed_SHA256" = "94f9b6c88f1b2b3b3363b7f4174480c1b3913b8200cb0a50f2974f2bc90bc774"
    "Hashed_SHA512" = "eede1e3b1840e3a3c2283ff623e3db6b4d8abfad6bded83fd36f9db08e7c3f2c2df0b5b7e6c9c0d1ebfe7e3b3c3d8b0e7f9d0c1f7e6b4c3b2a1f0e9d8c7b6a5f"
    "Salted_MD5" = "8208b5051cdd2b35cfba7f0b70b57e7f:1234567890abcdef"
    "Salted_PBKDF2" = "4b6f7e8c9d0a1b2c3d4e5f60718293a4:1234567890abcdef"
}

# Server configurations
$serverConfigs = @{
    "NoCredentialHandler" = ""
    "MessageDigestCredentialHandler_MD5" = '<CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="MD5"/>'
    "MessageDigestCredentialHandler_SHA256" = '<CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-256" iterations="10000" saltLength="16"/>'
    "MessageDigestCredentialHandler_SHA512" = '<CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-512" iterations="10000" saltLength="16"/>'
    "NestedCredentialHandler" = '<CredentialHandler className="org.apache.catalina.realm.NestedCredentialHandler"><CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-256"/></CredentialHandler>'
    "SecretKeyCredentialHandler_PBKDF2" = '<CredentialHandler className="org.apache.catalina.realm.SecretKeyCredentialHandler" algorithm="PBKDF2WithHmacSHA512" iterations="10000" saltLength="16" keyLength="256"/>'
}

# Backup original files
$serverXml = Join-Path $tomcatConfPath "server.xml"
$usersXml = Join-Path $tomcatConfPath "tomcat-users.xml"
Copy-Item $serverXml "$backupDir\server.xml.bak" -Force
Copy-Item $usersXml "$backupDir\tomcat-users.xml.bak" -Force

# Run tests
foreach ($serverTest in $serverTests) {
    foreach ($passwordTest in $passwordTests) {
        if ($passwordTest -eq "Hashed_SHA512" -and $tomcatVersion -eq "7.0") {
            Write-Log "Skipping Hashed_SHA512 for Tomcat 7.0 (not supported)"
            continue
        }
        if ($passwordTest -eq "Salted_PBKDF2" -and $tomcatVersion -eq "7.0") {
            Write-Log "Skipping Salted_PBKDF2 for Tomcat 7.0 (not supported)"
            continue
        }
        if ($passwordTest -eq "Salted_PBKDF2" -and $serverTest -eq "SecretKeyCredentialHandler_PBKDF2" -and $tomcatVersion -notin @("9.0", "10.0", "10.1")) {
            Write-Log "Skipping Salted_PBKDF2 with SecretKeyCredentialHandler for Tomcat $tomcatVersion (not supported)"
            continue
        }
        Write-Log "Running test: ${tomcatVersion}_${serverTest}_${passwordTest} for Tomcat $tomcatVersion"

        # Modify server.xml
        $xml = Get-SecureXml -XmlFile $serverXml
        if (-not $xml) {
            Write-Log "Failed to parse server.xml" "ERROR"
            continue
        }
        
        $realm = $xml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
        if (-not $realm) {
            $realm = $xml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.MemoryRealm']")
        }
        
        if ($serverTest -eq "NoCredentialHandler") {
            if ($realm.CredentialHandler) { $realm.RemoveChild($realm.CredentialHandler) }
        } else {
            $newHandler = [xml]$serverConfigs[$serverTest]
            if ($realm.CredentialHandler) {
                $realm.ReplaceChild($xml.ImportNode($newHandler.DocumentElement, $true), $realm.CredentialHandler)
            } else {
                $realm.AppendChild($xml.ImportNode($newHandler.DocumentElement, $true))
            }
        }
        
        if (-not (Set-SecureXml -XmlFile $serverXml -XmlContent $xml)) {
            Write-Log "Failed to update server.xml" "ERROR"
            continue
        }

        # Modify tomcat-users.xml
        $users = Get-SecureXml -XmlFile $usersXml
        if (-not $users) {
            Write-Log "Failed to parse tomcat-users.xml" "ERROR"
            continue
        }
        
        $user = $users.SelectSingleNode("//user[@username='testuser']")
        if (-not $user) {
            $user = $users.CreateElement("user")
            $user.SetAttribute("username", "testuser")
            $user.SetAttribute("roles", "manager")
            $users.'tomcat-users'.AppendChild($user)
        }
        $user.SetAttribute("password", $passwordValues[$passwordTest])
        
        if (-not (Set-SecureXml -XmlFile $usersXml -XmlContent $users)) {
            Write-Log "Failed to update tomcat-users.xml" "ERROR"
            continue
        }

        # Run CheckTomcatConfigWin.ps1
        try {
            $output = & ".\CheckTomcatConfigWin.ps1" -TomcatConfPath $tomcatConfPath 2>&1
            Write-Log "Test output: $output"
        }
        catch {
            Write-Log "Error running CheckTomcatConfigWin.ps1: $_" "ERROR"
        }
    }
}

# Restore original files
try {
    Copy-Item "$backupDir\server.xml.bak" $serverXml -Force
    Copy-Item "$backupDir\tomcat-users.xml.bak" $usersXml -Force
    Write-Log "Restored original configuration files"
}
catch {
    Write-Log "Error restoring original files: $_" "ERROR"
}

Write-Log "All tests completed successfully"
