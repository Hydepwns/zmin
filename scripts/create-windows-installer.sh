#!/bin/bash

# Create Windows installer for zmin using NSIS
set -e

# Configuration
PACKAGE_NAME="zmin"
VERSION=$(git describe --tags --always --dirty | sed 's/^v//')
ARCHITECTURE="x64"
INSTALLER_NAME="${PACKAGE_NAME}-${VERSION}-${ARCHITECTURE}-setup.exe"

echo "Creating Windows installer: ${INSTALLER_NAME}"

# Check if NSIS is available
if ! command -v makensis &> /dev/null; then
    echo "Error: NSIS (makensis) is not installed."
    echo "Please install NSIS from https://nsis.sourceforge.io/"
    echo "On Windows with Chocolatey: choco install nsis"
    echo "On Windows with Scoop: scoop install nsis"
    exit 1
fi

# Clean previous builds
rm -rf "windows-installer"
rm -f "${INSTALLER_NAME}"

# Create installer directory structure
mkdir -p "windows-installer"
mkdir -p "windows-installer/bin"
mkdir -p "windows-installer/lib"
mkdir -p "windows-installer/include"
mkdir -p "windows-installer/doc"
mkdir -p "windows-installer/examples"

# Build the project for Windows
zig build install-all -Dtarget=x86_64-windows-gnu

# Copy files from zig-out to installer directory
cp -r zig-out/bin/* "windows-installer/bin/" 2>/dev/null || true
cp -r zig-out/lib/* "windows-installer/lib/" 2>/dev/null || true
cp -r zig-out/include/* "windows-installer/include/" 2>/dev/null || true
cp -r zig-out/share/doc/zmin/* "windows-installer/doc/" 2>/dev/null || true
cp -r zig-out/share/zmin/examples/* "windows-installer/examples/" 2>/dev/null || true

# Create NSIS script
cat > "windows-installer/installer.nsi" << EOF
!include "MUI2.nsh"
!include "FileFunc.nsh"

; Basic settings
Name "${PACKAGE_NAME}"
OutFile "${INSTALLER_NAME}"
InstallDir "\$PROGRAMFILES64\\${PACKAGE_NAME}"
InstallDirRegKey HKLM "Software\\${PACKAGE_NAME}" "Install_Dir"

; Request application privileges
RequestExecutionLevel admin

; Interface settings
!define MUI_ABORTWARNING
!define MUI_ICON "windows-installer\\icon.ico"
!define MUI_UNICON "windows-installer\\icon.ico"

; Pages
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; Languages
!insertmacro MUI_LANGUAGE "English"

; Version information
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${PACKAGE_NAME}"
VIAddVersionKey "CompanyName" "zmin developers"
VIAddVersionKey "LegalCopyright" "MIT License"
VIAddVersionKey "FileDescription" "High-performance Zig minifier"
VIAddVersionKey "FileVersion" "${VERSION}"

; Installer sections
Section "Main Application" SecMain
    SetOutPath "\$INSTDIR"

    ; Install main executable and libraries
    File /r "bin\\*"
    File /r "lib\\*"

    ; Install headers
    SetOutPath "\$INSTDIR\\include"
    File /r "include\\*"

    ; Install documentation
    SetOutPath "\$INSTDIR\\doc"
    File /r "doc\\*"

    ; Install examples
    SetOutPath "\$INSTDIR\\examples"
    File /r "examples\\*"

    ; Write installation info to registry
    WriteRegStr HKLM "Software\\${PACKAGE_NAME}" "Install_Dir" "\$INSTDIR"
    WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\${PACKAGE_NAME}" "DisplayName" "${PACKAGE_NAME}"
    WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\${PACKAGE_NAME}" "UninstallString" '"\$INSTDIR\\uninstall.exe"'
    WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\${PACKAGE_NAME}" "DisplayIcon" "\$INSTDIR\\bin\\zmin.exe"
    WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\${PACKAGE_NAME}" "Publisher" "zmin developers"
    WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\${PACKAGE_NAME}" "DisplayVersion" "${VERSION}"
    WriteRegDWORD HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\${PACKAGE_NAME}" "NoModify" 1
    WriteRegDWORD HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\${PACKAGE_NAME}" "NoRepair" 1

    ; Create uninstaller
    WriteUninstaller "\$INSTDIR\\uninstall.exe"
SectionEnd

Section "Add to PATH" SecPath
    ; Add to system PATH
    \${EnvVarUpdate} \$0 "PATH" "A" "HKLM" "\$INSTDIR\\bin"
SectionEnd

Section "Start Menu Shortcuts" SecStartMenu
    CreateDirectory "\$SMPROGRAMS\\${PACKAGE_NAME}"
    CreateShortCut "\$SMPROGRAMS\\${PACKAGE_NAME}\\${PACKAGE_NAME}.lnk" "\$INSTDIR\\bin\\zmin.exe"
    CreateShortCut "\$SMPROGRAMS\\${PACKAGE_NAME}\\Documentation.lnk" "\$INSTDIR\\doc\\README.html"
    CreateShortCut "\$SMPROGRAMS\\${PACKAGE_NAME}\\Examples.lnk" "\$INSTDIR\\examples"
    CreateShortCut "\$SMPROGRAMS\\${PACKAGE_NAME}\\Uninstall.lnk" "\$INSTDIR\\uninstall.exe"
SectionEnd

; Uninstaller section
Section "Uninstall"
    ; Remove files and directories
    RMDir /r "\$INSTDIR\\bin"
    RMDir /r "\$INSTDIR\\lib"
    RMDir /r "\$INSTDIR\\include"
    RMDir /r "\$INSTDIR\\doc"
    RMDir /r "\$INSTDIR\\examples"

    ; Remove uninstaller
    Delete "\$INSTDIR\\uninstall.exe"
    RMDir "\$INSTDIR"

    ; Remove from PATH
    \${un.EnvVarUpdate} \$0 "PATH" "R" "HKLM" "\$INSTDIR\\bin"

    ; Remove start menu shortcuts
    Delete "\$SMPROGRAMS\\${PACKAGE_NAME}\\${PACKAGE_NAME}.lnk"
    Delete "\$SMPROGRAMS\\${PACKAGE_NAME}\\Documentation.lnk"
    Delete "\$SMPROGRAMS\\${PACKAGE_NAME}\\Examples.lnk"
    Delete "\$SMPROGRAMS\\${PACKAGE_NAME}\\Uninstall.lnk"
    RMDir "\$SMPROGRAMS\\${PACKAGE_NAME}"

    ; Remove registry keys
    DeleteRegKey HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\${PACKAGE_NAME}"
    DeleteRegKey HKLM "Software\\${PACKAGE_NAME}"
SectionEnd
EOF

# Create a simple icon file (placeholder)
cat > "windows-installer/create-icon.ps1" << 'EOF'
# PowerShell script to create a simple icon
Add-Type -AssemblyName System.Drawing

$icon = New-Object System.Drawing.Icon
$bitmap = New-Object System.Drawing.Bitmap 32, 32

# Create a simple colored square as icon
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Blue)
$graphics.FillRectangle($brush, 0, 0, 32, 32)
$graphics.Dispose()

# Save as ICO file
$bitmap.Save("icon.ico", [System.Drawing.Imaging.ImageFormat]::Icon)
$bitmap.Dispose()
EOF

# Create a simple icon if we're on Windows, otherwise create a placeholder
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    powershell -ExecutionPolicy Bypass -File "windows-installer/create-icon.ps1"
else
    # Create a placeholder icon file
    echo "Creating placeholder icon..."
    # This is a minimal ICO file structure
    printf '\x00\x00\x01\x00\x01\x00\x10\x10\x00\x00\x01\x00\x20\x00\x68\x04\x00\x00\x16\x00\x00\x00' > "windows-installer/icon.ico"
fi

# Build the installer
echo "Building Windows installer with NSIS..."
makensis "windows-installer/installer.nsi"

# Move the installer to the current directory
mv "${INSTALLER_NAME}" .

# Clean up
rm -rf "windows-installer"

echo "Windows installer created: ${INSTALLER_NAME}"
echo "To install: Double-click ${INSTALLER_NAME}"
