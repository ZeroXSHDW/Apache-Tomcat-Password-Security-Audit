param(
    [Parameter(Mandatory=$true)][string]$InputFile,
    [Parameter(Mandatory=$true)][string]$OutputCsv
)

function Remove-HostPrefix {
    param($line)
    if ($line -match '^\[([\w-]+)\] (.*)$') {
        return $matches[2]
    }
    return $line
}

function IsTomcatAuditBlock {
    param($block)
    # Must contain Execution Time and Tomcat Version and Hostname/HOSTNAME
    return (
        $block -match "Execution Time:" -and
        ($block -match "HOSTNAME:" -or $block -match "Hostname:") -and
        $block -match "Tomcat Version:"
    )
}

function Parse-Block {
    param($block)
    $obj = @{}
    $obj.Users = @()
    $obj.Timestamp = ""
    $obj.Server = ""
    $obj.TomcatVersion = ""
    $obj.CredentialHandler = ""
    $obj.Algorithm = ""
    $obj.Iterations = ""
    $obj.SaltLength = ""
    $obj.OverallStatus = ""
    $obj.Compliance = ""
    $obj.ComplianceDetails = @()
    $obj.TomcatHome = ""
    $obj.ConfigPath = ""
    $obj.AuditCompleted = $false
    $obj.OptionalWarnings = @()

    $lines = $block -split "`n"
    foreach ($line in $lines) {
        $trimmed = Remove-HostPrefix $line.Trim()
        if ($trimmed -match "^Execution Time: (.+)$") { $obj.Timestamp = $matches[1] }
        if ($trimmed -match "^HOSTNAME: (.+)$") { $obj.Server = $matches[1] }
        if ($trimmed -match "^Hostname: (.+)$") { $obj.Server = $matches[1] }
        if ($trimmed -match "^Tomcat Version: (.+)$") { $obj.TomcatVersion = $matches[1] }
        if ($trimmed -match "^Tomcat Home: (.+)$") { $obj.TomcatHome = $matches[1] }
        if ($trimmed -match "^Config Path: (.+)$") { $obj.ConfigPath = $matches[1] }
        if ($trimmed -match "^\s*Credential Handler: (.+)$") { $obj.CredentialHandler = $matches[1] }
        if ($trimmed -match "^\s*Algorithm: (.+)$") { $obj.Algorithm = $matches[1] }
        if ($trimmed -match "^\s*Iterations: (.+)$") { $obj.Iterations = $matches[1] }
        if ($trimmed -match "^\s*Salt Length: (.+)$") { $obj.SaltLength = $matches[1] }
        if ($trimmed -match "^Overall Status: (.+)$") { $obj.OverallStatus = $matches[1] }
        if ($trimmed -match "^  Status: (.+)$") { $obj.Compliance = $matches[1] }
        if ($trimmed -match "^Audit completed") { $obj.AuditCompleted = $true }
        # User line:  admin | Plaintext | Non-compliant
        if ($trimmed -match "^\s*([\w-]+) \| ([\w-]+) \| ([\w\s\(\)-]+)$") {
            $obj.Users += @{
                Username = $matches[1]
                PasswordType = $matches[2]
                UserCompliance = $matches[3]
            }
        }
        # Collect compliance and warning details
        if ($trimmed -match "COMPLIANCE:|WARNING:|is owned by|permissions|root check|Root Execution Compliance Check|Detection method:|Tomcat process is not running as root|Tomcat service is configured to run as root|Tomcat service is configured to run as user|has insecure permissions|permissions are secure|WARNING: Tomcat process") {
            $obj.ComplianceDetails += $trimmed
        }
        # Collect optional warnings
        if ($trimmed -match "^Warning: (.+)$") {
            $obj.OptionalWarnings += $matches[1]
        }
    }
    # Only return if it looks like a real audit block
    if ($obj.Server -and $obj.TomcatVersion) { return $obj }
    return $null
}

# Read the file and split into blocks
$content = Get-Content $InputFile -Raw
# Support both local and remote: split on 40+ # or = lines, or 10+ * lines
$blocks = $content -split "(#+|=+|\*{10,})[\r\n]+"

# Re-join lines into blocks by looking for Execution Time or [HOST] Execution Time
$realBlocks = @()
$current = ""
foreach ($line in $blocks) {
    if ($line -match "Execution Time: ") {
        if ($current -ne "") { $realBlocks += $current }
        $current = $line
    } else {
        $current += "`n$line"
    }
}
if ($current -ne "") { $realBlocks += $current }

$parsed = @()
foreach ($block in $realBlocks) {
    if (IsTomcatAuditBlock $block) {
        $obj = Parse-Block $block
        if ($obj) { $parsed += $obj }
    }
}

# Find the max number of users in any block
$maxUsers = ($parsed | ForEach-Object { $_.Users.Count } | Measure-Object -Maximum).Maximum

# Prepare data for CSV: one row per host, users in adjacent columns
$csvRows = @()
foreach ($entry in $parsed) {
    $row = [ordered]@{
        Server = $entry.Server
        Timestamp = $entry.Timestamp
        TomcatHome = $entry.TomcatHome
        ConfigPath = $entry.ConfigPath
        TomcatVersion = $entry.TomcatVersion
        CredentialHandler = $entry.CredentialHandler
        Algorithm = $entry.Algorithm
        Iterations = $entry.Iterations
        SaltLength = $entry.SaltLength
        OverallStatus = $entry.OverallStatus
        Compliance = $entry.Compliance
        ComplianceDetails = ($entry.ComplianceDetails -join "; ")
        OptionalWarnings = ($entry.OptionalWarnings -join "; ")
        AuditCompleted = $entry.AuditCompleted
    }
    for ($i = 0; $i -lt $maxUsers; $i++) {
        if ($i -lt $entry.Users.Count) {
            $row["Username$($i+1)"] = $entry.Users[$i].Username
            $row["PasswordType$($i+1)"] = $entry.Users[$i].PasswordType
            $row["UserCompliance$($i+1)"] = $entry.Users[$i].UserCompliance
        } else {
            $row["Username$($i+1)"] = ""
            $row["PasswordType$($i+1)"] = ""
            $row["UserCompliance$($i+1)"] = ""
        }
    }
    $csvRows += [PSCustomObject]$row
}

$csvRows | Export-Csv -Path $OutputCsv -NoTypeInformation
Write-Host "Exported to CSV: $OutputCsv" -ForegroundColor Green 