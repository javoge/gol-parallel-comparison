# extreme_stress_suite.ps1
# Corrida masiva de 24h para benchmark final

Write-Host "Iniciando suite de stress extremo de 24h..." -ForegroundColor Cyan

# 1. 8192 - Todas las versiones (1000 pasos, 1 repeticion)
Write-Host "Paso 1: 8192 x 8192 (All, 1000 steps, 1 Repeat)" -ForegroundColor Yellow
.\build_and_run.ps1 -Rows 8192 -Cols 8192 -Steps 1000 -Repeats 1 -MonitorResources -NoGraph

# 2. 16384 - Todas las versiones (1000 pasos, 1 repeticion)
Write-Host "Paso 2: 16384 x 16384 (All, 1000 steps, 1 Repeat)" -ForegroundColor Yellow
.\build_and_run.ps1 -Rows 16384 -Cols 16384 -Steps 1000 -Repeats 1 -MonitorResources -NoGraph

# 3. 32768 - Todas las versiones (1000 pasos, 1 repeticion) - ADVERTENCIA: Alto uso de CPU por horas
Write-Host "Paso 3: 32768 x 32768 (All, 1000 steps, 1 Repeat) - THE BEAST" -ForegroundColor Red
.\build_and_run.ps1 -Rows 32768 -Cols 32768 -Steps 1000 -Repeats 1 -MonitorResources -NoGraph

# 4. 65536 - SOLO CUDA (5000 pasos) - GPU Stress MAX
Write-Host "Paso 4: 65536 x 65536 (CUDA Only, 5000 steps) - GPU THERMAL SQUEEZE" -ForegroundColor Magenta
.\build_and_run.ps1 -Variants cuda_basic,cuda_shared -Rows 65536 -Cols 65536 -Steps 5000 -Repeats 1 -MonitorResources -NoGraph

Write-Host "Benchmark masivo finalizado." -ForegroundColor Green
