# CheckTomcatConfig.ps1
# Audits Tomcat configuration for password security and compliance (7.0, 8.5, 9.0)

# Log setup
$logFile = "$env:LOCALAPPDATA\Temp\TestTomcatConfig.log"
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message
}

Write-Log "Checking Apache Tomcat configuration security..."

# Detect Tomcat path and version
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

$tomcatInfo = Get-TomcatConfigPath
if (-not $tomcatInfo) {
    Write-Log "Error: No Tomcat configuration directory found"
    exit
}
$tomcatConfPath = $tomcatInfo.Path
$tomcatVersion = $tomcatInfo.Version
Write-Log "Detected Tomcat version $tomcatVersion at $tomcatConfPath"

# Load configuration files
$serverXmlPath = Join-Path $tomcatConfPath "server.xml"
$usersXmlPath = Join-Path $tomcatConfPath "tomcat-users.xml"

if (-not (Test-Path $serverXmlPath) -or -not (Test-Path $usersXmlPath)) {
    Write-Log "Error: server.xml or tomcat-users.xml not found"
    exit
}

$serverXml = [xml](Get-Content $serverXmlPath -Encoding UTF8)
$usersXml = [xml](Get-Content $usersXmlPath -Encoding UTF8)

# Analyze CredentialHandler
$realm = $serverXml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
if (-not $realm) {
    $realm = $serverXml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.MemoryRealm']")
}
$credentialHandler = $realm.CredentialHandler

# Initialize overall security status
$isSecure = $true

# Analyze users and passwords
$users = $usersXml.'tomcat-users'.user
if (-not $users) {
    Write-Log "- No users defined in tomcat-users.xml"
    Write-Log "- Status: Compliant (no passwords to evaluate)"
    Write-Log "Overall Configuration: Secure (no vulnerabilities detected)"
    Write-Log "Audit completed"
    exit
}

foreach ($user in $users) {
    $username = $user.username
    $password = $user.password

    # Skip users without passwords
    if (-not $password) {
        Write-Log "- User '$username': No password defined"
        Write-Log "  - Status: Compliant (no password to evaluate)"
        continue
    }

    # Detect password type
    $passwordType = switch -Regex ($password) {
        "^[a-f0-9]{32}$" { "Hashed_MD5" }
        "^[a-f0-9]{40}$" { "Hashed_SHA1" }
        "^[a-f0-9]{64}$" { "Hashed_SHA256" }
        "^[a-f0-9]{128}$" { "Hashed_SHA512" }
        "^[a-f0-9]{32}:[a-f0-9]{16}$" { "Salted_MD5" }
        "^[a-f0-9]{32}:[a-f0-9]{16}$" { "Salted_PBKDF2" }
        default { "Plaintext" }
    }

    Write-Log "- User '$username': $passwordType password ($(if ($passwordType -match 'Plaintext|MD5|SHA1') { 'insecure' } else { 'secure' }))"

    # Initialize parameter checks
    $params = @()

    # Parameter: Password Type
    $params += "- Parameter: Password Type = $passwordType [$(
        if ($passwordType -match 'Plaintext|MD5|SHA1') { 'FAIL' } else { 'PASS' }
    )]"

    # Parameter: CredentialHandler Presence
    $handlerClass = if ($credentialHandler) { $credentialHandler.className } else { "None" }
    $params += "- Parameter: CredentialHandler = $handlerClass [$(
        if ($credentialHandler) { 'PASS' } else { 'FAIL' }
    )]"

    # Parameter: Algorithm
    $algorithm = if ($credentialHandler -and $credentialHandler.algorithm) { $credentialHandler.algorithm } else { "None" }
    $params += "- Parameter: Algorithm = $algorithm [$(
        if ($algorithm -in @('SHA-256', 'SHA-512', 'PBKDF2WithHmacSHA512')) { 'PASS' } else { 'FAIL' }
    )]"

    # Parameter: Iterations (if applicable)
    $iterations = if ($credentialHandler -and $credentialHandler.iterations) { [int]$credentialHandler.iterations } else { 0 }
    $params += "- Parameter: Iterations = $iterations [$(
        if ($iterations -ge 10000) { 'PASS' } else { 'FAIL' }
    )]"

    # Parameter: Salt Length (if applicable)
    $saltLength = if ($credentialHandler -and $credentialHandler.saltLength) { [int]$credentialHandler.saltLength } else { 0 }
    $params += "- Parameter: Salt Length = $saltLength [$(
        if ($saltLength -ge 16) { 'PASS' } else { 'FAIL' }
    )]"

    # Log parameters
    foreach ($param in $params) {
        Write-Log "  $param"
    }

    # Compliance check
    if ($passwordType -eq "Plaintext") {
        Write-Log "  - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
        Write-Log "    - Plaintext passwords detected in tomcat-users.xml"
        Write-Log "    - Recommendation: Use salted and iterated passwords (e.g., SHA-256 or PBKDF2)"
        $isSecure = $false
    }
    elseif ($passwordType -in @("Hashed_MD5", "Salted_MD5")) {
        Write-Log "  - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
        Write-Log "    - Weak password hashing ($passwordType) detected"
        Write-Log "    - Recommendation: Use SHA-256, SHA-512, or PBKDF2"
        $isSecure = $false
    }
    elseif ($passwordType -eq "Hashed_SHA1") {
        Write-Log "  - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
        Write-Log "    - Weak password hashing (SHA-1) detected"
        Write-Log "    - Recommendation: Use SHA-256, SHA-512, or PBKDF2"
        $isSecure = $false
    }
    elseif ($passwordType -eq "Hashed_SHA256") {
        if ($tomcatVersion -eq "7.0") {
            Write-Log "  - Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark for Tomcat 7.0"
        } elseif (-not $credentialHandler -or $credentialHandler.algorithm -ne "SHA-256" -or
            [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
            Write-Log "  - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
            Write-Log "    - Hashed_SHA256 passwords should use salt and iterations"
            Write-Log "    - Recommendation: Configure MessageDigestCredentialHandler with saltLength >= 16 and iterations >= 10000"
            $isSecure = $false
        } else {
            Write-Log "  - Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
        }
    }
    elseif ($passwordType -eq "Hashed_SHA512") {
        if ($tomcatVersion -eq "7.0") {
            Write-Log "  - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
            Write-Log "    - SHA-512 not supported in Tomcat 7.0"
            Write-Log "    - Recommendation: Use SHA-256"
            $isSecure = $false
        } elseif (-not $credentialHandler -or $credentialHandler.algorithm -ne "SHA-512" -or
            [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
            Write-Log "  - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
            Write-Log "    - Hashed_SHA512 passwords should use salt and iterations"
            Write-Log "    - Recommendation: Configure MessageDigestCredentialHandler with saltLength >= 16 and iterations >= 10000"
            $isSecure = $false
        } else {
            Write-Log "  - Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
        }
    }
    elseif ($passwordType -eq "Salted_PBKDF2") {
        if ($tomcatVersion -eq "7.0") {
            Write-Log "  - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
            Write-Log "    - PBKDF2 not supported in Tomcat 7.0"
            Write-Log "    - Recommendation: Use SHA-256"
            $isSecure = $false
        } elseif ($tomcatVersion -eq "8.5") {
            if (-not $credentialHandler -or $credentialHandler.algorithm -notin @("SHA-256", "SHA-512") -or
                [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
                Write-Log "  - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
                Write-Log "    - Salted_PBKDF2 requires compatible MessageDigestCredentialHandler"
                Write-Log "    - Recommendation: Configure MessageDigestCredentialHandler with SHA-256/SHA-512, saltLength >= 16, iterations >= 10000"
                $isSecure = $false
            } else {
                Write-Log "  - Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
            }
        } else { # Tomcat 9.0
            if ($credentialHandler -and $credentialHandler.className -eq "org.apache.catalina.realm.SecretKeyCredentialHandler" -and
                $credentialHandler.algorithm -eq "PBKDF2WithHmacSHA512" -and
                [int]$credentialHandler.iterations -ge 10000 -and [int]$credentialHandler.saltLength -ge 16) {
                Write-Log "  - Status: Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
            } else {
                Write-Log "  - Status: Non-compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark"
                Write-Log "    - Salted_PBKDF2 requires SecretKeyCredentialHandler with PBKDF2"
                Write-Log "    - Recommendation: Configure SecretKeyCredentialHandler with PBKDF2, saltLength >= 16, iterations >= 10000"
                $isSecure = $false
            }
        }
    }
}

# Report overall security
Write-Log "Overall Configuration: $(if ($isSecure) { 'Secure' } else { 'Insecure' })"
Write-Log "Audit completed"
