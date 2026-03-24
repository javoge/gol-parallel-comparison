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

## Decisiones de implementacion

### Memoria plana 1D

Todas las versiones utilizan vectores unidimensionales (`vector<uint8_t>`) en lugar de matrices anidadas (`vector<vector<int>>`). Esto garantiza memoria contigua y mejora significativamente el aprovechamiento de la cache del procesador.

El acceso a la celda `(i, j)` se realiza como `grid[i * COLS + j]`.

### Tipo de dato `uint8_t`

Cada celda se almacena como un entero sin signo de 8 bits. Esto reduce el consumo de RAM y VRAM en un 75% respecto a usar `int` (4 bytes por celda), y disminuye el ancho de banda necesario en las transferencias MPI y CUDA.

### Generador aleatorio `mt19937`

La inicializacion del tablero usa `std::mt19937` de C++11 en lugar del antiguo `rand()` de C. Esto garantiza que la misma semilla produzca exactamente el mismo tablero en cualquier compilador o sistema operativo, lo cual es esencial para comparar resultados entre paradigmas.

## Requisitos

### Windows (PowerShell)

- Visual Studio 2022 con soporte de C++
- CUDA Toolkit
- Microsoft MPI Runtime
- Microsoft MPI SDK

### Linux / HPC

- `g++` con soporte de C++17 y OpenMP
- OpenMPI: `sudo apt install libopenmpi-dev openmpi-bin`
- CUDA Toolkit: [developer.nvidia.com/cuda-downloads](https://developer.nvidia.com/cuda-downloads)

## Estructura del proyecto

```text
gol-parallel-comparison/
|- src/
|  |- gol_sequential.cpp
|  |- gol_openmp.cpp
|  |- gol_mpi.cpp
|  |- gol_mixed.cpp
|  `- gol_cuda.cu
|- build_and_run.ps1   (Windows)
|- Makefile            (Linux / HPC)
|- plot_results.py     (Analisis y graficos)
`- README.md
```

## Compilacion y ejecucion

### Windows (PowerShell)

El archivo principal para automatizar todo es [`build_and_run.ps1`](build_and_run.ps1).

```powershell
# Compilar y ejecutar benchmarks
.\build_and_run.ps1

# Solo compilar
.\build_and_run.ps1 -BuildOnly

# Solo ejecutar
.\build_and_run.ps1 -RunOnly

# Parametros personalizados
.\build_and_run.ps1 -ROWS 2048 -COLS 2048 -STEPS 500 -SEED 123
```

### Linux / HPC (Makefile)

```bash
# Compilar todo
make all

# Compilar una variante especifica
make sequential
make openmp
make mpi
make mixed
make cuda

# Compilar y ejecutar benchmarks rapidos
make run

# Limpiar binarios
make clean
```

## Analisis y graficos

El script [`plot_results.py`](plot_results.py) procesa el archivo `results_unified.csv` generado por el benchmark y produce:

- **`grafico_comparativa.png`**: comparativa general de tiempo de ejecucion entre todos los paradigmas
- **`grafico_speedup_openmp.png`**: curva de aceleracion (speedup) de OpenMP vs cantidad de hilos

### Requisitos

```bash
pip install pandas matplotlib seaborn
```

### Uso

```bash
python plot_results.py
```

## Que mide el benchmark

Cada implementacion reporta metricas como:

- `time_s`: tiempo total de ejecucion
- `time_per_step_ms`: tiempo promedio por iteracion
- `alive_end`: cantidad de celulas vivas al finalizar

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

## Notas

- la inicializacion de la grilla usa `std::mt19937` con semilla para reproducibilidad determinista en cualquier plataforma
- la densidad inicial de celdas vivas es aproximadamente 30%
- la logica usa vecindad de Moore de 8 vecinos
- los bordes se manejan con comportamiento toroidal
- la memoria se almacena como arreglos planos 1D de tipo `uint8_t`
