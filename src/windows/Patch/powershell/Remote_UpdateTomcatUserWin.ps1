# Remote_UpdateTomcatUserWin.ps1
# Remotely updates Tomcat user password security configuration on Windows servers

param (
    [Parameter(Mandatory=$true)][string[]]$ServerName,
    [string]$TomcatHome = $null,
    [Parameter(Mandatory=$true)][PSCredential]$Credential
)

function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp - $Level - $Message"
}

$uniqueServers = $ServerName | Select-Object -Unique
foreach ($server in $uniqueServers) {
    Write-Log "Starting remote Tomcat user update on $server..."
    try {
        $result = Invoke-Command -ComputerName $server -Credential $Credential -ScriptBlock {
            param($TomcatHome)
            
            function Write-Log {
                param($Message, $Level = "INFO")
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Write-Host "$timestamp - $Level - $Message"
            }

            # --- Begin core logic from UpdateTomcatUserWin.ps1 ---
            # (Auto-detect TomcatHome if not provided)
            if (-not $TomcatHome -or -not (Test-Path $TomcatHome)) {
                $candidates = @(
                    "C:\\tomcat",
                    "C:\\Program Files\\Apache Software Foundation\\Tomcat\\apache-tomcat-10.1.42"
                )
                $found = $false
                foreach ($cand in $candidates) {
                    if (Test-Path $cand) {
                        $TomcatHome = $cand
                        $found = $true
                        Write-Log "Auto-detected TomcatHome: $TomcatHome"
                        break
                    }
                }
                if (-not $found) {
                    Write-Log "ERROR: Could not auto-detect Tomcat installation. Please specify -TomcatHome." "ERROR"
                    return
                }
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

            function Patch-ServerXml {
                param(
                    [string]$TomcatHome,
                    [string]$Version
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
                    return $null
                }
            }

            $version = Get-TomcatVersion -TomcatHome $TomcatHome
            if (-not $version) { return }
            $patched = Patch-ServerXml -TomcatHome $TomcatHome -Version $version
            if ($patched) {
                Write-Log "Successfully updated Tomcat user password security configuration on $env:COMPUTERNAME"
            } else {
                Write-Log "No changes made to Tomcat configuration on $env:COMPUTERNAME" "WARNING"
            }
            # --- End core logic ---
        } -ArgumentList $TomcatHome
        Write-Log "[$server] Update result:"
        $result | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Log "[$server] ERROR: $_" "ERROR"
    }
} 