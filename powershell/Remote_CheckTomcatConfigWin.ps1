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

                # Detect Tomcat path and version
                function Get-TomcatConfigPath {
                    if ($TomcatConfPath -and (Test-Path $TomcatConfPath)) {
                        $serverXml = Join-Path $TomcatConfPath "server.xml"
                        if (Test-Path $serverXml) {
                            $version = if ($TomcatConfPath -match "Tomcat\s*(\d+\.\d+)") { $matches[1] } else { "Unknown" }
                            Write-Log "Tomcat configuration directory located at $TomcatConfPath"
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

                    foreach ($path in $possiblePaths) {
                        if (Test-Path $path) {
                            $serverXml = Join-Path $path "server.xml"
                            if (Test-Path $serverXml) {
                                $version = if ($path -match "Tomcat\s*(\d+\.\d+)") { $matches[1] } else { "Unknown" }
                                Write-Log "Tomcat configuration directory located at $path"
                                return @{ Path = $path; Version = $version }
                            }
                        }
                    }
                    return $null
                }

                $tomcatInfo = Get-TomcatConfigPath
                if (-not $tomcatInfo) {
                    Write-Log "ERROR - No Tomcat configuration directory found"
                    return $logMessages
                }
                $tomcatConfPath = $tomcatInfo.Path
                $tomcatVersion = $tomcatInfo.Version
                Write-Log "Detected Tomcat version $tomcatVersion at $tomcatConfPath"

                # Load configuration files
                $serverXmlPath = Join-Path $tomcatConfPath "server.xml"
                $usersXmlPath = Join-Path $tomcatConfPath "tomcat-users.xml"

                if (-not (Test-Path $serverXmlPath) -or -not (Test-Path $usersXmlPath)) {
                    Write-Log "ERROR - server.xml or tomcat-users.xml not found"
                    return $logMessages
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
                    Write-Log "No users defined in tomcat-users.xml - Compliant"
                    Write-Log "Overall Configuration: Secure"
                    Write-Log "Audit completed"
                    return $logMessages
                }

                foreach ($user in $users) {
                    $username = $user.username
                    $password = $user.password

                    # Skip users without passwords
                    if (-not $password) {
                        Write-Log "User '$username': Compliant (no password)"
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

                    # Initialize compliance status
                    $complianceStatus = ""

                    # Compliance checks
                    if ($passwordType -eq "Plaintext") {
                        $complianceStatus = "Non-compliant - Plaintext password detected"
                        $isSecure = $false
                    }
                    elseif ($passwordType -in @("Hashed_MD5", "Salted_MD5")) {
                        $complianceStatus = "Non-compliant - Weak MD5 hashing"
                        $isSecure = $false
                    }
                    elseif ($passwordType -eq "Hashed_SHA1") {
                        $complianceStatus = "Non-compliant - Weak SHA1 hashing"
                        $isSecure = $false
                    }
                    elseif ($passwordType -eq "Hashed_SHA256") {
                        if ($tomcatVersion -eq "7.0") {
                            $complianceStatus = "Compliant for Tomcat 7.0"
                        } elseif (-not $credentialHandler -or $credentialHandler.algorithm -ne "SHA-256" -or
                            [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
                            $complianceStatus = "Non-compliant - SHA256 requires salt and iterations"
                            $isSecure = $false
                        } else {
                            $complianceStatus = "Compliant"
                        }
                    }
                    elseif ($passwordType -eq "Hashed_SHA512") {
                        if ($tomcatVersion -eq "7.0") {
                            $complianceStatus = "Non-compliant - SHA512 not supported in Tomcat 7.0"
                            $isSecure = $false
                        } elseif (-not $credentialHandler -or $credentialHandler.algorithm -ne "SHA-512" -or
                            [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
                            $complianceStatus = "Non-compliant - SHA512 requires salt and iterations"
                            $isSecure = $false
                        } else {
                            $complianceStatus = "Compliant"
                        }
                    }
                    elseif ($passwordType -eq "Salted_PBKDF2") {
                        if ($tomcatVersion -eq "7.0") {
                            $complianceStatus = "Non-compliant - PBKDF2 not supported in Tomcat 7.0"
                            $isSecure = $false
                        } elseif ($tomcatVersion -eq "8.5") {
                            if (-not $credentialHandler -or $credentialHandler.algorithm -notin @("SHA-256", "SHA-512") -or
                                [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
                                $complianceStatus = "Non-compliant - PBKDF2 requires compatible handler"
                                $isSecure = $false
                            } else {
                                $complianceStatus = "Compliant"
                            }
                        } else { # Tomcat 9.0, 10.0, or 10.1
                            if ($credentialHandler -and $credentialHandler.className -eq "org.apache.catalina.realm.SecretKeyCredentialHandler" -and
                                $credentialHandler.algorithm -eq "PBKDF2WithHmacSHA512" -and
                                [int]$credentialHandler.iterations -ge 10000 -and [int]$credentialHandler.saltLength -ge 16) {
                                $complianceStatus = "Compliant"
                            } else {
                                $complianceStatus = "Non-compliant - PBKDF2 requires SecretKeyCredentialHandler"
                                $isSecure = $false
                            }
                        }
                    }

                    # Log single compliance status line
                    Write-Log "User '$username': $complianceStatus"
                }

                # Report overall security
                Write-Log "Overall Configuration: $(if ($isSecure) { 'Secure' } else { 'Insecure' })"
                Write-Log "Audit completed"
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
