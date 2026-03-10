// ============================================================
// Juego de la Vida - Paralelismo en GPU con CUDA
// Trabajo Final - Programacion Paralela y Distribuida
// ============================================================
// Estrategia GPU:
//   - Cada thread CUDA calcula UNA celula del grid
//   - Se organiza en bloques 2D (BLOCK_DIM x BLOCK_DIM)
//   - Usamos memoria compartida (shared memory) para cargar
//     una tile con halo (ghost cells) y reducir accesos
//     a memoria global (optimizacion de rendimiento).
// ============================================================
#include <iostream>
#include <vector>
#include <chrono>
#include <fstream>
#include <cstdlib>
#include <cuda_runtime.h>

using namespace std;
using namespace chrono;

#define BLOCK_DIM 16

// ---- Macro de chequeo de errores CUDA ----
#define CUDA_CHECK(call) do { \
    cudaError_t err = (call); \
    if (err != cudaSuccess) { \
        fprintf(stderr, "CUDA error en %s:%d: %s\n", __FILE__, __LINE__, \
                cudaGetErrorString(err)); \
        exit(EXIT_FAILURE); \
    } \
} while(0)

// ---- Kernel basico (sin shared memory) ----
__global__ void golStepBasic(const int* __restrict__ current,
                               int* __restrict__ next,
                               int rows, int cols) {
    int j = blockIdx.x * blockDim.x + threadIdx.x;
    int i = blockIdx.y * blockDim.y + threadIdx.y;

    if (i >= rows || j >= cols) return;

    int count = 0;
    for (int di = -1; di <= 1; di++) {
        for (int dj = -1; dj <= 1; dj++) {
            if (di == 0 && dj == 0) continue;
            int ni = (i + di + rows) % rows;
            int nj = (j + dj + cols) % cols;
            count += current[ni * cols + nj];
        }
    }

    int cell = current[i * cols + j];
    next[i * cols + j] = (cell == 1)
        ? ((count == 2 || count == 3) ? 1 : 0)
        : ((count == 3) ? 1 : 0);
}

// ---- Kernel optimizado con shared memory ----
// Cada bloque carga una tile de (BLOCK_DIM+2) x (BLOCK_DIM+2)
// incluyendo el halo de 1 celda en cada borde.
__global__ void golStepShared(const int* __restrict__ current,
                               int* __restrict__ next,
                               int rows, int cols) {
    // Shared memory: tile con halo
    __shared__ int tile[BLOCK_DIM + 2][BLOCK_DIM + 2];

    int tx = threadIdx.x; // local x dentro del bloque
    int ty = threadIdx.y; // local y dentro del bloque
    int j  = blockIdx.x * BLOCK_DIM + tx;
    int i  = blockIdx.y * BLOCK_DIM + ty;

    // Coordenadas con wrap-around para cargar halo
    int gi = (i + rows) % rows;
    int gj = (j + cols) % cols;

    // Cargar celda principal (offset +1 por el halo)
    tile[ty + 1][tx + 1] = current[gi * cols + gj];

    // Cargar bordes del halo
    if (ty == 0) {
        int ni = (i - 1 + rows) % rows;
        tile[0][tx + 1] = current[ni * cols + gj];
    }
    if (ty == BLOCK_DIM - 1) {
        int ni = (i + 1) % rows;
        tile[BLOCK_DIM + 1][tx + 1] = current[ni * cols + gj];
    }
    if (tx == 0) {
        int nj = (j - 1 + cols) % cols;
        tile[ty + 1][0] = current[gi * cols + nj];
    }
    if (tx == BLOCK_DIM - 1) {
        int nj = (j + 1) % cols;
        tile[ty + 1][BLOCK_DIM + 1] = current[gi * cols + nj];
    }
    // Esquinas del halo
    if (tx == 0 && ty == 0)
        tile[0][0] = current[((i-1+rows)%rows)*cols + (j-1+cols)%cols];
    if (tx == BLOCK_DIM-1 && ty == 0)
        tile[0][BLOCK_DIM+1] = current[((i-1+rows)%rows)*cols + (j+1)%cols];
    if (tx == 0 && ty == BLOCK_DIM-1)
        tile[BLOCK_DIM+1][0] = current[((i+1)%rows)*cols + (j-1+cols)%cols];
    if (tx == BLOCK_DIM-1 && ty == BLOCK_DIM-1)
        tile[BLOCK_DIM+1][BLOCK_DIM+1] = current[((i+1)%rows)*cols + (j+1)%cols];

    __syncthreads();

    if (i >= rows || j >= cols) return;

    // Contar vecinos desde shared memory
    int count = 0;
    for (int di = 0; di <= 2; di++)
        for (int dj = 0; dj <= 2; dj++)
            if (!(di == 1 && dj == 1))
                count += tile[ty + di][tx + dj];

    int cell = tile[ty + 1][tx + 1];
    next[i * cols + j] = (cell == 1)
        ? ((count == 2 || count == 3) ? 1 : 0)
        : ((count == 3) ? 1 : 0);
}

int main(int argc, char* argv[]) {
    int ROWS  = (argc > 1) ? atoi(argv[1]) : 1024;
    int COLS  = (argc > 2) ? atoi(argv[2]) : 1024;
    int STEPS = (argc > 3) ? atoi(argv[3]) : 100;
    int SEED  = (argc > 4) ? atoi(argv[4]) : 42;
    bool USE_SHARED = (argc > 5) ? (atoi(argv[5]) == 1) : true;

    cout << "=== GPU CUDA ===" << endl;

    // Info de la GPU
    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, 0));
    cout << "GPU: " << prop.name << endl;
    cout << "Grid: " << ROWS << "x" << COLS << " | Steps: " << STEPS
         << " | Kernel: " << (USE_SHARED ? "shared memory" : "basico") << endl;

    // Inicializacion en CPU
    srand(SEED);
    int N = ROWS * COLS;
    vector<int> h_grid(N), h_result(N);

    for (int i = 0; i < N; i++)
        h_grid[i] = (rand() % 100 < 30) ? 1 : 0;

    long long alive_start = 0;
    for (int v : h_grid) alive_start += v;

    // Alocar memoria GPU
    int *d_current, *d_next;
    CUDA_CHECK(cudaMalloc(&d_current, N * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_next,    N * sizeof(int)));

    // Copiar datos a GPU
    CUDA_CHECK(cudaMemcpy(d_current, h_grid.data(), N * sizeof(int), cudaMemcpyHostToDevice));

    // Configurar grid de kernels
    dim3 block(BLOCK_DIM, BLOCK_DIM);
    dim3 grid((COLS + BLOCK_DIM - 1) / BLOCK_DIM,
              (ROWS + BLOCK_DIM - 1) / BLOCK_DIM);

    cout << "Bloques: " << grid.x << "x" << grid.y
         << " | Threads por bloque: " << block.x << "x" << block.y << endl;

    // Sincronizar y medir
    CUDA_CHECK(cudaDeviceSynchronize());
    auto t_start = high_resolution_clock::now();

    for (int s = 0; s < STEPS; s++) {
        if (USE_SHARED)
            golStepShared<<<grid, block>>>(d_current, d_next, ROWS, COLS);
        else
            golStepBasic<<<grid, block>>>(d_current, d_next, ROWS, COLS);

        CUDA_CHECK(cudaGetLastError());
        swap(d_current, d_next);
    }

    CUDA_CHECK(cudaDeviceSynchronize());
    auto t_end = high_resolution_clock::now();
    double elapsed = duration<double>(t_end - t_start).count();

    // Copiar resultado de vuelta
    CUDA_CHECK(cudaMemcpy(h_result.data(), d_current, N * sizeof(int), cudaMemcpyDeviceToHost));

    long long alive_end = 0;
    for (int v : h_result) alive_end += v;

    cout << "Celulas vivas al inicio: " << alive_start << endl;
    cout << "Celulas vivas al final:  " << alive_end << endl;
    cout << "Tiempo total: " << elapsed << " s" << endl;
    cout << "Tiempo por paso: " << (elapsed / STEPS) * 1000.0 << " ms" << endl;

    string mode = USE_SHARED ? "cuda_shared" : "cuda_basic";
    ofstream out("results_cuda.txt");
    out << "mode,rows,cols,steps,gpu,time_s,time_per_step_ms,alive_end" << endl;
    out << mode << "," << ROWS << "," << COLS << "," << STEPS << ","
        << prop.name << "," << elapsed << "," << (elapsed / STEPS) * 1000.0
        << "," << alive_end << endl;
    out.close();

    CUDA_CHECK(cudaFree(d_current));
    CUDA_CHECK(cudaFree(d_next));

    return 0;
}
