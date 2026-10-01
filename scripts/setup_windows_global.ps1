[CmdletBinding()]
param(
    [switch]$SkipPythonTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor DarkCyan
    Write-Host "STEP: $Name" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor DarkCyan

    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Step '$Name' failed with exit code $LASTEXITCODE."
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$originalLocation = Get-Location

try {
    Set-Location $repoRoot

    if ($env:VIRTUAL_ENV) {
        throw "A virtual environment is active. Open a clean PowerShell window and run this script again."
    }
    if ($env:CONDA_PREFIX) {
        throw "A Conda environment is active. Deactivate it or open a clean PowerShell window."
    }

    Invoke-Checked "Check Git" { git --version }
    Invoke-Checked "Check CMake" { cmake --version }
    Invoke-Checked "Check Python 3.12 x64" {
        py -3.12 -c "import struct, sys; print('Executable:', sys.executable); print('Version:', sys.version); print('Architecture:', struct.calcsize('P') * 8, 'bit'); assert sys.version_info[:2] == (3, 12); assert struct.calcsize('P') * 8 == 64"
    }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    $vsInstances = @()
    if (Test-Path $vswhere) {
        $vsJson = & $vswhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -format json
        if ($LASTEXITCODE -eq 0 -and $vsJson) {
            $vsInstances = @(($vsJson -join [Environment]::NewLine) | ConvertFrom-Json)
        }
    }
    if ($vsInstances.Count -eq 0) {
        throw @"
No complete Visual Studio C++ toolchain was found. In Visual Studio Installer,
select Modify and enable 'Desktop development with C++', then rerun this script.
A green 'Windows Version' line in flutter doctor is separate from the
'Visual Studio - develop Windows apps' check.
"@
    }

    $vsInstance = $vsInstances[0]
    $vsMajor = [int](($vsInstance.installationVersion -split "\.")[0])
    $cmakeGenerator = switch ($vsMajor) {
        18 { "Visual Studio 18 2026"; break }
        17 { "Visual Studio 17 2022"; break }
        16 { "Visual Studio 16 2019"; break }
        default { throw "Unsupported Visual Studio version: $($vsInstance.installationVersion)" }
    }
    Write-Host "Visual Studio: $($vsInstance.installationPath)" -ForegroundColor Green
    Write-Host "CMake generator: $cmakeGenerator" -ForegroundColor Green

    if (Test-Path ".venv") {
        Write-Host "Removing unused .venv directory..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force ".venv"
    }
    if (Test-Path "engine\build") {
        Write-Host "Removing stale native build..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force "engine\build"
    }

    Invoke-Checked "Upgrade pip in the Python 3.12 user site" {
        py -3.12 -m pip install --user --upgrade pip
    }
    Invoke-Checked "Install Python dependencies without a virtual environment" {
        py -3.12 -m pip install --user -r server\requirements-dev.txt pybind11
    }

    $pythonExe = (& py -3.12 -c "import sys; print(sys.executable)").Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not resolve the Python 3.12 executable." }
    $pythonRoot = Split-Path -Parent $pythonExe
    $pybind11Dir = (& py -3.12 -c "import pybind11; print(pybind11.get_cmake_dir())").Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not resolve the pybind11 CMake directory." }

    Write-Host "Python executable: $pythonExe" -ForegroundColor Green
    Write-Host "pybind11 CMake:    $pybind11Dir" -ForegroundColor Green

    Invoke-Checked "Configure native engine" {
        cmake -S engine -B engine\build `
            -G $cmakeGenerator `
            -A x64 `
            "-DPython_EXECUTABLE=$pythonExe" `
            "-DPython_ROOT_DIR=$pythonRoot" `
            "-Dpybind11_DIR=$pybind11Dir" `
            -DBUILD_TESTING=ON
    }
    Invoke-Checked "Build native engine" {
        cmake --build engine\build --config Release
    }
    Invoke-Checked "Run native tests" {
        ctest --test-dir engine\build -C Release --output-on-failure
    }

    $pyd = Get-ChildItem -Path "engine\build\Release" `
        -Filter "aiterm_engine*.pyd" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $pyd) {
        throw "The Release build did not create aiterm_engine*.pyd."
    }
    if ($pyd.Name -notmatch "cp312") {
        throw "Wrong native Python ABI: $($pyd.Name). Expected cp312."
    }

    $releaseDir = (Resolve-Path "engine\build\Release").Path
    Invoke-Checked "Import native module" {
        py -3.12 -c "import sys; sys.path.insert(0, sys.argv[1]); import aiterm_engine; print('Native engine OK:', aiterm_engine.__file__)" $releaseDir
    }

    if (-not $SkipPythonTests) {
        Invoke-Checked "Run Python tests" {
            py -3.12 -m pytest server\tests -q
        }
    }

    Write-Host ""
    Write-Host "SETUP AND BUILD COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "Backend: cd server; py -3.12 -m app.main" -ForegroundColor Green
    Write-Host "Client:  cd client; flutter run -d windows" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "SETUP STOPPED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    Set-Location $originalLocation
}
