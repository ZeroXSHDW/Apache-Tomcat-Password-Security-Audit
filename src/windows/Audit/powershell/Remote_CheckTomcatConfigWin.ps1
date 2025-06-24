# Remote_CheckTomcatConfigWin.ps1
# Audits Tomcat configuration for password security and compliance (7.0, 8.5, 9.0, 10.0, 10.1) on remote servers

param (
    [Parameter(Mandatory=$true)][string[]]$ServerName,
    [string]$TomcatConfPath,
    [Parameter(Mandatory=$true)][PSCredential]$Credential
)

# Log setup
$logFile = "C:\Temp\TomcatConfigCheck.csv"
function Log {
    param(
        [Parameter(Mandatory=$true)][String]$msg,
        [Parameter(Mandatory=$true)][String]$server
    )
    # Store message for single CSV line
    $script:logMessages += "[$server] $msg"
    # Output to console for debugging
    Write-Host "[$server] $msg"
}

# Ensure log file directory exists
if (-not (Test-Path (Split-Path $logFile -Parent))) {
    New-Item -Path (Split-Path $logFile -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

# Initialize log file with header if it doesn't exist
if (-not (Test-Path $logFile)) {
    Add-Content -Path $logFile -Value "Timestamp,Server,Message" -ErrorAction SilentlyContinue
}

# Check if script has already run in this session
if ($script:HasRun) {
    Write-Host "[Client] Error: Script has already executed in this PowerShell session."
    exit
}

# Mark script as executed
try {
    $script:HasRun = $true
    Write-Host "[Client] Starting script execution at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')."
}
catch {
    Write-Host "[Client] Error: Failed to set execution state: $($_.Exception.Message)"
    exit
}

try {
    # Deduplicate server names
    $uniqueServers = $ServerName | Select-Object -Unique
    if ($uniqueServers.Count -lt $ServerName.Count) {
        Write-Host "[Client] Warning: Duplicate server names detected. Auditing unique servers: $($uniqueServers -join ',')"
    }

    foreach ($server in $uniqueServers) {
        # Initialize log messages array for this server
        $script:logMessages = @()
        Log -msg "Checking Apache Tomcat configuration security on $server..." -server $server

        try {
            # Remote execution
            $auditResults = Invoke-Command -ComputerName $server -Credential $Credential -ScriptBlock {
                param($TomcatConfPath)

                # Local log function for remote execution
                $logMessages = @()
                function Write-Log {
                    param($Message)
                    $script:logMessages += $Message
                    Write-Host $Message
                }

                # Section divider and headers
                $execTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $hostname = $env:COMPUTERNAME
                Write-Host ("#" * 60 + $hostname + "#" * 59)
                Write-Host "Execution Time: $execTime"
                Write-Host "HOSTNAME: $hostname"
                Write-Host ("=" * 27)

                Write-Host "Searching common Tomcat configuration paths..."

                # Detect Tomcat path and version (with improved regex)
                function Get-TomcatConfigPath {
                    if ($TomcatConfPath -and (Test-Path $TomcatConfPath)) {
                        $serverXml = Join-Path $TomcatConfPath "server.xml"
                        if (Test-Path $serverXml) {
                            $version = "Unknown"
                            if ($TomcatConfPath -match "apache-tomcat-(\d+\.\d+)(?:\.\d+)?") {
                                $version = $matches[1]
                            } elseif ($TomcatConfPath -match "Tomcat\s*(\d+\.\d+)") {
                                $version = $matches[1]
                            }
                            Write-Host "Found Tomcat configuration at: $TomcatConfPath"
                            return @{ Path = $TomcatConfPath; Version = $version }
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
                    # Dynamically add all conf directories under Tomcat root (handles apache-tomcat-10.1.42 etc.)
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
                                Write-Host "Found Tomcat configuration at: $path"
                                return @{ Path = $path; Version = $version }
                            }
                        }
                    }
                    return $null
                }

                $tomcatInfo = Get-TomcatConfigPath
                if (-not $tomcatInfo) {
                    Write-Log "ERROR - No Tomcat configuration directory found" -server $env:COMPUTERNAME
                    return $logMessages
                }
                $tomcatConfPath = $tomcatInfo.Path
                $tomcatVersion = $tomcatInfo.Version
                Write-Log "Detected Tomcat version $tomcatVersion at $tomcatConfPath"
                $tomcatHome = Split-Path $tomcatConfPath
                Write-Log "Tomcat Home: $tomcatHome"
                Write-Log "Tomcat Version: $tomcatVersion"
                Write-Log "Auditing server.xml"
                Write-Log "Server Configuration:"
                if ($tomcatVersion -eq "7.0") {
                    Write-Log "    - Recommendation: Use MessageDigestCredentialHandler with SHA-256."
                    Write-Log "    - Example: <CredentialHandler className='org.apache.catalina.realm.MessageDigestCredentialHandler' algorithm='SHA-256'/>"
                    Write-Log "    - Tomcat 7.0 requires MessageDigestCredentialHandler with SHA-256"
                } else {
                    Write-Log "    - Recommendation: Use PBKDF2WithHmacSHA512 or SHA-256 with at least 10,000 iterations and 16+ salt length."
                    Write-Log "    - Example: <CredentialHandler className='org.apache.catalina.realm.SecretKeyCredentialHandler' algorithm='PBKDF2WithHmacSHA512' iterations='10000' saltLength='16'/>"
                }
                # Print credential handler details
                $serverXmlPath = Join-Path $tomcatConfPath "server.xml"
                $usersXmlPath = Join-Path $tomcatConfPath "tomcat-users.xml"
                $serverXml = [xml](Get-Content $serverXmlPath -Encoding UTF8)
                $usersXml = [xml](Get-Content $usersXmlPath -Encoding UTF8)
                $realm = $serverXml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
                if (-not $realm) { $realm = $serverXml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.MemoryRealm']") }
                $credentialHandler = $realm.CredentialHandler
                if ($credentialHandler) {
                    $chClass = $credentialHandler.className
                    $chAlg = $credentialHandler.algorithm
                    $chIter = $credentialHandler.iterations
                    $chSalt = $credentialHandler.saltLength
                    Write-Log "  Credential Handler: $chClass"
                    Write-Log "  Algorithm: $chAlg"
                    Write-Log "  Iterations: $chIter"
                    Write-Log "  Salt Length: $chSalt"
                } else {
                    Write-Log "  Credential Handler: None"
                    Write-Log "  Algorithm: None"
                    Write-Log "  Iterations: 0"
                    Write-Log "  Salt Length: 0"
                }
                # Compliance status for server.xml
                if ($tomcatVersion -eq "7.0" -and -not $credentialHandler) {
                    Write-Log "  Status: Non-compliant"
                } elseif ($credentialHandler -and $credentialHandler.algorithm -eq "SHA-256" -and [int]$credentialHandler.iterations -ge 10000 -and [int]$credentialHandler.saltLength -ge 16) {
                    Write-Log "  Status: Compliant"
                } elseif ($credentialHandler -and $credentialHandler.algorithm -eq "PBKDF2WithHmacSHA512" -and [int]$credentialHandler.iterations -ge 10000 -and [int]$credentialHandler.saltLength -ge 16) {
                    Write-Log "  Status: Compliant"
                } else {
                    Write-Log "  Status: Non-compliant"
                }
                Write-Log "Auditing tomcat-users.xml"
                Write-Log "    User Audit Results:"
                Write-Log "    Username | Password Type | Compliance"
                Write-Log "    ---------|---------------|-----------"
                $users = $usersXml.'tomcat-users'.user
                $isSecure = $true
                if (-not $users) {
                    Write-Log "    No users defined in tomcat-users.xml - Compliant"
                    Write-Log ("=" * 27)
                    Write-Log "Overall Status: Secure"
                    Write-Log "Audit completed. Log: $logFile"
                    return $logMessages
                }
                foreach ($user in $users) {
                    $username = $user.username
                    $password = $user.password
                    if (-not $password) {
                        $passwordType = "None"
                        $complianceStatus = "Compliant (no password)"
                        Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                        continue
                    }
                    $passwordType = switch -Regex ($password) {
                        "^[a-f0-9]{32}$" { "Hashed_MD5" }
                        "^[a-f0-9]{40}$" { "Hashed_SHA1" }
                        "^[a-f0-9]{64}$" { "Hashed_SHA256" }
                        "^[a-f0-9]{128}$" { "Hashed_SHA512" }
                        "^[a-f0-9]{32}:[a-f0-9]{16}$" { "Salted_MD5" }
                        "^[a-f0-9]{32}:[a-f0-9]{16}$" { "Salted_PBKDF2" }
                        default { "Plaintext" }
                    }
                    $complianceStatus = ""
                    if ($passwordType -eq "Plaintext") {
                        $complianceStatus = "Non-compliant"
                        $isSecure = $false
                        Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                        Write-Log "        - Plaintext passwords detected. Use PBKDF2WithHmacSHA512 or SHA-256 with salt and iterations."
                    } elseif ($passwordType -in @("Hashed_MD5", "Salted_MD5")) {
                        $complianceStatus = "Non-compliant"
                        $isSecure = $false
                        Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                        Write-Log "        - Weak MD5 hashing detected. Use SHA-256 or PBKDF2WithHmacSHA512."
                    } elseif ($passwordType -eq "Hashed_SHA1") {
                        $complianceStatus = "Non-compliant"
                        $isSecure = $false
                        Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                        Write-Log "        - Weak SHA1 hashing detected. Use SHA-256 or PBKDF2WithHmacSHA512."
                    } elseif ($passwordType -eq "Hashed_SHA256") {
                        if ($tomcatVersion -eq "7.0") {
                            $complianceStatus = "Compliant for Tomcat 7.0"
                            Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                        } elseif (-not $credentialHandler -or $credentialHandler.algorithm -ne "SHA-256" -or [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
                            $complianceStatus = "Non-compliant"
                            $isSecure = $false
                            Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                            Write-Log "        - SHA256 requires salt and iterations. Use PBKDF2WithHmacSHA512 if possible."
                        } else {
                            $complianceStatus = "Compliant"
                            Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                        }
                    } elseif ($passwordType -eq "Hashed_SHA512") {
                        if ($tomcatVersion -eq "7.0") {
                            $complianceStatus = "Non-compliant"
                            $isSecure = $false
                            Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                            Write-Log "        - SHA512 not supported in Tomcat 7.0. Use SHA-256 or PBKDF2WithHmacSHA512."
                        } elseif (-not $credentialHandler -or $credentialHandler.algorithm -ne "SHA-512" -or [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
                            $complianceStatus = "Non-compliant"
                            $isSecure = $false
                            Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                            Write-Log "        - SHA512 requires salt and iterations. Use PBKDF2WithHmacSHA512 if possible."
                        } else {
                            $complianceStatus = "Compliant"
                            Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                        }
                    } elseif ($passwordType -eq "Salted_PBKDF2") {
                        if ($tomcatVersion -eq "7.0") {
                            $complianceStatus = "Non-compliant"
                            $isSecure = $false
                            Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                            Write-Log "        - PBKDF2 not supported in Tomcat 7.0. Use SHA-256."
                        } elseif ($tomcatVersion -eq "8.5") {
                            if (-not $credentialHandler -or $credentialHandler.algorithm -notin @("SHA-256", "SHA-512") -or [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
                                $complianceStatus = "Non-compliant"
                                $isSecure = $false
                                Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                                Write-Log "        - PBKDF2 requires compatible handler. Use SHA-256 or PBKDF2WithHmacSHA512."
                            } else {
                                $complianceStatus = "Compliant"
                                Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                            }
                        } else {
                            if ($credentialHandler -and $credentialHandler.className -eq "org.apache.catalina.realm.SecretKeyCredentialHandler" -and $credentialHandler.algorithm -eq "PBKDF2WithHmacSHA512" -and [int]$credentialHandler.iterations -ge 10000 -and [int]$credentialHandler.saltLength -ge 16) {
                                $complianceStatus = "Compliant"
                                Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                            } else {
                                $complianceStatus = "Non-compliant"
                                $isSecure = $false
                                Write-Log ("    {0,-8} | {1,-13} | {2}" -f $username, $passwordType, $complianceStatus)
                                Write-Host "        - PBKDF2 requires SecretKeyCredentialHandler."
                            }
                        }
                    }
                }
                Write-Log ("=" * 27)
                Write-Log "Overall Status: $(if ($isSecure) { 'Secure' } else { 'Insecure' })"
                Write-Log "Audit completed. Log: $logFile"

                # Check for Tomcat processes running as NT AUTHORITY\SYSTEM
                $tomcatProcs = Get-WmiObject Win32_Process -Filter "Name = 'java.exe'" | Where-Object { $_.CommandLine -match 'org.apache.catalina.startup.Bootstrap' }
                foreach ($proc in $tomcatProcs) {
                    $ownerInfo = $proc.GetOwner()
                    $owner = "$($ownerInfo.Domain)\\$($ownerInfo.User)"
                    if ($owner -eq 'NT AUTHORITY\\SYSTEM') {
                        Write-Log "WARNING: Tomcat process (PID $($proc.ProcessId)) is running as NT AUTHORITY\\SYSTEM. This is a security risk." -server $env:COMPUTERNAME
                    }
                }

                return $logMessages
            } -ArgumentList $TomcatConfPath

            # Write single CSV line
            if ($auditResults) {
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $combinedMessage = $auditResults -join "; "
                $logEntry = "$timestamp,$server,$combinedMessage"
                Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
            }
        }
        catch {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $errorMessage = "ERROR - Failed to audit ${server}: $($_.Exception.Message)"
            $logEntry = "$timestamp,$server,$errorMessage"
            Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
            Write-Host $errorMessage
            continue
        }
    }
}
finally {
    # No lock file to clean up
}
