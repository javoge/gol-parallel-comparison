// ============================================================
// Juego de la Vida - Ejecucion Secuencial
// Trabajo Final - Programacion Paralela y Distribuida
// ============================================================
#include <iostream>
#include <vector>
#include <chrono>
#include <fstream>
#include <string>
#include <cstdlib>

using namespace std;
using namespace chrono;

// Cuenta vecinos vivos de la celda (i,j)
int countNeighbors(const vector<vector<int>>& grid, int i, int j, int rows, int cols) {
    int count = 0;
    for (int di = -1; di <= 1; di++) {
        for (int dj = -1; dj <= 1; dj++) {
            if (di == 0 && dj == 0) continue;
            int ni = (i + di + rows) % rows; // wrap-around toroidal
            int nj = (j + dj + cols) % cols;
            count += grid[ni][nj];
        }
    }
    return count;
}

// Ejecuta un paso de simulacion
void step(const vector<vector<int>>& current, vector<vector<int>>& next, int rows, int cols) {
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
    int SEED      = (argc > 4) ? atoi(argv[4]) : 42;

    cout << "=== SECUENCIAL ===" << endl;
    cout << "Grid: " << ROWS << "x" << COLS << " | Steps: " << STEPS << endl;

    // Inicializacion aleatoria
    srand(SEED);
    vector<vector<int>> grid(ROWS, vector<int>(COLS));
    vector<vector<int>> next_grid(ROWS, vector<int>(COLS));

    for (int i = 0; i < ROWS; i++)
        for (int j = 0; j < COLS; j++)
            grid[i][j] = (rand() % 100 < 30) ? 1 : 0; // 30% vivas

    long long alive_start = 0;
    for (int i = 0; i < ROWS; i++)
        for (int j = 0; j < COLS; j++)
            alive_start += grid[i][j];

    // Simulacion
    auto t_start = high_resolution_clock::now();

    for (int s = 0; s < STEPS; s++) {
        step(grid, next_grid, ROWS, COLS);
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

    // Guardar resultado para comparativas
    ofstream out("results_sequential.txt");
    out << "mode,rows,cols,steps,time_s,time_per_step_ms,alive_end" << endl;
    out << "sequential," << ROWS << "," << COLS << "," << STEPS << ","
        << elapsed << "," << (elapsed / STEPS) * 1000.0 << "," << alive_end << endl;
    out.close();

    return 0;
}
