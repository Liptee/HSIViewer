#!/usr/bin/env python3
"""
Скрипт для создания тестовых .npy файлов для HSIView
"""

import numpy as np
import os

def create_test_files():
    """Создает набор тестовых .npy файлов с различными параметрами"""
    
    output_dir = "test_npy_files"
    os.makedirs(output_dir, exist_ok=True)
    
    print(f"Создание тестовых .npy файлов в {output_dir}/")
    print("=" * 60)
    
    # 1. Разные типы данных (3D)
    print("\n1. Тестирование разных типов данных...")
    dtypes = {
        'float32': np.float32,
        'float64': np.float64,
        'int8': np.int8,
        'int16': np.int16,
        'int32': np.int32,
        'uint8': np.uint8,
        'uint16': np.uint16,
        'uint32': np.uint32,
    }
    
    for name, dtype in dtypes.items():
        if 'float' in name:
            data = np.random.rand(10, 64, 64).astype(dtype)
        else:
            max_val = np.iinfo(dtype).max if 'int' in name or 'uint' in name else 255
            data = (np.random.rand(10, 64, 64) * max_val).astype(dtype)
        
        filename = f"{output_dir}/test_dtype_{name}.npy"
        np.save(filename, data)
        print(f"  ✓ {name}: {data.shape}, dtype={data.dtype}, size={os.path.getsize(filename)/1024:.1f} KB")
    
    # 2. Разные размеры (3D)
    print("\n2. Тестирование разных размеров...")
    sizes = [
        (10, 64, 64, "small"),
        (100, 256, 256, "medium"),
        (50, 512, 512, "large"),
    ]
    
    for *size, label in sizes:
        data = np.random.rand(*size).astype(np.float32)
        filename = f"{output_dir}/test_size_{label}_{size[0]}x{size[1]}x{size[2]}.npy"
        np.save(filename, data)
        print(f"  ✓ {label}: {data.shape}, size={os.path.getsize(filename)/1024/1024:.1f} MB")
    
    # 3. 2D изображения
    print("\n3. Тестирование 2D изображений...")
    sizes_2d = [
        (256, 256, "small"),
        (512, 512, "medium"),
        (1024, 1024, "large"),
    ]
    
    for *size, label in sizes_2d:
        data = np.random.rand(*size).astype(np.float32)
        filename = f"{output_dir}/test_2d_{label}_{size[0]}x{size[1]}.npy"
        np.save(filename, data)
        print(f"  ✓ {label}: {data.shape}, size={os.path.getsize(filename)/1024:.1f} KB")
    
    # 4. Fortran order
    print("\n4. Тестирование Fortran order...")
    data_c = np.random.rand(20, 128, 128).astype(np.float32)
    data_f = np.asfortranarray(data_c)
    
    np.save(f"{output_dir}/test_c_order.npy", data_c)
    np.save(f"{output_dir}/test_fortran_order.npy", data_f)
    print(f"  ✓ C-order: {data_c.shape}, flags={data_c.flags['C_CONTIGUOUS']}")
    print(f"  ✓ Fortran-order: {data_f.shape}, flags={data_f.flags['F_CONTIGUOUS']}")
    
    # 5. Normalized data (имитация реальных HSI данных)
    print("\n5. Создание реалистичных HSI данных...")
    
    # Гиперспектральный куб с гауссовым шумом
    hsi_data = np.random.randn(100, 256, 256).astype(np.float32)
    hsi_data = (hsi_data - hsi_data.min()) / (hsi_data.max() - hsi_data.min())
    np.save(f"{output_dir}/test_hsi_normalized.npy", hsi_data)
    print(f"  ✓ Normalized HSI: shape={hsi_data.shape}, range=[{hsi_data.min():.4f}, {hsi_data.max():.4f}]")
    
    # Данные с паттерном (проверка визуализации)
    pattern_data = np.zeros((50, 256, 256), dtype=np.float32)
    for i in range(50):
        x, y = np.meshgrid(np.linspace(0, 10, 256), np.linspace(0, 10, 256))
        pattern_data[i] = np.sin(x + i * 0.1) * np.cos(y + i * 0.1)
    
    pattern_data = (pattern_data - pattern_data.min()) / (pattern_data.max() - pattern_data.min())
    np.save(f"{output_dir}/test_pattern.npy", pattern_data)
    print(f"  ✓ Pattern data: shape={pattern_data.shape}, для визуальной проверки")
    
    # 6. Edge cases
    print("\n6. Тестирование edge cases...")
    
    # Очень маленький куб
    tiny = np.random.rand(2, 8, 8).astype(np.float32)
    np.save(f"{output_dir}/test_tiny_2x8x8.npy", tiny)
    print(f"  ✓ Tiny: {tiny.shape}")
    
    # Один канал (проверка 2D режима)
    single_channel = np.random.rand(512, 512, 1).astype(np.float32)
    np.save(f"{output_dir}/test_single_channel_512x512x1.npy", single_channel)
    print(f"  ✓ Single channel: {single_channel.shape}")
    
    # Много каналов
    many_channels = np.random.rand(500, 64, 64).astype(np.float16)
    np.save(f"{output_dir}/test_many_channels_500x64x64.npy", many_channels)
    print(f"  ✓ Many channels: {many_channels.shape}")
    
    print("\n" + "=" * 60)
    print(f"✅ Создано {len(os.listdir(output_dir))} тестовых файлов в {output_dir}/")
    print("\nИспользование:")
    print("1. Откройте HSIView")
    print(f"2. Откройте файлы из папки {output_dir}/")
    print("3. Проверьте отображение, статистику и корректность данных")
    
    # Создать README в папке с тестами
    with open(f"{output_dir}/README.txt", "w") as f:
        f.write("Тестовые .npy файлы для HSIView\n")
        f.write("=" * 60 + "\n\n")
        f.write("Типы файлов:\n")
        f.write("- test_dtype_*.npy - разные типы данных\n")
        f.write("- test_size_*.npy - разные размеры (3D)\n")
        f.write("- test_2d_*.npy - 2D изображения\n")
        f.write("- test_c_order.npy - C-order (row-major)\n")
        f.write("- test_fortran_order.npy - Fortran-order (column-major)\n")
        f.write("- test_hsi_normalized.npy - нормализованные HSI данные\n")
        f.write("- test_pattern.npy - данные с паттерном (sin/cos)\n")
        f.write("- test_tiny_*.npy - очень маленькие данные\n")
        f.write("- test_single_channel_*.npy - один канал (2D режим)\n")
        f.write("- test_many_channels_*.npy - много каналов\n")
        f.write("\nВсе файлы созданы с помощью create_test_npy.py\n")

if __name__ == "__main__":
    create_test_files()

