import os
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

def main():
    csv_file = 'results_unified.csv'
    if not os.path.exists(csv_file):
        print(f"Error: {csv_file} not found.")
        print("Por favor, corre primero './build_and_run.ps1' para generar resultados.")
        return

    df = pd.read_csv(csv_file)
    
    # Descartar ejecuciones de calentamiento (warmup)
    if 'is_warmup' in df.columns:
        df = df[df['is_warmup'] == 0]
    
    if df.empty:
        print("No hay datos reales válidos (sin contar warmup) en el CSV.")
        return
        
    print("Generando gráficos basados en los siguientes modos:", df['mode'].unique())

    # --- 1. Comparativa Global (Mínimo Tiempo / Media por Modelo) ---
    plt.figure(figsize=(10, 6))
    
    # Diccionario para almacenar el mejor tiempo promedio por arquitectura
    best_times = {}
    
    seq_df = df[df['mode'] == 'sequential']
    if not seq_df.empty:
        best_times['Secuencial'] = seq_df['time_s'].mean()
        
    omp_df = df[df['mode'] == 'openmp']
    if not omp_df.empty:
        best_threads = omp_df.groupby('threads')['time_s'].mean().idxmin()
        best_times[f'OpenMP\n({int(best_threads)} Hilos)'] = omp_df[df['threads'] == best_threads]['time_s'].mean()
        
    mpi_df = df[df['mode'] == 'mpi']
    if not mpi_df.empty:
        best_procs = mpi_df.groupby('procs')['time_s'].mean().idxmin()
        best_times[f'MPI\n({int(best_procs)} Procs)'] = mpi_df[df['procs'] == best_procs]['time_s'].mean()
        
    mixed_df = df[df['mode'] == 'mixed']
    if not mixed_df.empty:
        best_mixed = mixed_df.groupby(['procs', 'threads'])['time_s'].mean().idxmin()
        best_times[f'Mixto\n({int(best_mixed[0])}P+{int(best_mixed[1])}H)'] = mixed_df[(df['procs'] == best_mixed[0]) & (df['threads'] == best_mixed[1])]['time_s'].mean()
        
    cuda_b_df = df[df['mode'] == 'cuda_basic']
    if not cuda_b_df.empty:
        best_times['CUDA (Básico)'] = cuda_b_df['time_s'].mean()
        
    cuda_s_df = df[df['mode'] == 'cuda_shared']
    if not cuda_s_df.empty:
        best_times['CUDA (Compartido)'] = cuda_s_df['time_s'].mean()

    if not best_times:
        print("Los datos son insuficientes para diagramar.")
        return

    # Gráfico de barras general
    names = list(best_times.keys())
    values = list(best_times.values())
    
    colors = sns.color_palette("magma", len(names))
    bars = plt.bar(names, values, color=colors)
    plt.ylabel('Tiempo de Ejecución Promedio (segundos)')
    plt.title('Comparativa General de Paradigmas HPC - Game of Life')
    plt.xticks(rotation=20)
    
    # Renderizar valor numérico arriba de cada barra
    for bar in bars:
        yval = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2.0, yval + (max(values)*0.01), f'{yval:.4f}s', va='bottom', ha='center', fontsize=9, fontweight='bold')
        
    plt.tight_layout()
    plt.savefig('grafico_comparativa.png', dpi=150)
    print("- Se ha guardado correctamente 'grafico_comparativa.png'")
    
    # --- 2. Curva de Escalabilidad (Speedup) OpenMP ---
    if 'Secuencial' in best_times and not omp_df.empty:
        seq_time = best_times['Secuencial']
        
        # Agrupar por cantidad de hilos
        omp_grouped = omp_df.groupby('threads')['time_s'].mean().reset_index()
        omp_grouped = omp_grouped.sort_values('threads')
        
        # Calcular Speedup = Tiempo secuencial base / Tiempo n-threads
        omp_grouped['speedup'] = seq_time / omp_grouped['time_s']
        
        plt.figure(figsize=(8, 5))
        
        # Curva de medición real
        plt.plot(omp_grouped['threads'], omp_grouped['speedup'], marker='o', linestyle='-', color='indigo', linewidth=2, markersize=8, label='Speedup Real (OpenMP)')
        
        # Curva de Amdahl ideal (Speedup = N)
        plt.plot(omp_grouped['threads'], omp_grouped['threads'], linestyle='--', color='gray', label='Speedup Lineal Ideal')
        
        plt.xlabel('Número de Hilos Procesadores')
        plt.ylabel('Speedup (Aceleración Relativa)')
        plt.title('Curva de Escalabilidad - OpenMP')
        plt.legend()
        plt.grid(True, linestyle=':', alpha=0.7)
        plt.tight_layout()
        plt.savefig('grafico_speedup_openmp.png', dpi=150)
        print("- Se ha guardado correctamente 'grafico_speedup_openmp.png'")
        
if __name__ == "__main__":
    main()
