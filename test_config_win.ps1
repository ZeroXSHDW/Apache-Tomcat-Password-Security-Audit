# test_config_win.ps1
# Tests for CheckTomcatConfigWin.ps1 to validate Apache Tomcat configuration security

# Log setup
$logFile = "$env:LOCALAPPDATA\Temp\TestTomcatConfig.log"
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
    Write-Output "[$timestamp] $Message"
}

Write-Log "Starting tests for CheckTomcatConfigWin.ps1..."

# Verify script exists
$scriptPath = ".\CheckTomcatConfigWin.ps1"
if (-not (Test-Path $scriptPath)) {
    Write-Log "Error: CheckTomcatConfigWin.ps1 not found"
    exit 1
}
Write-Log "Verified file exists: $scriptPath"

# Clear existing log
if (Test-Path $logFile) {
    Clear-Content $logFile
    Write-Log "Cleared existing log file: $logFile"
}

# Backup and restore configuration files
$tomcatConfPath = "C:\Program Files (x86)\Apache Software Foundation\Tomcat 10.1\conf"
$serverXmlPath = Join-Path $tomcatConfPath "server.xml"
$usersXmlPath = Join-Path $tomcatConfPath "tomcat-users.xml"
$backupPath = "$env:LOCALAPPDATA\Temp\TomcatConfigBackup"

function Backup-Config {
    if (-not (Test-Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath | Out-Null
    }
    Copy-Item $serverXmlPath "$backupPath\server.xml" -Force
    Copy-Item $usersXmlPath "$backupPath\tomcat-users.xml" -Force
    Write-Log "Backed up original files to $backupPath"
}

function Restore-Config {
    Copy-Item "$backupPath\server.xml" $serverXmlPath -Force
    Copy-Item "$backupPath\tomcat-users.xml" $usersXmlPath -Force
    Write-Log "Restored original configuration files"
}

# Test definitions
$tests = @(
    # NoCredentialHandler tests
    @{
        Name = "10.0_NoCredentialHandler_Plaintext"
        Version = "10.0"
        CredentialHandler = $null
        User = @{
            username = "testuser"
            password = "password123"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NoCredentialHandler_Hashed_MD5"
        Version = "10.0"
        CredentialHandler = $null
        User = @{
            username = "testuser"
            password = "5f4dcc3b5aa765d61d8327deb882cf99"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NoCredentialHandler_Hashed_SHA1"
        Version = "10.0"
        CredentialHandler = $null
        User = @{
            username = "testuser"
            password = "5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NoCredentialHandler_Hashed_SHA256"
        Version = "10.0"
        CredentialHandler = $null
        User = @{
            username = "testuser"
            password = "a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NoCredentialHandler_Hashed_SHA512"
        Version = "10.0"
        CredentialHandler = $null
        User = @{
            username = "testuser"
            password = "9e1f833ab408c8e136db274ed93b0061f0a5d790d4476e3058e8e6d4e3a3596d2c0a4524ae4b05f8e1f2f3e6f789f01ee9e8d607e9ee92f9b9e8d8c3f3d8427f6"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NoCredentialHandler_Salted_MD5"
        Version = "10.0"
        CredentialHandler = $null
        User = @{
            username = "testuser"
            password = "8208b5051cdd2b35cfba7f0b70b57e7f:1234567890abcdef"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    # MessageDigestCredentialHandler_MD5 tests
    @{
        Name = "10.0_MessageDigestCredentialHandler_MD5_Plaintext"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "MD5"
            iterations = "0"
            saltLength = "0"
        }
        User = @{
            username = "testuser"
            password = "password123"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_MD5_Hashed_MD5"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "MD5"
            iterations = "0"
            saltLength = "0"
        }
        User = @{
            username = "testuser"
            password = "5f4dcc3b5aa765d61d8327deb882cf99"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_MD5_Hashed_SHA1"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "MD5"
            iterations = "0"
            saltLength = "0"
        }
        User = @{
            username = "testuser"
            password = "5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_MD5_Hashed_SHA256"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "MD5"
            iterations = "0"
            saltLength = "0"
        }
        User = @{
            username = "testuser"
            password = "a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_MD5_Hashed_SHA512"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "MD5"
            iterations = "0"
            saltLength = "0"
        }
        User = @{
            username = "testuser"
            password = "9e1f833ab408c8e136db274ed93b0061f0a5d790d4476e3058e8e6d4e3a3596d2c0a4524ae4b05f8e1f2f3e6f789f01ee9e8d607e9ee92f9b9e8d8c3f3d8427f6"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_MD5_Salted_MD5"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "MD5"
            iterations = "0"
            saltLength = "0"
        }
        User = @{
            username = "testuser"
            password = "8208b5051cdd2b35cfba7f0b70b57e7f:1234567890abcdef"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    # MessageDigestCredentialHandler_SHA256 tests
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA256_Plaintext"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "SHA-256"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "password123"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA256_Hashed_MD5"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "SHA-256"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "5f4dcc3b5aa765d61d8327deb882cf99"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA256_Hashed_SHA1"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "SHA-256"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA256_Hashed_SHA256"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "SHA-256"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3"
            roles = "manager"
        }
        ExpectedSecure = $true
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA256_Hashed_SHA512"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "SHA-256"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "9e1f833ab408c8e136db274ed93b0061f0a5d790d4476e3058e8e6d4e3a3596d2c0a4524ae4b05f8e1f2f3e6f789f01ee9e8d607e9ee92f9b9e8d8c3f3d8427f6"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA256_Salted_MD5"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "SHA-256"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "8208b5051cdd2b35cfba7f0b70b57e7f:1234567890abcdef"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    # MessageDigestCredentialHandler_SHA512 tests
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA512_Plaintext"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "SHA-512"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "password123"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA512_Hashed_MD5"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "SHA-512"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "5f4dcc3b5aa765d61d8327deb882cf99"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA512_Hashed_SHA1"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "SHA-512"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA512_Hashed_SHA256"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "SHA-512"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA512_Hashed_SHA512"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "SHA-512"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "9e1f833ab408c8e136db274ed93b0061f0a5d790d4476e3058e8e6d4e3a3596d2c0a4524ae4b05f8e1f2f3e6f789f01ee9e8d607e9ee92f9b9e8d8c3f3d8427f6"
            roles = "manager"
        }
        ExpectedSecure = $true
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA512_Salted_MD5"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            algorithm = "SHA-512"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "8208b5051cdd2b35cfba7f0b70b57e7f:1234567890abcdef"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    # NestedCredentialHandler tests
    @{
        Name = "10.0_NestedCredentialHandler_Plaintext"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.NestedCredentialHandler"
            algorithm = "None"
            iterations = "0"
            saltLength = "0"
        }
        User = @{
            username = "testuser"
            password = "password123"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NestedCredentialHandler_Hashed_MD5"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.NestedCredentialHandler"
            algorithm = "None"
            iterations = "0"
            saltLength = "0"
        }
        User = @{
            username = "testuser"
            password = "5f4dcc3b5aa765d61d8327deb882cf99"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NestedCredentialHandler_Hashed_SHA1"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.NestedCredentialHandler"
            algorithm = "None"
            iterations = "0"
            saltLength = "0"
        }
        User = @{
            username = "testuser"
            password = "5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NestedCredentialHandler_Hashed_SHA256"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.NestedCredentialHandler"
            algorithm = "None"
            iterations = "0"
            saltLength = "0"
        }
        User = @{
            username = "testuser"
            password = "a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NestedCredentialHandler_Hashed_SHA512"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.NestedCredentialHandler"
            algorithm = "None"
            iterations = "0"
            saltLength = "0"
        }
        User = @{
            username = "testuser"
            password = "9e1f833ab408c8e136db274ed93b0061f0a5d790d4476e3058e8e6d4e3a3596d2c0a4524ae4b05f8e1f2f3e6f789f01ee9e8d607e9ee92f9b9e8d8c3f3d8427f6"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NestedCredentialHandler_Salted_MD5"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.NestedCredentialHandler"
            algorithm = "None"
            iterations = "0"
            saltLength = "0"
        }
        User = @{
            username = "testuser"
            password = "8208b5051cdd2b35cfba7f0b70b57e7f:1234567890abcdef"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    # SecretKeyCredentialHandler tests
    @{
        Name = "10.0_SecretKeyCredentialHandler_PBKDF2_Plaintext"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.SecretKeyCredentialHandler"
            algorithm = "PBKDF2WithHmacSHA512"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "password123"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_SecretKeyCredentialHandler_PBKDF2_Hashed_MD5"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.SecretKeyCredentialHandler"
            algorithm = "PBKDF2WithHmacSHA512"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "5f4dcc3b5aa765d61d8327deb882cf99"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_SecretKeyCredentialHandler_PBKDF2_Hashed_SHA1"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.SecretKeyCredentialHandler"
            algorithm = "PBKDF2WithHmacSHA512"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_SecretKeyCredentialHandler_PBKDF2_Hashed_SHA256"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.SecretKeyCredentialHandler"
            algorithm = "PBKDF2WithHmacSHA512"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_SecretKeyCredentialHandler_PBKDF2_Hashed_SHA512"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.SecretKeyCredentialHandler"
            algorithm = "PBKDF2WithHmacSHA512"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "9e1f833ab408c8e136db274ed93b0061f0a5d790d4476e3058e8e6d4e3a3596d2c0a4524ae4b05f8e1f2f3e6f789f01ee9e8d607e9ee92f9b9e8d8c3f3d8427f6"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_SecretKeyCredentialHandler_PBKDF2_Salted_MD5"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.SecretKeyCredentialHandler"
            algorithm = "PBKDF2WithHmacSHA512"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "8208b5051cdd2b35cfba7f0b70b57e7f:1234567890abcdef"
            roles = "manager"
        }
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_SecretKeyCredentialHandler_PBKDF2_Salted_PBKDF2"
        Version = "10.0"
        CredentialHandler = @{
            className = "org.apache.catalina.realm.SecretKeyCredentialHandler"
            algorithm = "PBKDF2WithHmacSHA512"
            iterations = "10000"
            saltLength = "16"
        }
        User = @{
            username = "testuser"
            password = "4b6f7e8c9d0a1b2c3d4e5f60718293a4b6f7e8c9d0a1b2c3d4e5f60718293a4:1234567890abcdef"
            roles = "manager"
        }
        ExpectedSecure = $true
    }
)

# Generate configuration files for testing
function Generate-ServerXml {
    param($Test)
    $credentialHandler = $Test.CredentialHandler
    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server port="8005" shutdown="SHUTDOWN">
    <Service name="Catalina">
        <Engine name="Catalina" defaultHost="localhost">
            <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true">
                <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
                    $(if ($credentialHandler) {
                        "<CredentialHandler className='$($credentialHandler.className)' algorithm='$($credentialHandler.algorithm)' iterations='$($credentialHandler.iterations)' saltLength='$($credentialHandler.saltLength)' />"
                    })
                </Realm>
            </Host>
        </Engine>
    </Service>
</Server>
"@
    $xml | Out-File $serverXmlPath -Encoding UTF8
}

function Generate-UsersXml {
    param($Test)
    $user = $Test.User
    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
    <user username="$($user.username)" password="$($user.password)" roles="$($user.roles)" />
</tomcat-users>
"@
    $xml | Out-File $usersXmlPath -Encoding UTF8
}

# Run tests
$totalTests = 0
$passedTests = 0
$failedTests = 0

Backup-Config

foreach ($test in $tests) {
    $testName = $test.Name
    $version = $test.Version

    # Skip unsupported tests
    if ($testName -match "Salted_PBKDF2" -and $test.CredentialHandler.className -ne "org.apache.catalina.realm.SecretKeyCredentialHandler") {
        Write-Log "Skipping $testName for Tomcat $version (only supported with SecretKeyCredentialHandler)"
        continue
    }

    Write-Log "Running test: $testName for Tomcat $version"
    $totalTests++

    # Setup configuration
    Generate-ServerXml -Test $test
    Generate-UsersXml -Test $test

    # Run script and capture output
    try {
        $output = & powershell.exe -ExecutionPolicy Bypass -File $scriptPath 2>&1
        $outputString = $output -join "`n"
        Write-Log "Test output: $outputString"
    } catch {
        Write-Log "Test failed due to script execution error: $($_.Exception.Message)"
        Write-Log "Result: FAILED"
        $failedTests++
        continue
    }

    # Check result
    if ($outputString -match "ParseException") {
        Write-Log "Result: FAILED (Script failed to execute due to syntax error)"
        $failedTests++
    } else {
        $isSecure = $outputString -match "Overall Configuration: Secure"
        $expectedSecure = $test.ExpectedSecure
        if ($isSecure -eq $expectedSecure) {
            Write-Log "Result: PASSED"
            $passedTests++
        } else {
            Write-Log "Result: FAILED (Expected secure: $expectedSecure, Actual output: $outputString)"
            $failedTests++
        }
    }
}

Restore-Config

# Summarize results
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
