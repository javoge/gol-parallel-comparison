// ============================================================
// Juego de la Vida - Ejecucion Distribuida con MPI
// Trabajo Final - Programacion Paralela y Distribuida
// ============================================================
// Estrategia: descomposicion por filas.
// Cada proceso MPI maneja un subconjunto de filas del grid.
// Se intercambian "ghost rows" (filas fantasma) con vecinos
// antes de cada paso para calcular correctamente los bordes.
// ============================================================
#include <iostream>
#include <vector>
#include <chrono>
#include <fstream>
#include <cstdlib>
#include <mpi.h>

using namespace std;
using namespace chrono;

int countNeighborsLocal(const vector<int>& flat, int i, int j,
                         int local_rows, int cols) {
    // flat tiene ghost rows: fila 0 = ghost superior, filas 1..local_rows = datos
    // fila local_rows+1 = ghost inferior
    int count = 0;
    int total_rows = local_rows + 2; // incluyendo ghost rows
    for (int di = -1; di <= 1; di++) {
        for (int dj = -1; dj <= 1; dj++) {
            if (di == 0 && dj == 0) continue;
            int ni = i + di;
            int nj = (j + dj + cols) % cols;
            if (ni >= 0 && ni < total_rows)
                count += flat[ni * cols + nj];
        }
    }
    return count;
}

int main(int argc, char* argv[]) {
    MPI_Init(&argc, &argv);

    int rank, nprocs;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &nprocs);

    int ROWS  = (argc > 1) ? atoi(argv[1]) : 1024;
    int COLS  = (argc > 2) ? atoi(argv[2]) : 1024;
    int STEPS = (argc > 3) ? atoi(argv[3]) : 100;
    int SEED  = (argc > 4) ? atoi(argv[4]) : 42;

    if (rank == 0) {
        cout << "=== DISTRIBUIDO (MPI) ===" << endl;
        cout << "Grid: " << ROWS << "x" << COLS << " | Steps: " << STEPS
             << " | Procesos: " << nprocs << endl;
    }

    // Distribucion de filas entre procesos
    int base_rows = ROWS / nprocs;
    int extra     = ROWS % nprocs;
    int local_rows = base_rows + (rank < extra ? 1 : 0);

    // Calcular desplazamientos para Scatterv/Gatherv
    vector<int> sendcounts(nprocs), displs(nprocs);
    int offset = 0;
    for (int p = 0; p < nprocs; p++) {
        int r = base_rows + (p < extra ? 1 : 0);
        sendcounts[p] = r * COLS;
        displs[p]     = offset;
        offset       += r * COLS;
    }

    // Grid completo solo en rank 0
    vector<int> full_grid;
    if (rank == 0) {
        full_grid.resize(ROWS * COLS);
        srand(SEED);
        for (int i = 0; i < ROWS * COLS; i++)
            full_grid[i] = (rand() % 100 < 30) ? 1 : 0;
    }

    // Buffer local con ghost rows (1 arriba, 1 abajo)
    int total_buf = (local_rows + 2) * COLS;
    vector<int> local(total_buf, 0);
    vector<int> local_next(total_buf, 0);

    // Distribuir grid a todos los procesos
    MPI_Scatterv(full_grid.data(), sendcounts.data(), displs.data(), MPI_INT,
                 &local[COLS], local_rows * COLS, MPI_INT, 0, MPI_COMM_WORLD);

    int prev_rank = (rank - 1 + nprocs) % nprocs;
    int next_rank = (rank + 1) % nprocs;

    MPI_Barrier(MPI_COMM_WORLD);
    double t_start = MPI_Wtime();

    for (int s = 0; s < STEPS; s++) {
        // Intercambiar ghost rows con vecinos
        // Enviar primera fila real al proceso anterior, recibir su ultima
        MPI_Sendrecv(&local[COLS],                    COLS, MPI_INT, prev_rank, 0,
                     &local[(local_rows + 1) * COLS],  COLS, MPI_INT, next_rank, 0,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);

        // Enviar ultima fila real al proceso siguiente, recibir su primera
        MPI_Sendrecv(&local[local_rows * COLS],  COLS, MPI_INT, next_rank, 1,
                     &local[0],                  COLS, MPI_INT, prev_rank, 1,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);

        // Calcular paso (solo filas reales: indices 1..local_rows)
        for (int i = 1; i <= local_rows; i++) {
            for (int j = 0; j < COLS; j++) {
                int neighbors = countNeighborsLocal(local, i, j, local_rows, COLS);
                int cell = local[i * COLS + j];
                local_next[i * COLS + j] = (cell == 1)
                    ? ((neighbors == 2 || neighbors == 3) ? 1 : 0)
                    : ((neighbors == 3) ? 1 : 0);
            }
        }
        swap(local, local_next);
    }

    MPI_Barrier(MPI_COMM_WORLD);
    double elapsed = MPI_Wtime() - t_start;

    // Contar celulas locales vivas
    long long local_alive = 0;
    for (int i = 1; i <= local_rows; i++)
        for (int j = 0; j < COLS; j++)
            local_alive += local[i * COLS + j];

    long long total_alive = 0;
    MPI_Reduce(&local_alive, &total_alive, 1, MPI_LONG_LONG, MPI_SUM, 0, MPI_COMM_WORLD);

    if (rank == 0) {
        cout << "Celulas vivas al final: " << total_alive << endl;
        cout << "Tiempo total: " << elapsed << " s" << endl;
        cout << "Tiempo por paso: " << (elapsed / STEPS) * 1000.0 << " ms" << endl;

        ofstream out("results_mpi.txt");
        out << "mode,rows,cols,steps,procs,time_s,time_per_step_ms,alive_end" << endl;
        out << "mpi," << ROWS << "," << COLS << "," << STEPS << "," << nprocs << ","
            << elapsed << "," << (elapsed / STEPS) * 1000.0 << "," << total_alive << endl;
        out.close();
    }

    MPI_Finalize();
    return 0;
}
