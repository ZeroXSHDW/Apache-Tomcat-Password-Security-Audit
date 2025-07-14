param (
    [Parameter(Mandatory=$true)][string[]]$ServerName,
    [string]$TomcatConfPath,
    [Parameter(Mandatory=$true)][PSCredential]$Credential
)

function Get-TomcatAuditJson {
    param($server, $TomcatConfPath, $Credential)
    $result = @{
        Server = $server
        Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        TomcatHome = $null
        TomcatVersion = $null
        ServerXml = $null
        Users = @()
        OverallStatus = $null
        RunningAsSystem = $null
        Errors = @()
    }
    try {
        $auditResults = Invoke-Command -ComputerName $server -Credential $Credential -ScriptBlock {
            param($TomcatConfPath)
            $output = @{
                TomcatHome = $null
                TomcatVersion = $null
                ServerXml = $null
                Users = @()
                OverallStatus = $null
                RunningAsSystem = $null
                Errors = @()
            }
            function Add-Error { param($msg) $output.Errors += $msg }
            function Set-Field { param($k,$v) $output[$k] = $v }
            try {
                function Get-TomcatConfigPath {
                    param($TomcatConfPath)
                    if ($TomcatConfPath -and (Test-Path $TomcatConfPath)) {
                        $serverXml = Join-Path $TomcatConfPath "server.xml"
                        if (Test-Path $serverXml) {
                            $version = "Unknown"
                            if ($TomcatConfPath -match "apache-tomcat-(\d+\.\d+)(?:\.\d+)?") {
                                $version = $matches[1]
                            } elseif ($TomcatConfPath -match "Tomcat\s*(\d+\.\d+)") {
                                $version = $matches[1]
                            }
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
                                $version = "Unknown"
                                if ($path -match "apache-tomcat-(\d+\.\d+)(?:\.\d+)?") {
                                    $version = $matches[1]
                                } elseif ($path -match "Tomcat\s*(\d+\.\d+)") {
                                    $version = $matches[1]
                                }
                                return @{ Path = $path; Version = $version }
                            }
                        }
                    }
                    return $null
                }
                $tomcatInfo = Get-TomcatConfigPath $TomcatConfPath
                if (-not $tomcatInfo) {
                    Add-Error "No Tomcat configuration directory found"
                    return $output
                }
                $output.TomcatHome = (Split-Path $tomcatInfo.Path)
                $output.TomcatVersion = $tomcatInfo.Version
                $serverXmlPath = Join-Path $tomcatInfo.Path "server.xml"
                $usersXmlPath = Join-Path $tomcatInfo.Path "tomcat-users.xml"
                $serverXml = [xml](Get-Content $serverXmlPath -Encoding UTF8)
                $usersXml = [xml](Get-Content $usersXmlPath -Encoding UTF8)
                $realm = $serverXml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.UserDatabaseRealm']")
                if (-not $realm) { $realm = $serverXml.SelectSingleNode("//Realm[@className='org.apache.catalina.realm.MemoryRealm']") }
                $credentialHandler = $realm.CredentialHandler
                $output.ServerXml = @{
                    CredentialHandler = if ($credentialHandler) { $credentialHandler.className } else { $null }
                    Algorithm = if ($credentialHandler) { $credentialHandler.algorithm } else { $null }
                    Iterations = if ($credentialHandler) { $credentialHandler.iterations } else { $null }
                    SaltLength = if ($credentialHandler) { $credentialHandler.saltLength } else { $null }
                }
                # Compliance status for server.xml
                $serverCompliant = $false
                if ($output.TomcatVersion -eq "7.0" -and -not $credentialHandler) {
                    $serverCompliant = $false
                } elseif ($credentialHandler -and $credentialHandler.algorithm -eq "SHA-256" -and [int]$credentialHandler.iterations -ge 10000 -and [int]$credentialHandler.saltLength -ge 16) {
                    $serverCompliant = $true
                } elseif ($credentialHandler -and $credentialHandler.algorithm -eq "PBKDF2WithHmacSHA512" -and [int]$credentialHandler.iterations -ge 10000 -and [int]$credentialHandler.saltLength -ge 16) {
                    $serverCompliant = $true
                }
                $users = $usersXml.'tomcat-users'.user
                $isSecure = $true
                if ($users) {
                    foreach ($user in $users) {
                        $username = $user.username
                        $password = $user.password
                        if (-not $password) {
                            $passwordType = "None"
                            $complianceStatus = "Compliant (no password)"
                        } else {
                            $passwordType = switch -Regex ($password) {
                                "^[a-f0-9]{32}$" { "Hashed_MD5" }
                                "^[a-f0-9]{40}$" { "Hashed_SHA1" }
                                "^[a-f0-9]{64}$" { "Hashed_SHA256" }
                                "^[a-f0-9]{128}$" { "Hashed_SHA512" }
                                "^[a-f0-9]{32}:[a-f0-9]{16}$" { "Salted_MD5" }
                                "^[a-f0-9]{32}:[a-f0-9]{16}$" { "Salted_PBKDF2" }
                                default { "Plaintext" }
                            }
                            if ($passwordType -eq "Plaintext") {
                                $complianceStatus = "Non-compliant"
                                $isSecure = $false
                            } elseif ($passwordType -in @("Hashed_MD5", "Salted_MD5")) {
                                $complianceStatus = "Non-compliant"
                                $isSecure = $false
                            } elseif ($passwordType -eq "Hashed_SHA1") {
                                $complianceStatus = "Non-compliant"
                                $isSecure = $false
                            } elseif ($passwordType -eq "Hashed_SHA256") {
                                if ($output.TomcatVersion -eq "7.0") {
                                    $complianceStatus = "Compliant for Tomcat 7.0"
                                } elseif (-not $credentialHandler -or $credentialHandler.algorithm -ne "SHA-256" -or [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
                                    $complianceStatus = "Non-compliant"
                                    $isSecure = $false
                                } else {
                                    $complianceStatus = "Compliant"
                                }
                            } elseif ($passwordType -eq "Hashed_SHA512") {
                                if ($output.TomcatVersion -eq "7.0") {
                                    $complianceStatus = "Non-compliant"
                                    $isSecure = $false
                                } elseif (-not $credentialHandler -or $credentialHandler.algorithm -ne "SHA-512" -or [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
                                    $complianceStatus = "Non-compliant"
                                    $isSecure = $false
                                } else {
                                    $complianceStatus = "Compliant"
                                }
                            } elseif ($passwordType -eq "Salted_PBKDF2") {
                                if ($output.TomcatVersion -eq "7.0") {
                                    $complianceStatus = "Non-compliant"
                                    $isSecure = $false
                                } elseif ($output.TomcatVersion -eq "8.5") {
                                    if (-not $credentialHandler -or $credentialHandler.algorithm -notin @("SHA-256", "SHA-512") -or [int]$credentialHandler.iterations -lt 10000 -or [int]$credentialHandler.saltLength -lt 16) {
                                        $complianceStatus = "Non-compliant"
                                        $isSecure = $false
                                    } else {
                                        $complianceStatus = "Compliant"
                                    }
                                } else {
                                    if ($credentialHandler -and $credentialHandler.className -eq "org.apache.catalina.realm.SecretKeyCredentialHandler" -and $credentialHandler.algorithm -eq "PBKDF2WithHmacSHA512" -and [int]$credentialHandler.iterations -ge 10000 -and [int]$credentialHandler.saltLength -ge 16) {
                                        $complianceStatus = "Compliant"
                                    } else {
                                        $complianceStatus = "Non-compliant"
                                        $isSecure = $false
                                    }
                                }
                            } else {
                                $complianceStatus = "Unknown"
                                $isSecure = $false
                            }
                        }
                        $output.Users += @{
                            Username = $username
                            PasswordType = $passwordType
                            Compliance = $complianceStatus
                        }
                    }
                } else {
                    $output.Users = @()
                }
                $output.OverallStatus = if ($isSecure) { 'Secure' } else { 'Insecure' }
                # Check for Tomcat processes running as NT AUTHORITY\SYSTEM
                $systemFound = $false
                $tomcatProcs = Get-WmiObject Win32_Process -Filter "Name = 'java.exe'" | Where-Object { $_.CommandLine -match 'org.apache.catalina.startup.Bootstrap' }
                foreach ($proc in $tomcatProcs) {
                    $ownerInfo = $proc.GetOwner()
                    $owner = "$($ownerInfo.Domain)\\$($ownerInfo.User)"
                    if ($owner -eq 'NT AUTHORITY\\SYSTEM') {
                        $systemFound = $true
                    }
                }
                $output.RunningAsSystem = $systemFound
            } catch {
                Add-Error $_.Exception.Message
            }
            return $output
        } -ArgumentList $TomcatConfPath
        $result.TomcatHome = $auditResults.TomcatHome
        $result.TomcatVersion = $auditResults.TomcatVersion
        $result.ServerXml = $auditResults.ServerXml
        $result.Users = $auditResults.Users
        $result.OverallStatus = $auditResults.OverallStatus
        $result.RunningAsSystem = $auditResults.RunningAsSystem
        $result.Errors = $auditResults.Errors
    } catch {
        $result.Errors += $_.Exception.Message
    }
    return $result
}

$allResults = @()
foreach ($server in $ServerName) {
    $allResults += Get-TomcatAuditJson -server $server -TomcatConfPath $TomcatConfPath -Credential $Credential
}

$allResults | ConvertTo-Json -Depth 5 