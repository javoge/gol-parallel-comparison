# =============================================================
# Makefile - Game of Life: Comparativa de Paradigmas HPC
# Compatible con Linux / Clústeres HPC
# =============================================================
# REQUISITOS:
#   - g++ con soporte OpenMP       (sudo apt install g++)
#   - MPI (mpicxx / mpirun)        (sudo apt install libopenmpi-dev openmpi-bin)
#   - CUDA Toolkit                 (https://developer.nvidia.com/cuda-downloads)
# =============================================================

CXX      = g++
MPICXX   = mpicxx
NVCC     = nvcc

CXXFLAGS = -O2 -std=c++17
OMPFLAGS = -fopenmp
CUDAFLAGS = -O2

SRC_DIR = src
BIN_DIR = bin

# Crear el directorio bin si no existe
$(BIN_DIR):
	mkdir -p $(BIN_DIR)

# --- Targets individuales ---

sequential: $(BIN_DIR)
	$(CXX) $(CXXFLAGS) $(SRC_DIR)/gol_sequential.cpp -o $(BIN_DIR)/gol_sequential

openmp: $(BIN_DIR)
	$(CXX) $(CXXFLAGS) $(OMPFLAGS) $(SRC_DIR)/gol_openmp.cpp -o $(BIN_DIR)/gol_openmp

mpi: $(BIN_DIR)
	$(MPICXX) $(CXXFLAGS) $(SRC_DIR)/gol_mpi.cpp -o $(BIN_DIR)/gol_mpi

mixed: $(BIN_DIR)
	$(MPICXX) $(CXXFLAGS) $(OMPFLAGS) $(SRC_DIR)/gol_mixed.cpp -o $(BIN_DIR)/gol_mixed

cuda: $(BIN_DIR)
	$(NVCC) $(CUDAFLAGS) $(SRC_DIR)/gol_cuda.cu -o $(BIN_DIR)/gol_cuda

# --- Target principal ---
all: sequential openmp mpi mixed cuda

# --- Ejecutar benchmarks rapidos (1024x1024, 100 pasos) ---
run: all
	@echo "\n=== Secuencial ==="
	$(BIN_DIR)/gol_sequential 1024 1024 100 42
	@echo "\n=== OpenMP (4 hilos) ==="
	$(BIN_DIR)/gol_openmp 1024 1024 100 4 42
	@echo "\n=== MPI (4 procesos) ==="
	mpirun -n 4 $(BIN_DIR)/gol_mpi 1024 1024 100 42
	@echo "\n=== Mixto MPI 2proc + OpenMP 2hilos ==="
	mpirun -n 2 $(BIN_DIR)/gol_mixed 1024 1024 100 2 42
	@echo "\n=== CUDA (shared memory) ==="
	$(BIN_DIR)/gol_cuda 1024 1024 100 42 1

# --- Limpieza ---
clean:
	rm -rf $(BIN_DIR)

.PHONY: all sequential openmp mpi mixed cuda run clean
