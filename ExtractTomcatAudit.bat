@echo off
setlocal EnableDelayedExpansion

:: Configuration
set "INPUT_FILE=audit_output.txt"
set "TEMP_FILE=temp_audit_output.txt"

:: Check if input file exists
if not exist "%INPUT_FILE%" (
    echo Error: Input file "%INPUT_FILE%" not found.
    exit /b 1
)

:: Check if PowerShell is available
powershell -Command "exit 0" >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Error: PowerShell is required for this script.
    exit /b 1
)

:: Print header to terminal
echo Hostname                    ^| Tomcat Version ^| Credential Handler                                    ^| Algorithm                ^| Iterations ^| Salt Length ^| Username   ^| Password Type  ^| Compliance
echo ---------------------------^|---------------^|------------------------------------------------------^|-------------------------^|------------^|-------------^|------------^|---------------^|-----------

:: Replace ###### with a unique delimiter for parsing
powershell -Command "(Get-Content '%INPUT_FILE%' -Raw) -replace '#{6,}', '|' | Set-Content '%TEMP_FILE%'" 2>nul
if %ERRORLEVEL% neq 0 (
    echo Error: Failed to process input file with PowerShell.
    exit /b 1
)

:: Check if temp file was created
if not exist "%TEMP_FILE%" (
    echo Error: Failed to create temporary file "%TEMP_FILE%".
    exit /b 1
)

:: Read the temp file line by line
set "current_hostname="
set "current_output="
set "collecting_output=0"

for /f "tokens=1* delims=|" %%a in (%TEMP_FILE%) do (
    set "line=%%a"
    :: Remove leading/trailing whitespace
    for /f "tokens=*" %%i in ("!line!") do set "line=%%i"

    :: Check if line is a hostname (non-empty and not audit output)
    if "!collecting_output!"=="0" (
        if not "!line!"=="" (
            set "current_hostname=!line!"
            set "collecting_output=1"
            set "current_output="
        )
    ) else (
        :: Check if line is empty or delimiter (indicating end of current output)
        if "!line!"=="" (
            :: Process the collected output for the current hostname
            if not "!current_hostname!"=="" if not "!current_output!"=="" (
                call :process_output "!current_hostname!" "!current_output!"
            )
            set "collecting_output=0"
            set "current_hostname="
            set "current_output="
        ) else (
            :: Append line to current output
            set "current_output=!current_output!!line!\n"
        )
    )
)

:: Process the last output if exists
if not "!current_hostname!"=="" if not "!current_output!"=="" (
    call :process_output "!current_hostname!" "!current_output!"
)

echo.
echo Processing complete. Temporary file preserved at "%TEMP_FILE%".
exit /b 0

:process_output
set "hostname=%~1"
set "output=%~2"

:: Create a temp file for the output
set "PROC_TEMP_FILE=%TEMP_FILE%_proc"
echo !output!>%PROC_TEMP_FILE%

:: Initialize variables
set "tomcat_version="
set "credential_handler="
set "algorithm="
set "iterations="
set "salt_length="

:: Extract information using findstr
for /f "tokens=1,* delims=:" %%i in ('findstr /C:"Tomcat Version" %PROC_TEMP_FILE%') do (
    set "tomcat_version=%%j"
    for /f "tokens=*" %%k in ("!tomcat_version!") do set "tomcat_version=%%k"
)

for /f "tokens=1,* delims=:" %%i in ('findstr /C:"Credential Handler" %PROC_TEMP_FILE%') do (
    set "credential_handler=%%j"
    for /f "tokens=*" %%k in ("!credential_handler!") do set "credential_handler=%%k"
)

for /f "tokens=1,* delims=:" %%i in ('findstr /C:"Algorithm" %PROC_TEMP_FILE%') do (
    set "algorithm=%%j"
    for /f "tokens=*" %%k in ("!algorithm!") do set "algorithm=%%k"
)

for /f "tokens=1,* delims=:" %%i in ('findstr /C:"Iterations" %PROC_TEMP_FILE%') do (
    set "iterations=%%j"
    for /f "tokens=*" %%k in ("!iterations!") do set "iterations=%%k"
)

for /f "tokens=1,* delims=:" %%i in ('findstr /C:"Salt Length" %PROC_TEMP_FILE%') do (
    set "salt_length=%%j"
    for /f "tokens=*" %%k in ("!salt_length!") do set "salt_length=%%k"
)

:: Extract user audit results
set "in_user_section=0"
for /f "tokens=*" %%i in (%PROC_TEMP_FILE%) do (
    set "line=%%i"
    if "!line!"=="User Audit Results:" (
        set "in_user_section=1"
    ) else if "!line!"=="===========================" (
        set "in_user_section=0"
    ) else if "!in_user_section!"=="1" (
        :: Skip header and divider lines
        if not "!line!"=="Username | Password Type | Compliance" (
            if not "!line!"=="---------|---------------|-----------" (
                :: Parse user line (trim leading spaces and split by |)
                for /f "tokens=*" %%j in ("!line!") do set "trimmed_line=%%j"
                for /f "tokens=1,2,3 delims=|" %%j in ("!trimmed_line!") do (
                    set "username=%%j"
                    set "password_type=%%k"
                    set "compliance=%%l"
                    :: Trim leading/trailing spaces
                    for /f "tokens=*" %%m in ("!username!") do set "username=%%m"
                    for /f "tokens=*" %%m in ("!password_type!") do set "password_type=%%m"
                    for /f "tokens=*" %%m in ("!compliance!") do set "compliance=%%m"
                    if not "!username!"=="" (
                        :: Set default values if fields are empty
                        if "!tomcat_version!"=="" set "tomcat_version=Unknown"
                        if "!credential_handler!"=="" set "credential_handler=None"
                        if "!algorithm!"=="" set "algorithm=None"
                        if "!iterations!"=="" set "iterations=0"
                        if "!salt_length!"=="" set "salt_length=0"
                        :: Pad fields for alignment
                        set "padded_hostname=!hostname!                         "
                        set "padded_hostname=!padded_hostname:~0,25!"
                        set "padded_version=!tomcat_version!              "
                        set "padded_version=!padded_version:~0,13!"
                        set "padded_handler=!credential_handler!                                                   "
                        set "padded_handler=!padded_handler:~0,52!"
                        set "padded_algorithm=!algorithm!                      "
                        set "padded_algorithm=!padded_algorithm:~0,23!"
                        set "padded_iterations=!iterations!           "
                        set "padded_iterations=!padded_iterations:~0,10!"
                        set "padded_salt_length=!salt_length!           "
                        set "padded_salt_length=!padded_salt_length:~0,11!"
                        set "padded_username=!username!          "
                        set "padded_username=!padded_username:~0,10!"
                        set "padded_password_type=!password_type!            "
                        set "padded_password_type=!padded_password_type:~0,13!"
                        set "padded_compliance=!compliance!         "
                        set "padded_compliance=!padded_compliance:~0,10!"
                        echo !padded_hostname!^| !padded_version!^| !padded_handler!^| !padded_algorithm!^| !padded_iterations!^| !padded_salt_length!^| !padded_username!^| !padded_password_type!^| !padded_compliance!
                    )
                )
            )
        )
    )
)

:: Clean up processing temp file
if exist %PROC_TEMP_FILE% del %PROC_TEMP_FILE%
exit /b