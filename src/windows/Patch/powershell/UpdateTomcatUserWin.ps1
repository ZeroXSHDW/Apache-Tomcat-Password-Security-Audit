# UpdateTomcatUserWin.ps1
# Updates Tomcat user credentials with secure password hashing for Windows systems
# Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark

#Requires -RunAsAdministrator

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$CustomConfPath,
    
    [Parameter(Mandatory=$false)]
    [string]$Username = "tomcat",
    
    [Parameter(Mandatory=$false)]
    [string]$Roles = "manager,admin"
)

# Constants
$LOG_FILE = "$env:TEMP\TomcatManager.csv"
$LOG_DIR = "$env:TEMP"
$LOG_FILE_PATH = Join-Path $LOG_DIR "TomcatManager.log"
$TIMESTAMP = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$HOSTNAME = $env:COMPUTERNAME

# Configure logging
$ErrorActionPreference = "Stop"
$LogFile = Join-Path $LOG_DIR "TomcatManager.log"
$LogCSV = Join-Path $LOG_DIR "TomcatManager.csv"

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

# Function to take ownership and grant full control
function Set-FilePermissions {
    param(
        [string]$Path
    )
    try {
        # Take ownership
        $acl = Get-Acl $Path
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $owner = New-Object System.Security.Principal.SecurityIdentifier($identity.User)
        $acl.SetOwner($owner)
        Set-Acl -Path $Path -AclObject $acl

        # Grant full control to current user
        $acl = Get-Acl $Path
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $identity.Name,
            "FullControl",
            "Allow"
        )
        $acl.AddAccessRule($rule)
        Set-Acl -Path $Path -AclObject $acl
        return $true
    }
    catch {
        Write-Log "Error setting file permissions on $Path : $_" "ERROR"
        return $false
    }
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

# Add dynamic Tomcat path detection (like audit script)
function Get-TomcatConfigPath {
    if ($CustomConfPath -and (Test-Path $CustomConfPath)) {
        return $CustomConfPath
    }
    $possiblePaths = @(
        "C:\Program Files\Apache Software Foundation\Tomcat 7.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 8.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 8.5\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 9.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 10.0\conf",
        "C:\Program Files\Apache Software Foundation\Tomcat 10.1\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 7.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 8.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 8.5\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 9.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 10.0\conf",
        "C:\Program Files (x86)\Apache Software Foundation\Tomcat 10.1\conf",
        "C:\Tomcat\conf",
        "C:\Tomcat7\conf",
        "C:\Tomcat8\conf",
        "C:\Tomcat9\conf",
        "C:\Tomcat10\conf",
        "C:\Apache\Tomcat\conf",
        "C:\Apache\Tomcat7\conf",
        "C:\Apache\Tomcat8\conf",
        "C:\Apache\Tomcat9\conf",
        "C:\Apache\Tomcat10\conf",
        "D:\Program Files\Apache Software Foundation\Tomcat 7.0\conf",
        "D:\Program Files\Apache Software Foundation\Tomcat 8.5\conf",
        "D:\Program Files\Apache Software Foundation\Tomcat 9.0\conf",
        "D:\Program Files\Apache Software Foundation\Tomcat 10.0\conf",
        "D:\Program Files\Apache Software Foundation\Tomcat 10.1\conf",
        "D:\Tomcat\conf",
        "E:\Program Files\Apache Software Foundation\Tomcat 7.0\conf",
        "E:\Program Files\Apache Software Foundation\Tomcat 8.5\conf",
        "E:\Program Files\Apache Software Foundation\Tomcat 9.0\conf",
        "E:\Program Files\Apache Software Foundation\Tomcat 10.0\conf",
        "E:\Program Files\Apache Software Foundation\Tomcat 10.1\conf",
        "E:\Tomcat\conf"
    )
    $tomcatRoot = "C:\Program Files\Apache Software Foundation\Tomcat"
    if (Test-Path $tomcatRoot) {
        $subDirs = Get-ChildItem -Path $tomcatRoot -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $subDirs) {
            $confPath = Join-Path $dir.FullName "conf"
            if (Test-Path (Join-Path $confPath "server.xml")) {
                $possiblePaths += $confPath
            }
        }
    }
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $serverXml = Join-Path $path "server.xml"
            if (Test-Path $serverXml) {
                return $path
            }
        }
    }
    return $null
}

# Function to detect Tomcat version
function Get-TomcatVersion {
    param(
        [string]$TomcatHome
    )
    try {
        $versionFile = Join-Path $TomcatHome "RELEASE-NOTES"
        $version = "7.0"  # Default

        if (Test-Path $versionFile) {
            $content = Get-Content $versionFile -Raw
            if ($content -match "Apache Tomcat Version\s+(\d+\.\d+\.\d+)") {
                $fullVersion = $matches[1]
                switch -Regex ($fullVersion) {
                    "^7\.0" { $version = "7.0" }
                    "^8\.5" { $version = "8.5" }
                    "^9\.0" { $version = "9.0" }
                    "^10\.0" { $version = "10.0" }
                    "^10\.1" { $version = "10.1" }
                }
            }
        }
        
        Write-Log "Detected Tomcat version: $version"
        return $version
    }
    catch {
        Write-Log "Error detecting Tomcat version: $_" "ERROR"
        return "7.0"  # Default fallback
    }
}

# Function to find a valid JAVA_HOME
function Find-JavaHome {
    # Try JAVA_HOME first
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
        return $env:JAVA_HOME
    }
    # Common JDK install locations
    $candidates = @(
        'C:\Program Files\Java',
        'C:\Program Files\AdoptOpenJDK',
        'C:\Program Files\Zulu',
        'C:\Program Files\Eclipse Foundation',
        'C:\Program Files (x86)\Java',
        'C:\Program Files (x86)\AdoptOpenJDK',
        'C:\Program Files (x86)\Zulu',
        'C:\Program Files (x86)\Eclipse Foundation'
    )
    foreach ($base in $candidates) {
        if (Test-Path $base) {
            $jdks = Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'jdk*' }
            foreach ($jdk in $jdks) {
                $javaExe = Join-Path $jdk.FullName 'bin\java.exe'
                if (Test-Path $javaExe) {
                    return $jdk.FullName
                }
            }
        }
    }
    return $null
}

# Function to generate password hash using Tomcat's digest tool
function Get-PasswordHash {
    param(
        [string]$TomcatBin,
        [string]$Password,
        [string]$Version,
        [string]$TomcatHome
    )
    try {
        # Auto-detect JAVA_HOME if not set or invalid
        $javaHome = $env:JAVA_HOME
        if (-not $javaHome -or -not (Test-Path (Join-Path $javaHome 'bin\java.exe'))) {
            $javaHome = Find-JavaHome
            if ($javaHome) {
                Write-Log "Auto-detected JAVA_HOME: $javaHome"
                $env:JAVA_HOME = $javaHome
            }
        }
        # Check for JAVA_HOME or JRE_HOME
        if (-not $env:JAVA_HOME -and -not $env:JRE_HOME) {
            $msg = @(
                "ERROR: Neither JAVA_HOME nor JRE_HOME is set, and no JDK was auto-detected. Java is required to run Tomcat's digest.bat.",
                "Please install a JDK and set the JAVA_HOME environment variable to your Java installation directory.",
                "Example: $env:JAVA_HOME = 'C:\Program Files\Java\jdk-17.0.1'"
            ) -join "`n"
            Write-Host $msg
            Write-Log $msg "ERROR"
            throw "Java not found. Set JAVA_HOME or JRE_HOME."
        }
        # Set CATALINA_HOME for digest.bat
        $oldCatalinaHome = $env:CATALINA_HOME
        $env:CATALINA_HOME = $TomcatHome
        Write-Log "Set CATALINA_HOME to $TomcatHome for digest.bat"
        $digestScript = Join-Path $TomcatBin "digest.bat"
        if (-not (Test-Path $digestScript)) {
            throw "digest.bat not found at $digestScript"
        }
        Write-Log "Generating password hash for Tomcat $Version"
        if ($Version -eq "7.0") {
            $algorithm = "SHA-256"
            $args = @('-a', $algorithm, $Password)
        } else {
            $algorithm = "PBKDF2WithHmacSHA512"
            $iterations = "10000"
            $saltLength = "16"
            $args = @('-a', $algorithm, '-i', $iterations, '-s', $saltLength, $Password)
        }
        Write-Log "Running: $digestScript $($args -join ' ')"
        $result = & $digestScript @args 2>&1
        Write-Log "digest.bat output: $result"
        Write-Host "digest.bat output: $result"
        # Restore previous CATALINA_HOME
        $env:CATALINA_HOME = $oldCatalinaHome
        if (-not $result -or $result.Count -eq 0) {
            Write-Host "ERROR: digest.bat returned no output. Check Java installation and Tomcat environment."
            throw "digest.bat returned no output."
        }
        if ($result -match 'Neither the JAVA_HOME nor the JRE_HOME environment variable is defined correctly') {
            $msg = @(
                "ERROR: JAVA_HOME is not configured correctly. digest.bat output:",
                $result,
                "Please ensure JAVA_HOME points to a JDK (not a JRE) and contains bin\java.exe."
            ) -join "`n"
            Write-Host $msg
            Write-Log $msg "ERROR"
            throw "JAVA_HOME not set correctly."
        }
        if ($result -match 'The CATALINA_HOME environment variable is not defined correctly') {
            $msg = @(
                "ERROR: CATALINA_HOME is not configured correctly. digest.bat output:",
                $result,
                "Please check the Tomcat installation path."
            ) -join "`n"
            Write-Host $msg
            Write-Log $msg "ERROR"
            throw "CATALINA_HOME not set correctly."
        }
        if ($result -match 'Access is denied') {
            $msg = @(
                "ERROR: Access is denied when running digest.bat.",
                $result,
                "Try running PowerShell as administrator.",
                "Also check permissions on the Tomcat and Java folders."
            ) -join "`n"
            Write-Host $msg
            Write-Log $msg "ERROR"
            throw "Access is denied. Try running as administrator."
        }
        if ($result -match '([0-9a-fA-F:]+)$') {
            $hash = $matches[1].Trim()
            Write-Log "Generated hash: $hash"
            return $hash
        }
        throw "Failed to extract hash from digest.bat output: $result"
    }
    catch {
        Write-Log "Error generating password hash: $_" "ERROR"
        return $null
    }
}

# Function to validate username
function Test-Username {
    param([string]$Username)
    return $Username -match '^[a-zA-Z0-9_\-\.]+$'
}

# Function to validate roles
function Test-Roles {
    param([string]$Roles)
    $validRoles = @("manager", "admin", "manager-gui", "manager-script", "manager-jmx", "manager-status")
    $userRoles = $Roles -split ','
    return $userRoles | Where-Object { $validRoles -contains $_ }
}

# Function to update Tomcat user
function Update-TomcatUser {
    param(
        [string]$UsersXmlPath,
        [string]$Username,
        [string]$Password,
        [string]$Roles
    )
    try {
        if (-not (Test-Path $UsersXmlPath)) {
            throw "Users XML file not found"
        }
        
        # Set permissions for tomcat-users.xml
        if (-not (Set-FilePermissions -Path $UsersXmlPath)) {
            throw "Failed to set permissions on tomcat-users.xml"
        }
        
        $xml = Get-SecureXml -XmlFile $UsersXmlPath
        if (-not $xml) {
            throw "Failed to parse users XML file"
        }
        
        $user = $xml.SelectSingleNode("//user[@username='$Username']")
        if ($user) {
            Write-Log "Updating existing user: $Username"
            $user.SetAttribute("password", $Password)
            $user.SetAttribute("roles", $Roles)
        } else {
            Write-Log "Creating new user: $Username"
            $newUser = $xml.CreateElement("user")
            $newUser.SetAttribute("username", $Username)
            $newUser.SetAttribute("password", $Password)
            $newUser.SetAttribute("roles", $Roles)
            $xml.'tomcat-users'.AppendChild($newUser)
        }
        
        if (-not (Set-SecureXml -XmlFile $UsersXmlPath -XmlContent $xml)) {
            throw "Failed to write users XML file"
        }
        
        return $true
    }
    catch {
        Write-Log "Error updating Tomcat user: $_" "ERROR"
        return $false
    }
}

# Function to patch CredentialHandler in server.xml
function Patch-CredentialHandler {
    param(
        [string]$ServerXmlPath,
        [string]$TomcatVersion
    )
    try {
        # Take ownership and set permissions
        if (-not (Set-FilePermissions -Path $ServerXmlPath)) {
            throw "Failed to set permissions on server.xml"
        }

        $xml = Get-SecureXml -XmlFile $ServerXmlPath
        if (-not $xml) { throw "Failed to parse server.xml" }
        
        $realm = $xml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
        if (-not $realm) {
            $realm = $xml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.MemoryRealm']")
        }
        if (-not $realm) { throw "No supported Realm found in server.xml" }
        
        $credHandler = $realm.SelectSingleNode("CredentialHandler")
        if ($TomcatVersion -eq "7.0") {
            $chClass = "org.apache.catalina.realm.MessageDigestCredentialHandler"
            $chAlg = "SHA-256"
            if ($credHandler) {
                $credHandler.SetAttribute("className", $chClass)
                $credHandler.SetAttribute("algorithm", $chAlg)
                $credHandler.RemoveAttribute("iterations")
                $credHandler.RemoveAttribute("saltLength")
            } else {
                $newCH = $xml.CreateElement("CredentialHandler")
                $newCH.SetAttribute("className", $chClass)
                $newCH.SetAttribute("algorithm", $chAlg)
                $realm.AppendChild($newCH)
            }
        } else {
            $chClass = "org.apache.catalina.realm.SecretKeyCredentialHandler"
            $chAlg = "PBKDF2WithHmacSHA512"
            $chIter = "10000"
            $chSalt = "16"
            if ($credHandler) {
                $credHandler.SetAttribute("className", $chClass)
                $credHandler.SetAttribute("algorithm", $chAlg)
                $credHandler.SetAttribute("iterations", $chIter)
                $credHandler.SetAttribute("saltLength", $chSalt)
            } else {
                $newCH = $xml.CreateElement("CredentialHandler")
                $newCH.SetAttribute("className", $chClass)
                $newCH.SetAttribute("algorithm", $chAlg)
                $newCH.SetAttribute("iterations", $chIter)
                $newCH.SetAttribute("saltLength", $chSalt)
                $realm.AppendChild($newCH)
            }
        }
        
        if (-not (Set-SecureXml -XmlFile $ServerXmlPath -XmlContent $xml)) {
            throw "Failed to write server.xml with updated CredentialHandler"
        }
        
        Write-Log "Patched CredentialHandler in server.xml for Tomcat $TomcatVersion"
        return $true
    } catch {
        Write-Log "Error patching CredentialHandler: $_" "ERROR"
        return $false
    }
}

# Function to manage Tomcat service
function Set-TomcatService {
    param(
        [string]$Action,
        [int]$Timeout = 60,
        [string]$TomcatHome
    )
    try {
        # Set CATALINA_HOME if not already set
        if (-not $env:CATALINA_HOME) {
            $env:CATALINA_HOME = $TomcatHome
            Write-Log "Set CATALINA_HOME to $TomcatHome"
        }

        $service = Get-Service -Name "Tomcat*" -ErrorAction SilentlyContinue | 
                  Where-Object { $_.Status -eq "Running" } | 
                  Select-Object -First 1
        
        if ($service) {
            Write-Log "Found Tomcat Windows service: $($service.Name)"
            # Use Windows service
            switch ($Action) {
                "restart" {
                    Write-Log "Stopping Tomcat service..."
                    Stop-Service $service -Force
                    Start-Sleep -Seconds 5
                    Write-Log "Starting Tomcat service..."
                    Start-Service $service
                }
                "stop" { Stop-Service $service -Force }
                "start" { Start-Service $service }
            }
        } else {
            Write-Log "No Tomcat service found, using catalina.bat"
            # Use catalina.bat
            $catalinaScript = Join-Path $TomcatHome "bin\catalina.bat"
            if (-not (Test-Path $catalinaScript)) {
                throw "catalina.bat not found at $catalinaScript"
            }
            
            switch ($Action) {
                "restart" {
                    Write-Log "Stopping Tomcat using catalina.bat..."
                    & $catalinaScript stop
                    Start-Sleep -Seconds 5
                    Write-Log "Starting Tomcat using catalina.bat..."
                    & $catalinaScript start
                }
                "stop" { & $catalinaScript stop }
                "start" { & $catalinaScript start }
            }
        }
        
        # Wait for service to be ready
        Write-Log "Waiting for Tomcat to be ready..."
        $startTime = Get-Date
        while ((Get-Date).Subtract($startTime).TotalSeconds -lt $Timeout) {
            if (Test-NetConnection -ComputerName localhost -Port 8080 -WarningAction SilentlyContinue) {
                Write-Log "Tomcat is ready"
                return $true
            }
            Start-Sleep -Seconds 1
        }
        
        throw "Service failed to start within timeout"
    }
    catch {
        Write-Log "Error managing Tomcat service: $_" "ERROR"
        return $false
    }
}

# Function to generate a secure random password
function New-SecurePassword {
    param(
        [int]$Length = 16
    )
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{};:,.<>?'
    $bytes = New-Object 'System.Byte[]' ($Length)
    (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    $password = -join ($bytes | ForEach-Object { $chars[ $_ % $chars.Length ] })
    return $password
}

# Main script
try {
    Write-Log "Starting Tomcat configuration and user update"

    # Get Tomcat configuration path
    $tomcatConfPath = Get-TomcatConfigPath
    if (-not $tomcatConfPath) { throw "Could not determine Tomcat configuration path" }
    $tomcatHome = Split-Path $tomcatConfPath

    # Detect Tomcat version
    $version = Get-TomcatVersion -TomcatHome $tomcatHome
    Write-Log "Detected Tomcat version: $version"

    # 1. Patch CredentialHandler in server.xml first
    $serverXmlPath = Join-Path $tomcatConfPath "server.xml"
    $chResult = Patch-CredentialHandler -ServerXmlPath $serverXmlPath -TomcatVersion $version
    if (-not $chResult) {
        throw "Failed to patch CredentialHandler in server.xml"
    }
    Write-Log "Successfully patched CredentialHandler in server.xml"

    # 2. Validate user input
    if (-not (Test-Username $Username)) { throw "Invalid username format" }
    if (-not (Test-Roles $Roles)) { throw "Invalid roles specified" }

    # 3. Generate a secure random password
    $Password = New-SecurePassword -Length 16
    Write-Log "Generated new password for $Username"

    # 4. Generate secure hash for the user
    $hash = Get-PasswordHash -TomcatBin (Join-Path $tomcatHome "bin") -Password $Password -Version $version -TomcatHome $tomcatHome
    if (-not $hash) { throw "Failed to generate password hash" }

    # 5. Update user in tomcat-users.xml
    $usersXmlPath = Join-Path $tomcatConfPath "tomcat-users.xml"
    $userResult = $false
    if (Update-TomcatUser -UsersXmlPath $usersXmlPath -Username $Username -Password $hash -Roles $Roles) {
        Write-Log "Successfully updated user $Username"
        $userResult = $true
    } else {
        Write-Log "Failed to update user" "ERROR"
    }

    # 6. Restart Tomcat service
    $restartResult = $false
    if (Set-TomcatService -Action "restart" -TomcatHome $tomcatHome) {
        Write-Log "Successfully restarted Tomcat service"
        $restartResult = $true
    } else {
        Write-Log "Failed to restart Tomcat service" "ERROR"
    }

    # 7. Summary output
    Write-Host ("=" * 27)
    Write-Host "CredentialHandler patch: $($chResult)"
    Write-Host "User update: $($userResult)"
    Write-Host "Tomcat restart: $($restartResult)"
    Write-Host "Audit with the check script to verify compliance."
    Write-Host ("New credentials:")
    Write-Host ("Username: $Username")
    Write-Host ("Password: $Password")
    Write-Log "Tomcat configuration and user update completed successfully"
} catch {
    Write-Log "Error in main script: $_" "ERROR"
    Write-Host "ERROR: $_"
    exit 1
}