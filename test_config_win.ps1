# test_config.ps1
# Tests CheckTomcatConfig.ps1 for various Tomcat configurations (7.0, 8.5, 9.0)

# Log setup
$logFile = "$env:LOCALAPPDATA\Temp\TestTomcatConfig.log"
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp $Message" | Out-File -FilePath $logFile -Append
    Write-Host "[$timestamp] $Message"
}

Write-Log "Starting tests for CheckTomcatConfig.ps1..."

# Verify script exists
if (-not (Test-Path ".\CheckTomcatConfig.ps1")) {
    Write-Log "Error: CheckTomcatConfig.ps1 not found"
    exit
}
Write-Log "Verified file exists: .\CheckTomcatConfig.ps1"

# Clear existing log
if (Test-Path $logFile) {
    Clear-Content $logFile
    Write-Log "Cleared existing log file: $logFile"
}

# Function to detect Tomcat path and version
function Get-TomcatConfigPath {
    $possiblePaths = @(
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 7.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 8.5\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 9.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 7.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 8.5\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 9.0\conf"
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

# Detect Tomcat installation
$tomcatInfo = Get-TomcatConfigPath
if (-not $tomcatInfo) {
    Write-Log "Error: No Tomcat configuration directory found"
    exit
}
$tomcatConfPath = $tomcatInfo.Path
$tomcatVersion = $tomcatInfo.Version
Write-Log "Detected Tomcat version $tomcatVersion at $tomcatConfPath"

# Backup directory
$backupDir = "$env:LOCALAPPDATA\Temp\TomcatConfigBackup"
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
if ($tomcatVersion -in @("8.5", "9.0")) {
    $serverTests += "MessageDigestCredentialHandler_SHA512"
    $serverTests += "NestedCredentialHandler"
}
if ($tomcatVersion -eq "9.0") {
    $serverTests += "SecretKeyCredentialHandler_PBKDF2"
}
if ($tomcatVersion -eq "7.0") {
    Write-Log "Limiting tests for Tomcat 7.0: Excluding SHA-512, NestedCredentialHandler, and SecretKeyCredentialHandler"
}

# Password examples (simplified for demo)
$passwordValues = @{
    "Plaintext" = "s3cret"
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
        if ($passwordTest -eq "Salted_PBKDF2" -and $serverTest -eq "SecretKeyCredentialHandler_PBKDF2" -and $tomcatVersion -ne "9.0") {
            Write-Log "Skipping Salted_PBKDF2 with SecretKeyCredentialHandler for Tomcat $tomcatVersion (not supported)"
            continue
        }
        Write-Log "Running test: ${tomcatVersion}_${serverTest}_${passwordTest} for Tomcat $tomcatVersion"

        # Modify server.xml
        $xml = [xml](Get-Content $serverXml -Encoding UTF8)
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
        $xml.Save($serverXml)

        # Modify tomcat-users.xml
        $users = [xml](Get-Content $usersXml -Encoding UTF8)
        $user = $users.SelectSingleNode("//user[@username='testuser']")
        if (-not $user) {
            $user = $users.CreateElement("user")
            $user.SetAttribute("username", "testuser")
            $user.SetAttribute("roles", "manager")
            $users.'tomcat-users'.AppendChild($user)
        }
        $user.SetAttribute("password", $passwordValues[$passwordTest])
        # Save with explicit UTF-8 encoding
        $writerSettings = New-Object System.Xml.XmlWriterSettings
        $writerSettings.Encoding = [System.Text.Encoding]::UTF8
        $writerSettings.Indent = $true
        $writer = [System.Xml.XmlWriter]::Create($usersXml, $writerSettings)
        $users.Save($writer)
        $writer.Close()

        # Run CheckTomcatConfig.ps1
        $output = & ".\CheckTomcatConfig.ps1" 2>&1
        Write-Log "Test output: $output"
    }
}

# Restore original files
Copy-Item "$backupDir\server.xml.bak" $serverXml -Force
Copy-Item "$backupDir\tomcat-users.xml.bak" $usersXml -Force
Write-Log "Restored original configuration files"

Write-Log "All tests completed successfully"
