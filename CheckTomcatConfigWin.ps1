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

# Function to parse server.xml for CredentialHandler details
function Get-CredentialHandler {
    param($ServerXmlPath)
    try {
        $xml = [xml](Get-Content $ServerXmlPath)
        $credentialHandler = $xml.Server.Service.Engine.Host.Realm.CredentialHandler
        if ($credentialHandler) {
            $iterations = 0
            if ($credentialHandler.iterations) {
                $iterations = [int]$credentialHandler.iterations
            }
            $saltLength = 0
            if ($credentialHandler.saltLength) {
                $saltLength = [int]$credentialHandler.saltLength
            }
            return @{
                className = $credentialHandler.className
                algorithm = $credentialHandler.algorithm
                iterations = $iterations
                saltLength = $saltLength
            }
        }
        return $null
    } catch {
        Write-Log "Error parsing server.xml: $($_.Exception.Message)"
        return $null
    }
}

# Function to parse tomcat-users.xml for user password
function Get-UserPassword {
    param($UsersXmlPath)
    try {
        $xml = [xml](Get-Content $UsersXmlPath)
        $user = $xml.'tomcat-users'.user | Where-Object { $_.username -eq "testuser" }
        if ($user) {
            return $user.password
        }
        return $null
    } catch {
        Write-Log "Error parsing tomcat-users.xml: $($_.Exception.Message)"
        return $null
    }
}

# Function to check password security
function Check-PasswordSecurity {
    param($Password, $CredentialHandler, $Algorithm, $Iterations, $SaltLength)

    Write-Log "  - Debug: Raw password for 'testuser': $Password"
    Write-Log "  - Debug: CredentialHandler=$CredentialHandler, Algorithm=$Algorithm, Iterations=$Iterations, SaltLength=$SaltLength"

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
    $results += "  - Parameter: Password Type = $passwordType [$(if ($isSecure) { 'PASS' } else { 'FAIL' })]"
    $results += "  - Parameter: CredentialHandler = $CredentialHandler [$(if ($CredentialHandler -match 'CredentialHandler') { 'PASS' } else { 'FAIL' })]"
    $results += "  - Parameter: Algorithm = $Algorithm [$(if ($Algorithm -match 'SHA-256|SHA-512|PBKDF2') { 'PASS' } else { 'FAIL' })]"
    $results += "  - Parameter: Iterations = $Iterations [$(if ($Iterations -ge 10000) { 'PASS' } else { 'FAIL' })]"
    $results += "  - Parameter: Salt Length = $SaltLength [$(if ($SaltLength -ge 16) { 'PASS' } else { 'FAIL' })]"

    # Compliance check
    $isCompliant = $true
    if ($passwordType -match "MD5|SHA1|Plaintext" -or $Password -eq "password123") {
        $isCompliant = $false
        Write-Log "  - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
        Write-Log "    - Reason: Weak or plaintext password format detected"
    }
    elseif ($passwordType -eq "Hashed_SHA256" -and $CredentialHandler -eq "org.apache.catalina.realm.MessageDigestCredentialHandler" -and $Algorithm -match "SHA-256" -and $Iterations -ge 10000 -and $SaltLength -ge 16) {
        Write-Log "  - Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
    }
    elseif ($passwordType -eq "Hashed_SHA512" -and $CredentialHandler -eq "org.apache.catalina.realm.MessageDigestCredentialHandler" -and $Algorithm -match "SHA-512" -and $Iterations -ge 10000 -and $SaltLength -ge 16) {
        Write-Log "  - Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
    }
    elseif ($passwordType -eq "Salted_PBKDF2" -and $CredentialHandler -eq "org.apache.catalina.realm.SecretKeyCredentialHandler" -and $Algorithm -match "PBKDF2WithHmacSHA512" -and $Iterations -ge 10000 -and $SaltLength -ge 16) {
        Write-Log "  - Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
    }
    else {
        $isCompliant = $false
        Write-Log "  - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
        Write-Log "    - Reason: Configuration does not meet security requirements"
        Write-Log "    - Debug: PasswordType=$passwordType, CredentialHandler=$CredentialHandler, Algorithm=$Algorithm, Iterations=$Iterations, SaltLength=$SaltLength"
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
    $serverXmlPath = Join-Path $tomcatPath "server.xml"
    $usersXmlPath = Join-Path $tomcatPath "tomcat-users.xml"
    $tomcatVersion = Get-TomcatVersion -TomcatPath $tomcatPath
    Write-Log "Detected Tomcat version $tomcatVersion at $tomcatPath"

    # Get configuration from XML files
    $credentialHandler = Get-CredentialHandler -ServerXmlPath $serverXmlPath
    $password = Get-UserPassword -UsersXmlPath $usersXmlPath

    if (-not $password) {
        Write-Log "Error: No password found for testuser in tomcat-users.xml"
        return
    }

    $handlerClass = $credentialHandler ? $credentialHandler.className : "None"
    $algorithm = $credentialHandler ? $credentialHandler.algorithm : "None"
    $iterations = $credentialHandler ? $credentialHandler.iterations : 0
    $saltLength = $credentialHandler ? $credentialHandler.saltLength : 0

    # Evaluate configuration
    $isCompliant = Check-PasswordSecurity -Password $password -CredentialHandler $handlerClass -Algorithm $algorithm -Iterations $iterations -SaltLength $saltLength

    Write-Log "Overall Configuration: $(if ($isCompliant) { 'Secure' } else { 'Insecure' })"
    Write-Log "Audit completed"
}

# Execute audit
Check-TomcatConfig
Restart-TomcatService
