# test_config_win.ps1
# Tests CheckTomcatConfigWin.ps1 for various Tomcat configurations

# Log setup
$logFile = "$env:LOCALAPPDATA\Temp\TestTomcatConfig.log"
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
    Write-Output "[$timestamp] $Message"
}

Write-Log "Starting tests for CheckTomcatConfigWin.ps1..."

# Resolve script path relative to this script's location
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $scriptDir "CheckTomcatConfigWin.ps1"
Write-Log "Resolved script path: $scriptPath"

# Verify script exists
if (-not (Test-Path $scriptPath)) {
    Write-Log "Error: CheckTomcatConfigWin.ps1 not found at $scriptPath"
    Write-Log "Please ensure CheckTomcatConfigWin.ps1 is in the same directory as test_config_win.ps1"
    exit 1
}
Write-Log "Verified file exists: $scriptPath"

# Clear existing log
if (Test-Path $logFile) {
    Clear-Content $logFile
    Write-Log "Cleared existing log file: $logFile"
}

# Test configuration
$testTomcatPath = "C:\Program Files (x86)\Apache Software Foundation\Tomcat 10.1"
$testConfPath = Join-Path $testTomcatPath "conf"
$backupPath = "$env:LOCALAPPDATA\Temp\TomcatConfigBackup"
$serverXmlPath = Join-Path $testConfPath "server.xml"
$usersXmlPath = Join-Path $testConfPath "tomcat-users.xml"

# Stop Tomcat service to avoid file locks
try {
    $tomcatService = Get-Service -Name "Tomcat*" -ErrorAction SilentlyContinue
    if ($tomcatService -and $tomcatService.Status -eq "Running") {
        Write-Log "Stopping Tomcat service to avoid file locks..."
        Stop-Service -Name $tomcatService.Name -Force -ErrorAction Stop
        Start-Sleep -Seconds 2
        Write-Log "Tomcat service stopped"
    }
} catch {
    Write-Log "Warning: Could not stop Tomcat service: $($_.Exception.Message)"
}

# Backup original files
if (-not (Test-Path $backupPath)) {
    New-Item -Path $backupPath -ItemType Directory -ErrorAction Stop | Out-Null
}
if (Test-Path $serverXmlPath) {
    Copy-Item -Path $serverXmlPath -Destination $backupPath -Force -ErrorAction Stop
}
if (Test-Path $usersXmlPath) {
    Copy-Item -Path $usersXmlPath -Destination $backupPath -Force -ErrorAction Stop
}
Write-Log "Backed up original files to $backupPath"

# Create test directory if it doesn't exist
if (-not (Test-Path $testConfPath)) {
    New-Item -Path $testConfPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
}

# Function to validate XML
function Test-ValidXml {
    param($XmlString)
    try {
        [xml]$XmlString | Out-Null
        return $true
    } catch {
        return $false
    }
}

# XML Templates
$serverXmlBase = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">{0}</Realm>
    </Engine>
  </Service>
</Server>
"@

$usersXmlBase = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="{0}" roles="manager"/>
</tomcat-users>
"@

# CredentialHandler Configurations
$credentialHandlers = @(
    @{
        Name = "NoCredentialHandler"
        Xml = ""
    },
    @{
        Name = "MessageDigestCredentialHandler_MD5"
        Xml = '<CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="MD5"/>'
    },
    @{
        Name = "MessageDigestCredentialHandler_SHA256"
        Xml = '<CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-256" iterations="10000" saltLength="16"/>'
    },
    @{
        Name = "MessageDigestCredentialHandler_SHA512"
        Xml = '<CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-512" iterations="10000" saltLength="16"/>'
    },
    @{
        Name = "NestedCredentialHandler"
        Xml = '<CredentialHandler className="org.apache.catalina.realm.NestedCredentialHandler"/>'
    },
    @{
        Name = "SecretKeyCredentialHandler_PBKDF2"
        Xml = '<CredentialHandler className="org.apache.catalina.realm.SecretKeyCredentialHandler" algorithm="PBKDF2WithHmacSHA512" iterations="10000" saltLength="16"/>'
    }
)

# Password Configurations
$passwords = @(
    @{
        Type = "Plaintext"
        Value = "password123"
        ExpectedSecure = $false
    },
    @{
        Type = "Hashed_MD5"
        Value = "5f4dcc3b5aa765d61d8327deb882cf99"
        ExpectedSecure = $false
    },
    @{
        Type = "Hashed_SHA1"
        Value = "7c4a8d09ca3762af61e59520943dc26494f8941b"
        ExpectedSecure = $false
    },
    @{
        Type = "Hashed_SHA256"
        Value = "a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3"
        ExpectedSecure = $false
    },
    @{
        Type = "Hashed_SHA512"
        Value = "c775e7b757ede630cd0aa1113bd102661ab38829ca52a6422ab782862f268646e6b4b3b4f1f2f3f4f5f6f7f8f9f0a1b2c3d4e5f60718293a4b6f7e8c9d0a1b2c"
        ExpectedSecure = $false
    },
    @{
        Type = "Salted_MD5"
        Value = "5f4dcc3b5aa765d61d8327deb882cf99:1234567890abcdef"
        ExpectedSecure = $false
    },
    @{
        Type = "Salted_PBKDF2"
        Value = "4b6f7e8c9d0a1b2c3d4e5f60718293a4b6f7e8c9d0a1b2c3d4e5f60718293a4:1234567890abcdef"
        ExpectedSecure = $false
    }
)

# Generate Test Cases
$testCases = @()
$version = "10.0"
foreach ($handler in $credentialHandlers) {
    foreach ($password in $passwords) {
        if (-not $handler.Name -or -not $password.Type) {
            Write-Log "Skipping invalid test case: Handler=$($handler.Name), Password=$($password.Type)"
            continue
        }
        $testName = "${version}_$($handler.Name)_$($password.Type)"
        Write-Log "Generated test case: $testName"
        $serverXml = $serverXmlBase -f $handler.Xml
        $usersXml = $usersXmlBase -f $password.Value
        $expectedSecure = $password.ExpectedSecure
        # Override ExpectedSecure for specific secure combinations
        if ($handler.Name -eq "MessageDigestCredentialHandler_SHA256" -and $password.Type -eq "Hashed_SHA256") {
            $expectedSecure = $true
        }
        if ($handler.Name -eq "MessageDigestCredentialHandler_SHA512" -and $password.Type -eq "Hashed_SHA512") {
            $expectedSecure = $true
        }
        if ($handler.Name -eq "SecretKeyCredentialHandler_PBKDF2" -and $password.Type -eq "Salted_PBKDF2") {
            $expectedSecure = $true
        }
        $testCases += @{
            Name = $testName
            Version = $version
            ServerXml = $serverXml
            UsersXml = $usersXml
            ExpectedSecure = $expectedSecure
        }
    }
}

# Verify test cases
if ($testCases.Count -eq 0) {
    Write-Log "Error: No test cases generated"
    exit 1
}
Write-Log "Generated $($testCases.Count) test cases"

# Run tests
$totalTests = $testCases.Count
$passedTests = 0
$failedTests = 0

foreach ($test in $testCases) {
    Write-Log "Running test: $($test.Name) for Tomcat $($test.Version)"

    # Validate XML content
    if (-not (Test-ValidXml $test.ServerXml)) {
        Write-Log "Error: Invalid server.xml content for test $($test.Name)"
        $failedTests++
        continue
    }
    if (-not (Test-ValidXml $test.UsersXml)) {
        Write-Log "Error: Invalid tomcat-users.xml content for test $($test.Name)"
        $failedTests++
        continue
    }

    # Write test configuration with timeout
    try {
        $job = Start-Job -ScriptBlock {
            param($path, $content)
            Set-Content -Path $path -Value $content -Encoding UTF8 -ErrorAction Stop
        } -ArgumentList $serverXmlPath, $test.ServerXml
        Wait-Job -Job $job -Timeout 5 | Out-Null
        if ($job.State -eq "Running") { throw "Timeout writing server.xml" }
        Receive-Job -Job $job -ErrorAction Stop
        Remove-Job -Job $job -Force

        $job = Start-Job -ScriptBlock {
            param($path, $content)
            Set-Content -Path $path -Value $content -Encoding UTF8 -ErrorAction Stop
        } -ArgumentList $usersXmlPath, $test.UsersXml
        Wait-Job -Job $job -Timeout 5 | Out-Null
        if ($job.State -eq "Running") { throw "Timeout writing tomcat-users.xml" }
        Receive-Job -Job $job -ErrorAction Stop
        Remove-Job -Job $job -Force
    } catch {
        Write-Log "Error writing test configuration files: $($_.Exception.Message)"
        $failedTests++
        continue
    }

    # Validate configuration files
    if (-not (Test-Path $serverXmlPath) -or -not (Test-Path $usersXmlPath)) {
        Write-Log "Error: Test configuration files not created"
        $failedTests++
        continue
    }

    # Run script with timeout
    try {
        $job = Start-Job -ScriptBlock {
            param($scriptPath)
            # Ensure the script path is valid in the job context
            if (-not (Test-Path $scriptPath)) {
                throw "Script not found at $scriptPath"
            }
            & $scriptPath 2>&1
        } -ArgumentList $scriptPath
        $output = Wait-Job -Job $job -Timeout 10 | Receive-Job
        if ($job.State -eq "Running") {
            Stop-Job -Job $job
            throw "Timeout executing CheckTomcatConfigWin.ps1"
        }
        $output = $output | Out-String
        Remove-Job -Job $job -Force
    } catch {
        Write-Log "Error executing script: $($_.Exception.Message)"
        Write-Log "Script path used: $scriptPath"
        $failedTests++
        continue
    }

    Write-Log "Test output: $output"

    # Check result
    $isSecure = $output -match "Overall Configuration: Secure"
    if ($isSecure -eq $test.ExpectedSecure) {
        Write-Log "Result: PASSED"
        $passedTests++
    } else {
        Write-Log "Result: FAILED (Expected secure: $($test.ExpectedSecure), Actual secure: $isSecure, Output: $output)"
        $failedTests++
    }
}

# Restore original files
try {
    if (Test-Path (Join-Path $backupPath "server.xml")) {
        Copy-Item -Path (Join-Path $backupPath "server.xml") -Destination $serverXmlPath -Force -ErrorAction Stop
    }
    if (Test-Path (Join-Path $backupPath "tomcat-users.xml")) {
        Copy-Item -Path (Join-Path $backupPath "tomcat-users.xml") -Destination $usersXmlPath -Force -ErrorAction Stop
    }
    Write-Log "Restored original configuration files"
} catch {
    Write-Log "Error restoring original files: $($_.Exception.Message)"
}

# Restart Tomcat service if it was stopped
try {
    if ($tomcatService -and $tomcatService.Status -eq "Stopped") {
        Write-Log "Restarting Tomcat service..."
        Start-Service -Name $tomcatService.Name -ErrorAction Stop
        Write-Log "Tomcat service restarted"
    }
} catch {
    Write-Log "Warning: Could not restart Tomcat service: $($_.Exception.Message)"
}

# Summary
Write-Log "Test Summary:"
Write-Log "  Total tests run: $totalTests"
Write-Log "  Tests passed: $passedTests"
Write-Log "  Tests failed: $failedTests"

if ($failedTests -gt 0) {
    Write-Log "Some tests failed. Check $logFile for details"
    exit 1
} else {
    Write-Log "All tests passed successfully"
    exit 0
}
