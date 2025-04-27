# TomcatManager.ps1
# Manages installation and uninstallation of Apache Tomcat 7.0, 8.5, 9.0, 10.0, and 10.1 on Windows
# Run as Administrator: .\TomcatManager.ps1 [install 7|8.5|9|10.0|10.1] [uninstall]

# Global Variables
$TOMCAT_DIR = "C:\tomcat"
$LOG_FILE = "$env:TEMP\TomcatManager.log"

# Log function
function Write-Log {
    param (
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Output $logMessage | Out-File -FilePath $LOG_FILE -Append
    Write-Output $logMessage
}

# Check for Administrator privileges
function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "This script must be run as Administrator."
        exit 1
    }
}

# Install OpenJDK 8 manually from Adoptium
function Install-OpenJDK8Manual {
    Write-Log "Attempting manual installation of OpenJDK 8 from Adoptium..."
    $JDK_URL = "https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u412-b08/OpenJDK8U-jdk_x64_windows_hotspot_8u412b08.zip"
    $JDK_ZIP = "$env:TEMP\OpenJDK8U-jdk_x64_windows_hotspot_8u412b08.zip"
    $JAVA_HOME = "C:\Program Files\Java\jdk8u412-b08"
    $TEMP_EXTRACT_PATH = "$env:TEMP\jdk8u412-b08"

    # Download JDK
    Write-Log "Downloading OpenJDK 8 from $JDK_URL..."
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($JDK_URL, $JDK_ZIP)
    } catch {
        Write-Log "ERROR: Failed to download OpenJDK 8 from $JDK_URL. Exception: $($_.Exception.Message)"
        Write-Log "Check your network connection or verify the URL."
        exit 1
    }

    # Verify downloaded file exists
    if (-not (Test-Path $JDK_ZIP)) {
        Write-Log "ERROR: Downloaded JDK ZIP file not found at $JDK_ZIP."
        exit 1
    }

    # Extract JDK to temporary location
    Write-Log "Extracting OpenJDK 8 to temporary path $TEMP_EXTRACT_PATH..."
    try {
        New-Item -ItemType Directory -Path $TEMP_EXTRACT_PATH -Force | Out-Null
        Expand-Archive -Path $JDK_ZIP -DestinationPath $TEMP_EXTRACT_PATH -Force
    } catch {
        Write-Log "ERROR: Failed to extract JDK ZIP file. Exception: $($_.Exception.Message)"
        Write-Log "Ensure you have write permissions to $TEMP_EXTRACT_PATH and sufficient disk space."
        exit 1
    }
    Remove-Item $JDK_ZIP -Force

    # Move contents from nested jdk8u412-b08 to JAVA_HOME
    Write-Log "Moving extracted files to $JAVA_HOME..."
    try {
        New-Item -ItemType Directory -Path $JAVA_HOME -Force | Out-Null
        $nestedPath = Join-Path -Path $TEMP_EXTRACT_PATH -ChildPath "jdk8u412-b08"
        if (Test-Path $nestedPath) {
            Get-ChildItem -Path $nestedPath | Move-Item -Destination $JAVA_HOME -Force
            Write-Log "Moved contents from $nestedPath to $JAVA_HOME"
        } else {
            Write-Log "ERROR: Expected nested directory $nestedPath not found."
            exit 1
        }
        Remove-Item -Path $TEMP_EXTRACT_PATH -Recurse -Force
    } catch {
        Write-Log "ERROR: Failed to move files to $JAVA_HOME. Exception: $($_.Exception.Message)"
        exit 1
    }

    # Verify java.exe exists
    $javaExe = "$JAVA_HOME\bin\java.exe"
    if (-not (Test-Path $javaExe)) {
        Write-Log "ERROR: java.exe not found at $javaExe after moving files."
        exit 1
    }

    # Set JAVA_HOME environment variable
    Write-Log "Setting JAVA_HOME environment variable..."
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $JAVA_HOME, [EnvironmentVariableTarget]::Machine)
    $env:JAVA_HOME = $JAVA_HOME

    # Update PATH
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
    if ($currentPath -notlike "*$JAVA_HOME\bin*") {
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$JAVA_HOME\bin", [EnvironmentVariableTarget]::Machine)
        $env:PATH = "$env:PATH;$JAVA_HOME\bin"
    }

    # Verify installation
    Write-Log "Verifying Java installation..."
    try {
        $javaVersion = & $javaExe -version 2>&1 | ForEach-Object { $_ -replace '^.*?(openjdk version.*)$', '$1' } | Out-String
        Write-Log "java -version output: $javaVersion"
        if ($javaVersion -notmatch "1\.8\." -and $javaVersion -notmatch "8u") {
            Write-Log "ERROR: Installed Java version is not 8. Output: $javaVersion"
            exit 1
        }
    } catch {
        Write-Log "ERROR: Failed to run java -version. Exception: $($_.Exception.Message)"
        exit 1
    }
    Write-Log "OpenJDK 8 successfully installed at $JAVA_HOME"
}

# Install OpenJDK 11 manually from Adoptium
function Install-OpenJDK11Manual {
    Write-Log "Attempting manual installation of OpenJDK 11 from Adoptium..."
    $JDK_URL = "https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.22%2B7/OpenJDK11U-jdk_x64_windows_hotspot_11.0.22_7.zip"
    $JDK_ZIP = "$env:TEMP\OpenJDK11U-jdk_x64_windows_hotspot_11.0.22_7.zip"
    $JAVA_HOME = "C:\Program Files\Java\jdk-11"
    $TEMP_EXTRACT_PATH = "$env:TEMP\jdk-11.0.22"

    # Download JDK
    Write-Log "Downloading OpenJDK 11 from $JDK_URL..."
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($JDK_URL, $JDK_ZIP)
    } catch {
        Write-Log "ERROR: Failed to download OpenJDK 11 from $JDK_URL. Exception: $($_.Exception.Message)"
        Write-Log "Check your network connection or verify the URL."
        exit 1
    }

    # Verify downloaded file exists
    if (-not (Test-Path $JDK_ZIP)) {
        Write-Log "ERROR: Downloaded JDK ZIP file not found at $JDK_ZIP."
        exit 1
    }

    # Extract JDK to temporary location
    Write-Log "Extracting OpenJDK 11 to temporary path $TEMP_EXTRACT_PATH..."
    try {
        New-Item -ItemType Directory -Path $TEMP_EXTRACT_PATH -Force | Out-Null
        Expand-Archive -Path $JDK_ZIP -DestinationPath $TEMP_EXTRACT_PATH -Force
    } catch {
        Write-Log "ERROR: Failed to extract JDK ZIP file. Exception: $($_.Exception.Message)"
        Write-Log "Ensure you have write permissions to $TEMP_EXTRACT_PATH and sufficient disk space."
        exit 1
    }
    Remove-Item $JDK_ZIP -Force

    # Move contents from nested jdk-11.0.22+7 to JAVA_HOME
    Write-Log "Moving extracted files to $JAVA_HOME..."
    try {
        New-Item -ItemType Directory -Path $JAVA_HOME -Force | Out-Null
        $nestedPath = Join-Path -Path $TEMP_EXTRACT_PATH -ChildPath "jdk-11.0.22+7"
        if (Test-Path $nestedPath) {
            Get-ChildItem -Path $nestedPath | Move-Item -Destination $JAVA_HOME -Force
            Write-Log "Moved contents from $nestedPath to $JAVA_HOME"
        } else {
            Write-Log "ERROR: Expected nested directory $nestedPath not found."
            exit 1
        }
        Remove-Item -Path $TEMP_EXTRACT_PATH -Recurse -Force
    } catch {
        Write-Log "ERROR: Failed to move files to $JAVA_HOME. Exception: $($_.Exception.Message)"
        exit 1
    }

    # Verify java.exe exists
    $javaExe = "$JAVA_HOME\bin\java.exe"
    if (-not (Test-Path $javaExe)) {
        Write-Log "ERROR: java.exe not found at $javaExe after moving files."
        exit 1
    }

    # Set JAVA_HOME environment variable
    Write-Log "Setting JAVA_HOME environment variable..."
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $JAVA_HOME, [EnvironmentVariableTarget]::Machine)
    $env:JAVA_HOME = $JAVA_HOME

    # Update PATH
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
    if ($currentPath -notlike "*$JAVA_HOME\bin*") {
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$JAVA_HOME\bin", [EnvironmentVariableTarget]::Machine)
        $env:PATH = "$env:PATH;$JAVA_HOME\bin"
    }

    # Verify installation
    Write-Log "Verifying Java installation..."
    try {
        $javaVersion = & $javaExe -version 2>&1 | ForEach-Object { $_ -replace '^.*?(openjdk version.*)$', '$1' } | Out-String
        Write-Log "java -version output: $javaVersion"
        if ($javaVersion -notmatch "11\.") {
            Write-Log "ERROR: Installed Java version is not 11. Output: $javaVersion"
            exit 1
        }
    } catch {
        Write-Log "ERROR: Failed to run java -version. Exception: $($_.Exception.Message)"
        exit 1
    }
    Write-Log "OpenJDK 11 successfully installed at $JAVA_HOME"
}

# Uninstall Tomcat
function Uninstall-Tomcat {
    Write-Log "Starting Tomcat uninstallation process..."

    Write-Log "Stopping Tomcat service..."
    $service = Get-Service -Name "Tomcat" -ErrorAction SilentlyContinue
    if ($service) {
        Stop-Service -Name "Tomcat" -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Removing Tomcat service..."
    if ($service) {
        sc.exe delete Tomcat | Out-Null
    }

    Write-Log "Removing Tomcat directory..."
    if (Test-Path $TOMCAT_DIR) {
        Remove-Item -Path $TOMCAT_DIR -Recurse -Force
    }

    Write-Log "Removing tomcat user..."
    $tomcatUser = Get-LocalUser -Name "tomcat" -ErrorAction SilentlyContinue
    if ($tomcatUser) {
        Remove-LocalUser -Name "tomcat" -ErrorAction SilentlyContinue
    }

    Write-Log "Tomcat uninstallation completed successfully"
}

# Install Tomcat
function Install-Tomcat {
    param (
        [string]$TomcatMajor
    )

    $TOMCAT_VERSION = ""
    $TOMCAT_URLS = @()
    $JAVA_HOME = ""
    $JAVA_VERSION = ""
    $JAVA_OPTS = ""
    $JAVA_BIN = ""
    $CHECKSUM_URL = ""
    $CHECKSUM = ""
    $LOCAL_FILE = ""

    switch ($TomcatMajor) {
        "7" {
            $TOMCAT_VERSION = "7.0.100"
            $LOCAL_FILE = "$env:TEMP\apache-tomcat-$TOMCAT_VERSION-windows-x64.zip"
            $TOMCAT_URLS = @(
                "https://archive.apache.org/dist/tomcat/tomcat-7/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION-windows-x64.zip",
                "https://dlcdn.apache.org/tomcat/tomcat-7/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION-windows-x64.zip",
                "https://downloads.apache.org/tomcat/tomcat-7/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION-windows-x64.zip"
            )
            $JAVA_VERSION = "8"
            $JAVA_HOME = "C:\Program Files\Java\jdk8u412-b08"
            $JAVA_OPTS = "-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom"
            $JAVA_BIN = "$JAVA_HOME\bin\java.exe"
            $CHECKSUM_URL = "https://archive.apache.org/dist/tomcat/tomcat-7/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION-windows-x64.zip.sha512"
            $CHECKSUM = "75265bdf9bd5366fe33cbd1f5c7d01319c4803d2432f786f610237e0ae5cd00abda50a996a3d4df5adcb5ec814df0c7ebc80529e4505ce4ff749d50b36686efa"
        }
        "8.5" {
            $TOMCAT_VERSION = "8.5.100"
            $LOCAL_FILE = "$env:TEMP\apache-tomcat-$TOMCAT_VERSION-windows-x64.zip"
            $TOMCAT_URLS = @(
                "https://dlcdn.apache.org/tomcat/tomcat-8/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION-windows-x64.zip",
                "https://archive.apache.org/dist/tomcat/tomcat-8/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION-windows-x64.zip",
                "https://downloads.apache.org/tomcat/tomcat-8/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION-windows-x64.zip"
            )
            $JAVA_VERSION = "11"
            $JAVA_HOME = "C:\Program Files\Java\jdk-11"
            $JAVA_OPTS = "-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED"
            $JAVA_BIN = "$JAVA_HOME\bin\java.exe"
            $CHECKSUM_URL = "https://archive.apache.org/dist/tomcat/tomcat-8/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION-windows-x64.zip.sha512"
            $CHECKSUM = "6493b64743374040cccc98ee8225c0f145587541d8f79de76803208e879e01a156da66e3e32bc5564f340a638c48d6e24b723cae28b2e83ee18db82c54527e1b"
        }
        "9" {
            $TOMCAT_VERSION = "9.0.104"
            $LOCAL_FILE = "$env:TEMP\apache-tomcat-$TOMCAT_VERSION.zip"
            $TOMCAT_URLS = @(
                "https://dlcdn.apache.org/tomcat/tomcat-9/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.zip",
                "https://archive.apache.org/dist/tomcat/tomcat-9/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.zip",
                "https://downloads.apache.org/tomcat/tomcat-9/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.zip"
            )
            $JAVA_VERSION = "11"
            $JAVA_HOME = "C:\Program Files\Java\jdk-11"
            $JAVA_OPTS = "-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom"
            $JAVA_BIN = "$JAVA_HOME\bin\java.exe"
            $CHECKSUM_URL = "https://archive.apache.org/dist/tomcat/tomcat-9/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.zip.sha512"
            $CHECKSUM = "822db923d14a8600a62f9c87504f2e33dc8f3263cab46320288fd40312aad45aa0933fb50dcab68a1f5fd397180cb9a0e262a255647db247fc8426a78b012a50"
        }
        "10.0" {
            $TOMCAT_VERSION = "10.0.27"
            $LOCAL_FILE = "$env:TEMP\apache-tomcat-$TOMCAT_VERSION.zip"
            $TOMCAT_URLS = @(
                "https://dlcdn.apache.org/tomcat/tomcat-10/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.zip",
                "https://archive.apache.org/dist/tomcat/tomcat-10/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.zip",
                "https://downloads.apache.org/tomcat/tomcat-10/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.zip"
            )
            $JAVA_VERSION = "11"
            $JAVA_HOME = "C:\Program Files\Java\jdk-11"
            $JAVA_OPTS = "-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom"
            $JAVA_BIN = "$JAVA_HOME\bin\java.exe"
            $CHECKSUM_URL = "https://archive.apache.org/dist/tomcat/tomcat-10/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.zip.sha512"
            $CHECKSUM = "dd42eaef1a95a9a45033aea113196b9a033e805c0a4ca326d700616637186f4f7238aa048d0df60cfcdea682cc3f8471105ee94d984939d07c62289583fd6281"
        }
        "10.1" {
            $TOMCAT_VERSION = "10.1.31"
            $LOCAL_FILE = "$env:TEMP\apache-tomcat-$TOMCAT_VERSION.zip"
            $TOMCAT_URLS = @(
                "https://dlcdn.apache.org/tomcat/tomcat-10/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.zip",
                "https://archive.apache.org/dist/tomcat/tomcat-10/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.zip",
                "https://downloads.apache.org/tomcat/tomcat-10/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.zip"
            )
            $JAVA_VERSION = "11"
            $JAVA_HOME = "C:\Program Files\Java\jdk-11"
            $JAVA_OPTS = "-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom"
            $JAVA_BIN = "$JAVA_HOME\bin\java.exe"
            $CHECKSUM_URL = "https://archive.apache.org/dist/tomcat/tomcat-10/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.zip.sha512"
            $CHECKSUM = "1f17166d97a4e41b066a75ee77bca12b2a834a8121fb1a354485d79f43668fd49200e991b13bf573ac4481fd061310b760f06788fbee28f459ab4f15c8dd355c"
        }
        default {
            Write-Log "ERROR: Unsupported Tomcat version. Choose 7, 8.5, 9, 10.0, or 10.1."
            exit 1
        }
    }

    Write-Log "Starting installation of Tomcat $TomcatMajor ($TOMCAT_VERSION)"

    # Check internet connectivity
    Write-Log "Checking internet connectivity..."
    try {
        Test-Connection -ComputerName google.com -Count 1 -Quiet | Out-Null
    } catch {
        Write-Log "ERROR: No internet connection. Please connect to the internet and try again."
        exit 1
    }

    # Install required Java version
    Write-Log "Checking OpenJDK $JAVA_VERSION..."
    if ($JAVA_VERSION -eq "8") {
        if (-not (Test-Path "$JAVA_HOME\bin\java.exe")) {
            Write-Log "OpenJDK 8 not found. Attempting manual installation..."
            Install-OpenJDK8Manual
        }
    } elseif ($JAVA_VERSION -eq "11") {
        if (-not (Test-Path "$JAVA_HOME\bin\java.exe")) {
            Write-Log "OpenJDK 11 not found. Attempting manual installation..."
            Install-OpenJDK11Manual
        }
    }

    # Verify Java installation
    Write-Log "Verifying Java installation..."
    if (-not (Test-Path $JAVA_BIN)) {
        Write-Log "ERROR: Java binary $JAVA_BIN not found. Ensure $JAVA_HOME is correct."
        exit 1
    }
    $JAVA_VERSION_OUTPUT = & $JAVA_BIN -version 2>&1 | ForEach-Object { $_ -replace '^.*?(openjdk version.*)$', '$1' } | Out-String
    Write-Log "java -version output: $JAVA_VERSION_OUTPUT"
    if ($JAVA_VERSION_OUTPUT -notmatch "1${JAVA_VERSION}\." -and $JAVA_VERSION_OUTPUT -notmatch "${JAVA_VERSION}\." -and $JAVA_VERSION_OUTPUT -notmatch "openjdk version.*${JAVA_VERSION}") {
        Write-Log "ERROR: Java $JAVA_VERSION not detected with $JAVA_BIN."
        exit 1
    }

    # Create tomcat user
    Write-Log "Creating tomcat user..."
    $tomcatUser = Get-LocalUser -Name "tomcat" -ErrorAction SilentlyContinue
    if (-not $tomcatUser) {
        New-LocalUser -Name "tomcat" -NoPassword -UserMayNotChangePassword -AccountNeverExpires -Description "Tomcat Service User" | Out-Null
    } else {
        Write-Log "Tomcat user already exists"
    }

    # Download Tomcat with fallback
    Write-Log "Downloading Apache Tomcat $TOMCAT_VERSION..."
    $DOWNLOADED = $false
    foreach ($TOMCAT_URL in $TOMCAT_URLS) {
        Write-Log "Attempting download from $TOMCAT_URL..."
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($TOMCAT_URL, "$env:TEMP\apache-tomcat-$TOMCAT_VERSION.zip")
            Write-Log "Successfully downloaded from $TOMCAT_URL"
            $DOWNLOADED = $true
            break
        } catch {
            Write-Log "WARNING: Failed to download from $TOMCAT_URL. Trying next URL..."
            Start-Sleep -Seconds 2
        }
    }

    # Check for local file if download failed
    if (-not $DOWNLOADED) {
        Write-Log "All download URLs failed. Checking for local file at $LOCAL_FILE..."
        if (Test-Path $LOCAL_FILE) {
            Write-Log "Found local file $LOCAL_FILE. Proceeding with installation..."
            $DOWNLOADED = $true
            Move-Item -Path $LOCAL_FILE -Destination "$env:TEMP\apache-tomcat-$TOMCAT_VERSION.zip"
        } else {
            Write-Log "ERROR: Failed to download Tomcat archive from all URLs and no local file found."
            Write-Log "URLs tried: $TOMCAT_URLS"
            Write-Log "Place apache-tomcat-$TOMCAT_VERSION.zip in $env:TEMP and retry."
            exit 1
        }
    }

    # Verify downloaded file
    if (-not (Test-Path "$env:TEMP\apache-tomcat-$TOMCAT_VERSION.zip")) {
        Write-Log "ERROR: Downloaded Tomcat archive not found."
        exit 1
    }

    # Verify checksum
    Write-Log "Verifying checksum of downloaded file..."
    $COMPUTED_CHECKSUM = (Get-FileHash -Path "$env:TEMP\apache-tomcat-$TOMCAT_VERSION.zip" -Algorithm SHA512).Hash.ToLower()
    if ($COMPUTED_CHECKSUM -ne $CHECKSUM) {
        Write-Log "ERROR: Checksum verification failed for apache-tomcat-$TOMCAT_VERSION.zip."
        Write-Log "Expected SHA512: $CHECKSUM"
        Write-Log "Computed SHA512: $COMPUTED_CHECKSUM"
        Write-Log "Download may be corrupted or tampered with."
        Remove-Item -Path "$env:TEMP\apache-tomcat-$TOMCAT_VERSION.zip" -Force
        exit 1
    }
    Write-Log "Checksum verification passed."

    # Remove existing installation
    Write-Log "Removing previous installations..."
    $service = Get-Service -Name "Tomcat" -ErrorAction SilentlyContinue
    if ($service) {
        Stop-Service -Name "Tomcat" -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $TOMCAT_DIR) {
        Remove-Item -Path $TOMCAT_DIR -Recurse -Force
    }

    # Extract Tomcat
    Write-Log "Extracting Tomcat to $TOMCAT_DIR..."
    New-Item -ItemType Directory -Path $TOMCAT_DIR -Force | Out-Null
    try {
        Expand-Archive -Path "$env:TEMP\apache-tomcat-$TOMCAT_VERSION.zip" -DestinationPath $TOMCAT_DIR -Force
    } catch {
        Write-Log "ERROR: Failed to extract Tomcat archive. Exception: $($_.Exception.Message)"
        exit 1
    }
    $extractedFolder = Get-ChildItem -Path $TOMCAT_DIR -Directory | Select-Object -First 1
    Get-ChildItem -Path "$TOMCAT_DIR\$($extractedFolder.Name)" | Move-Item -Destination $TOMCAT_DIR -Force
    Remove-Item -Path "$TOMCAT_DIR\$($extractedFolder.Name)" -Recurse -Force
    Remove-Item -Path "$env:TEMP\apache-tomcat-$TOMCAT_VERSION.zip" -Force

    # Verify startup.bat exists
    $startupBin = "$TOMCAT_DIR\bin\startup.bat"
    if (-not (Test-Path $startupBin)) {
        Write-Log "ERROR: startup.bat not found in $TOMCAT_DIR\bin. The downloaded Tomcat archive is invalid or corrupted."
        Write-Log "Downloaded from: $TOMCAT_URL"
        Write-Log "Ensure the archive is a valid Tomcat distribution containing bin\startup.bat."
        exit 1
    }

    # Set permissions
    Write-Log "Setting permissions..."
    try {
        $acl = Get-Acl $TOMCAT_DIR
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("tomcat", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.SetAccessRule($rule)
        Set-Acl -Path $TOMCAT_DIR -AclObject $acl
    } catch {
        Write-Log "ERROR: Failed to set permissions on $TOMCAT_DIR. Exception: $($_.Exception.Message)"
        exit 1
    }

    # Install Tomcat as a service
    Write-Log "Installing Tomcat as a Windows service..."
    $serviceBin = "$TOMCAT_DIR\bin\service.bat"
    if (Test-Path $serviceBin) {
        Write-Log "Using service.bat to install Tomcat service..."
        try {
            & $serviceBin install | Out-Null
        } catch {
            Write-Log "ERROR: Failed to run service.bat to install Tomcat service. Exception: $($_.Exception.Message)"
            Write-Log "Falling back to manual service creation..."
            Install-TomcatServiceManually -TomcatDir $TOMCAT_DIR -JavaHome $JAVA_HOME -JavaOpts $JAVA_OPTS -TomcatVersion $TOMCAT_VERSION
        }
    } else {
        Write-Log "service.bat not found in $TOMCAT_DIR\bin. Creating service manually..."
        Install-TomcatServiceManually -TomcatDir $TOMCAT_DIR -JavaHome $JAVA_HOME -JavaOpts $JAVA_OPTS -TomcatVersion $TOMCAT_VERSION
    }

    # Configure service
    Write-Log "Configuring Tomcat service..."
    try {
        sc.exe config Tomcat start= auto | Out-Null
    } catch {
        Write-Log "ERROR: Failed to configure Tomcat service. Exception: $($_.Exception.Message)"
        exit 1
    }

    # Wait for service registration to complete
    Write-Log "Waiting 5 seconds for service registration..."
    Start-Sleep -Seconds 5

    # Start service
    Write-Log "Starting Tomcat service..."
    try {
        Start-Service -Name "Tomcat" -ErrorAction Stop
        if ((Get-Service -Name "Tomcat").Status -ne "Running") {
            Write-Log "ERROR: Failed to start Tomcat service. Check logs in $TOMCAT_DIR\logs\catalina.out."
            exit 1
        }
    } catch {
        Write-Log "ERROR: Failed to start Tomcat service. Exception: $($_.Exception.Message)"
        Write-Log "Check logs in $TOMCAT_DIR\logs\catalina.out for details."
        exit 1
    }

    # Verify installation
    Write-Log "Verifying installation..."
    Start-Sleep -Seconds 10
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080" -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            Write-Log "SUCCESS: Tomcat $TOMCAT_VERSION is running at http://localhost:8080"
        }
    } catch {
        Write-Log "WARNING: Tomcat service started but web interface not accessible. Check $TOMCAT_DIR\logs\catalina.out."
    }

    Write-Log "Installation complete. Configure tomcat-users.xml in $TOMCAT_DIR\conf for auditing."
}

# Function to manually create Tomcat service
function Install-TomcatServiceManually {
    param (
        [string]$TomcatDir,
        [string]$JavaHome,
        [string]$JavaOpts,
        [string]$TomcatVersion
    )
    Write-Log "Creating Tomcat service manually using sc.exe..."
    $catalinaBin = "$TomcatDir\bin\catalina.bat"
    if (-not (Test-Path $catalinaBin)) {
        Write-Log "ERROR: catalina.bat not found in $TomcatDir\bin. Cannot create service."
        exit 1
    }

    $serviceName = "Tomcat"
    $serviceDisplayName = "Apache Tomcat $TomcatVersion"
    $serviceDescription = "Apache Tomcat Web Application Container"
    $command = "`"$JavaHome\bin\java.exe`" -Djava.util.logging.config.file=`"$TomcatDir\conf\logging.properties`" -Djava.util.logging.manager=org.apache.juli.ClassLoaderLogManager $JavaOpts -Djava.endorsed.dirs=`"$TomcatDir\endorsed`" -classpath `"$TomcatDir\bin\bootstrap.jar;$TomcatDir\bin\tomcat-juli.jar`" -Dcatalina.base=`"$TomcatDir`" -Dcatalina.home=`"$TomcatDir`" -Djava.io.tmpdir=`"$TomcatDir\temp`" org.apache.catalina.startup.Bootstrap start"

    try {
        sc.exe create $serviceName binPath= "$command" DisplayName= "$serviceDisplayName" start= auto | Out-Null
        sc.exe description $serviceName "$serviceDescription" | Out-Null
        Write-Log "Tomcat service created manually."
    } catch {
        Write-Log "ERROR: Failed to create Tomcat service manually. Exception: $($_.Exception.Message)"
        exit 1
    }
}

# Main script execution
Test-Admin

switch ($args[0]) {
    "install" {
        if (-not $args[1]) {
            Write-Log "ERROR: Please specify a Tomcat version (7, 8.5, 9, 10.0, or 10.1)"
            exit 1
        }
        Install-Tomcat -TomcatMajor $args[1]
    }
    "uninstall" {
        Uninstall-Tomcat
    }
    default {
        Write-Output "Usage: .\TomcatManager.ps1 [install 7|8.5|9|10.0|10.1] [uninstall]"
        exit 1
    }
}

exit 0
