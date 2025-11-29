#!/usr/bin/env python3
"""
Тестирование экспорта MAT файлов из HSIView
"""
import numpy as np
import scipy.io as sio
import sys

def test_mat_file(filepath):
    """Проверяет корректность экспортированного MAT файла"""
    print(f"📂 Тестирование: {filepath}")
    print("=" * 60)
    
    try:
        mat = sio.loadmat(filepath)
        
        print(f"\n✅ Файл успешно загружен")
        print(f"\nПеременные в файле:")
        for key in mat.keys():
            if not key.startswith('__'):
                data = mat[key]
                if isinstance(data, np.ndarray):
                    print(f"  📊 {key}:")
                    print(f"     Shape: {data.shape}")
                    print(f"     Dtype: {data.dtype}")
                    print(f"     Min: {data.min():.6f}")
                    print(f"     Max: {data.max():.6f}")
                    print(f"     Mean: {data.mean():.6f}")
                    
                    if data.ndim == 3:
                        print(f"\n  🔍 Проверка на полосатость:")
                        
                        channel_0 = data[:, :, 0]
                        
                        print(f"     Первые 5x5 элементов канала 0:")
                        print(f"     {channel_0[:5, :5]}")
                        
                        row_variance = np.var(channel_0, axis=1)
                        col_variance = np.var(channel_0, axis=0)
                        
                        print(f"\n     Дисперсия по строкам (mean): {row_variance.mean():.6f}")
                        print(f"     Дисперсия по столбцам (mean): {col_variance.mean():.6f}")
                        
                        if row_variance.mean() < 1e-10 or col_variance.mean() < 1e-10:
                            print(f"     ⚠️  ПРЕДУПРЕЖДЕНИЕ: Низкая дисперсия - возможна полосатость!")
                        else:
                            print(f"     ✅ Дисперсия в норме")
                    
                    elif data.ndim == 2:
                        print(f"\n  📏 Двумерный массив (вероятно wavelengths)")
                        if data.shape[1] == 1:
                            print(f"     Первые 10 значений:")
                            for i in range(min(10, data.shape[0])):
                                print(f"       [{i}]: {data[i, 0]:.4f}")
        
        print(f"\n{'=' * 60}")
        print(f"✅ ТЕСТ ПРОЙДЕН")
        
    except Exception as e:
        print(f"\n❌ ОШИБКА: {e}")
        sys.exit(1)

def compare_with_original(original_file, exported_file, variable_name="hypercube"):
    """Сравнивает оригинальный и экспортированный MAT файлы"""
    print(f"\n📊 Сравнение файлов:")
    print("=" * 60)
    
    try:
        orig = sio.loadmat(original_file)
        exported = sio.loadmat(exported_file)
        
        orig_keys = [k for k in orig.keys() if not k.startswith('__')]
        exp_keys = [k for k in exported.keys() if not k.startswith('__')]
        
        print(f"Оригинал: {orig_keys}")
        print(f"Экспорт:  {exp_keys}")
        
        if variable_name in exported:
            exp_data = exported[variable_name]
            
            if len(orig_keys) > 0:
                orig_data = orig[orig_keys[0]]
                
                print(f"\n🔍 Сравнение данных:")
                print(f"  Оригинал: shape={orig_data.shape}, dtype={orig_data.dtype}")
                print(f"  Экспорт:  shape={exp_data.shape}, dtype={exp_data.dtype}")
                
                if orig_data.shape == exp_data.shape:
                    print(f"  ✅ Размеры совпадают")
                    
                    if np.allclose(orig_data, exp_data, rtol=1e-5):
                        print(f"  ✅ Данные идентичны (с учетом погрешности)")
                    else:
                        diff = np.abs(orig_data - exp_data)
                        print(f"  ⚠️  Данные отличаются:")
                        print(f"     Max diff: {diff.max():.6e}")
                        print(f"     Mean diff: {diff.mean():.6e}")
                else:
                    print(f"  ❌ Размеры не совпадают!")
        
        print(f"{'=' * 60}")
        
    except Exception as e:
        print(f"❌ Ошибка сравнения: {e}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 test_mat_export.py <exported.mat> [original.mat]")
        print("\nПримеры:")
        print("  python3 test_mat_export.py exported_hypercube.mat")
        print("  python3 test_mat_export.py exported.mat original.mat")
        sys.exit(1)
    
    exported_file = sys.argv[1]
    
    test_mat_file(exported_file)
    
    if len(sys.argv) > 2:
        original_file = sys.argv[2]
        compare_with_original(original_file, exported_file)

if __name__ == "__main__":
    main()


