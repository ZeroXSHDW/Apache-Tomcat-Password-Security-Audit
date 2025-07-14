param(
    [Parameter(Mandatory=$true)][string]$InputFile,
    [Parameter(Mandatory=$true)][string]$OutputCsv
)

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

    $lines = $block -split "`n"
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match "^Execution Time: (.+)$") { $obj.Timestamp = $matches[1] }
        if ($trimmed -match "^Hostname: (.+)$") { $obj.Server = $matches[1] }
        if ($trimmed -match "^Tomcat Version: (.+)$") { $obj.TomcatVersion = $matches[1] }
        if ($trimmed -match "^  Credential Handler: (.+)$") { $obj.CredentialHandler = $matches[1] }
        if ($trimmed -match "^  Algorithm: (.+)$") { $obj.Algorithm = $matches[1] }
        if ($trimmed -match "^  Iterations: (.+)$") { $obj.Iterations = $matches[1] }
        if ($trimmed -match "^  Salt Length: (.+)$") { $obj.SaltLength = $matches[1] }
        if ($trimmed -match "^Overall Status: (.+)$") { $obj.OverallStatus = $matches[1] }
        if ($trimmed -match "^  Status: (.+)$") { $obj.Compliance = $matches[1] }
        # User line:  admin | Plaintext | Non-compliant
        if ($trimmed -match "^\s*([\w-]+) \| ([\w-]+) \| ([\w\s\(\)-]+)$") {
            $obj.Users += @{
                Username = $matches[1]
                PasswordType = $matches[2]
                UserCompliance = $matches[3]
            }
        }
    }
    # Only return if it looks like a real audit block
    if ($obj.Server -and $obj.TomcatVersion) { return $obj }
    return $null
}

# Read the file and split into blocks
$content = Get-Content $InputFile -Raw
$blocks = $content -split "\*{10,}"  # Split on 10 or more asterisks

$parsed = @()
foreach ($block in $blocks) {
    $obj = Parse-Block $block
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