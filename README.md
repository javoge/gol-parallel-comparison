# gol-parallel-comparison

Comparacion de implementaciones del Juego de la Vida de Conway para analizar distintos paradigmas de ejecucion:

- CPU secuencial
- CPU paralela con OpenMP
- distribuida con MPI
- mixta con MPI + OpenMP
- GPU con CUDA

El objetivo del proyecto es medir rendimiento, comparar tiempos de ejecucion y observar como escala una misma simulacion cuando cambia la estrategia de paralelismo.

## Objetivo

Todas las versiones resuelven el mismo problema: simular una grilla bidimensional donde cada celda vive o muere segun la cantidad de vecinos vivos.

La comparacion busca responder preguntas como:

- cuanto mejora OpenMP frente a la version secuencial
- como impacta dividir el trabajo entre procesos con MPI
- si una version hibrida MPI + OpenMP mejora el aprovechamiento del hardware
- cuanto acelera la GPU con CUDA frente a CPU

## Implementaciones

### 1. Secuencial

Archivo: [`src/gol_sequential.cpp`](src/gol_sequential.cpp)

- ejecuta todo en un solo hilo
- sirve como linea base para comparar
- usa una grilla toroidal, es decir, los bordes "envuelven"

### 2. OpenMP

Archivo: [`src/gol_openmp.cpp`](src/gol_openmp.cpp)

- paraleliza el procesamiento por filas
- cada hilo trabaja sobre una parte de la grilla
- permite comparar speedup en CPU multinucleo

### 3. MPI

Archivo: [`src/gol_mpi.cpp`](src/gol_mpi.cpp)

- divide la grilla por filas entre procesos
- intercambia `ghost rows` entre procesos vecinos antes de cada iteracion
- representa una estrategia distribuida de memoria

### 4. Mixto MPI + OpenMP

Archivo: [`src/gol_mixed.cpp`](src/gol_mixed.cpp)

- usa MPI para repartir trabajo entre procesos
- usa OpenMP dentro de cada proceso para explotar varios hilos
- apunta a un modelo hibrido comun en HPC

### 5. CUDA

Archivo: [`src/gol_cuda.cu`](src/gol_cuda.cu)

- ejecuta la simulacion en GPU
- incluye un kernel basico
- incluye un kernel optimizado con `shared memory`

## Requisitos

El proyecto esta preparado principalmente para Windows con PowerShell.

### Requisitos de compilacion

- Visual Studio 2022 con soporte de C++
- CUDA Toolkit
- Microsoft MPI Runtime
- Microsoft MPI SDK

El script asume que estas herramientas estan disponibles en el sistema y en rutas estandar de Windows.

## Estructura del proyecto

```text
gol-parallel-comparison/
|- src/
|  |- gol_sequential.cpp
|  |- gol_openmp.cpp
|  |- gol_mpi.cpp
|  |- gol_mixed.cpp
|  `- gol_cuda.cu
|- build_and_run.ps1
`- README.md
```

## Compilacion y ejecucion

El archivo principal para automatizar todo es [`build_and_run.ps1`](build_and_run.ps1).

### Compilar y ejecutar benchmarks

```powershell
.\build_and_run.ps1
```

### Compilar solamente

```powershell
.\build_and_run.ps1 -BuildOnly
```

### Ejecutar solamente

```powershell
.\build_and_run.ps1 -RunOnly
```

### Ejecutar con parametros personalizados

```powershell
.\build_and_run.ps1 -ROWS 2048 -COLS 2048 -STEPS 500 -SEED 123
```

## Que mide el benchmark

Cada implementacion reporta metricas como:

- `time_s`: tiempo total de ejecucion
- `time_per_step_ms`: tiempo promedio por iteracion
- `alive_end`: cantidad de celulas vivas al finalizar

La idea es comparar esas metricas entre versiones que resuelven el mismo problema.

## Archivos de salida

Al finalizar una ejecucion, cada programa guarda un archivo de resultados en formato texto con encabezado tipo CSV:

- `results_sequential.txt`
- `results_openmp.txt`
- `results_mpi.txt`
- `results_mixed.txt`
- `results_cuda.txt`
- `results_unified.csv`

Los `results_*.txt` se van sobrescribiendo en cada corrida; el archivo `results_unified.csv` acumula todas las muestras (incluye semilla, run, warmup, hilos/procesos y kernel CUDA).

Opcional: si corres `build_and_run.ps1` con `-MonitorResources`, se genera un CSV con uso de CPU/Memoria y metricas de GPU en `monitors/resource_session_YYYYMMDD_HHMMSS.csv`.

Si ademas agregas `-MonitorPerCore`, se genera otro CSV con uso de CPU por nucleo (CPU logico) en `monitors/resource_per_core_YYYYMMDD_HHMMSS.csv`.

## Ejemplos de comparacion

Con este proyecto se pueden analizar escenarios como:

- secuencial vs OpenMP con 1, 2, 4, 8 o mas hilos
- MPI con distinta cantidad de procesos
- combinaciones hibridas de procesos MPI e hilos OpenMP
- kernel CUDA basico vs kernel CUDA con `shared memory`

## Notas

- la inicializacion de la grilla usa una semilla para reproducibilidad
- la densidad inicial de celdas vivas es aproximadamente 30%
- la logica usa vecindad de Moore de 8 vecinos
- los bordes se manejan con comportamiento toroidal

## Posibles mejoras futuras

- agregar calculo explicito de speedup y eficiencia
- incorporar visualizacion de la grilla
- agregar scripts de graficos y analisis estadistico
- incluir instrucciones para Linux
