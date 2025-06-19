# UpdateTomcatUserWin.ps1
#Requires -RunAsAdministrator

param(
    [string]$TomcatHome = "C:\Program Files\Apache Software Foundation\Tomcat\apache-tomcat-10.1.42",
    [string]$ServiceName = "Tomcat101"
)

function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp - $Level - $Message"
}

function Test-AdminRights {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Log "This script requires administrative privileges. Please run as Administrator." "ERROR"
        exit 1
    }
    Write-Log "Administrative privileges confirmed" "INFO"
}

function Backup-ConfigFile {
    param($FilePath)
    try {
        $backupPath = "$FilePath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -Path $FilePath -Destination $backupPath -Force
        Write-Log "Created backup: $backupPath"
        return $backupPath
    } catch {
        Write-Log "Failed to create backup of $FilePath : $_" "ERROR"
        return $null
    }
}

function Get-TomcatVersion {
    param([string]$TomcatHome)
    $versionFile = Join-Path $TomcatHome "RELEASE-NOTES"
    $version = $null
    if (Test-Path $versionFile) {
        $content = Get-Content $versionFile -Raw
        if ($content -match "Apache Tomcat Version\s+(\d+\.\d+\.\d+)") {
            $fullVersion = $matches[1]
            if ($fullVersion -match "^(\d+\.\d+)") {
                $version = $matches[1]
            }
        }
    } elseif ($TomcatHome -match "tomcat-(\d+\.\d+)") {
        $version = $matches[1]
    }
    if ($version -and $version -in @("7.0", "8.5", "9.0", "10.0", "10.1")) {
        Write-Log "Detected Tomcat version: $version"
        return $version
    } else {
        Write-Log "ERROR: Could not determine Tomcat version at $TomcatHome. Exiting." "ERROR"
        exit 1
    }
}

function Test-PBKDF2Support {
    param([string]$TomcatHome)
    $digestScript = Join-Path $TomcatHome "bin\digest.bat"
    $env:CATALINA_HOME = $TomcatHome
    $testPassword = "TestPassword123!"
    $digestArgs = @('-a', 'PBKDF2WithHmacSHA512', '-i', '10000', '-s', '16', $testPassword)
    try {
        $process = Start-Process -FilePath $digestScript -ArgumentList $digestArgs -NoNewWindow -Wait -RedirectStandardOutput "temp_hash.txt" -PassThru
        $output = Get-Content "temp_hash.txt" -ErrorAction SilentlyContinue | Out-String
        Remove-Item "temp_hash.txt" -Force -ErrorAction SilentlyContinue
        if ($output -match "NoSuchAlgorithmException" -or $output -match "not available" -or $output -match "Error") {
            return $false
        }
        if ($process.ExitCode -eq 0 -and $output -match ":") {
            return $true
        } else {
            return $false
        }
    } catch {
        return $false
    }
}

function Patch-ServerXml {
    param(
        [string]$TomcatHome,
        [string]$Version,
        [string]$HandlerClass,
        [string]$Algorithm,
        [string]$Iterations = $null,
        [string]$SaltLength = $null
    )
    $serverXmlPath = Join-Path $TomcatHome "conf\server.xml"
    if (-not (Test-Path $serverXmlPath)) {
        Write-Log "server.xml not found at $serverXmlPath" "ERROR"
        return $false
    }
    Backup-ConfigFile $serverXmlPath | Out-Null
    [xml]$xml = Get-Content $serverXmlPath
    $realm = $xml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
    if (-not $realm) {
        Write-Log "UserDatabaseRealm not found in server.xml. No changes made to Realm structure." "WARNING"
        return $false
    }
    # Remove all existing CredentialHandler children
    $handlers = @()
    foreach ($node in $realm.ChildNodes) {
        if ($node.Name -eq "CredentialHandler") { $handlers += $node }
    }
    foreach ($h in $handlers) { $realm.RemoveChild($h) | Out-Null }
    # Add new CredentialHandler
    $ch = $xml.CreateElement("CredentialHandler")
    $ch.SetAttribute("className", $HandlerClass)
    $ch.SetAttribute("algorithm", $Algorithm)
    if ($Iterations) { $ch.SetAttribute("iterations", $Iterations) }
    if ($SaltLength) { $ch.SetAttribute("saltLength", $SaltLength) }
    $realm.AppendChild($ch) | Out-Null
    $xml.Save($serverXmlPath)
    Write-Log "Patched server.xml with $HandlerClass, $Algorithm, Iterations: $Iterations, SaltLength: $SaltLength"
    return $true
}

function Get-PasswordHash {
    param(
        [string]$TomcatBin,
        [string]$Password,
        [string]$Version,
        [string]$TomcatHome
    )
    $digestScript = Join-Path $TomcatBin "digest.bat"
    if (-not (Test-Path $digestScript)) {
        Write-Log "digest.bat not found at $digestScript" "ERROR"
        return $null
    }
    $env:CATALINA_HOME = $TomcatHome
    if ($Version -eq "7.0") {
        $algorithm = "SHA-256"
        $args = @('-a', $algorithm, $Password)
    } elseif ($Version -in @("8.5", "9.0", "10.0", "10.1")) {
        $algorithm = "PBKDF2WithHmacSHA512"
        $iterations = "10000"
        $saltLength = "16"
        $args = @('-a', $algorithm, '-i', $iterations, '-s', $saltLength, $Password)
    } else {
        Write-Log "ERROR: Unsupported Tomcat version $Version for password hashing." "ERROR"
        return $null
    }
    try {
        $process = Start-Process -FilePath $digestScript -ArgumentList $args -NoNewWindow -Wait -RedirectStandardOutput "temp_hash.txt" -PassThru
        $digestRaw = Get-Content "temp_hash.txt" -ErrorAction SilentlyContinue | Out-String
        Remove-Item "temp_hash.txt" -Force -ErrorAction SilentlyContinue
        if ($Version -in @("8.5", "9.0", "10.0", "10.1") -and $digestRaw -match "^([^:]+):") {
            $hash = $matches[1].Trim()
            if ($hash -match '^[0-9a-fA-F]+\$[0-9]+\$[0-9a-fA-F]+$') {
                return $hash
            } else {
                Write-Log "digest.bat output did not match expected PBKDF2 hash format: $digestRaw" "ERROR"
                return $null
            }
        } elseif ($Version -eq "7.0" -and $digestRaw -match "^[0-9a-fA-F]{64}$") {
            return $digestRaw.Trim()
        } else {
            Write-Log "digest.bat output: $digestRaw" "ERROR"
            return $null
        }
    } catch {
        Write-Log "Error running digest.bat: $_" "ERROR"
        return $null
    }
}

function Update-AllUserPasswords {
    param(
        [string]$TomcatHome,
        [string]$Version
    )
    $usersXmlPath = Join-Path $TomcatHome "conf\tomcat-users.xml"
    if (-not (Test-Path $usersXmlPath)) {
        Write-Log "tomcat-users.xml not found at $usersXmlPath" "ERROR"
        exit 1
    }
    Backup-ConfigFile $usersXmlPath | Out-Null
    [xml]$usersXml = Get-Content $usersXmlPath
    $users = $usersXml.SelectNodes("//user")
    $updated = $false
    $binPath = Join-Path $TomcatHome "bin"
    foreach ($user in $users) {
        $username = $user.GetAttribute("username")
        $password = $user.GetAttribute("password")
        # Only update if password is plaintext
        if ($Version -eq "7.0" -and $password -match '^[0-9a-fA-F]{64,}$') {
            Write-Log "User $username already has a SHA-256 hash. Skipping."
            continue
        } elseif ($Version -in @("8.5", "9.0", "10.0", "10.1") -and $password -match '^[^:]+:[0-9a-fA-F]+\$[0-9]+\$[0-9a-fA-F]+\$[0-9a-fA-F]+$') {
            Write-Log "User $username already has a PBKDF2WithHmacSHA512 hash. Skipping."
            continue
        } elseif ($password -match '^[0-9a-fA-F]{128,}$') {
            Write-Log "User $username already has a SHA-512 hash. Skipping."
            continue
        }
        Write-Log "Hashing plaintext password for user $username using Tomcat $Version"
        $hash = Get-PasswordHash -TomcatBin $binPath -Password $password -Version $Version -TomcatHome $TomcatHome
        if ($hash -and $hash -ne $password) {
            $user.SetAttribute("password", $hash)
            $updated = $true
            Write-Log "Updated password for user $username"
        } else {
            Write-Log "Failed to hash password for user $username. Leaving as is." "ERROR"
        }
    }
    if ($updated) {
        $usersXml.Save($usersXmlPath)
        Write-Log "Successfully updated user hashes in tomcat-users.xml"
    } else {
        Write-Log "No plaintext user passwords found to update."
    }
    return $updated
}

function Restart-TomcatService {
    param($ServiceName)
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        if ($service.Status -eq 'Running') {
            Write-Log "Stopping Tomcat service..."
            Stop-Service -Name $ServiceName -Force
            Start-Sleep -Seconds 5
        } else {
            Write-Log "Tomcat service is already stopped."
        }
        Write-Log "Starting Tomcat service..."
        Start-Service -Name $ServiceName
        $service = Get-Service -Name $ServiceName
        if ($service.Status -eq 'Running') {
            Write-Log "Tomcat service successfully started"
            return $true
        } else {
            Write-Log "Failed to start Tomcat service. Status: $($service.Status)" "ERROR"
            return $false
        }
    } catch {
        Write-Log "Error managing Tomcat service: $_" "ERROR"
        return $false
    }
}

# Main execution
Write-Log "Starting Tomcat configuration and user update"
Test-AdminRights

$Version = Get-TomcatVersion -TomcatHome $TomcatHome

if ($Version -eq "7.0") {
    Patch-ServerXml -TomcatHome $TomcatHome -Version $Version -HandlerClass "org.apache.catalina.realm.MessageDigestCredentialHandler" -Algorithm "SHA-256" | Out-Null
    $HashAlg = "SHA-256"
} elseif ($Version -in @("8.5", "9.0", "10.0", "10.1")) {
    $pbkdf2Supported = Test-PBKDF2Support -TomcatHome $TomcatHome
    if (-not $pbkdf2Supported) {
        Write-Log "ERROR: PBKDF2WithHmacSHA512 is not available in your Java runtime. Please upgrade Java to at least 8u161 or 11+ with PBKDF2 support. Cannot update user passwords to compliance. Exiting." "ERROR"
        exit 1
    }
    Patch-ServerXml -TomcatHome $TomcatHome -Version $Version -HandlerClass "org.apache.catalina.realm.SecretKeyCredentialHandler" -Algorithm "PBKDF2WithHmacSHA512" -Iterations "10000" -SaltLength "16" | Out-Null
    $HashAlg = "PBKDF2WithHmacSHA512"
} else {
    Write-Log "ERROR: Unsupported Tomcat version $Version. Exiting without making changes." "ERROR"
    exit 1
}

$updated = Update-AllUserPasswords -TomcatHome $TomcatHome -Version $Version

if (-not (Restart-TomcatService -ServiceName $ServiceName)) {
    Write-Log "Failed to restart Tomcat service" "ERROR"
    exit 1
}

Write-Log "Configuration update completed successfully" 