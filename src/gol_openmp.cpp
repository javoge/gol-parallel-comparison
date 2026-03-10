// ============================================================
// Juego de la Vida - Ejecucion Paralela con OpenMP
// Trabajo Final - Programacion Paralela y Distribuida
// ============================================================
#include <iostream>
#include <vector>
#include <chrono>
#include <fstream>
#include <cstdlib>
#include <omp.h>

using namespace std;
using namespace chrono;

int countNeighbors(const vector<vector<int>>& grid, int i, int j, int rows, int cols) {
    int count = 0;
    for (int di = -1; di <= 1; di++) {
        for (int dj = -1; dj <= 1; dj++) {
            if (di == 0 && dj == 0) continue;
            int ni = (i + di + rows) % rows;
            int nj = (j + dj + cols) % cols;
            count += grid[ni][nj];
        }
    }
    return count;
}

void stepParallel(const vector<vector<int>>& current, vector<vector<int>>& next, int rows, int cols) {
    // Paralelizamos el loop externo: cada hilo procesa filas distintas
    #pragma omp parallel for schedule(static)
    for (int i = 0; i < rows; i++) {
        for (int j = 0; j < cols; j++) {
            int neighbors = countNeighbors(current, i, j, rows, cols);
            if (current[i][j] == 1) {
                next[i][j] = (neighbors == 2 || neighbors == 3) ? 1 : 0;
            } else {
                next[i][j] = (neighbors == 3) ? 1 : 0;
            }
        }
    }
}

int main(int argc, char* argv[]) {
    int ROWS      = (argc > 1) ? atoi(argv[1]) : 1024;
    int COLS      = (argc > 2) ? atoi(argv[2]) : 1024;
    int STEPS     = (argc > 3) ? atoi(argv[3]) : 100;
    int THREADS   = (argc > 4) ? atoi(argv[4]) : omp_get_max_threads();
    int SEED      = (argc > 5) ? atoi(argv[5]) : 42;

    omp_set_num_threads(THREADS);

    cout << "=== PARALELO (OpenMP) ===" << endl;
    cout << "Grid: " << ROWS << "x" << COLS << " | Steps: " << STEPS
         << " | Hilos: " << THREADS << endl;

    srand(SEED);
    vector<vector<int>> grid(ROWS, vector<int>(COLS));
    vector<vector<int>> next_grid(ROWS, vector<int>(COLS));

    for (int i = 0; i < ROWS; i++)
        for (int j = 0; j < COLS; j++)
            grid[i][j] = (rand() % 100 < 30) ? 1 : 0;

    long long alive_start = 0;
    for (int i = 0; i < ROWS; i++)
        for (int j = 0; j < COLS; j++)
            alive_start += grid[i][j];

    auto t_start = high_resolution_clock::now();

    for (int s = 0; s < STEPS; s++) {
        stepParallel(grid, next_grid, ROWS, COLS);
        swap(grid, next_grid);
    }

    auto t_end = high_resolution_clock::now();
    double elapsed = duration<double>(t_end - t_start).count();

    long long alive_end = 0;
    for (int i = 0; i < ROWS; i++)
        for (int j = 0; j < COLS; j++)
            alive_end += grid[i][j];

    cout << "Celulas vivas al inicio: " << alive_start << endl;
    cout << "Celulas vivas al final:  " << alive_end << endl;
    cout << "Tiempo total: " << elapsed << " s" << endl;
    cout << "Tiempo por paso: " << (elapsed / STEPS) * 1000.0 << " ms" << endl;
    cout << "Speedup estimado vs secuencial: (ver comparativa)" << endl;

    ofstream out("results_openmp.txt");
    out << "mode,rows,cols,steps,threads,time_s,time_per_step_ms,alive_end" << endl;
    out << "openmp," << ROWS << "," << COLS << "," << STEPS << "," << THREADS << ","
        << elapsed << "," << (elapsed / STEPS) * 1000.0 << "," << alive_end << endl;
    out.close();

    return 0;
}
