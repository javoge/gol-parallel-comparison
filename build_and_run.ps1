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
    [string[]]$Seeds,
    [string[]]$OpenMPThreads,
    [string[]]$MPIProcs = @(1, 2, 4, 8),
    [string[]]$MixedMPIProcs = @(2, 4),
    [int]$MixedThreads = 4,
    [int]$Repeats = 1,
    [int]$WarmupRuns = 0,
    [string]$UnifiedResultsFile = "results_unified.csv",
    [string]$CudaArch = "",
    [switch]$MonitorResources,
    [int]$MonitorIntervalMs = 250,
    [int]$MonitorGpuIndex = 0,
    [string]$MonitorDir = "monitors",
    [switch]$MonitorPerCore,
    [switch]$BuildOnly,
    [switch]$RunOnly
)

$ErrorActionPreference = "Stop"

# ---- Colores para output ----
function Write-Header($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-OK($msg)     { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-ERR($msg)    { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-INFO($msg)   { Write-Host "[INFO] $msg" -ForegroundColor Yellow }

function Invoke-CmdQuiet($commandLine) {
    $stdout = Join-Path $env:TEMP "gol_build_stdout.log"
    $stderr = Join-Path $env:TEMP "gol_build_stderr.log"
    $script = Join-Path $env:TEMP "gol_build_cmd.bat"
    if (Test-Path $stdout) { Remove-Item $stdout -Force }
    if (Test-Path $stderr) { Remove-Item $stderr -Force }
    Set-Content -Path $script -Value $commandLine -Encoding ASCII

    $proc = Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c", "`"$script`"" `
        -NoNewWindow `
        -Wait `
        -PassThru `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr

    return $proc.ExitCode
}

$SCRIPT_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$SRC = Join-Path $SCRIPT_ROOT "src"
$BIN = Join-Path $SCRIPT_ROOT "bin"

if (-not (Test-Path $BIN)) { New-Item -ItemType Directory -Path $BIN | Out-Null }

# ---- Buscar entorno de Visual Studio ----
function Find-VCVARS {
    $vswhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $installPath = & $vswhere -latest -products * -property installationPath 2>$null
        if ($installPath) {
            $vcvars = Join-Path $installPath "VC\Auxiliary\Build\vcvars64.bat"
            if (Test-Path $vcvars) { return $vcvars }
        }
    }

    $vsPaths = @(
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
    )
    foreach ($p in $vsPaths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Find-MPI {
    $mpiIncludeCandidates = @(
        "C:\Program Files (x86)\Microsoft SDKs\MPI\Include",
        "C:\Program Files\Microsoft SDKs\MPI\Include"
    )
    $mpiLibCandidates = @(
        "C:\Program Files (x86)\Microsoft SDKs\MPI\Lib\x64",
        "C:\Program Files\Microsoft SDKs\MPI\Lib\x64"
    )
    $mpiExecCandidates = @(
        "C:\Program Files\Microsoft MPI\Bin\mpiexec.exe",
        "C:\Program Files (x86)\Microsoft MPI\Bin\mpiexec.exe"
    )

    $mpiInclude = $mpiIncludeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    $mpiLib = $mpiLibCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    $mpiExec = $mpiExecCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $mpiExec) {
        $mpiExec = (Get-Command mpiexec -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
    }

    [PSCustomObject]@{
        Include = $mpiInclude
        Lib     = $mpiLib
        Exec    = $mpiExec
        Ready   = [bool]($mpiInclude -and $mpiLib -and $mpiExec)
    }
}

function Get-DefaultThreadCounts {
    param([int]$MaxThreads)

    $defaults = @(1, 2, 4, 8, $MaxThreads) |
        Where-Object { $_ -ge 1 -and $_ -le $MaxThreads } |
        Select-Object -Unique

    if (-not $defaults) { return @(1) }
    return @($defaults)
}

function Invoke-MPIProgram {
    param(
        [string]$MPIExec,
        [int]$Processes,
        [string]$Executable,
        [object[]]$Arguments
    )

    $resolvedExe = (Resolve-Path $Executable).Path
    & $MPIExec -n $Processes $resolvedExe @Arguments
}

function Parse-IntList {
    param(
        [object[]]$Values
    )

    if (-not $Values -or $Values.Count -eq 0) { return @() }

    $tokens = @()
    foreach ($v in $Values) {
        if ($null -eq $v) { continue }
        foreach ($t in ("$v" -split ",")) {
            $s = $t.Trim()
            if ($s) { $tokens += $s }
        }
    }

    $out = @()
    foreach ($t in $tokens) {
        try {
            $out += [int]$t
        } catch {
            throw "Valor invalido (se esperaba entero o lista separada por comas): '$t'"
        }
    }

    return @($out)
}

function Get-ResultRecord {
    param(
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        throw "No se encontro archivo de resultado: $FilePath"
    }

    $lines = Get-Content $FilePath
    if ($lines.Count -lt 2) {
        throw "Archivo de resultado invalido (sin filas de datos): $FilePath"
    }

    $csv = $lines | ConvertFrom-Csv
    if (-not $csv) {
        throw "No se pudo parsear CSV de: $FilePath"
    }

    if ($csv -is [System.Array]) {
        return $csv[-1]
    }
    return $csv
}

function Ensure-UnifiedResultsFile {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        "timestamp,mode,rows,cols,steps,seed,run_index,is_warmup,threads,procs,kernel,gpu,time_s,time_per_step_ms,alive_end" |
            Out-File -FilePath $Path -Encoding ASCII
    }
}

function Add-UnifiedResult {
    param(
        [string]$Path,
        [object]$Record,
        [int]$SeedValue,
        [int]$RunIndex,
        [bool]$IsWarmup,
        [int]$Threads = 0,
        [int]$Procs = 0,
        [string]$Kernel = "",
        [string]$Gpu = ""
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $row = [PSCustomObject]@{
        timestamp = $timestamp
        mode = $Record.mode
        rows = $Record.rows
        cols = $Record.cols
        steps = $Record.steps
        seed = $SeedValue
        run_index = $RunIndex
        is_warmup = [int]$IsWarmup
        threads = $Threads
        procs = $Procs
        kernel = $Kernel
        gpu = $Gpu
        time_s = $Record.time_s
        time_per_step_ms = $Record.time_per_step_ms
        alive_end = $Record.alive_end
    }

    $row | Select-Object timestamp,mode,rows,cols,steps,seed,run_index,is_warmup,threads,procs,kernel,gpu,time_s,time_per_step_ms,alive_end |
        ConvertTo-Csv -NoTypeInformation |
        Select-Object -Skip 1 |
        Add-Content -Path $Path -Encoding ASCII
}

function Reset-ResultFile {
    param(
        [string]$Path
    )
    if (Test-Path $Path) {
        Remove-Item $Path -Force
    }
}

function Start-ResourceMonitorJob {
    param(
        [string]$OutputPath,
        [int]$IntervalMs,
        [int]$GpuIndex,
        [string]$PerCoreOutputPath = "",
        [int]$CoreCount = 0
    )

    $dir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

    # Session-wide monitoring avoids distorting very short runs (e.g., CUDA kernel timing).
    $header = "timestamp,cpu_total_pct,mem_avail_mb,gpu_util_pct,gpu_mem_util_pct,gpu_mem_used_mb,gpu_mem_total_mb,gpu_power_w,gpu_temp_c,gpu_clock_graphics_mhz,gpu_clock_sm_mhz"
    $header | Out-File -FilePath $OutputPath -Encoding ASCII

    if ($PerCoreOutputPath) {
        $pcDir = Split-Path -Parent $PerCoreOutputPath
        if (-not (Test-Path $pcDir)) { New-Item -ItemType Directory -Path $pcDir | Out-Null }
        if ($CoreCount -lt 1) { $CoreCount = [Environment]::ProcessorCount }

        $pcCols = @("timestamp")
        for ($i = 0; $i -lt $CoreCount; $i++) { $pcCols += ("cpu_core_{0}_pct" -f $i) }
        ($pcCols -join ",") | Out-File -FilePath $PerCoreOutputPath -Encoding ASCII
    }

    $job = Start-Job -ArgumentList $OutputPath, $IntervalMs, $GpuIndex, $PerCoreOutputPath, $CoreCount -ScriptBlock {
        param($Path, $IntervalMs, $GpuIndex, $PerCorePath, $CoreCount)

        $ErrorActionPreference = "SilentlyContinue"

        function Get-CounterValueAny([string[]]$CounterPaths) {
            foreach ($CounterPath in $CounterPaths) {
                try {
                    $c = Get-Counter -Counter $CounterPath -ErrorAction Stop
                    if ($c -and $c.CounterSamples -and $c.CounterSamples.Count -gt 0) {
                        return [double]$c.CounterSamples[0].CookedValue
                    }
                } catch {}
            }
            return $null
        }

        function Get-TotalCpuPct {
            return Get-CounterValueAny @(
                "\Processor(_Total)\% Processor Time",
                "\Procesador(_Total)\% de tiempo de procesador"
            )
        }

        function Get-MemAvailMb {
            return Get-CounterValueAny @(
                "\Memory\Available MBytes",
                "\Memoria\Mbytes disponibles"
            )
        }

        function Get-NvidiaSample([int]$GpuIndex) {
            $nvsmi = (Get-Command nvidia-smi -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
            if (-not $nvsmi) { return $null }

            $q = "utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,temperature.gpu,clocks.gr,clocks.sm"
            $line = & $nvsmi "--query-gpu=$q" "--format=csv,noheader,nounits" "-i" $GpuIndex 2>$null
            if (-not $line) { return $null }

            $parts = ($line -split ",") | ForEach-Object { $_.Trim() }
            if ($parts.Count -lt 8) { return $null }

            return [PSCustomObject]@{
                gpu_util_pct = $parts[0]
                gpu_mem_util_pct = $parts[1]
                gpu_mem_used_mb = $parts[2]
                gpu_mem_total_mb = $parts[3]
                gpu_power_w = $parts[4]
                gpu_temp_c = $parts[5]
                gpu_clock_graphics_mhz = $parts[6]
                gpu_clock_sm_mhz = $parts[7]
            }
        }

        function Get-PerCoreCpu([int]$CoreCount) {
            if ($CoreCount -lt 1) { return $null }

            $paths = @(
                "\Processor(*)\% Processor Time",
                "\Procesador(*)\% de tiempo de procesador"
            )

            foreach ($path in $paths) {
                try {
                    $c = Get-Counter -Counter $path -ErrorAction Stop
                    if (-not $c -or -not $c.CounterSamples) { continue }

                    $map = @{}
                    foreach ($s in $c.CounterSamples) {
                        $name = $s.InstanceName
                        if ($name -match '^\d+$') {
                            $idx = [int]$name
                            if ($idx -ge 0 -and $idx -lt $CoreCount) {
                                $map[$idx] = [double]$s.CookedValue
                            }
                        }
                    }
                    return $map
                } catch {}
            }

            return $null
        }

        while ($true) {
            $ts = (Get-Date).ToString("o")
            $cpu = Get-TotalCpuPct
            $mem = Get-MemAvailMb
            $gpu = Get-NvidiaSample -GpuIndex $GpuIndex

            $row = [PSCustomObject]@{
                timestamp = $ts
                cpu_total_pct = $cpu
                mem_avail_mb = $mem
                gpu_util_pct = $gpu.gpu_util_pct
                gpu_mem_util_pct = $gpu.gpu_mem_util_pct
                gpu_mem_used_mb = $gpu.gpu_mem_used_mb
                gpu_mem_total_mb = $gpu.gpu_mem_total_mb
                gpu_power_w = $gpu.gpu_power_w
                gpu_temp_c = $gpu.gpu_temp_c
                gpu_clock_graphics_mhz = $gpu.gpu_clock_graphics_mhz
                gpu_clock_sm_mhz = $gpu.gpu_clock_sm_mhz
            }

            $row |
                Select-Object timestamp,cpu_total_pct,mem_avail_mb,gpu_util_pct,gpu_mem_util_pct,gpu_mem_used_mb,gpu_mem_total_mb,gpu_power_w,gpu_temp_c,gpu_clock_graphics_mhz,gpu_clock_sm_mhz |
                ConvertTo-Csv -NoTypeInformation |
                Select-Object -Skip 1 |
                Add-Content -Path $Path -Encoding ASCII

            if ($PerCorePath) {
                if ($CoreCount -lt 1) { $CoreCount = [Environment]::ProcessorCount }
                $cores = Get-PerCoreCpu -CoreCount $CoreCount

                $pc = [ordered]@{ timestamp = $ts }
                for ($i = 0; $i -lt $CoreCount; $i++) {
                    $pc[("cpu_core_{0}_pct" -f $i)] = if ($cores -and $cores.ContainsKey($i)) { $cores[$i] } else { $null }
                }

                [PSCustomObject]$pc |
                    ConvertTo-Csv -NoTypeInformation |
                    Select-Object -Skip 1 |
                    Add-Content -Path $PerCorePath -Encoding ASCII
            }

            Start-Sleep -Milliseconds $IntervalMs
        }
    }

    # Best-effort: wait briefly for the first sample so short benchmark runs still get data.
    $deadline = (Get-Date).AddSeconds(2)
    while ((Get-Date) -lt $deadline) {
        try {
            $lines = Get-Content -Path $OutputPath -TotalCount 2 -ErrorAction SilentlyContinue
            if ($lines -and $lines.Count -ge 2) { break }
        } catch {}
        Start-Sleep -Milliseconds 50
    }

    return $job
}

function Stop-ResourceMonitorJob {
    param(
        [System.Management.Automation.Job]$Job
    )

    if (-not $Job) { return }
    try { Stop-Job -Job $Job -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
}

# =============================================================
# COMPILACION
# =============================================================
if (-not $RunOnly) {
    Write-Header "COMPILANDO"
    $vcvars = Find-VCVARS
    if (-not $vcvars) {
        Write-ERR "No se encontro Visual Studio C++/Build Tools."
        exit 1
    }
    $mpi = Find-MPI

    # 1. Secuencial
    Write-INFO "Compilando secuencial..."
    $cmd = "`"$vcvars`" && cl.exe /EHsc /O2 /std:c++17 `"$SRC\gol_sequential.cpp`" /Fe:`"$BIN\gol_sequential.exe`""
    $exitCode = Invoke-CmdQuiet $cmd
    if ($exitCode -eq 0) { Write-OK "gol_sequential.exe" } else { Write-ERR "Fallo secuencial" }

    # 2. OpenMP
    Write-INFO "Compilando OpenMP..."
    $cmd = "`"$vcvars`" && cl.exe /EHsc /O2 /openmp /std:c++17 `"$SRC\gol_openmp.cpp`" /Fe:`"$BIN\gol_openmp.exe`""
    $exitCode = Invoke-CmdQuiet $cmd
    if ($exitCode -eq 0) { Write-OK "gol_openmp.exe" } else { Write-ERR "Fallo OpenMP" }

    # 3. MPI
    if ($mpi.Ready) {
        Write-INFO "Compilando MPI..."
        $cmd = "`"$vcvars`" && cl.exe /EHsc /O2 /std:c++17 /I`"$($mpi.Include)`" `"$SRC\gol_mpi.cpp`" /Fe:`"$BIN\gol_mpi.exe`" /link /LIBPATH:`"$($mpi.Lib)`" msmpi.lib"
        $exitCode = Invoke-CmdQuiet $cmd
        if ($exitCode -eq 0) { Write-OK "gol_mpi.exe" } else { Write-ERR "Fallo MPI (revisa MS-MPI SDK/Runtime)" }
    } else {
        Write-INFO "MPI no disponible. Se omite compilacion de gol_mpi.exe"
    }

    # 4. Mixto
    if ($mpi.Ready) {
        Write-INFO "Compilando Mixto (MPI+OpenMP)..."
        $cmd = "`"$vcvars`" && cl.exe /EHsc /O2 /openmp /std:c++17 /I`"$($mpi.Include)`" `"$SRC\gol_mixed.cpp`" /Fe:`"$BIN\gol_mixed.exe`" /link /LIBPATH:`"$($mpi.Lib)`" msmpi.lib"
        $exitCode = Invoke-CmdQuiet $cmd
        if ($exitCode -eq 0) { Write-OK "gol_mixed.exe" } else { Write-ERR "Fallo Mixto" }
    } else {
        Write-INFO "MPI no disponible. Se omite compilacion de gol_mixed.exe"
    }

    # 5. CUDA
    Write-INFO "Compilando CUDA..."
    if (Get-Command nvcc -ErrorAction SilentlyContinue) {
        $cudaFlags = @("-O2")
        if ($CudaArch) {
            $cudaFlags += "-arch=$CudaArch"
        }
        $cudaFlagString = $cudaFlags -join " "
        $cmd = "`"$vcvars`" && nvcc $cudaFlagString `"$SRC\gol_cuda.cu`" -o `"$BIN\gol_cuda.exe`""
        $exitCode = Invoke-CmdQuiet $cmd
        if ($exitCode -eq 0) {
            if ($CudaArch) {
                Write-OK "gol_cuda.exe ($CudaArch)"
            } else {
                Write-OK "gol_cuda.exe"
            }
        } else {
            Write-ERR "Fallo CUDA"
        }
    } else {
        Write-INFO "nvcc no encontrado. Se omite compilacion CUDA."
    }
}

# =============================================================
# EJECUCION Y BENCHMARKS
# =============================================================
if (-not $BuildOnly) {
    Write-Header "EJECUTANDO BENCHMARKS"
    if ($Repeats -lt 1) {
        Write-ERR "Repeats debe ser >= 1."
        exit 1
    }
    if ($WarmupRuns -lt 0) {
        Write-ERR "WarmupRuns debe ser >= 0."
        exit 1
    }

    $seedRuns = if ($Seeds -and $Seeds.Count -gt 0) {
        @(Parse-IntList -Values $Seeds | Select-Object -Unique)
    } else {
        @($SEED)
    }

    $totalRunsPerConfig = $WarmupRuns + $Repeats
    $unifiedPath = Join-Path $SCRIPT_ROOT $UnifiedResultsFile
    Ensure-UnifiedResultsFile -Path $unifiedPath

    Write-INFO "Grid: ${ROWS}x${COLS} | Pasos: $STEPS"
    Write-INFO "Semillas: $($seedRuns -join ', ') | Warmup: $WarmupRuns | Repeticiones: $Repeats"
    Write-INFO "Resultados unificados: $unifiedPath"

    $monitorJob = $null
    $monitorPath = $null
    if ($MonitorResources) {
        $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $monitorPath = Join-Path $SCRIPT_ROOT (Join-Path $MonitorDir ("resource_session_{0}.csv" -f $stamp))
        Write-INFO "Monitoreo de recursos habilitado: $monitorPath (cada ${MonitorIntervalMs}ms)"

        $perCorePath = ""
        if ($MonitorPerCore) {
            $perCorePath = Join-Path $SCRIPT_ROOT (Join-Path $MonitorDir ("resource_per_core_{0}.csv" -f $stamp))
            Write-INFO "Monitoreo por nucleo habilitado: $perCorePath"
        }

        $monitorJob = Start-ResourceMonitorJob -OutputPath $monitorPath -IntervalMs $MonitorIntervalMs -GpuIndex $MonitorGpuIndex -PerCoreOutputPath $perCorePath -CoreCount ([Environment]::ProcessorCount)
    }

    $mpi = Find-MPI

    # Numero de hilos logicos visibles para el proceso
    $THREADS = [Environment]::ProcessorCount
    $threadRuns = if ($OpenMPThreads) {
        @(Parse-IntList -Values $OpenMPThreads | Where-Object { $_ -ge 1 } | Select-Object -Unique)
    } else {
        Get-DefaultThreadCounts -MaxThreads $THREADS
    }

    try {
        foreach ($seedValue in $seedRuns) {
            Write-Header "Semilla $seedValue"

            for ($run = 1; $run -le $totalRunsPerConfig; $run++) {
                $isWarmup = ($run -le $WarmupRuns)
                $runLabel = if ($isWarmup) { "warmup $run/$WarmupRuns" } else { "muestra $($run - $WarmupRuns)/$Repeats" }

            # 1. Secuencial
            Write-Header "1/5 - Secuencial ($runLabel)"
            if (Test-Path "$BIN\gol_sequential.exe") {
                $resultFile = Join-Path $SCRIPT_ROOT "results_sequential.txt"
                Reset-ResultFile -Path $resultFile
                & "$BIN\gol_sequential.exe" $ROWS $COLS $STEPS $seedValue
                if ($LASTEXITCODE -ne 0) {
                    Write-ERR "Fallo secuencial (exit code $LASTEXITCODE)."
                } elseif (Test-Path $resultFile) {
                    $rec = Get-ResultRecord -FilePath $resultFile
                    Add-UnifiedResult -Path $unifiedPath -Record $rec -SeedValue $seedValue -RunIndex $run -IsWarmup $isWarmup
                } else {
                    Write-ERR "No se genero results_sequential.txt."
                }
            } else {
                Write-INFO "Binario secuencial no encontrado. Se omite."
            }

            # 2. OpenMP (varios conteos de hilos)
            Write-Header "2/5 - OpenMP ($runLabel)"
            foreach ($t in $threadRuns) {
                if (Test-Path "$BIN\gol_openmp.exe") {
                    Write-INFO "--- $t hilos ---"
                    $resultFile = Join-Path $SCRIPT_ROOT "results_openmp.txt"
                    Reset-ResultFile -Path $resultFile
                    & "$BIN\gol_openmp.exe" $ROWS $COLS $STEPS $t $seedValue
                    if ($LASTEXITCODE -ne 0) {
                        Write-ERR "Fallo OpenMP para $t hilos (exit code $LASTEXITCODE)."
                        continue
                    }
                    if (Test-Path $resultFile) {
                        $rec = Get-ResultRecord -FilePath $resultFile
                        Add-UnifiedResult -Path $unifiedPath -Record $rec -SeedValue $seedValue -RunIndex $run -IsWarmup $isWarmup -Threads $t
                    } else {
                        Write-ERR "No se genero results_openmp.txt para $t hilos."
                    }
                }
            }
            if (-not (Test-Path "$BIN\gol_openmp.exe")) { Write-INFO "Binario OpenMP no encontrado. Se omite." }

            # 3. MPI (varios conteos de procesos)
            Write-Header "3/5 - MPI ($runLabel)"
            foreach ($p in (Parse-IntList -Values $MPIProcs | Where-Object { $_ -ge 1 } | Select-Object -Unique)) {
                if ($mpi.Exec -and (Test-Path "$BIN\gol_mpi.exe")) {
                    Write-INFO "--- $p procesos ---"
                    $resultFile = Join-Path $SCRIPT_ROOT "results_mpi.txt"
                    Reset-ResultFile -Path $resultFile
                    Invoke-MPIProgram -MPIExec $mpi.Exec -Processes $p -Executable "$BIN\gol_mpi.exe" -Arguments @($ROWS, $COLS, $STEPS, $seedValue)
                    if ($LASTEXITCODE -ne 0) {
                        Write-ERR "Fallo MPI para $p procesos (exit code $LASTEXITCODE)."
                        continue
                    }
                    if (Test-Path $resultFile) {
                        $rec = Get-ResultRecord -FilePath $resultFile
                        Add-UnifiedResult -Path $unifiedPath -Record $rec -SeedValue $seedValue -RunIndex $run -IsWarmup $isWarmup -Procs $p
                    } else {
                        Write-ERR "No se genero results_mpi.txt para $p procesos."
                    }
                }
            }
            if (-not $mpi.Exec) { Write-INFO "MPI no disponible. Se omite ejecucion MPI." }
            if (-not (Test-Path "$BIN\gol_mpi.exe")) { Write-INFO "Binario MPI no encontrado. Se omite." }

            # 4. Mixto MPI+OpenMP
            Write-Header "4/5 - Mixto (MPI+OpenMP) ($runLabel)"
            if ($mpi.Exec -and (Test-Path "$BIN\gol_mixed.exe")) {
                foreach ($p in (Parse-IntList -Values $MixedMPIProcs | Where-Object { $_ -ge 1 } | Select-Object -Unique)) {
                    Write-INFO "--- $p procesos / $MixedThreads hilos ---"
                    $resultFile = Join-Path $SCRIPT_ROOT "results_mixed.txt"
                    Reset-ResultFile -Path $resultFile
                    Invoke-MPIProgram -MPIExec $mpi.Exec -Processes $p -Executable "$BIN\gol_mixed.exe" -Arguments @($ROWS, $COLS, $STEPS, $MixedThreads, $seedValue)
                    if ($LASTEXITCODE -ne 0) {
                        Write-ERR "Fallo mixto para $p procesos y $MixedThreads hilos (exit code $LASTEXITCODE)."
                        continue
                    }
                    if (Test-Path $resultFile) {
                        $rec = Get-ResultRecord -FilePath $resultFile
                        Add-UnifiedResult -Path $unifiedPath -Record $rec -SeedValue $seedValue -RunIndex $run -IsWarmup $isWarmup -Procs $p -Threads $MixedThreads
                    } else {
                        Write-ERR "No se genero results_mixed.txt para $p procesos."
                    }
                }
            }
            if (-not $mpi.Exec) { Write-INFO "MPI no disponible. Se omite ejecucion mixta." }
            if (-not (Test-Path "$BIN\gol_mixed.exe")) { Write-INFO "Binario mixto no encontrado. Se omite." }

                # 5. CUDA
                Write-Header "5/5 - GPU CUDA ($runLabel)"
                if (Test-Path "$BIN\gol_cuda.exe") {
                    Write-INFO "--- Kernel basico ---"
                    $resultFile = Join-Path $SCRIPT_ROOT "results_cuda.txt"
                    Reset-ResultFile -Path $resultFile
                    & "$BIN\gol_cuda.exe" $ROWS $COLS $STEPS $seedValue 0
                    if ($LASTEXITCODE -ne 0) {
                        Write-ERR "Fallo CUDA kernel basico (exit code $LASTEXITCODE)."
                    } elseif (Test-Path $resultFile) {
                        $rec = Get-ResultRecord -FilePath $resultFile
                        Add-UnifiedResult -Path $unifiedPath -Record $rec -SeedValue $seedValue -RunIndex $run -IsWarmup $isWarmup -Kernel "basic" -Gpu $rec.gpu
                    } else {
                        Write-ERR "No se genero results_cuda.txt para kernel basico."
                    }

                    Write-INFO "--- Kernel con shared memory ---"
                    Reset-ResultFile -Path $resultFile
                    & "$BIN\gol_cuda.exe" $ROWS $COLS $STEPS $seedValue 1
                    if ($LASTEXITCODE -ne 0) {
                        Write-ERR "Fallo CUDA kernel shared (exit code $LASTEXITCODE)."
                    } elseif (Test-Path $resultFile) {
                        $rec = Get-ResultRecord -FilePath $resultFile
                        Add-UnifiedResult -Path $unifiedPath -Record $rec -SeedValue $seedValue -RunIndex $run -IsWarmup $isWarmup -Kernel "shared" -Gpu $rec.gpu
                    } else {
                        Write-ERR "No se genero results_cuda.txt para kernel shared."
                    }
                } else {
                    Write-INFO "Binario CUDA no encontrado. Se omite."
                }
            }
        }
    } finally {
        if ($MonitorResources) {
            Stop-ResourceMonitorJob -Job $monitorJob
            if ($monitorPath) { Write-OK "Monitoreo guardado en: $monitorPath" }
        }
    }

    Write-Header "BENCHMARKS COMPLETADOS"
    Write-OK "Resultados guardados en results_*.txt y $unifiedPath"
}
