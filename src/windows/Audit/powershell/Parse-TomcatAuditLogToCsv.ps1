param(
    [Parameter(Mandatory=$true)][string]$InputFile,
    [Parameter(Mandatory=$true)][string]$OutputCsv
)

function Parse-LogLine {
    param($line)
    $obj = @{}
    $obj.Users = @()
    $fields = $line -split ",", 3
    if ($fields.Count -lt 3) { return $null }
    $obj.Timestamp = $fields[0]
    $obj.Server = $fields[1]
    $obj.RawMessage = $fields[2]
    $obj.OverallStatus = ""
    $obj.Compliance = ""
    $obj.TomcatVersion = ""
    $obj.CredentialHandler = ""
    $obj.Algorithm = ""
    $obj.Iterations = ""
    $obj.SaltLength = ""

    # Parse message for compliance and user info
    $messages = $obj.RawMessage -split ";"
    foreach ($msg in $messages) {
        $trimmed = $msg.Trim()
        if ($trimmed -match "Tomcat Version: (.+)") { $obj.TomcatVersion = $matches[1] }
        if ($trimmed -match "Credential Handler: (.+)") { $obj.CredentialHandler = $matches[1] }
        if ($trimmed -match "Algorithm: (.+)") { $obj.Algorithm = $matches[1] }
        if ($trimmed -match "Iterations: (.+)") { $obj.Iterations = $matches[1] }
        if ($trimmed -match "Salt Length: (.+)") { $obj.SaltLength = $matches[1] }
        if ($trimmed -match "Overall Status: (.+)") { $obj.OverallStatus = $matches[1] }
        if ($trimmed -match "Status: (.+)") { $obj.Compliance = $matches[1] }
        if ($trimmed -match "([\w-]+) \| ([\w-]+) \| ([\w\s\(\)-]+)") {
            $obj.Users += @{
                Username = $matches[1]
                PasswordType = $matches[2]
                UserCompliance = $matches[3]
            }
        }
    }
    return $obj
}

# Read and parse all lines except header
$lines = Get-Content $InputFile | Where-Object { $_ -and $_ -notmatch '^Timestamp,Server,Message' }
$parsed = @()
foreach ($line in $lines) {
    $obj = Parse-LogLine $line
    if ($obj) { $parsed += $obj }
}

# Print parsed data for validation
Write-Host "Parsed Audit Data:" -ForegroundColor Cyan
foreach ($entry in $parsed) {
    Write-Host "Server: $($entry.Server), Timestamp: $($entry.Timestamp), TomcatVersion: $($entry.TomcatVersion), OverallStatus: $($entry.OverallStatus)"
    Write-Host "  CredentialHandler: $($entry.CredentialHandler), Algorithm: $($entry.Algorithm), Iterations: $($entry.Iterations), SaltLength: $($entry.SaltLength)"
    Write-Host "  Compliance: $($entry.Compliance)"
    foreach ($user in $entry.Users) {
        Write-Host "    User: $($user.Username), Type: $($user.PasswordType), Compliance: $($user.UserCompliance)"
    }
    Write-Host "----"
}

# Prepare data for CSV: flatten users
$csvRows = @()
foreach ($entry in $parsed) {
    if ($entry.Users.Count -eq 0) {
        $csvRows += [PSCustomObject]@{
            Server = $entry.Server
            Timestamp = $entry.Timestamp
            TomcatVersion = $entry.TomcatVersion
            CredentialHandler = $entry.CredentialHandler
            Algorithm = $entry.Algorithm
            Iterations = $entry.Iterations
            SaltLength = $entry.SaltLength
            OverallStatus = $entry.OverallStatus
            Compliance = $entry.Compliance
            Username = ""
            PasswordType = ""
            UserCompliance = ""
        }
    } else {
        foreach ($user in $entry.Users) {
            $csvRows += [PSCustomObject]@{
                Server = $entry.Server
                Timestamp = $entry.Timestamp
                TomcatVersion = $entry.TomcatVersion
                CredentialHandler = $entry.CredentialHandler
                Algorithm = $entry.Algorithm
                Iterations = $entry.Iterations
                SaltLength = $entry.SaltLength
                OverallStatus = $entry.OverallStatus
                Compliance = $entry.Compliance
                Username = $user.Username
                PasswordType = $user.PasswordType
                UserCompliance = $user.UserCompliance
            }
        }
    }
}

$csvRows | Export-Csv -Path $OutputCsv -NoTypeInformation
Write-Host "Exported to CSV: $OutputCsv" -ForegroundColor Green 