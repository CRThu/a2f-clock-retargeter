@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: A2F Clock Retargeter - Headless One-Click Batch Launcher
:: =============================================================================

set "VIVADO_BIN="

:: 1. Priority 1: Query Windows Native Registry Association for .xpr
for /f "tokens=3" %%a in ('reg query HKCR\.xpr /ve 2^>nul ^| findstr REG_SZ') do (
    for /f "tokens=2,*" %%b in ('reg query HKCR\%%a\shell\open\command /ve 2^>nul ^| findstr REG_SZ') do (
        for %%w in (%%c) do (
            if not defined VIVADO_BIN (
                if /i "%%~nxw"=="vivado.bat" (
                    if exist "%%~fw" set "VIVADO_BIN=%%~fw"
                )
            )
        )
    )
)

:: 2. Priority 2: Fallback scan across standard installation paths (C:, D:, E:)
if not defined VIVADO_BIN (
    for %%d in (C: D: E:) do (
        if exist "%%d\Xilinx\Vivado" (
            for /f "delims=" %%v in ('dir /b /ad /o-n "%%d\Xilinx\Vivado" 2^>nul') do (
                if not defined VIVADO_BIN (
                    if exist "%%d\Xilinx\Vivado\%%v\bin\vivado.bat" (
                        set "VIVADO_BIN=%%d\Xilinx\Vivado\%%v\bin\vivado.bat"
                    )
                )
            )
        )
    )
)

if not defined VIVADO_BIN (
    echo ==================================================================
    echo [ERROR] Vivado installation not detected!
    echo Please ensure Vivado is installed in C:\Xilinx or D:\Xilinx.
    echo ==================================================================
    pause
    exit /b 1
)

set "SCRIPT_DIR=%~dp0"
set "TARGET_XPR=%~1"

:: 3. If no argument passed, scan current directory for *.xpr
if "%TARGET_XPR%"=="" (
    set "COUNT=0"
    for %%f in (*.xpr) do (
        set /a COUNT+=1
        set "TARGET_XPR=%%~ff"
    )
    if !COUNT! equ 1 (
        echo [A2F] Auto-detected project in current directory: !TARGET_XPR!
    ) else if !COUNT! gtr 1 (
        echo [A2F] Warning: Multiple .xpr files found in current directory.
        set "TARGET_XPR="
    )
)

:: 4. If still empty, prompt user to drag & drop .xpr file into window
if "%TARGET_XPR%"=="" (
    echo ==================================================================
    echo [A2F] No .xpr project detected in current directory.
    echo Please drag and drop your .xpr file into this window and press ENTER:
    echo ==================================================================
    set /p "INPUT_PATH=> "
    for /f "tokens=*" %%i in ("!INPUT_PATH!") do set "TARGET_XPR=%%~fi"
)

:: 5. Validate existence
if not exist "!TARGET_XPR!" (
    echo [ERROR] Project file not found: "!TARGET_XPR!"
    pause
    exit /b 1
)

echo [A2F] Using Vivado Engine: "!VIVADO_BIN!"
echo [A2F] Starting analysis for: "!TARGET_XPR!" ...
call "!VIVADO_BIN!" -mode batch -notrace -source "%SCRIPT_DIR%auto_run_retarget.tcl" -tclargs "!TARGET_XPR!"

echo ==================================================================
echo [A2F] Done! XDC generated in the project directory.
echo ==================================================================
