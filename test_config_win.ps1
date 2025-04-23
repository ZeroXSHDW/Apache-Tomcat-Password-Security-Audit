# test_config_win.ps1
# Tests CheckTomcatConfigWin.ps1 for various Tomcat configurations

# Log setup
$logFile = "$env:LOCALAPPDATA\Temp\TestTomcatConfig.log"
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
    Write-Output "[$timestamp] $Message"
}

Write-Log "Starting tests for CheckTomcatConfigWin.ps1..."

# Verify script exists
$scriptPath = ".\CheckTomcatConfigWin.ps1"
if (-not (Test-Path $scriptPath)) {
    Write-Log "Error: CheckTomcatConfigWin.ps1 not found"
    exit 1
}
Write-Log "Verified file exists: $scriptPath"

# Clear existing log
if (Test-Path $logFile) {
    Clear-Content $logFile
    Write-Log "Cleared existing log file: $logFile"
}

# Test configuration
$testTomcatPath = "C:\Program Files (x86)\Apache Software Foundation\Tomcat 10.1"
$testConfPath = Join-Path $testTomcatPath "conf"
$backupPath = "$env:LOCALAPPDATA\Temp\TomcatConfigBackup"
$serverXmlPath = Join-Path $testConfPath "server.xml"
$usersXmlPath = Join-Path $testConfPath "tomcat-users.xml"

# Backup original files
if (-not (Test-Path $backupPath)) {
    New-Item -Path $backupPath -ItemType Directory | Out-Null
}
if (Test-Path $serverXmlPath) {
    Copy-Item -Path $serverXmlPath -Destination $backupPath -Force
}
if (Test-Path $usersXmlPath) {
    Copy-Item -Path $usersXmlPath -Destination $backupPath -Force
}
Write-Log "Backed up original files to $backupPath"

# Create test directory if it doesn't exist
if (-not (Test-Path $testConfPath)) {
    New-Item -Path $testConfPath -ItemType Directory -Force | Out-Null
}

# Test cases
$testCases = @(
    # Tomcat 10.0 Tests
    @{
        Name = "10.0_NoCredentialHandler_Plaintext"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase"/>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="password123" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NoCredentialHandler_Hashed_MD5"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase"/>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="5f4dcc3b5aa765d61d8327deb882cf99" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NoCredentialHandler_Hashed_SHA1"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase"/>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="7c4a8d09ca3762af61e59520943dc26494f8941b" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NoCredentialHandler_Hashed_SHA256"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase"/>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NoCredentialHandler_Hashed_SHA512"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase"/>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="c775e7b757ede630cd0aa1113bd102661ab38829ca52a6422ab782862f268646e6b4b3b4f1f2f3f4f5f6f7f8f9f0a1b2c3d4e5f60718293a4b6f7e8c9d0a1b2c" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NoCredentialHandler_Salted_MD5"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase"/>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="5f4dcc3b5aa765d61d8327deb882cf99:1234567890abcdef" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_MD5_Plaintext"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="MD5"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="password123" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_MD5_Hashed_MD5"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="MD5"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="5f4dcc3b5aa765d61d8327deb882cf99" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_MD5_Hashed_SHA1"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="MD5"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="7c4a8d09ca3762af61e59520943dc26494f8941b" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_MD5_Hashed_SHA256"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="MD5"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_MD5_Hashed_SHA512"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="MD5"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="c775e7b757ede630cd0aa1113bd102661ab38829ca52a6422ab782862f268646e6b4b3b4f1f2f3f4f5f6f7f8f9f0a1b2c3d4e5f60718293a4b6f7e8c9d0a1b2c" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_MD5_Salted_MD5"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="MD5"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="5f4dcc3b5aa765d61d8327deb882cf99:1234567890abcdef" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA256_Plaintext"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-256" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="password123" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA256_Hashed_MD5"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-256" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="5f4dcc3b5aa765d61d8327deb882cf99" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA256_Hashed_SHA1"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-256" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="7c4a8d09ca3762af61e59520943dc26494f8941b" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA256_Hashed_SHA256"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-256" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $true
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA256_Hashed_SHA512"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-256" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="c775e7b757ede630cd0aa1113bd102661ab38829ca52a6422ab782862f268646e6b4b3b4f1f2f3f4f5f6f7f8f9f0a1b2c3d4e5f60718293a4b6f7e8c9d0a1b2c" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA256_Salted_MD5"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-256" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="5f4dcc3b5aa765d61d8327deb882cf99:1234567890abcdef" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA512_Plaintext"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-512" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="password123" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA512_Hashed_MD5"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-512" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="5f4dcc3b5aa765d61d8327deb882cf99" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA512_Hashed_SHA1"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-512" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="7c4a8d09ca3762af61e59520943dc26494f8941b" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA512_Hashed_SHA256"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-512" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA512_Hashed_SHA512"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-512" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="c775e7b757ede630cd0aa1113bd102661ab38829ca52a6422ab782862f268646e6b4b3b4f1f2f3f4f5f6f7f8f9f0a1b2c3d4e5f60718293a4b6f7e8c9d0a1b2c" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $true
    },
    @{
        Name = "10.0_MessageDigestCredentialHandler_SHA512_Salted_MD5"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-512" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="5f4dcc3b5aa765d61d8327deb882cf99:1234567890abcdef" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NestedCredentialHandler_Plaintext"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.NestedCredentialHandler"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="password123" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NestedCredentialHandler_Hashed_MD5"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.NestedCredentialHandler"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="5f4dcc3b5aa765d61d8327deb882cf99" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NestedCredentialHandler_Hashed_SHA1"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.NestedCredentialHandler"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="7c4a8d09ca3762af61e59520943dc26494f8941b" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NestedCredentialHandler_Hashed_SHA256"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.NestedCredentialHandler"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NestedCredentialHandler_Hashed_SHA512"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.NestedCredentialHandler"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="c775e7b757ede630cd0aa1113bd102661ab38829ca52a6422ab782862f268646e6b4b3b4f1f2f3f4f5f6f7f8f9f0a1b2c3d4e5f60718293a4b6f7e8c9d0a1b2c" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_NestedCredentialHandler_Salted_MD5"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.NestedCredentialHandler"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="5f4dcc3b5aa765d61d8327deb882cf99:1234567890abcdef" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_SecretKeyCredentialHandler_PBKDF2_Plaintext"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.SecretKeyCredentialHandler" algorithm="PBKDF2WithHmacSHA512" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="password123" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_SecretKeyCredentialHandler_PBKDF2_Hashed_MD5"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.SecretKeyCredentialHandler" algorithm="PBKDF2WithHmacSHA512" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="5f4dcc3b5aa765d61d8327deb882cf99" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_SecretKeyCredentialHandler_PBKDF2_Hashed_SHA1"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.SecretKeyCredentialHandler" algorithm="PBKDF2WithHmacSHA512" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="7c4a8d09ca3762af61e59520943dc26494f8941b" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_SecretKeyCredentialHandler_PBKDF2_Hashed_SHA256"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.SecretKeyCredentialHandler" algorithm="PBKDF2WithHmacSHA512" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_SecretKeyCredentialHandler_PBKDF2_Hashed_SHA512"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.SecretKeyCredentialHandler" algorithm="PBKDF2WithHmacSHA512" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="c775e7b757ede630cd0aa1113bd102661ab38829ca52a6422ab782862f268646e6b4b3b4f1f2f3f4f5f6f7f8f9f0a1b2c3d4e5f60718293a4b6f7e8c9d0a1b2c" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_SecretKeyCredentialHandler_PBKDF2_Salted_MD5"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.SecretKeyCredentialHandler" algorithm="PBKDF2WithHmacSHA512" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="5f4dcc3b5aa765d61d8327deb882cf99:1234567890abcdef" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $false
    },
    @{
        Name = "10.0_SecretKeyCredentialHandler_PBKDF2_Salted_PBKDF2"
        Version = "10.0"
        ServerXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Server>
  <Service>
    <Engine>
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase">
        <CredentialHandler className="org.apache.catalina.realm.SecretKeyCredentialHandler" algorithm="PBKDF2WithHmacSHA512" iterations="10000" saltLength="16"/>
      </Realm>
    </Engine>
  </Service>
</Server>
"@
        UsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <user username="testuser" password="4b6f7e8c9d0a1b2c3d4e5f60718293a4b6f7e8c9d0a1b2c3d4e5f60718293a4:1234567890abcdef" roles="manager"/>
</tomcat-users>
"@
        ExpectedSecure = $true
    }
)

# Run tests
$totalTests = $testCases.Count
$passedTests = 0
$failedTests = 0

foreach ($test in $testCases) {
    Write-Log "Running test: $($test.Name) for Tomcat $($test.Version)"

    # Write test configuration
    try {
        Set-Content -Path $serverXmlPath -Value $test.ServerXml -Encoding UTF8 -ErrorAction Stop
        Set-Content -Path $usersXmlPath -Value $test.UsersXml -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Log "Error writing test configuration files: $($_.Exception.Message)"
        $failedTests++
        continue
    }

    # Validate configuration files
    if (-not (Test-Path $serverXmlPath) -or -not (Test-Path $usersXmlPath)) {
        Write-Log "Error: Test configuration files not created"
        $failedTests++
        continue
    }

    # Run script
    $output = & $scriptPath 2>&1 | Out-String
    Write-Log "Test output: $output"

    # Check result
    $isSecure = $output -match "Overall Configuration: Secure"
    if ($isSecure -eq $test.ExpectedSecure) {
        Write-Log "Result: PASSED"
        $passedTests++
    } else {
        Write-Log "Result: FAILED (Expected secure: $($test.ExpectedSecure), Actual output: $output)"
        $failedTests++
    }
}

# Restore original files
if (Test-Path (Join-Path $backupPath "server.xml")) {
    Copy-Item -Path (Join-Path $backupPath "server.xml") -Destination $serverXmlPath -Force
}
if (Test-Path (Join-Path $backupPath "tomcat-users.xml")) {
    Copy-Item -Path (Join-Path $backupPath "tomcat-users.xml") -Destination $usersXmlPath -Force
}
Write-Log "Restored original configuration files"

# Summary
Write-Log "Test Summary:"
Write-Log "  Total tests run: $totalTests"
Write-Log "  Tests passed: $passedTests"
Write-Log "  Tests failed: $failedTests"

if ($failedTests -gt 0) {
    Write-Log "Some tests failed. Check $logFile for details"
    exit 1
} else {
    Write-Log "All tests passed successfully"
    exit 0
}
