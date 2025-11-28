#!/usr/bin/env python3
"""
Диагностика MAT файла
"""

import scipy.io as sio
import numpy as np
import sys

if len(sys.argv) < 2:
    print("Usage: python3 inspect_mat_file.py <file.mat>")
    sys.exit(1)

filepath = sys.argv[1]
print(f"Анализ MAT файла: {filepath}\n")

try:
    print("="*70)
    print("1. ЗАГРУЗКА ФАЙЛА")
    print("="*70)
    
    mat = sio.loadmat(filepath)
    
    print(f"Ключи в файле: {list(mat.keys())}")
    print()
    
    # Фильтруем служебные ключи
    data_keys = [k for k in mat.keys() if not k.startswith('__')]
    print(f"Данные (без служебных): {data_keys}")
    
    print()
    print("="*70)
    print("2. АНАЛИЗ ПЕРЕМЕННЫХ")
    print("="*70)
    
    for key in data_keys:
        var = mat[key]
        print(f"\nПеременная '{key}':")
        print(f"  Type: {type(var)}")
        print(f"  Dtype: {var.dtype}")
        print(f"  Shape: {var.shape}")
        print(f"  Ndim: {var.ndim}")
        
        if isinstance(var, np.ndarray):
            print(f"  Range: [{var.min()}, {var.max()}]")
            print(f"  Mean: {var.mean():.4f}")
            print(f"  C_CONTIGUOUS: {var.flags['C_CONTIGUOUS']}")
            print(f"  F_CONTIGUOUS: {var.flags['F_CONTIGUOUS']}")
            
            # Если 3D, покажем какая ось вероятно каналы
            if var.ndim == 3:
                d0, d1, d2 = var.shape
                print(f"\n  Интерпретация 3D:")
                if d0 < d1 and d0 < d2:
                    print(f"    Вероятно (C, H, W): C={d0}, H={d1}, W={d2}")
                elif d2 < d0 and d2 < d1:
                    print(f"    Вероятно (H, W, C): H={d0}, W={d1}, C={d2}")
                elif d1 < d0 and d1 < d2:
                    print(f"    Вероятно (H, C, W): H={d0}, C={d1}, W={d2}")
                else:
                    print(f"    Неоднозначно: {d0} × {d1} × {d2}")
    
    print()
    print("="*70)
    print("3. ЧТО ИЩЕТ НАШ КОД")
    print("="*70)
    
    print("\nНаш MatHelper.c ищет переменную с 3D shape (rank==3).")
    print("Критерии:")
    print("  - ndim = 3")
    print("  - dtype: double (MAT_C_DOUBLE) или single (MAT_C_SINGLE)")
    print("  - class_type: MAT_C_DOUBLE или MAT_C_SINGLE")
    
    # Найдем подходящие переменные
    candidates = []
    for key in data_keys:
        var = mat[key]
        if isinstance(var, np.ndarray) and var.ndim == 3:
            if var.dtype in [np.float32, np.float64]:
                candidates.append(key)
    
    print(f"\nПодходящие переменные (3D, float): {candidates}")
    
    if not candidates:
        print("\n⚠️  НЕ НАЙДЕНО ПОДХОДЯЩИХ ПЕРЕМЕННЫХ!")
        print("\nВозможные причины:")
        print("  1. Нет 3D массивов")
        print("  2. Данные не float32/float64")
        print("  3. Структура файла нестандартная")
        
        # Покажем все переменные
        print("\nВсе переменные в файле:")
        for key in data_keys:
            var = mat[key]
            print(f"  '{key}': shape={var.shape}, dtype={var.dtype}")
    else:
        print(f"\n✅ Найдено {len(candidates)} подходящих переменных")
        print("Наш код должен загрузить первую подходящую.")
        
        # Покажем детали первой
        first_key = candidates[0]
        first_var = mat[first_key]
        print(f"\nПервая переменная '{first_key}':")
        print(f"  Shape: {first_var.shape}")
        print(f"  Dtype: {first_var.dtype}")
        print(f"  Size: {first_var.nbytes / (1024**2):.1f} МБ")
    
    print()
    print("="*70)
    print("4. ВЕРСИЯ MAT ФАЙЛА")
    print("="*70)
    
    # Проверим версию
    if '__version__' in mat:
        print(f"MAT version: {mat['__version__']}")
    if '__header__' in mat:
        print(f"Header: {mat['__header__']}")
    
except Exception as e:
    print(f"\n❌ ОШИБКА при загрузке файла:")
    print(f"   {e}")
    import traceback
    traceback.print_exc()
    
    print("\n" + "="*70)
    print("ВОЗМОЖНЫЕ ПРИЧИНЫ")
    print("="*70)
    print("1. Файл поврежден")
    print("2. Несовместимая версия MAT (v7.3 HDF5)")
    print("3. Файл не является MAT файлом")
    print("4. Недостаточно прав на чтение")


