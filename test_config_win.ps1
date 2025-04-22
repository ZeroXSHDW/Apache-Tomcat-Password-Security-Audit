# test_config_win.ps1
# Tests CheckTomcatConfigWin.ps1 for various Tomcat configurations (7.x, 8.0.x, 8.5.x, 9.x, 10.x)

# Log setup
$logFile = "$env:LOCALAPPDATA\Temp\TestTomcatConfig.log"
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp $Message" | Out-File -FilePath $logFile -Append
    Write-Host "[$timestamp] $Message"
}

Write-Log "Starting tests for CheckTomcatConfigWin.ps1..."

# Verify script exists
if (-not (Test-Path ".\CheckTomcatConfigWin.ps1")) {
    Write-Log "Error: CheckTomcatConfigWin.ps1 not found"
    exit 1
}
Write-Log "Verified file exists: .\CheckTomcatConfigWin.ps1"

# Clear existing log
if (Test-Path $logFile) {
    Clear-Content $logFile
    Write-Log "Cleared existing log file: $logFile"
}

# Function to detect Tomcat path and version
function Get-TomcatConfigPath {
    # Check CATALINA_HOME first
    $catalinaHome = [System.Environment]::GetEnvironmentVariable("CATALINA_HOME")
    if ($catalinaHome) {
        $confPath = Join-Path $catalinaHome "conf"
        $serverXml = Join-Path $confPath "server.xml"
        if (Test-Path $serverXml) {
            $version = if ($catalinaHome -match "Tomcat\s*(\d+\.\d+\.\d+|\d+\.\d+)") { $matches[1] } else { "Unknown" }
            if ($version -match "^7\.") { $version = "7.0" }
            elseif ($version -match "^8\.0") { $version = "8.0" }
            elseif ($version -match "^8\.5") { $version = "8.5" }
            elseif ($version -match "^9\.") { $version = "9.0" }
            elseif ($version -match "^10\.") { $version = "10.0" }
            Write-Log "Found Tomcat configuration at CATALINA_HOME: $confPath"
            return @{ Path = $confPath; Version = $version }
        } else {
            Write-Log "CATALINA_HOME set to $catalinaHome, but no valid conf/server.xml found"
        }
    } else {
        Write-Log "CATALINA_HOME not set"
    }

    # Search common paths
    $basePaths = @(
        "C:\Program Files\Apache Software Foundation",
        "C:\Program Files (x86)\Apache Software Foundation",
        "C:\Apache\Tomcat",
        "C:\Tomcat"
    )
    $versionPatterns = @(
        "Tomcat 7.*",
        "Tomcat 8.0.*",
        "Tomcat 8.5.*",
        "Tomcat 9.*",
        "Tomcat 10.*"
    )

    foreach ($base in $basePaths) {
        if (-not (Test-Path $base)) {
            Write-Log "Base path $base does not exist"
            continue
        }
        foreach ($pattern in $versionPatterns) {
            $dirs = Get-ChildItem -Path $base -Directory -Filter $pattern -ErrorAction SilentlyContinue
            foreach ($dir in $dirs) {
                $confPath = Join-Path $dir.FullName "conf"
                $serverXml = Join-Path $confPath "server.xml"
                if (Test-Path $serverXml) {
                    $version = if ($dir.Name -match "Tomcat\s*(\d+\.\d+\.\d+|\d+\.\d+)") { $matches[1] } else { "Unknown" }
                    if ($version -match "^7\.") { $version = "7.0" }
                    elseif ($version -match "^8\.0") { $version = "8.0" }
                    elseif ($version -match "^8\.5") { $version = "8.5" }
                    elseif ($version -match "^9\.") { $version = "9.0" }
                    elseif ($version -match "^10\.") { $version = "10.0" }
                    Write-Log "Found Tomcat configuration at $confPath"
                    return @{ Path = $confPath; Version = $version }
                } else {
                    Write-Log "No server.xml found in $confPath"
                }
            }
        }
    }
    Write-Log "Error: No Tomcat configuration directory found in any searched paths"
    return $null
}

# Detect Tomcat installation
$tomcatInfo = Get-TomcatConfigPath
if (-not $tomcatInfo) {
    Write-Log "Error: No Tomcat configuration directory found"
    exit 1
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
if ($tomcatVersion -in @("8.0", "8.5", "9.0", "10.0")) {
    $serverTests += "MessageDigestCredentialHandler_SHA512"
    $serverTests += "NestedCredentialHandler"
}
if ($tomcatVersion -in @("9.0", "10.0")) {
    $serverTests += "SecretKeyCredentialHandler_PBKDF2"
}
if ($tomcatVersion -eq "7.0") {
    Write-Log "Limiting tests for Tomcat 7.0: Excluding SHA-512, NestedCredentialHandler, and SecretKeyCredentialHandler"
}

# Password examples
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
Write-Log "Backed up original files to $backupDir"

# Track test results
$totalTests = 0
$passedTests = 0
$failedTests = 0

# Run tests
foreach ($serverTest in $serverTests) {
    foreach ($passwordTest in $passwordTests) {
        if ($passwordTest -eq "Hashed_SHA512" -and $tomcatVersion -in @("7.0", "8.0")) {
            Write-Log "Skipping Hashed_SHA512 for Tomcat $tomcatVersion (not supported)"
            continue
        }
        if ($passwordTest -eq "Salted_PBKDF2" -and $tomcatVersion -in @("7.0", "8.0")) {
            Write-Log "Skipping Salted_PBKDF2 for Tomcat $tomcatVersion (not supported)"
            continue
        }
        if ($passwordTest -eq "Salted_PBKDF2" -and $serverTest -ne "SecretKeyCredentialHandler_PBKDF2" -and $tomcatVersion -in @("9.0", "10.0")) {
            Write-Log "Skipping Salted_PBKDF2 with $serverTest for Tomcat $tomcatVersion (only supported with SecretKeyCredentialHandler)"
            continue
        }
        Write-Log "Running test: ${tomcatVersion}_${serverTest}_${passwordTest} for Tomcat $tomcatVersion"
        $totalTests++

        # Modify server.xml
        $xml = [xml](Get-Content $serverXml -Encoding UTF8)
        $realm = $xml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
        if (-not $realm) {
            $realm = $xml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.MemoryRealm']")
        }
        if ($serverTest -eq "NoCredentialHandler") {
            if ($realm.CredentialHandler) { $realm.RemoveChild($realm.CredentialHandler) | Out-Null }
        } else {
            $newHandler = [xml]$serverConfigs[$serverTest]
            if ($realm.CredentialHandler) {
                $realm.ReplaceChild($xml.ImportNode($newHandler.DocumentElement, $true), $realm.CredentialHandler) | Out-Null
            } else {
                $realm.AppendChild($xml.ImportNode($newHandler.DocumentElement, $true)) | Out-Null
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
            $users.'tomcat-users'.AppendChild($user) | Out-Null
        }
        $user.SetAttribute("password", $passwordValues[$passwordTest])

        # Save with explicit UTF-8 encoding
        $writerSettings = New-Object System.Xml.XmlWriterSettings
        $writerSettings.Encoding = [System.Text.Encoding]::UTF8
        $writerSettings.Indent = $true
        $writer = [System.Xml.XmlWriter]::Create($usersXml, $writerSettings)
        $users.Save($writer)
        $writer.Close()

        # Run CheckTomcatConfigWin.ps1 and capture output
        $output = & ".\CheckTomcatConfigWin.ps1" | Out-String
        Write-Log "Test output: $output"

        # Validate test result
        $isSecure = $output -match "Compliant" -or $output -match "Secure"
        $expectedSecure = switch ($passwordTest) {
            "Plaintext" { $false }
            "Hashed_MD5" { $false }
            "Hashed_SHA1" { $false }
            "Salted_MD5" { $false }
            "Hashed_SHA256" {
                $tomcatVersion -eq "7.0" -or (
                    $serverTest -eq "MessageDigestCredentialHandler_SHA256" -and
                    $tomcatVersion -notin @("7.0")
                )
            }
            "Hashed_SHA512" {
                $serverTest -eq "MessageDigestCredentialHandler_SHA512" -and
                $tomcatVersion -notin @("7.0", "8.0")
            }
            "Salted_PBKDF2" {
                $serverTest -eq "SecretKeyCredentialHandler_PBKDF2" -and
                $tomcatVersion -in @("9.0", "10.0")
            }
            default { $false }
        }

        if ($isSecure -eq $expectedSecure) {
            Write-Log "Result: PASSED"
            $passedTests++
        } else {
            Write-Log "Result: FAILED (Expected secure: $expectedSecure, Actual output: $output)"
            $failedTests++
        }
    } # End passwordTests loop
} # End serverTests loop

# Restore original files
Copy-Item "$backupDir\server.xml.bak" $serverXml -Force
Copy-Item "$backupDir\tomcat-users.xml.bak" $usersXml -Force
Write-Log "Restored original configuration files"

# Summarize results
Write-Log "Test Summary:"
Write-Log "  Total tests run: $totalTests"
Write-Log "  Tests passed: $passedTests"
Write-Log "  Tests failed: $failedTests"
if ($failedTests -eq 0) {
    Write-Log "All tests completed successfully"
} else {
    Write-Log "Some tests failed. Check $logFile for details"
}
