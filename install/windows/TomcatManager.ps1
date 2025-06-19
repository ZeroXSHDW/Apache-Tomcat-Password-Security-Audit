# TomcatManager.ps1
# Installs and configures Apache Tomcat with secure password hashing for Windows systems
# Compliant with NIST 800-53 IA-5 and CIS Tomcat Benchmark

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$InstallPath = "C:\Program Files\Apache Software Foundation\Tomcat",
    
    [Parameter(Mandatory=$false)]
    [string]$Version = "9.0",
    
    [Parameter(Mandatory=$false)]
    [string]$Username = "tomcat",
    
    [Parameter(Mandatory=$false)]
    [string]$Password = "s3cret",
    
    [Parameter(Mandatory=$false)]
    [string]$Roles = "manager,admin",
    
    [Parameter(Mandatory=$false)]
    [switch]$InstallService = $true,
    
    [Parameter(Mandatory=$false)]
    [switch]$ConfigureFirewall = $true
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

# Function to validate hash format
function Test-HashFormat {
    param(
        [string]$Hash,
        [string]$Version
    )
    $patterns = @{
        "7.0" = '^[0-9a-fA-F]{64}$'
        "8.5" = '^[0-9a-fA-F]{128}$'
        "9.0" = '^[0-9a-fA-F]+:[0-9a-fA-F]+$'
        "10.0" = '^[0-9a-fA-F]+:[0-9a-fA-F]+$'
        "10.1" = '^[0-9a-fA-F]+:[0-9a-fA-F]+$'
    }
    
    if (-not $patterns.ContainsKey($Version)) {
        Write-Log "Unsupported Tomcat version: $Version" "ERROR"
        return $false
    }
    
    return $Hash -match $patterns[$Version]
}

# Function to generate password hash
function Get-PasswordHash {
    param(
        [string]$TomcatBin,
        [string]$Password,
        [string]$Version
    )
    try {
        $digestScript = Join-Path $TomcatBin "digest.bat"
        if (-not (Test-Path $digestScript)) {
            throw "digest.bat not found"
        }
        # Automatically detect JAVA_HOME
        $javaHome = $null
        $javaExe = Get-Command java -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
        if ($javaExe) {
            # Go up two directories from java.exe (e.g., .../bin/java.exe -> ...)
            $javaBin = Split-Path $javaExe -Parent
            $javaHomeCandidate = Split-Path $javaBin -Parent
            if (Test-Path (Join-Path $javaHomeCandidate 'bin\java.exe')) {
                $javaHome = $javaHomeCandidate
            }
        }
        if ($javaHome) {
            $env:JAVA_HOME = $javaHome
            Write-Log "Detected JAVA_HOME: $javaHome" "INFO"
        } else {
            Write-Log "Could not detect JAVA_HOME. Attempting to download and install OpenJDK..." "WARNING"
            # Use a stable, versioned OpenJDK 17 MSI URL
            $jdkUrl = "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.11+9/OpenJDK17U-jdk_x64_windows_hotspot_17.0.11_9.msi"
            $jdkReleasesPage = "https://github.com/adoptium/temurin17-binaries/releases?prefix=temurin17"
            $jdkMsi = Join-Path $env:TEMP "OpenJDK17U-jdk_x64_windows_hotspot_17.0.11_9.msi"
            $downloaded = $false
            $maxTries = 3
            for ($i = 1; $i -le $maxTries; $i++) {
                try {
                    Write-Log ("Attempt {0}: Downloading OpenJDK MSI from {1}" -f $i, $jdkUrl) "INFO"
                    Invoke-WebRequestCompat -Uri $jdkUrl -OutFile $jdkMsi
                    if (Test-Path $jdkMsi) {
                        $downloaded = $true
                        break
                    }
                } catch {
                    Write-Log ("Attempt {0} failed: {1}" -f $i, $_) "ERROR"
                    Start-Sleep -Seconds 2
                }
            }
            if (-not $downloaded) {
                Write-Log "Automatic download failed. Please download Java manually from:`n$jdkUrl or visit:`n$jdkReleasesPage" "ERROR"
                Start-Process $jdkReleasesPage
                throw "JAVA_HOME not found and OpenJDK download failed"
            }
            try {
                Write-Log "Running OpenJDK installer..." "INFO"
                $installResult = Start-Process msiexec.exe -ArgumentList "/i `"$jdkMsi`" /qn" -Wait -NoNewWindow -PassThru
                if ($installResult.ExitCode -ne 0) {
                    Write-Log "Silent install failed (exit code $($installResult.ExitCode)). Please run the installer manually: $jdkMsi" "ERROR"
                    Start-Process $jdkMsi
                    throw "OpenJDK silent install failed"
                }
                Write-Log "Installed OpenJDK MSI" "INFO"
                $javaHome = $null
                $possibleHomes = @(
                    'C:\Program Files\Eclipse Adoptium',
                    'C:\Program Files\Java',
                    'C:\Program Files (x86)\Java'
                )
                foreach ($base in $possibleHomes) {
                    if (Test-Path $base) {
                        $candidates = Get-ChildItem -Path $base -Directory | Where-Object { $_.Name -match 'jdk|jre' }
                        foreach ($cand in $candidates) {
                            if (Test-Path (Join-Path $cand.FullName 'bin\java.exe')) {
                                $javaHome = $cand.FullName
                                break
                            }
                        }
                    }
                    if ($javaHome) { break }
                }
                if ($javaHome) {
                    $env:JAVA_HOME = $javaHome
                    $env:PATH = "$($env:JAVA_HOME)\bin;" + $env:PATH
                    Write-Log "Set JAVA_HOME to $javaHome and updated PATH" "INFO"
                } else {
                    Write-Log "OpenJDK installation completed but JAVA_HOME could not be found. Please set JAVA_HOME manually." "ERROR"
                    throw "JAVA_HOME not found after OpenJDK install"
                }
            } catch {
                Write-Log "Failed to install OpenJDK automatically. Please run the installer manually: $jdkMsi" "ERROR"
                Start-Process $jdkMsi
                throw "JAVA_HOME not found and OpenJDK install failed"
            }
        }
        # Set CATALINA_HOME for digest.bat
        $env:CATALINA_HOME = $TomcatBin | Split-Path -Parent
        # Log environment before running digest.bat
        Write-Log "About to run digest.bat with environment:" "DEBUG"
        Write-Log "JAVA_HOME: $($env:JAVA_HOME)" "DEBUG"
        Write-Log "CATALINA_HOME: $($env:CATALINA_HOME)" "DEBUG"
        Write-Log "PATH: $($env:PATH)" "DEBUG"
        if ($Version -eq "7.0") {
            $cmd = "& '$digestScript' -a SHA-256 '$Password'"
            Write-Log "Running command: $cmd" "DEBUG"
            $result = Invoke-Expression $cmd
            Write-Log "digest.bat output: $result" "DEBUG"
            if ($result -is [System.Array]) {
                $result = $result[-1]
            }
            $result = $result.Trim()
            # Log the full output for troubleshooting
            Write-Log "Full digest.bat output: $result" "DEBUG"
            if ($result -match '^[^:]+:([0-9a-fA-F]{64})$') {
                return $matches[1]
            } elseif ($result -match '^[0-9a-fA-F]{64}$') {
                return $result
            } elseif ($result -match 'openjdk version|java version') {
                Write-Log "digest.bat failed: Output appears to be Java version info, not a hash. Check JAVA_HOME and PATH." "ERROR"
                throw "digest.bat did not return a valid hash. Output was Java version info."
            } else {
                Write-Log "digest.bat did not return a valid SHA-256 hash. Output: $result" "ERROR"
                return $null
            }
        } else {
            $cmd = "& '$digestScript' -a SHA-512 -i 10000 -s 16 '$Password'"
            Write-Log "Running command: $cmd" "DEBUG"
            $result = Invoke-Expression $cmd
            Write-Log "digest.bat output: $result" "DEBUG"
            if ($result -is [System.Array]) {
                $result = $result[-1]
            }
            $result = $result.Trim()
            # Log the full output for troubleshooting
            Write-Log "Full digest.bat output: $result" "DEBUG"
            if ($result -match '[0-9a-fA-F:]+$') {
                return $matches[0]
            } elseif ($result -match 'openjdk version|java version') {
                Write-Log "digest.bat failed: Output appears to be Java version info, not a hash. Check JAVA_HOME and PATH." "ERROR"
                throw "digest.bat did not return a valid hash. Output was Java version info."
            } else {
                Write-Log "digest.bat did not return a valid hash. Output: $result" "ERROR"
                return $null
            }
        }
    }
    catch {
        Write-Log "Error generating password hash: $_" "ERROR"
        return $null
    }
}

# Function to manage Tomcat service
function Set-TomcatService {
    param(
        [string]$Action,
        [string]$ServiceName,
        [string]$BinPath,
        [int]$Timeout = 60
    )
    try {
        if ($Action -eq "install") {
            # Install service
            $servicePath = Join-Path $BinPath "service.bat"
            if (-not (Test-Path $servicePath)) {
                throw "service.bat not found"
            }
            & $servicePath install $ServiceName
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to install service"
            }
            # Configure service
            $service = Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'"
            $service.Change($null, $null, $null, $null, $null, $null, $null, $null, $null, $null, $null)
            $service.StartService()
            # Wait for service to be ready
            $startTime = Get-Date
            while ((Get-Date).Subtract($startTime).TotalSeconds -lt $Timeout) {
                if ((Get-Service $ServiceName).Status -eq "Running") {
                    return $true
                }
                Start-Sleep -Seconds 1
            }
            throw "Service failed to start within timeout"
        }
        else {
            # Manage existing service
            $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if (-not $service) {
                throw "Service $ServiceName not found"
            }
            switch ($Action) {
                "start" { Start-Service $ServiceName }
                "stop" { Stop-Service $ServiceName -Force }
                "restart" {
                    Stop-Service $ServiceName -Force
                    Start-Sleep -Seconds 5
                    Start-Service $ServiceName
                }
                "remove" {
                    Stop-Service $ServiceName -Force
                    $servicePath = Join-Path $BinPath "service.bat"
                    & $servicePath remove $ServiceName
                }
            }
            if ($Action -ne "remove") {
                # Wait for service to be ready
                $startTime = Get-Date
                while ((Get-Date).Subtract($startTime).TotalSeconds -lt $Timeout) {
                    if ((Get-Service $ServiceName).Status -eq "Running") {
                        return $true
                    }
                    Start-Sleep -Seconds 1
                }
                throw "Service failed to start within timeout"
            }
        }
        return $true
    }
    catch {
        Write-Log "Error managing Tomcat service: $_" "ERROR"
        return $false
    }
}

# Function to configure Windows Firewall
function Set-FirewallRules {
    param(
        [string]$ServiceName
    )
    try {
        # Add inbound rule for Tomcat
        $ruleName = "Tomcat-$ServiceName"
        $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        
        if (-not $existingRule) {
            New-NetFirewallRule -DisplayName $ruleName `
                               -Direction Inbound `
                               -Protocol TCP `
                               -LocalPort 8080 `
                               -Action Allow `
                               -Program (Join-Path $InstallPath "bin\tomcat.exe") `
                               -Description "Allow Tomcat $ServiceName inbound traffic"
            
            Write-Log "Added firewall rule: $ruleName"
        }
        
        return $true
    }
    catch {
        Write-Log "Error configuring firewall: $_" "ERROR"
        return $false
    }
}

# Function to validate username
function Test-Username {
    param([string]$Username)
    return $Username -match '^[a-zA-Z0-9_\-\.]+$'
}

# Function to validate password
function Test-Password {
    param([string]$Password)
    return $Password.Length -ge 8
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
        
        $xml = Get-SecureXml -XmlFile $UsersXmlPath
        if (-not $xml) {
            throw "Failed to parse users XML file"
        }
        
        $user = $xml.SelectSingleNode("//user[@username='$Username']")
        if ($user) {
            $user.SetAttribute("password", $Password)
            $user.SetAttribute("roles", $Roles)
        } else {
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

# Helper function to get latest Tomcat minor version from Apache archive
function Get-LatestTomcatMinorVersion {
    param(
        [string]$MajorVersion
    )
    $archiveBase = "https://archive.apache.org/dist/tomcat/tomcat-$MajorVersion/"
    $web = Invoke-WebRequest -Uri $archiveBase -UseBasicParsing -ErrorAction SilentlyContinue
    if ($web -and $web.Content) {
        $matches = [regex]::Matches($web.Content, "v$MajorVersion\\.([0-9]+)")
        $minorVersions = $matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object {[int]$_} -Descending
        if ($minorVersions.Count -gt 0) {
            return "$MajorVersion.$($minorVersions[0])"
        }
    }
    return $null
}

# Detect PowerShell version
$PSMajorVersion = $PSVersionTable.PSVersion.Major

# Helper function for archive extraction compatible with PS 5.1 and 7+
function Extract-ArchiveCompat {
    param(
        [string]$ZipPath,
        [string]$Destination
    )
    if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
        try {
            Expand-Archive -Path $ZipPath -DestinationPath $Destination -Force
            return $true
        } catch {
            Write-Log "Expand-Archive failed: $_" "ERROR"
        }
    }
    # Fallback for PS 5.1: use Shell.Application
    try {
        $shell = New-Object -ComObject shell.application
        $zip = $shell.NameSpace($ZipPath)
        $dest = $shell.NameSpace($Destination)
        $dest.CopyHere($zip.Items(), 0x10)
        Start-Sleep -Seconds 5
        return $true
    } catch {
        Write-Log "Shell.Application extraction failed: $_" "ERROR"
        Write-Log "Please extract $ZipPath manually to $Destination" "ERROR"
        return $false
    }
}

# Helper function for Invoke-WebRequest compatibility
function Invoke-WebRequestCompat {
    param(
        [string]$Uri,
        [string]$OutFile
    )
    if ($PSMajorVersion -ge 6) {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile
    } else {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
    }
}

# Function to install the required Java version for the Tomcat version
function Install-RequiredJava {
    param(
        [string]$TomcatVersion
    )
    if ($TomcatVersion -eq "7.0") {
        $jdkUrl = "https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u402-b06/OpenJDK8U-jdk_x64_windows_hotspot_8u402b06.msi"
        $jdkMsi = Join-Path $env:TEMP "OpenJDK8U-jdk_x64_windows_hotspot_8u402b06.msi"
        $javaHomePattern = "jdk8"
        $javaMajor = 8
    } elseif ($TomcatVersion -in @("8.5", "9.0", "10.0", "10.1")) {
        $jdkUrl = "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.11+9/OpenJDK17U-jdk_x64_windows_hotspot_17.0.11_9.msi"
        $jdkMsi = Join-Path $env:TEMP "OpenJDK17U-jdk_x64_windows_hotspot_17.0.11_9.msi"
        $javaHomePattern = "jdk-17"
        $javaMajor = 17
    } else {
        Write-Log "ERROR: Unsupported Tomcat version $TomcatVersion for Java installation." "ERROR"
        exit 1
    }
    # Check if Java is already installed and version is sufficient
    $javaExe = Get-Command java -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
    if ($javaExe) {
        $javaVersionOutput = & $javaExe -version 2>&1 | Out-String
        Write-Log "java -version output: $javaVersionOutput" "DEBUG"
        if ($javaVersionOutput -match 'version "([0-9]+)') {
            $detectedMajor = [int]$matches[1]
            if ($TomcatVersion -eq "7.0" -and $javaVersionOutput -match 'version "1\.8') {
                Write-Log "Detected Java 8, sufficient for Tomcat 7.0. Skipping Java install." "INFO"
                return
            } elseif ($detectedMajor -ge $javaMajor) {
                Write-Log "Detected Java $detectedMajor, sufficient for Tomcat $TomcatVersion. Skipping Java install." "INFO"
                return
            }
        } elseif ($javaVersionOutput -match 'version "1\.8') {
            # Java 8 reports as 1.8.0_xx
            if ($TomcatVersion -eq "7.0") {
                Write-Log "Detected Java 8 (1.8), sufficient for Tomcat 7.0. Skipping Java install." "INFO"
                return
            }
        } else {
            Write-Log "Could not parse Java version from output: $javaVersionOutput" "WARNING"
        }
    }
    # Download and install the required JDK
    Write-Log "Downloading required JDK from $jdkUrl" "INFO"
    $downloaded = $false
    $maxTries = 3
    for ($i = 1; $i -le $maxTries; $i++) {
        try {
            Invoke-WebRequest -Uri $jdkUrl -OutFile $jdkMsi -UseBasicParsing
            if (Test-Path $jdkMsi) {
                $downloaded = $true
                break
            }
        } catch {
            Write-Log ("Attempt {0} failed: {1}" -f $i, $_) "ERROR"
            Start-Sleep -Seconds 2
        }
    }
    if (-not $downloaded) {
        Write-Log "Automatic download failed. Please download Java manually from: $jdkUrl" "ERROR"
        Start-Process $jdkUrl
        exit 1
    }
    try {
        Write-Log "Running JDK installer..." "INFO"
        $installResult = Start-Process msiexec.exe -ArgumentList "/i `"$jdkMsi`" /qn" -Wait -NoNewWindow -PassThru
        if ($installResult.ExitCode -ne 0) {
            Write-Log "Silent install failed (exit code $($installResult.ExitCode)). Please run the installer manually: $jdkMsi" "ERROR"
            Start-Process $jdkMsi
            exit 1
        }
        Write-Log "Installed JDK MSI" "INFO"
        $javaHome = $null
        $possibleHomes = @(
            'C:\Program Files\Eclipse Adoptium',
            'C:\Program Files\Java',
            'C:\Program Files (x86)\Java'
        )
        foreach ($base in $possibleHomes) {
            if (Test-Path $base) {
                $candidates = Get-ChildItem -Path $base -Directory | Where-Object { $_.Name -like "*${javaHomePattern}*" }
                foreach ($cand in $candidates) {
                    if (Test-Path (Join-Path $cand.FullName 'bin\java.exe')) {
                        $javaHome = $cand.FullName
                        break
                    }
                }
            }
            if ($javaHome) { break }
        }
        if ($javaHome) {
            $env:JAVA_HOME = $javaHome
            $env:PATH = "$($env:JAVA_HOME)\bin;" + $env:PATH
            Write-Log "Set JAVA_HOME to $javaHome and updated PATH" "INFO"
        } else {
            Write-Log "JDK installation completed but JAVA_HOME could not be found. Please set JAVA_HOME manually." "ERROR"
            exit 1
        }
    } catch {
        Write-Log "Failed to install JDK automatically. Please run the installer manually: $jdkMsi" "ERROR"
        Start-Process $jdkMsi
        exit 1
    }
}

# Main script
try {
    Write-Log "Starting Tomcat installation"
    
    # Install required Java version for Tomcat
    Install-RequiredJava -TomcatVersion $Version

    # Validate input
    if (-not (Test-Username $Username)) {
        throw "Invalid username format"
    }
    if (-not (Test-Password $Password)) {
        throw "Password must be at least 8 characters long"
    }
    if (-not (Test-Roles $Roles)) {
        throw "Invalid roles specified"
    }
    
    # Create installation directory
    if (-not (Test-Path $InstallPath)) {
        New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
        Write-Log "Created installation directory: $InstallPath"
    }
    
    # Determine Tomcat version and download URL
    $majorVersion = $Version
    $latestMinor = $null
    $downloadUrl = $null
    $zipFile = $null

    # List of hardcoded latest versions for EOL or fallback
    $hardcodedVersions = @{
        "7.0" = "7.0.109"
        "8.5" = "8.5.99"
        "9.0" = "9.0.87"
        "10.0" = "10.0.27"
        "10.1" = "10.1.20"
    }

    $majorDir = $majorVersion.Split('.')[0]

    # Try dlcdn first
    $dlcdnUrl = "https://dlcdn.apache.org/tomcat/tomcat-$majorVersion/"
    try {
        $dlcdnWeb = Invoke-WebRequest -Uri $dlcdnUrl -UseBasicParsing -ErrorAction SilentlyContinue
        if ($dlcdnWeb -and $dlcdnWeb.Content) {
            $matches = [regex]::Matches($dlcdnWeb.Content, "v$majorVersion\.([0-9]+)")
            $minorVersions = $matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object {[int]$_} -Descending
            if ($minorVersions.Count -gt 0) {
                $latestMinor = "$majorVersion.$($minorVersions[0])"
                $downloadUrl = "https://dlcdn.apache.org/tomcat/tomcat-$majorVersion/v$latestMinor/bin/apache-tomcat-$latestMinor-windows-x64.zip"
            }
        }
    } catch {}

    # If not found, try archive
    if (-not $downloadUrl) {
        $archiveBase = "https://archive.apache.org/dist/tomcat/tomcat-$majorDir/"
        try {
            $archiveWeb = Invoke-WebRequest -Uri $archiveBase -UseBasicParsing -ErrorAction SilentlyContinue
            if ($archiveWeb -and $archiveWeb.Content) {
                $matches = [regex]::Matches($archiveWeb.Content, "v$majorVersion\.([0-9]+)")
                $minorVersions = $matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object {[int]$_} -Descending
                if ($minorVersions.Count -gt 0) {
                    $latestMinor = "$majorVersion.$($minorVersions[0])"
                    $downloadUrl = "https://archive.apache.org/dist/tomcat/tomcat-$majorDir/v$latestMinor/bin/apache-tomcat-$latestMinor-windows-x64.zip"
                }
            }
        } catch {}
    }

    # If still not found, use hardcoded
    if (-not $downloadUrl -and $hardcodedVersions.ContainsKey($majorVersion)) {
        $latestMinor = $hardcodedVersions[$majorVersion]
        $downloadUrl = "https://archive.apache.org/dist/tomcat/tomcat-$majorDir/v$latestMinor/bin/apache-tomcat-$latestMinor-windows-x64.zip"
    }

    if (-not $downloadUrl) {
        throw "Could not determine latest Tomcat version for $majorVersion"
    }
    $zipFile = Join-Path $env:TEMP "apache-tomcat-$latestMinor-windows-x64.zip"
    Write-Log "Downloading Tomcat $latestMinor from $downloadUrl"
    Invoke-WebRequestCompat -Uri $downloadUrl -OutFile $zipFile
    
    # Extract Tomcat
    Write-Log "Extracting Tomcat to $InstallPath"
    if (-not (Extract-ArchiveCompat -ZipPath $zipFile -Destination $InstallPath)) {
        throw "Extraction failed. Please extract $zipFile manually to $InstallPath."
    }
    Remove-Item $zipFile -Force

    # Always use the directory for the version just extracted
    $expectedDir = Join-Path $InstallPath "apache-tomcat-$latestMinor"
    if (Test-Path $expectedDir) {
        $tomcatBase = $expectedDir
    } else {
        # fallback: pick the first apache-tomcat* directory
        $tomcatDir = Get-ChildItem -Path $InstallPath -Directory | Where-Object { $_.Name -like "apache-tomcat*" } | Select-Object -First 1
        if ($null -eq $tomcatDir) {
            throw "Could not find extracted Tomcat directory in $InstallPath"
        }
        $tomcatBase = $tomcatDir.FullName
    }
    $binPath = Join-Path $tomcatBase "bin"
    $confPath = Join-Path $tomcatBase "conf"

    # Check for digest.bat
    $digestScript = Join-Path $binPath "digest.bat"
    if (-not (Test-Path $digestScript)) {
        if ($majorVersion -eq "7.0") {
            Write-Log "digest.bat not found, downloading from Tomcat 8.5.99..." "WARNING"
            $digestUrl = "https://archive.apache.org/dist/tomcat/tomcat-8/v8.5.99/bin/digest.bat"
            try {
                Invoke-WebRequestCompat -Uri $digestUrl -OutFile $digestScript
                Write-Log "Downloaded digest.bat from Tomcat 8.5.99 to $digestScript" "INFO"
            } catch {
                throw "Failed to download digest.bat for Tomcat 7.0. Cannot generate password hash."
            }
        } else {
            throw "digest.bat not found in $binPath. Cannot generate password hash."
        }
    }
    
    # --- Patch server.xml to add CredentialHandler ---
    $serverXml = Join-Path $confPath "server.xml"
    [xml]$xml = Get-Content $serverXml
    $realm = $xml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
    if (-not $realm) {
        # Optionally, create the Realm if missing
        $engine = $xml.SelectSingleNode("//Engine")
        $realm = $xml.CreateElement("Realm")
        $realm.SetAttribute("className", "org.apache.catalina.realm.UserDatabaseRealm")
        $realm.SetAttribute("resourceName", "UserDatabase")
        $engine.AppendChild($realm) | Out-Null
    }
    # Remove existing CredentialHandler(s)
    $handlers = $realm.SelectNodes("CredentialHandler")
    foreach ($h in $handlers) { $realm.RemoveChild($h) | Out-Null }
    # Add new CredentialHandler
    $ch = $xml.CreateElement("CredentialHandler")
    $ch.SetAttribute("className", "org.apache.catalina.realm.SecretKeyCredentialHandler")
    $ch.SetAttribute("algorithm", "PBKDF2WithHmacSHA512")
    $ch.SetAttribute("iterations", "10000")
    $ch.SetAttribute("saltLength", "16")
    $realm.AppendChild($ch) | Out-Null
    $xml.Save($serverXml)
    Write-Log "Patched server.xml with compliant CredentialHandler"

    # --- Generate secure hash with PBKDF2WithHmacSHA512 ---
    $env:CATALINA_HOME = $tomcatBase
    $hash = $null
    try {
        $process = Start-Process -FilePath $digestScript -ArgumentList "-a", "PBKDF2WithHmacSHA512", "-i", "10000", "-s", "16", $Password -NoNewWindow -Wait -RedirectStandardOutput "temp_hash.txt" -PassThru
        $hash = Get-Content "temp_hash.txt" | Select-String -Pattern "${Password}:(.*)" | ForEach-Object { $_.Matches.Groups[1].Value }
        Remove-Item "temp_hash.txt" -Force -ErrorAction SilentlyContinue
        if ([string]::IsNullOrEmpty($hash)) {
            throw "Failed to generate password hash - no output found"
        }
        $hash = $hash.Trim()
    } catch {
        Write-Log "Error generating password hash: $_" "ERROR"
        throw "Failed to generate password hash"
    }

    # Update user with hashed password
    $usersXmlPath = Join-Path $confPath "tomcat-users.xml"
    if (-not (Test-XmlStructure $usersXmlPath)) {
        throw "Invalid or missing tomcat-users.xml at $usersXmlPath"
    }
    if (Update-TomcatUser -UsersXmlPath $usersXmlPath -Username $Username -Password $hash -Roles $Roles) {
        Write-Log "Successfully configured user $Username"
    } else {
        throw "Failed to configure user"
    }

    # --- Permission fix for Tomcat config files ---
    Start-Process icacls -ArgumentList "`"$serverXml`"", "/grant", "SYSTEM:R", "/grant", "Users:R" -NoNewWindow -Wait
    Start-Process icacls -ArgumentList "`"$usersXmlPath`"", "/grant", "SYSTEM:R", "/grant", "Users:R" -NoNewWindow -Wait
    Write-Log "Granted SYSTEM and Users read access to server.xml and tomcat-users.xml"
    
    # Install service if requested
    if ($InstallService) {
        $serviceName = "Tomcat$($majorVersion.Replace('.', ''))"
        # DEBUG: Log the binPath and serviceBat
        Write-Log ("DEBUG: binPath is $binPath") "DEBUG"
        $serviceBat = Join-Path $binPath "service.bat"
        Write-Log ("DEBUG: serviceBat is $serviceBat") "DEBUG"
        # Diagnostic: Log current user and elevation
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Write-Log ("DEBUG: Current user is $currentUser, Elevated: $isElevated") "DEBUG"
        # Diagnostic: Log ACLs for bin directory and service.bat
        try {
            $binAcl = Get-Acl $binPath | Format-List | Out-String
            Write-Log ("DEBUG: ACL for binPath: $binAcl") "DEBUG"
        } catch { Write-Log ("DEBUG: Failed to get ACL for binPath: $_") "DEBUG" }
        try {
            $batAcl = Get-Acl $serviceBat | Format-List | Out-String
            Write-Log ("DEBUG: ACL for service.bat: $batAcl") "DEBUG"
        } catch { Write-Log ("DEBUG: Failed to get ACL for service.bat: $_") "DEBUG" }
        # Diagnostic: Try to read the file
        try {
            $batContent = Get-Content $serviceBat -ErrorAction Stop | Out-String
            Write-Log ("DEBUG: Successfully read service.bat (first 100 chars): $($batContent.Substring(0, [Math]::Min(100, $batContent.Length)))") "DEBUG"
        } catch { Write-Log ("DEBUG: Failed to read service.bat: $_") "DEBUG" }
        # Diagnostic: Check if file is locked
        try {
            $stream = [System.IO.File]::Open($serviceBat, 'Open', 'Read', 'None')
            $stream.Close()
            Write-Log ("DEBUG: service.bat is not locked by another process") "DEBUG"
        } catch { Write-Log ("DEBUG: service.bat is locked or cannot be opened: $_") "DEBUG" }
        if (Set-TomcatService -Action "install" -ServiceName $serviceName -BinPath $binPath) {
            Write-Log "Successfully installed Tomcat service: $serviceName"
        } else {
            throw "Failed to install Tomcat service"
        }
        # Configure firewall if requested
        if ($ConfigureFirewall) {
            $tomcatExe = Join-Path $binPath "tomcat.exe"
            if (-not (Test-Path $tomcatExe)) {
                Write-Log "tomcat.exe not found, adding generic port 8080 rule instead." "WARNING"
                New-NetFirewallRule -DisplayName "Tomcat-$serviceName" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow -Description "Allow Tomcat $serviceName inbound traffic"
            } else {
                if (Set-FirewallRules -ServiceName $serviceName) {
                    Write-Log "Successfully configured firewall rules"
                } else {
                    throw "Failed to configure firewall rules"
                }
            }
        }
    }

    # After extraction, set permissions for Administrators and current user recursively
    try {
        $admin = [System.Security.Principal.NTAccount]"BUILTIN\Administrators"
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $ruleAdmin = New-Object System.Security.AccessControl.FileSystemAccessRule($admin, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $ruleUser = New-Object System.Security.AccessControl.FileSystemAccessRule($user, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $items = Get-ChildItem -Path $tomcatBase -Recurse -Force -Directory
        $items = @($tomcatBase) + $items
        foreach ($item in $items) {
            try {
                $acl = Get-Acl $item.FullName
                $acl.AddAccessRule($ruleAdmin)
                $acl.AddAccessRule($ruleUser)
                Set-Acl -Path $item.FullName -AclObject $acl
            } catch {
                Write-Log ("Failed to set permissions on {0}: {1}" -f $item.FullName, $_) "WARNING"
            }
        }
        Write-Log "Set full control permissions for Administrators and $user on $tomcatBase and all subfolders" "INFO"
    } catch {
        Write-Log ("Failed to set permissions recursively on {0}: {1}" -f $tomcatBase, $_) "WARNING"
    }
    # Remove read-only attribute from all files and directories
    try {
        Get-ChildItem -Path $tomcatBase -Recurse -Force | ForEach-Object {
            if ($_.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                $_.Attributes = $_.Attributes -bxor [System.IO.FileAttributes]::ReadOnly
            }
        }
        Write-Log "Removed read-only attribute from all files and directories in $tomcatBase" "INFO"
    } catch {
        Write-Log ("Failed to remove read-only attribute from files/directories in {0}: {1}" -f $tomcatBase, $_) "WARNING"
    }
}
catch {
    Write-Log "Error in main script: $_" "ERROR"
    exit 1
}

Write-Log "Tomcat installation completed successfully"
