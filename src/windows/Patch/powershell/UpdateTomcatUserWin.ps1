# UpdateTomcatUserWin.ps1
# Processes existing users with plaintext passwords, generates compliant hashes, updates tomcat-users.xml and server.xml, and restarts Tomcat service on Windows

param (
    [string]$TomcatConfPath
)

# Log setup
$logFile = "$env:LOCALAPPDATA\Temp\TomcatManager.csv"
$logMessages = @()

function Write-Log {
    param(
        [string]$Message,
        [int]$Indent = 0
    )
    $indentSpaces = "  " * $Indent
    $logMessage = "$indentSpaces$Message"
    $script:logMessages += $logMessage
    Write-Host $logMessage
}

# Ensure log file directory exists and set secure permissions
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}
if (-not (Test-Path $logFile)) {
    Add-Content -Path $logFile -Value "Timestamp,Message" -ErrorAction SilentlyContinue
}
# Set log file permissions (restrict to current user)
try {
    $acl = Get-Acl $logFile -ErrorAction SilentlyContinue
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($env:USERNAME, "FullControl", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $logFile $acl -ErrorAction SilentlyContinue
} catch {
    Write-Log "Warning: Cannot set permissions on $logFile" -Indent 2
}

Write-Log "Execution Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Hostname: $env:COMPUTERNAME"
Write-Log "==========================="

# Function to detect Tomcat configuration path
function Get-TomcatConfigPath {
    param([string]$CustomConfPath)

    if ($CustomConfPath -and (Test-Path $CustomConfPath)) {
        $serverXml = Join-Path $CustomConfPath "server.xml"
        $usersXml = Join-Path $CustomConfPath "tomcat-users.xml"
        $digestBat = Join-Path (Split-Path $CustomConfPath -Parent) "bin\digest.bat"
        if ((Test-Path $serverXml) -and (Test-Path $usersXml) -and (Test-Path $digestBat)) {
            Write-Log "Found valid Tomcat configuration at custom path: $CustomConfPath"
            return @{ Path = $CustomConfPath; Version = "Unknown" }
        }
    }

    $defaultPath = "F:\Koger\apps\apache-tomcat-7.0.94"
    Write-Log "Checking default configuration path: $defaultPath"
    if (Test-Path "$defaultPath\conf") {
        $serverXml = "$defaultPath\conf\server.xml"
        $usersXml = "$defaultPath\conf\tomcat-users.xml"
        $digestBat = "$defaultPath\bin\digest.bat"
        if ((Test-Path $serverXml) -and (Test-Path $usersXml) -and (Test-Path $digestBat)) {
            $version = if ($defaultPath -match "apache-tomcat-(\d+\.\d+)") { $matches[1] } else { "7.0" }
            Write-Log "Found valid Tomcat configuration at default path: $defaultPath\conf"
            return @{ Path = "$defaultPath\conf"; Version = $version }
        }
    }

    $possiblePaths = @(
        "C:\Program Files\Apache Software Foundation\Tomcat 7.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 8.5\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 9.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 10.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 10.1\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 7.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 8.5\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 9.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 10.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 10.1\conf",
        "C:\Tomcat\conf",
        "C:\Tomcat7\conf",
        "C:\Tomcat8\conf",
        "C:\Tomcat9\conf",
        "C:\Tomcat10\conf"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $serverXml = Join-Path $path "server.xml"
            $usersXml = Join-Path $path "tomcat-users.xml"
            $digestBat = Join-Path (Split-Path $path -Parent) "bin\digest.bat"
            if ((Test-Path $serverXml) -and (Test-Path $usersXml) -and (Test-Path $digestBat)) {
                $version = if ($path -match "Tomcat\s*(\d+\.\d+)") { $matches[1] } else { "7.0" }
                Write-Log "Found valid Tomcat configuration at: $path"
                return @{ Path = $path; Version = $version }
            }
        }
    }

    Write-Log "ERROR: Could not locate Tomcat configuration directory" -Indent 2
    return $null
}

# Function to detect Tomcat version
function Get-TomcatVersion {
    param([string]$TomcatHome)

    $versionFile = Join-Path $TomcatHome "RELEASE-NOTES"
    $version = "7.0"  # Default

    if (Test-Path $versionFile) {
        $content = Get-Content $versionFile -Raw
        if ($content -match "Apache Tomcat Version\s+(\d+\.\d+\.\d+)") {
            $fullVersion = $matches[1]
            if ($fullVersion -like "7.0.*") { $version = "7.0" }
            elseif ($fullVersion -like "8.0.*") { $version = "8.0" }
            elseif ($fullVersion -like "8.5.*") { $version = "8.5" }
            elseif ($fullVersion -like "9.0.*") { $version = "9.0" }
            elseif ($fullVersion -like "10.0.*") { $version = "10.0" }
            elseif ($fullVersion -like "10.1.*") { $version = "10.1" }
            Write-Log "Version found in RELEASE-NOTES: $fullVersion ($version)"
        }
    } else {
        Write-Log "Warning: RELEASE-NOTES not found, defaulting to version 7.0" -Indent 2
    }

    return $version
}

# Function to generate password hash using digest.bat
function Generate-PasswordHash {
    param(
        [string]$TomcatBin,
        [string]$Password,
        [string]$TomcatVersion
    )

    $digestBat = Join-Path $TomcatBin "digest.bat"
    $algorithm = ""
    $iterations = ""
    $saltLength = ""

    switch ($TomcatVersion) {
        "7.0" { $algorithm = "SHA-256" }
        "8.5" { 
            $algorithm = "SHA-512"
            $iterations = "10000"
            $saltLength = "16"
        }
        { $_ -in "9.0","10.0","10.1" } { 
            $algorithm = "PBKDF2WithHmacSHA512"
            $iterations = "10000"
            $saltLength = "16"
        }
        default {
            Write-Log "ERROR: Unsupported Tomcat version: $TomcatVersion" -Indent 2
            return $null
        }
    }

    if (-not (Test-Path $digestBat)) {
        Write-Log "ERROR: digest.bat not found at $digestBat" -Indent 2
        return $null
    }

    # Verify JAVA_HOME
    if (-not $env:JAVA_HOME) {
        Write-Log "ERROR: JAVA_HOME is not set, required for digest.bat" -Indent 2
        return $null
    }

    # Run digest.bat
    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        if ($TomcatVersion -eq "7.0") {
            Start-Process -FilePath $digestBat -ArgumentList "-a $algorithm `"$Password`"" -RedirectStandardOutput $tempFile -NoNewWindow -Wait
        } else {
            Start-Process -FilePath $digestBat -ArgumentList "-a $algorithm -i $iterations -s $saltLength `"$Password`"" -RedirectStandardOutput $tempFile -NoNewWindow -Wait
        }

        $hashOutput = Get-Content $tempFile -Raw
        $hash = ($hashOutput -match '([0-9a-fA-F:]+)') ? $matches[1] : $null

        if (-not $hash) {
            Write-Log "ERROR: Failed to parse hash from digest.bat output" -Indent 2
            return $null
        }

        return $hash
    } catch {
        Write-Log "ERROR: Failed to generate hash using digest.bat: $($_.Exception.Message)" -Indent 2
        return $null
    } finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

# Function to get users with plaintext passwords
function Get-PlaintextUsers {
    param([string]$UsersXmlPath)

    if (-not (Test-Path $UsersXmlPath)) {
        Write-Log "ERROR: $UsersXmlPath not found" -Indent 2
        return $null
    }

    if ((Get-Item $UsersXmlPath).Length -eq 0) {
        Write-Log "WARNING: $UsersXmlPath is empty" -Indent 2
        return @()
    }

    try {
        $xml = [xml](Get-Content $UsersXmlPath -Encoding UTF8)
        $users = $xml.'tomcat-users'.user
        $plaintextUsers = @()

        foreach ($user in $users) {
            $username = $user.username
            $password = $user.password
            # Check if password is plaintext (not a hash)
            if ($password -and $password -notmatch '^[0-9a-fA-F:]+$' -or 
                $password -notmatch '^[0-9a-fA-F]{32}$|^[0-9a-fA-F]{40}$|^[0-9a-fA-F]{64}$|^[0-9a-fA-F]{128}$|^[0-9a-fA-F]+:[0-9a-fA-F]+$') {
                $plaintextUsers += @{ Username = $username; Password = $password }
            }
        }

        if ($plaintextUsers.Count -eq 0) {
            Write-Log "No users with plaintext passwords found in $UsersXmlPath" -Indent 2
        }

        return $plaintextUsers
    } catch {
        Write-Log "ERROR: Failed to read $UsersXmlPath: $($_.Exception.Message)" -Indent 2
        return $null
    }
}

# Function to update tomcat-users.xml
function Update-TomcatUsersXml {
    param(
        [string]$UsersXmlPath,
        [array]$UserPairs
    )

    $backupPath = "$UsersXmlPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
    try {
        Copy-Item -Path $UsersXmlPath -Destination $backupPath -Force -ErrorAction Stop
        Write-Log "Backed up $UsersXmlPath to $backupPath"
        # Set backup permissions
        $acl = Get-Acl $backupPath
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($env:USERNAME, "FullControl", "Allow")
        $acl.SetAccessRule($rule)
        Set-Acl $backupPath $acl -ErrorAction SilentlyContinue
    } catch {
        Write-Log "ERROR: Failed to backup $UsersXmlPath: $($_.Exception.Message)" -Indent 2
        return $false
    }

    try {
        $xml = [xml](Get-Content $UsersXmlPath -Encoding UTF8)
        foreach ($pair in $UserPairs) {
            $username = $pair.Username
            $hash = $pair.Hash
            $userNode = $xml.'tomcat-users'.user | Where-Object { $_.username -eq $username }
            if ($userNode) {
                $userNode.password = $hash
                Write-Log "Updated user $username with new hash in $UsersXmlPath"
            }
        }
        $xml.Save($UsersXmlPath)
        return $true
    } catch {
        Write-Log "ERROR: Failed to update $UsersXmlPath: $($_.Exception.Message)" -Indent 2
        Copy-Item -Path $backupPath -Destination $UsersXmlPath -Force -ErrorAction SilentlyContinue
        Write-Log "Restored $UsersXmlPath from backup"
        return $false
    }
}

# Function to update server.xml
function Update-ServerXml {
    param(
        [string]$ServerXmlPath,
        [string]$TomcatVersion
    )

    $backupPath = "$ServerXmlPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
    try {
        Copy-Item -Path $ServerXmlPath -Destination $backupPath -Force -ErrorAction Stop
        Write-Log "Backed up $ServerXmlPath to $backupPath"
        $acl = Get-Acl $backupPath
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($env:USERNAME, "FullControl", "Allow")
        $acl.SetAccessRule($rule)
        Set-Acl $backupPath $acl -ErrorAction SilentlyContinue
    } catch {
        Write-Log "ERROR: Failed to backup $ServerXmlPath: $($_.Exception.Message)" -Indent 2
        return $false
    }

    try {
        $xml = [xml](Get-Content $ServerXmlPath -Encoding UTF8)
        $realm = $xml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
        if (-not $realm) {
            $engine = $xml.SelectSingleNode("//Engine")
            $realm = $xml.CreateElement("Realm")
            $realm.SetAttribute("className", "org.apache.catalina.realm.UserDatabaseRealm")
            $realm.SetAttribute("resourceName", "UserDatabase")
            $engine.AppendChild($realm) | Out-Null
            Write-Log "Added new Realm to $ServerXmlPath"
        }

        $credentialHandler = $realm.CredentialHandler
        if ($credentialHandler) {
            $realm.RemoveChild($credentialHandler) | Out-Null
        }
        $credentialHandler = $xml.CreateElement("CredentialHandler")

        switch ($TomcatVersion) {
            "7.0" {
                $credentialHandler.SetAttribute("className", "org.apache.catalina.realm.MessageDigestCredentialHandler")
                $credentialHandler.SetAttribute("algorithm", "SHA-256")
            }
            "8.5" {
                $credentialHandler.SetAttribute("className", "org.apache.catalina.realm.MessageDigestCredentialHandler")
                $credentialHandler.SetAttribute("algorithm", "SHA-512")
                $credentialHandler.SetAttribute("iterations", "10000")
                $credentialHandler.SetAttribute("saltLength", "16")
            }
            { $_ -in "9.0","10.0","10.1" } {
                $credentialHandler.SetAttribute("className", "org.apache.catalina.realm.SecretKeyCredentialHandler")
                $credentialHandler.SetAttribute("algorithm", "PBKDF2WithHmacSHA512")
                $credentialHandler.SetAttribute("iterations", "10000")
                $credentialHandler.SetAttribute("saltLength", "16")
                $credentialHandler.SetAttribute("keyLength", "256")
            }
            default {
                Write-Log "ERROR: Unsupported Tomcat version: $TomcatVersion" -Indent 2
                return $false
            }
        }

        $realm.AppendChild($credentialHandler) | Out-Null
        $xml.Save($ServerXmlPath)
        Write-Log "Updated Realm configuration in $ServerXmlPath"
        return $true
    } catch {
        Write-Log "ERROR: Failed to update $ServerXmlPath: $($_.Exception.Message)" -Indent 2
        Copy-Item -Path $backupPath -Destination $ServerXmlPath -Force -ErrorAction SilentlyContinue
        Write-Log "Restored $ServerXmlPath from backup"
        return $false
    }
}

# Function to restart Tomcat service
function Restart-TomcatService {
    param([string]$TomcatHome)

    $serviceNames = @("Tomcat", "Tomcat7", "Tomcat8", "Tomcat9", "Tomcat10")
    $service = $null

    foreach ($svc in $serviceNames) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "Running") {
            break
        }
    }

    if ($service) {
        Write-Log "Restarting Tomcat service: $($service.Name)"
        try {
            Restart-Service -Name $service.Name -Force -ErrorAction Stop
            Start-Sleep -Seconds 5
            if ((Get-Service -Name $service.Name).Status -ne "Running") {
                Write-Log "ERROR: Tomcat service $($service.Name) failed to start" -Indent 2
                return $false
            }
            Write-Log "Tomcat service $($service.Name) restarted successfully"
            return $true
        } catch {
            Write-Log "ERROR: Failed to restart Tomcat service $($service.Name): $($_.Exception.Message)" -Indent 2
            return $false
        }
    } else {
        $catalinaBat = Join-Path $TomcatHome "bin\catalina.bat"
        if (Test-Path $catalinaBat) {
            Write-Log "No service found, using catalina.bat to restart"
            try {
                Start-Process -FilePath $catalinaBat -ArgumentList "stop" -NoNewWindow -Wait
                Start-Sleep -Seconds 5
                Start-Process -FilePath $catalinaBat -ArgumentList "start" -NoNewWindow -Wait
                Start-Sleep -Seconds 5
                $process = Get-Process -Name "java" -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*$TomcatHome*" }
                if (-not $process) {
                    Write-Log "ERROR: Tomcat failed to start via catalina.bat" -Indent 2
                    return $false
                }
                Write-Log "Tomcat restarted successfully via catalina.bat"
                return $true
            } catch {
                Write-Log "ERROR: Failed to restart Tomcat using catalina.bat: $($_.Exception.Message)" -Indent 2
                return $false
            }
        } else {
            Write-Log "ERROR: No Tomcat service or catalina.bat found" -Indent 2
            return $false
        }
    }
}

# Main execution
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "ERROR: This script must be run as Administrator"
    exit 1
}

$tomcatInfo = Get-TomcatConfigPath -CustomConfPath $TomcatConfPath
if (-not $tomcatInfo) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $combinedMessage = $logMessages -join "; "
    Add-Content -Path $logFile -Value "$timestamp,$combinedMessage" -ErrorAction SilentlyContinue
    exit 1
}

$tomcatConfPath = $tomcatInfo.Path
$tomcatHome = Split-Path $tomcatConfPath -Parent
$tomcatVersion = Get-TomcatVersion -TomcatHome $tomcatHome
Write-Log "Tomcat Home: $tomcatHome"
Write-Log "Config Path: $tomcatConfPath"
Write-Log "Tomcat Version: $tomcatVersion"

$usersXmlPath = Join-Path $tomcatConfPath "tomcat-users.xml"
Write-Log "Reading $usersXmlPath for users with plaintext passwords"
$plaintextUsers = Get-PlaintextUsers -UsersXmlPath $usersXmlPath
if ($null -eq $plaintextUsers) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $combinedMessage = $logMessages -join "; "
    Add-Content -Path $logFile -Value "$timestamp,$combinedMessage" -ErrorAction SilentlyContinue
    exit 1
}

if ($plaintextUsers.Count -eq 0) {
    Write-Log "No plaintext passwords to update"
    Write-Log "Updating $usersXmlPath for compliance only"
} else {
    Write-Log "Found $($plaintextUsers.Count) user(s) with plaintext passwords"
}

$updatedUsers = @()
foreach ($user in $plaintextUsers) {
    $username = $user.Username
    $password = $user.Password
    Write-Log "Processing user: $username (Original plaintext password: [REDACTED])" -Indent 2
    $hash = Generate-PasswordHash -TomcatBin (Join-Path $tomcatHome "bin") -Password $password -TomcatVersion $tomcatVersion
    if (-not $hash) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $combinedMessage = $logMessages -join "; "
        Add-Content -Path $logFile -Value "$timestamp,$combinedMessage" -ErrorAction SilentlyContinue
        exit 1
    }
    Write-Log "Generated Hash for $username: $hash" -Indent 2
    $updatedUsers += @{ Username = $username; Hash = $hash }
}

if ($updatedUsers.Count -gt 0) {
    Write-Log "Updating $usersXmlPath with new hashes"
    if (-not (Update-TomcatUsersXml -UsersXmlPath $usersXmlPath -UserPairs $updatedUsers)) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $combinedMessage = $logMessages -join "; "
        Add-Content -Path $logFile -Value "$timestamp,$combinedMessage" -ErrorAction SilentlyContinue
        exit 1
    }
}

$serverXmlPath = Join-Path $tomcatConfPath "server.xml"
Write-Log "Updating $serverXmlPath for compliance"
if (-not (Update-ServerXml -ServerXmlPath $serverXmlPath -TomcatVersion $tomcatVersion)) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $combinedMessage = $logMessages -join "; "
    Add-Content -Path $logFile -Value "$timestamp,$combinedMessage" -ErrorAction SilentlyContinue
    exit 1
}

Write-Log "Restarting Tomcat to apply changes"
if (-not (Restart-TomcatService -TomcatHome $tomcatHome)) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $combinedMessage = $logMessages -join "; "
    Add-Content -Path $logFile -Value "$timestamp,$combinedMessage" -ErrorAction SilentlyContinue
    exit 1
}

$complianceStatus = switch ($tomcatVersion) {
    "7.0" { "Compliant with SHA-256 (MessageDigestCredentialHandler)" }
    "8.5" { "Compliant with SHA-512, 10000 iterations, 16-byte salt (MessageDigestCredentialHandler)" }
    { $_ -in "9.0","10.0","10.1" } { "Compliant with PBKDF2WithHmacSHA512, 10000 iterations, 16-byte salt (SecretKeyCredentialHandler)" }
}
Write-Log "Compliance Status: $complianceStatus"
Write-Log "==========================="
Write-Log "Overall Status: Secure"
Write-Log "Audit completed"

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$combinedMessage = $logMessages -join "; "
Add-Content -Path $logFile -Value "$timestamp,$combinedMessage" -ErrorAction SilentlyContinue