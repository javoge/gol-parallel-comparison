# =============================================================
# Script de Compilacion y Ejecucion - Windows (PowerShell)
# Juego de la Vida - Comparativa de Paradigmas de Paralelismo
# =============================================================
# REQUISITOS PREVIOS:
#   1. Visual Studio 2022 con "Desarrollo para escritorio en C++"
#   2. CUDA Toolkit (https://developer.nvidia.com/cuda-downloads)
#   3. Microsoft MPI:
#      - Runtime:  https://www.microsoft.com/en-us/download/details.aspx?id=57467
#      - SDK:      https://www.microsoft.com/en-us/download/details.aspx?id=57467
#   Todos deben estar en el PATH del sistema.
# =============================================================

param(
    [int]$ROWS  = 1024,
    [int]$COLS  = 1024,
    [int]$STEPS = 100,
    [int]$SEED  = 42,
    [switch]$BuildOnly,
    [switch]$RunOnly
)

$ErrorActionPreference = "Stop"

# ---- Colores para output ----
function Write-Header($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-OK($msg)     { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-ERR($msg)    { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-INFO($msg)   { Write-Host "[INFO] $msg" -ForegroundColor Yellow }

$SRC = "src"
$BIN = "bin"

if (-not (Test-Path $BIN)) { New-Item -ItemType Directory -Path $BIN | Out-Null }

# ---- Buscar entorno de Visual Studio ----
function Find-VCVARS {
    $vsPaths = @(
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"
    )
    foreach ($p in $vsPaths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# ---- Compilar con cl.exe via cmd batch ----
function Compile-WithMSVC($src, $out, $extraFlags = "") {
    $vcvars = Find-VCVARS
    if (-not $vcvars) {
        Write-ERR "No se encontro Visual Studio. Instala VS 2022 con C++."
        return $false
    }

    $mpiInclude = "C:\Program Files (x86)\Microsoft SDKs\MPI\Include"
    $mpiLib     = "C:\Program Files (x86)\Microsoft SDKs\MPI\Lib\x64"

    $cmd = "`"$vcvars`" && cl.exe /EHsc /O2 /openmp /std:c++17 " +
           "/I`"$mpiInclude`" " +
           "`"$src`" " +
           "/Fe:`"$out`" " +
           "/link /LIBPATH:`"$mpiLib`" msmpi.lib $extraFlags"

    $result = cmd /c $cmd 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ERR "Fallo compilacion de $src"
        Write-Host $result
        return $false
    }
    return $true
}

# =============================================================
# COMPILACION
# =============================================================
if (-not $RunOnly) {
    Write-Header "COMPILANDO"

    # 1. Secuencial
    Write-INFO "Compilando secuencial..."
    $vcvars = Find-VCVARS
    if ($vcvars) {
        $cmd = "`"$vcvars`" && cl.exe /EHsc /O2 /std:c++17 `"$SRC\gol_sequential.cpp`" /Fe:`"$BIN\gol_sequential.exe`""
        cmd /c $cmd 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-OK "gol_sequential.exe" } else { Write-ERR "Fallo secuencial" }
    }

    # 2. OpenMP
    Write-INFO "Compilando OpenMP..."
    $cmd = "`"$vcvars`" && cl.exe /EHsc /O2 /openmp /std:c++17 `"$SRC\gol_openmp.cpp`" /Fe:`"$BIN\gol_openmp.exe`""
    cmd /c $cmd 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-OK "gol_openmp.exe" } else { Write-ERR "Fallo OpenMP" }

    # 3. MPI
    Write-INFO "Compilando MPI..."
    $mpiInc = "C:\Program Files (x86)\Microsoft SDKs\MPI\Include"
    $mpiLib = "C:\Program Files (x86)\Microsoft SDKs\MPI\Lib\x64"
    $cmd = "`"$vcvars`" && cl.exe /EHsc /O2 /std:c++17 /I`"$mpiInc`" `"$SRC\gol_mpi.cpp`" /Fe:`"$BIN\gol_mpi.exe`" /link /LIBPATH:`"$mpiLib`" msmpi.lib"
    cmd /c $cmd 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-OK "gol_mpi.exe" } else { Write-ERR "Fallo MPI (instala MS-MPI SDK?)" }

    # 4. Mixto
    Write-INFO "Compilando Mixto (MPI+OpenMP)..."
    $cmd = "`"$vcvars`" && cl.exe /EHsc /O2 /openmp /std:c++17 /I`"$mpiInc`" `"$SRC\gol_mixed.cpp`" /Fe:`"$BIN\gol_mixed.exe`" /link /LIBPATH:`"$mpiLib`" msmpi.lib"
    cmd /c $cmd 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-OK "gol_mixed.exe" } else { Write-ERR "Fallo Mixto" }

    # 5. CUDA
    Write-INFO "Compilando CUDA..."
    if (Get-Command nvcc -ErrorAction SilentlyContinue) {
        & nvcc -O2 -arch=sm_89 "$SRC\gol_cuda.cu" -o "$BIN\gol_cuda.exe" 2>&1
        if ($LASTEXITCODE -eq 0) { Write-OK "gol_cuda.exe (sm_89 = RTX 40xx)" } else { Write-ERR "Fallo CUDA" }
    } else {
        Write-ERR "nvcc no encontrado. Instala CUDA Toolkit."
    }
}

# =============================================================
# EJECUCION Y BENCHMARKS
# =============================================================
if (-not $BuildOnly) {
    Write-Header "EJECUTANDO BENCHMARKS"
    Write-INFO "Grid: ${ROWS}x${COLS} | Pasos: $STEPS | Semilla: $SEED"

    # Numero de hilos del CPU (Ryzen 7 = 8 cores / 16 threads)
    $THREADS = (Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors

    # 1. Secuencial
    Write-Header "1/5 - Secuencial"
    if (Test-Path "$BIN\gol_sequential.exe") {
        & "$BIN\gol_sequential.exe" $ROWS $COLS $STEPS $SEED
    }

    # 2. OpenMP (varios conteos de hilos)
    Write-Header "2/5 - OpenMP"
    foreach ($t in @(1, 2, 4, 8, $THREADS)) {
        if (Test-Path "$BIN\gol_openmp.exe") {
            Write-INFO "--- $t hilos ---"
            & "$BIN\gol_openmp.exe" $ROWS $COLS $STEPS $t $SEED
        }
    }

    # 3. MPI (varios conteos de procesos)
    Write-Header "3/5 - MPI"
    foreach ($p in @(1, 2, 4, 8)) {
        if (Test-Path "$BIN\gol_mpi.exe") {
            Write-INFO "--- $p procesos ---"
            & mpiexec -n $p "$BIN\gol_mpi.exe" $ROWS $COLS $STEPS $SEED
        }
    }

    # 4. Mixto MPI+OpenMP
    Write-Header "4/5 - Mixto (MPI+OpenMP)"
    if (Test-Path "$BIN\gol_mixed.exe") {
        # 2 procesos x 4 hilos = 8 trabajadores (similar al Ryzen 7)
        & mpiexec -n 2 "$BIN\gol_mixed.exe" $ROWS $COLS $STEPS 4 $SEED
        & mpiexec -n 4 "$BIN\gol_mixed.exe" $ROWS $COLS $STEPS 4 $SEED
    }

    # 5. CUDA
    Write-Header "5/5 - GPU CUDA"
    if (Test-Path "$BIN\gol_cuda.exe") {
        Write-INFO "--- Kernel basico ---"
        & "$BIN\gol_cuda.exe" $ROWS $COLS $STEPS $SEED 0
        Write-INFO "--- Kernel con shared memory ---"
        & "$BIN\gol_cuda.exe" $ROWS $COLS $STEPS $SEED 1
    }

    Write-Header "BENCHMARKS COMPLETADOS"
    Write-OK "Resultados guardados en results_*.txt"
}
