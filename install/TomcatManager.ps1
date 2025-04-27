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
    Write-Log "Extracting OpenJDK
