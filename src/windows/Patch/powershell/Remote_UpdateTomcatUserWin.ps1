# Remote_UpdateTomcatUserWin.ps1
# Remotely updates Tomcat user password security configuration on Windows servers (format matches Remote_CheckTomcatConfigWin.ps1)

param (
    [Parameter(Mandatory=$true)][string[]]$ServerName,
    [string]$TomcatHome = $null,
    [string]$ServiceName = "Tomcat101",
    [Parameter(Mandatory=$true)][PSCredential]$Credential
)

function Log {
    param(
        [Parameter(Mandatory=$true)][String]$msg,
        [Parameter(Mandatory=$true)][String]$server
    )
    $script:logMessages += "[$server] $msg"
    Write-Host "[$server] $msg"
}

$uniqueServers = $ServerName | Select-Object -Unique
foreach ($server in $uniqueServers) {
    $script:logMessages = @()
    Log -msg "Starting remote Tomcat user update on $server..." -server $server
    try {
        $updateResults = Invoke-Command -ComputerName $server -Credential $Credential -ScriptBlock {
            param($TomcatHome, $ServiceName)
            $logMessages = @()
            function Write-Log {
                param($Message)
                $script:logMessages += $Message
                Write-Host $Message
            }
            $execTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $hostname = $env:COMPUTERNAME
            Write-Host ("#" * 60 + $hostname + "#" * 59)
            Write-Host "Execution Time: $execTime"
            Write-Host "HOSTNAME: $hostname"
            Write-Host ("=" * 27)
            Write-Log "[Remote] Script block started"

            # --- Robust Java detection ---
            function Find-JavaHome {
                if ($env:JAVA_HOME) {
                    $javaExe = Join-Path $env:JAVA_HOME 'bin\java.exe'
                    if (Test-Path $javaExe) { Write-Log "[Remote] Found JAVA_HOME: $env:JAVA_HOME"; return $env:JAVA_HOME }
                }
                if (Test-Path 'C:\Program Files\Java') {
                    $dirs = Get-ChildItem 'C:\Program Files\Java' -Directory | Sort-Object Name -Descending
                    foreach ($dir in $dirs) {
                        $javaExe = Join-Path $dir.FullName 'bin\java.exe'
                        if (Test-Path $javaExe) {
                            Write-Log "[Remote] Found Java in $($dir.FullName)"; return $dir.FullName
                        }
                    }
                }
                $javaCmd = Get-Command java.exe -ErrorAction SilentlyContinue
                if ($javaCmd -is [System.Management.Automation.CommandInfo]) {
                    $javaPath = $javaCmd.Source
                    $parent = Split-Path (Split-Path $javaPath -Parent) -Parent
                    Write-Log "[Remote] Found java.exe in PATH: $javaPath, parent: $parent"; return $parent
                }
                Write-Log "[Remote] No valid Java found (JAVA_HOME, C:\\Program Files\\Java, or PATH)"; return $null
            }
            $ResolvedJavaHome = Find-JavaHome
            if (-not $ResolvedJavaHome -or [string]::IsNullOrWhiteSpace($ResolvedJavaHome)) {
                Write-Log "[Remote] ERROR: Could not auto-detect a valid Java installation. Please install Java 11+ and try again."
                Write-Log "[Remote] Script block ended"
                return $logMessages
            }
            $env:JAVA_HOME = $ResolvedJavaHome
            $env:PATH = "$ResolvedJavaHome\bin;" + $env:PATH
            Write-Log "Using JAVA_HOME: $ResolvedJavaHome"
            # --- End Java detection ---

            # --- Tomcat detection (like audit script) ---
            function Get-TomcatConfigPath {
                if ($TomcatHome -and (Test-Path $TomcatHome)) {
                    $confPath = Join-Path $TomcatHome "conf"
                    $serverXml = Join-Path $confPath "server.xml"
                    if (Test-Path $serverXml) {
                        $version = "Unknown"
                        if ($TomcatHome -match "apache-tomcat-(\d+\.\d+)(?:\.\d+)?") {
                            $version = $matches[1]
                        } elseif ($TomcatHome -match "Tomcat\s*(\d+\.\d+)") {
                            $version = $matches[1]
                        }
                        Write-Log "Found Tomcat configuration at: $confPath"
                        return @{ Path = $confPath; Version = $version }
                    }
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
                            $version = "Unknown"
                            if ($path -match "apache-tomcat-(\d+\.\d+)(?:\.\d+)?") {
                                $version = $matches[1]
                            } elseif ($path -match "Tomcat\s*(\d+\.\d+)") {
                                $version = $matches[1]
                            }
                            Write-Log "Found Tomcat configuration at: $path"
                            return @{ Path = $path; Version = $version }
                        }
                    }
                }
                return $null
            }
            $tomcatInfo = Get-TomcatConfigPath
            if (-not $tomcatInfo) {
                Write-Log "ERROR - No Tomcat configuration directory found"
                Write-Log "[Remote] Script block ended"
                return $logMessages
            }
            $confPath = $tomcatInfo.Path
            $Version = $tomcatInfo.Version
            $TomcatHome = Split-Path $confPath
            Write-Log "Detected Tomcat version $Version at $confPath"
            Write-Log "Tomcat Home: $TomcatHome"
            Write-Log "Tomcat Version: $Version"

            # --- Main update logic (from previous script, using Write-Log for all output) ---
            function Backup-ConfigFile {
                param($FilePath)
                if (-not $FilePath -or [string]::IsNullOrWhiteSpace($FilePath)) {
                    Write-Log "ERROR: FilePath is null or empty in Backup-ConfigFile."
                    return $null
                }
                try {
                    $backupPath = "$FilePath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
                    Copy-Item -Path $FilePath -Destination $backupPath -Force
                    Write-Log "Created backup: $backupPath"
                    return $backupPath
                } catch {
                    Write-Log "Failed to create backup of $FilePath : $_"
                    return $null
                }
            }
            function Get-TomcatVersion {
                param([string]$TomcatHome)
                if (-not $TomcatHome -or [string]::IsNullOrWhiteSpace($TomcatHome)) {
                    Write-Log "ERROR: TomcatHome is null or empty in Get-TomcatVersion."
                    return $null
                }
                $versionFile = Join-Path $TomcatHome "RELEASE-NOTES"
                $version = $null
                if (Test-Path $versionFile) {
                    $content = Get-Content $versionFile -Raw
                    if ($content -match "Apache Tomcat Version\s+(\d+\.\d+\.\d+)") {
                        $fullVersion = $matches[1]
                        if ($fullVersion -match "^(\d+\.\d+)") { $version = $matches[1] }
                    }
                } elseif ($TomcatHome -match "tomcat-(\d+\.\d+)") { $version = $matches[1] }
                if ($version -and $version -in @("7.0", "8.5", "9.0", "10.0", "10.1")) {
                    Write-Log "Detected Tomcat version: $version"
                    return $version
                } else {
                    Write-Log "ERROR: Could not determine Tomcat version at $TomcatHome. Exiting."
                    return $null
                }
            }
            function Ensure-SetenvBat {
                param([string]$TomcatHome)
                if (-not $TomcatHome -or [string]::IsNullOrWhiteSpace($TomcatHome)) {
                    Write-Log "ERROR: TomcatHome is null or empty in Ensure-SetenvBat."
                    return $null
                }
                if (-not (Test-Path $TomcatHome)) {
                    Write-Log "ERROR: Tomcat home directory $TomcatHome does not exist. Cannot create setenv.bat."
                    return $null
                }
                $binDir = Join-Path $TomcatHome "bin"
                if (-not (Test-Path $binDir)) {
                    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
                    Write-Log "Created missing Tomcat bin directory: $binDir"
                }
                $setenvPath = Join-Path $binDir "setenv.bat"
                $desired = 'set "CATALINA_HOME=' + $TomcatHome + '"'
                $needsUpdate = $true
                if (Test-Path $setenvPath) {
                    $current = Get-Content $setenvPath -Raw
                    if ($current -match [regex]::Escape($desired)) { $needsUpdate = $false }
                }
                if ($needsUpdate) {
                    Set-Content -Path $setenvPath -Value $desired -Encoding ASCII
                    Write-Log "Created or updated setenv.bat at $setenvPath to set CATALINA_HOME."
                } else {
                    Write-Log "setenv.bat already sets CATALINA_HOME correctly."
                }
            }
            function Test-PBKDF2Support {
                param([string]$TomcatHome)
                if (-not $TomcatHome -or [string]::IsNullOrWhiteSpace($TomcatHome)) {
                    Write-Log "ERROR: TomcatHome is null or empty in Test-PBKDF2Support."
                    return $false
                }
                Ensure-SetenvBat -TomcatHome $TomcatHome
                $digestScript = Join-Path $TomcatHome "bin\digest.bat"
                $testPassword = "TestPassword123!"
                $digestArgs = "-a PBKDF2WithHmacSHA512 -i 10000 -s 16 $testPassword"
                try {
                    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
                    $startInfo.FileName = 'cmd.exe'
                    $startInfo.Arguments = "/c `"$digestScript $digestArgs`""
                    $startInfo.WorkingDirectory = (Split-Path $digestScript)
                    $startInfo.UseShellExecute = $false
                    $startInfo.RedirectStandardOutput = $true
                    $startInfo.EnvironmentVariables["JAVA_HOME"] = $env:JAVA_HOME
                    $process = [System.Diagnostics.Process]::Start($startInfo)
                    $output = $process.StandardOutput.ReadToEnd()
                    $process.WaitForExit()
                    if ($output -match "NoSuchAlgorithmException" -or $output -match "not available" -or $output -match "Error") { return $false }
                    if ($process.ExitCode -eq 0 -and $output -match ":") { return $true } else { return $false }
                } catch { return $false }
            }
            function Patch-ServerXml {
                param([string]$TomcatHome, [string]$Version)
                if (-not $TomcatHome -or [string]::IsNullOrWhiteSpace($TomcatHome)) {
                    Write-Log "ERROR: TomcatHome is null or empty in Patch-ServerXml."
                    return $false
                }
                $serverXmlPath = Join-Path $TomcatHome "conf\server.xml"
                if (-not (Test-Path $serverXmlPath)) {
                    Write-Log "server.xml not found at $serverXmlPath"
                    return $false
                }
                Backup-ConfigFile $serverXmlPath | Out-Null
                [xml]$xml = Get-Content $serverXmlPath
                $realm = $xml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
                if (-not $realm) {
                    Write-Log "UserDatabaseRealm not found in server.xml. No changes made to Realm structure."
                    return $false
                }
                $handlers = @(); foreach ($node in $realm.ChildNodes) { if ($node.Name -eq "CredentialHandler") { $handlers += $node } }
                foreach ($h in $handlers) { $realm.RemoveChild($h) | Out-Null }
                $ch = $xml.CreateElement("CredentialHandler")
                if ($Version -eq "7.0") {
                    $ch.SetAttribute("className", "org.apache.catalina.realm.MessageDigestCredentialHandler")
                    $ch.SetAttribute("algorithm", "SHA-256")
                } else {
                    $ch.SetAttribute("className", "org.apache.catalina.realm.SecretKeyCredentialHandler")
                    $ch.SetAttribute("algorithm", "PBKDF2WithHmacSHA512")
                    $ch.SetAttribute("iterations", "10000")
                    $ch.SetAttribute("saltLength", "16")
                }
                $realm.AppendChild($ch) | Out-Null
                $xml.Save($serverXmlPath)
                Write-Log "Patched server.xml with correct CredentialHandler for Tomcat $Version"
                return $true
            }
            function Get-PasswordHash {
                param([string]$TomcatBin, [string]$Password, [string]$Version, [string]$TomcatHome)
                if (-not $TomcatHome -or [string]::IsNullOrWhiteSpace($TomcatHome)) {
                    Write-Log "ERROR: TomcatHome is null or empty in Get-PasswordHash."
                    return $null
                }
                Ensure-SetenvBat -TomcatHome $TomcatHome
                $digestScript = Join-Path $TomcatBin "digest.bat"
                if (-not (Test-Path $digestScript)) {
                    Write-Log "digest.bat not found at $digestScript"
                    return $null
                }
                if ($Version -eq "7.0") {
                    $algorithm = "SHA-256"
                    $args = "-a $algorithm $Password"
                } elseif ($Version -eq "8.5") {
                    $algorithm = "PBKDF2WithHmacSHA512"
                    $iterations = "10000"
                    $saltLength = "16"
                    $args = "-a $algorithm -i $iterations -s $saltLength $Password"
                } elseif ($Version -in @("9.0", "10.0", "10.1")) {
                    $algorithm = "PBKDF2WithHmacSHA512"
                    $iterations = "10000"
                    $saltLength = "16"
                    $args = "-h org.apache.catalina.realm.SecretKeyCredentialHandler -a $algorithm -i $iterations -s $saltLength $Password"
                } else {
                    Write-Log "ERROR: Unsupported Tomcat version $Version for password hashing."
                    return $null
                }
                try {
                    Write-Log "Running digest.bat command: $digestScript $args"
                    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
                    $startInfo.FileName = 'cmd.exe'
                    $startInfo.Arguments = "/c `"$digestScript $args`""
                    $startInfo.WorkingDirectory = (Split-Path $digestScript)
                    $startInfo.UseShellExecute = $false
                    $startInfo.RedirectStandardOutput = $true
                    $startInfo.EnvironmentVariables["JAVA_HOME"] = $env:JAVA_HOME
                    $process = [System.Diagnostics.Process]::Start($startInfo)
                    $digestRaw = $process.StandardOutput.ReadToEnd()
                    $process.WaitForExit()
                    $digestRaw = $digestRaw.Trim()
                    Write-Log "digest.bat output: $digestRaw"
                    if ($digestRaw -match "MessageDigestCredentialHandler" -or $digestRaw -match "NoSuchAlgorithmException") {
                        Write-Log "WARNING: digest.bat output indicates MessageDigestCredentialHandler or missing PBKDF2 support. Check your Tomcat and Java versions!"
                    }
                    if ($Version -in @("8.5", "9.0", "10.0", "10.1")) {
                        if ($digestRaw -match "^.+:[0-9a-fA-F]+\$[0-9]+\$[0-9a-fA-F]+(\$[0-9a-fA-F]+)?$") {
                            $hash = $digestRaw
                            return $hash
                        } else {
                            Write-Log "digest.bat output did not match expected PBKDF2 hash format: $digestRaw"
                            return $null
                        }
                    } elseif ($Version -eq "7.0" -and $digestRaw -match "^[0-9a-fA-F]{64}$") {
                        return $digestRaw.Trim()
                    } else {
                        Write-Log "digest.bat output: $digestRaw"
                        return $null
                    }
                } catch {
                    Write-Log "Error running digest.bat: $_"
                    return $null
                }
            }
            function Update-AllUserPasswords {
                param([string]$TomcatHome, [string]$Version)
                $usersXmlPath = Join-Path $TomcatHome "conf\tomcat-users.xml"
                if (-not (Test-Path $usersXmlPath)) {
                    Write-Log "tomcat-users.xml not found at $usersXmlPath"
                    return $false
                }
                Backup-ConfigFile $usersXmlPath | Out-Null
                [xml]$usersXml = Get-Content $usersXmlPath
                $users = $usersXml.SelectNodes("//user")
                $updated = $false
                $binPath = Join-Path $TomcatHome "bin"
                foreach ($user in $users) {
                    $username = $user.GetAttribute("username")
                    $password = $user.GetAttribute("password")
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
                        Write-Log "Failed to hash password for user $username. Leaving as is."
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
            function Get-TomcatStatus {
                param([string]$ServiceName, [string]$TomcatHome)
                $status = @{}
                try {
                    $service = Get-Service -Name $ServiceName -ErrorAction Stop
                    $status.ServiceFound = $true
                    $status.ServiceStatus = $service.Status
                } catch {
                    $status.ServiceFound = $false
                    $status.ServiceStatus = 'NotFound'
                }
                $proc = Get-Process | Where-Object {
                    ($_.ProcessName -like 'tomcat*' -or $_.ProcessName -eq 'java') -and ($_.Path -like "$TomcatHome*" -or $_.Path -like '*catalina*')
                }
                if ($proc) {
                    $status.ProcessFound = $true
                    $status.ProcessCount = $proc.Count
                } else {
                    $status.ProcessFound = $false
                    $status.ProcessCount = 0
                }
                return $status
            }
            function Restart-TomcatIfRunning {
                param([string]$ServiceName, [string]$TomcatHome)
                $status = Get-TomcatStatus -ServiceName $ServiceName -TomcatHome $TomcatHome
                if ($status.ServiceFound -and $status.ServiceStatus -eq 'Running') {
                    Write-Log "Tomcat is running as a service ($ServiceName). Restarting via service..."
                    try {
                        Stop-Service -Name $ServiceName -Force
                        Start-Sleep -Seconds 5
                        Start-Service -Name $ServiceName
                        $service = Get-Service -Name $ServiceName
                        if ($service.Status -eq 'Running') {
                            Write-Log "Tomcat service successfully restarted."
                            return $true
                        } else {
                            Write-Log "Failed to restart Tomcat service. Status: $($service.Status)" "ERROR"
                            return $false
                        }
                    } catch {
                        Write-Log "Error managing Tomcat service: $_" "ERROR"
                        return $false
                    }
                } elseif ($status.ProcessFound) {
                    Write-Log "Tomcat is running as a standalone process. Attempting to restart process..."
                    try {
                        $proc = Get-Process | Where-Object {
                            ($_.ProcessName -like 'tomcat*' -or $_.ProcessName -eq 'java') -and ($_.Path -like "$TomcatHome*" -or $_.Path -like '*catalina*')
                        }
                        $proc | Stop-Process -Force
                        Start-Sleep -Seconds 5
                        $startupScript = Join-Path $TomcatHome 'bin\startup.bat'
                        if (Test-Path $startupScript) {
                            Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$startupScript`"" -WorkingDirectory (Join-Path $TomcatHome 'bin')
                            Write-Log "Tomcat process restarted via $startupScript."
                            return $true
                        } else {
                            Write-Log "Could not find startup.bat to restart Tomcat process." "ERROR"
                            return $false
                        }
                    } catch {
                        Write-Log "Error restarting Tomcat process: $_" "ERROR"
                        return $false
                    }
                } else {
                    Write-Log "Tomcat is not running. No restart will be performed."
                    return $true
                }
            }
            Write-Log "Starting Tomcat configuration and user update"
            $Version = Get-TomcatVersion -TomcatHome $TomcatHome
            if (-not $Version) {
                Write-Log "ERROR: Could not determine Tomcat version. Exiting."
                Write-Log "[Remote] Script block ended"
                return $logMessages
            }
            if ($Version -eq "7.0") {
                Patch-ServerXml -TomcatHome $TomcatHome -Version $Version
                $HashAlg = "SHA-256"
            } elseif ($Version -in @("8.5", "9.0", "10.0", "10.1")) {
                $pbkdf2Supported = Test-PBKDF2Support -TomcatHome $TomcatHome
                if (-not $pbkdf2Supported) {
                    Write-Log "ERROR: PBKDF2WithHmacSHA512 is not available in your Java runtime. Please upgrade Java to at least 8u161 or 11+ with PBKDF2 support. Cannot update user passwords to compliance. Exiting."
                    Write-Log "[Remote] Script block ended"
                    return $logMessages
                }
                Patch-ServerXml -TomcatHome $TomcatHome -Version $Version
                $HashAlg = "PBKDF2WithHmacSHA512"
            } else {
                Write-Log "ERROR: Unsupported Tomcat version $Version. Exiting without making changes."
                Write-Log "[Remote] Script block ended"
                return $logMessages
            }
            $updated = Update-AllUserPasswords -TomcatHome $TomcatHome -Version $Version
            Restart-TomcatIfRunning -ServiceName $ServiceName -TomcatHome $TomcatHome | Out-Null
            Write-Log "Configuration update completed successfully"
            Write-Log "[Remote] Script block ended"
            return $logMessages
        } -ArgumentList $TomcatHome, $ServiceName
        if ($updateResults) {
            $updateResults | ForEach-Object { Log -msg $_ -server $server }
        } else {
            Log -msg "No output returned from remote script." -server $server
        }
    } catch {
        Log -msg "[Client][$server] ERROR: $_" -server $server
    }
}
