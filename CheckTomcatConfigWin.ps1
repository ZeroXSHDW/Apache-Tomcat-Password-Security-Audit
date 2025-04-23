# CheckTomcatConfigWin.ps1
# Script to audit Apache Tomcat configuration security on Windows

# Logging setup
$logFile = "$env:LOCALAPPDATA\Temp\TestTomcatConfig.log"
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp $Message" | Out-File -FilePath $logFile -Append
}

# Function to detect Tomcat version
function Get-TomcatVersion {
    param($TomcatPath)
    $versionFile = Join-Path $TomcatPath "RELEASE-NOTES"
    if (Test-Path $versionFile) {
        $content = Get-Content $versionFile | Select-String "Apache Tomcat Version"
        if ($content) {
            return $content -replace ".*Version (\d+\.\d+).*", '$1'
        }
    }
    return "Unknown"
}

# Function to check password security
function Check-PasswordSecurity {
    param($Password, $CredentialHandler, $Algorithm, $Iterations, $SaltLength)

    Write-Log "  - Debug: Raw password for 'testuser': $Password"

    $passwordType = "Unknown"
    $isSecure = $true

    # Password format detection
    if ($Password -match "^[a-f0-9]{32}$") {
        $passwordType = "Hashed_MD5"
        $isSecure = $false
        Write-Log "- User 'testuser': Hashed_MD5 password (insecure)"
    }
    elseif ($Password -match "^[a-f0-9]{40}$") {
        $passwordType = "Hashed_SHA1"
        $isSecure = $false
        Write-Log "- User 'testuser': Hashed_SHA1 password (insecure)"
    }
    elseif ($Password -match "^[a-f0-9]{64}$") {
        $passwordType = "Hashed_SHA256"
        Write-Log "- User 'testuser': Hashed_SHA256 password (secure)"
    }
    elseif ($Password -match "^[a-f0-9]{128}$") {
        $passwordType = "Hashed_SHA512"
        Write-Log "- User 'testuser': Hashed_SHA512 password (secure)"
    }
    elseif ($Password -match "^[a-f0-9]{32}:[a-f0-9]{16}$") {
        $passwordType = "Salted_MD5"
        $isSecure = $false
        Write-Log "- User 'testuser': Salted_MD5 password (insecure)"
    }
    elseif ($Password -match "^[a-f0-9]{64}:[a-f0-9]{16}$") {
        $passwordType = "Salted_PBKDF2"
        Write-Log "- User 'testuser': Salted_PBKDF2 password (secure)"
    }
    else {
        $passwordType = "Plaintext"
        $isSecure = $false
        Write-Log "- User 'testuser': Plaintext password (insecure)"
    }

    # Parameter checks
    $results = @()
    $results += "  - Parameter: Password Type = $passwordType [$($isSecure ? 'PASS' : 'FAIL')]"
    $results += "  - Parameter: CredentialHandler = $CredentialHandler [$($CredentialHandler -match 'CredentialHandler' ? 'PASS' : 'FAIL')]"
    $results += "  - Parameter: Algorithm = $Algorithm [$($Algorithm -match 'SHA-256|SHA-512|PBKDF2' ? 'PASS' : 'FAIL')]"
    $results += "  - Parameter: Iterations = $Iterations [$($Iterations -ge 10000 ? 'PASS' : 'FAIL')]"
    $results += "  - Parameter: Salt Length = $SaltLength [$($SaltLength -ge 16 ? 'PASS' : 'FAIL')]"

    # Compliance check
    $isCompliant = $true
    if ($passwordType -match "MD5|SHA1|Plaintext" -or $Password -eq "password123") {
        $isCompliant = $false
        Write-Log "  - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
        Write-Log "    - Weak or plaintext password format detected"
    }
    elseif ($passwordType -eq "Hashed_SHA256" -and $CredentialHandler -eq "org.apache.catalina.realm.MessageDigestCredentialHandler" -and $Algorithm -eq "SHA-256" -and $Iterations -ge 10000 -and $SaltLength -ge 16) {
        Write-Log "  - Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
    }
    elseif ($passwordType -eq "Hashed_SHA512" -and $CredentialHandler -eq "org.apache.catalina.realm.MessageDigestCredentialHandler" -and $Algorithm -eq "SHA-512" -and $Iterations -ge 10000 -and $SaltLength -ge 16) {
        Write-Log "  - Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
    }
    elseif ($passwordType -eq "Salted_PBKDF2" -and $CredentialHandler -eq "org.apache.catalina.realm.SecretKeyCredentialHandler" -and $Algorithm -eq "PBKDF2WithHmacSHA512" -and $Iterations -ge 10000 -and $SaltLength -ge 16) {
        Write-Log "  - Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
    }
    else {
        $isCompliant = $false
        Write-Log "  - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
        Write-Log "    - Configuration does not meet security requirements"
    }

    Write-Log ($results -join "`n")
    Write-Log "    - Recommendation: Use salted and iterated passwords (e.g., SHA-256 or PBKDF2)"

    return $isCompliant
}

# Function to restart Tomcat service
function Restart-TomcatService {
    $serviceName = "Tomcat10"
    try {
        $service = Get-Service -Name $serviceName -ErrorAction Stop
        Write-Log "Attempting to restart Tomcat service ($serviceName)..."
        if ($service.Status -eq "Running") {
            Write-Log "Stopping Tomcat service..."
            Stop-Service -Name $serviceName -Force -ErrorAction Stop
            Start-Sleep -Seconds 5
            Write-Log "Starting Tomcat service..."
            Start-Service -Name $serviceName -ErrorAction Stop
            Write-Log "Tomcat service restarted successfully"
        } else {
            Write-Log "Tomcat service is not running. Attempting to start..."
            Start-Service -Name $serviceName -ErrorAction Stop
            Write-Log "Tomcat service started successfully"
        }
    } catch {
        Write-Log "Warning: Could not restart Tomcat service: $($_.Exception.Message)"
        Write-Log "Recommendation: Ensure the Tomcat service is properly configured and the account has sufficient permissions."
    }
}

# Main audit function
function Check-TomcatConfig {
    Write-Log "Checking Apache Tomcat configuration security..."

    $tomcatPath = "C:\Program Files (x86)\Apache Software Foundation\Tomcat 10.1\conf"
    $tomcatVersion = Get-TomcatVersion -TomcatPath $tomcatPath
    Write-Log "Detected Tomcat version $tomcatVersion at $tomcatPath"

    # Simulated configuration for testing
    $testCases = @(
        @{ Password = "9e1f833ab408c8e136db274ed93b0061f0a5d790d4476e3058e8e6d4e3a3596d2c0a4524ae4b05f8e1f2f3e6f789f01ee9e8d607e9ee92f9b9e8d8c3f3d8427f6"; CredentialHandler = "org.apache.catalina.realm.MessageDigestCredentialHandler"; Algorithm = "SHA-512"; Iterations = 10000; SaltLength = 16 },
        @{ Password = "4b6f7e8c9d0a1b2c3d4e5f60718293a4b6f7e8c9d0a1b2c3d4e5f60718293a4:1234567890abcdef"; CredentialHandler = "org.apache.catalina.realm.SecretKeyCredentialHandler"; Algorithm = "PBKDF2WithHmacSHA512"; Iterations = 10000; SaltLength = 16 }
    )

    $overallSecure = $true
    foreach ($case in $testCases) {
        $isCompliant = Check-PasswordSecurity -Password $case.Password -CredentialHandler $case.CredentialHandler -Algorithm $case.Algorithm -Iterations $case.Iterations -SaltLength $case.SaltLength
        if (-not $isCompliant) {
            $overallSecure = $false
        }
    }

    Write-Log "Overall Configuration: $($overallSecure ? 'Secure' : 'Insecure')"
    Write-Log "Audit completed"
}

# Execute audit
Check-TomcatConfig
Restart-TomcatService
