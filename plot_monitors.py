import pandas as pd
import matplotlib.pyplot as plt
import glob
import os

def main():
    # Buscar el ultimo archivo de sesion generado
    session_files = glob.glob(os.path.join('monitors', 'resource_session_*.csv'))
    if not session_files:
        print("No se encontraron archivos resource_session_*.csv en monitors/")
        return
    
    latest_session = max(session_files, key=os.path.getctime)
    print(f"Leyendo datos globales de: {latest_session}")
    
    df_session = pd.read_csv(latest_session)

    # Forzar conversión robusta a float lidiando con cualquier configuración regional (comas o puntos)
    cols_to_float = ['cpu_total_pct', 'gpu_power_w', 'gpu_util_pct', 'gpu_mem_util_pct', 'gpu_mem_used_mb', 'gpu_temp_c']
    for col in cols_to_float:
        df_session[col] = df_session[col].astype(str).str.replace(',', '.').astype(float)

    df_session['timestamp'] = pd.to_datetime(df_session['timestamp']).dt.tz_localize(None)
    
    # Crear un eje X en segundos partiendo del instante cero de la prueba
    df_session['time_s'] = (df_session['timestamp'] - df_session['timestamp'].iloc[0]).dt.total_seconds()
    
    # ----- LECTURA DE RESULTADOS PARA MARCAR PARADIGMAS -----
    df_results = pd.read_csv('results_unified.csv')
    df_results['timestamp'] = pd.to_datetime(df_results['timestamp']).dt.tz_localize(None)
    df_results['start_time'] = df_results.apply(lambda row: row['timestamp'] - pd.Timedelta(seconds=row['time_s']), axis=1)
    
    # Eje X base
    t0 = df_session['timestamp'].iloc[0]
    
    # Colores por paradigma
    p_colors = {
        'sequential': 'gray',
        'openmp': 'cyan',
        'mpi': 'green',
        'mixed': 'orange',
        'cuda_basic': 'purple',
        'cuda_shared': 'magenta'
    }

    # ----- 1. GRAFICO BÁSICO: CPU vs GPU -----
    fig, ax = plt.subplots(figsize=(12, 6))
    ax.plot(df_session['time_s'], df_session['cpu_total_pct'], label='Uso Total de CPU (%)', color='blue', linewidth=2)
    ax.plot(df_session['time_s'], df_session['gpu_util_pct'], label='Uso de Procesamiento GPU (%)', color='lime', linewidth=2)
    
    # Marcas para rellenar visualmente el area
    ax.fill_between(df_session['time_s'], df_session['cpu_total_pct'], alpha=0.1, color='blue')
    ax.fill_between(df_session['time_s'], df_session['gpu_util_pct'], alpha=0.1, color='lime')

    # Dibujar las franjas de fondo según el paradigma
    drawn_labels = set()
    for _, row in df_results.iterrows():
        x_start = (row['start_time'] - t0).total_seconds()
        x_end = (row['timestamp'] - t0).total_seconds()
        
        # Filtrar solo los que cayeron en la ventana temporal de este monitoreo
        if x_end > 0 and x_start < df_session['time_s'].max():
            mode = row['mode']
            c = p_colors.get(mode, 'red')
            lbl = mode if mode not in drawn_labels else ""
            ax.axvspan(max(0, x_start), min(df_session['time_s'].max(), x_end), color=c, alpha=0.15, label=lbl)
            if lbl:
                drawn_labels.add(mode)

    ax.set_title('Comparativa de Carga y Paradigmas Activos: CPU vs GPU', fontsize=14)
    ax.set_xlabel('Evolución del tiempo (segundos)')
    ax.set_ylabel('Porcentaje de Uso (%)')
    ax.set_ylim(0, 105)
    ax.grid(True, linestyle='--', alpha=0.6)
    ax.legend(loc='upper right', bbox_to_anchor=(1.15, 1))
    plt.tight_layout()
    
    plt.savefig('grafico_monitores_carga.png', dpi=150)
    print("- Guardado: grafico_monitores_carga.png")
    
    # ----- 2. GRAFICO AVANZADO: VRAM y TERMICAS (Opcional) -----
    fig, ax1 = plt.subplots(figsize=(10, 5))
    
    ax1.set_xlabel('Tiempo (segundos)')
    ax1.set_ylabel('Consumo Eléctrico GPU (Watts)', color='tab:red')
    ax1.plot(df_session['time_s'], df_session['gpu_power_w'], color='tab:red', linewidth=2, label='Watts')
    ax1.tick_params(axis='y', labelcolor='tab:red')
    
    ax2 = ax1.twinx()  
    ax2.set_ylabel('Memoria de Video (MB)', color='tab:purple')
    ax2.plot(df_session['time_s'], df_session['gpu_mem_used_mb'], color='tab:purple', linewidth=2, linestyle='--', label='VRAM MB')
    ax2.tick_params(axis='y', labelcolor='tab:purple')

    # Relleno de temperatura para dar un contexto termal
    ax1.fill_between(df_session['time_s'], df_session['gpu_temp_c'], alpha=0.15, color='orange', label='Temp °C')
    
    plt.title('Salud y Consumo Físico de la Tarjeta Gráfica en CUDA', fontsize=14)
    fig.tight_layout()
    
    plt.savefig('grafico_monitores_fisicos.png', dpi=150)
    print("- Guardado: grafico_monitores_fisicos.png")

if __name__ == "__main__":
    main()
