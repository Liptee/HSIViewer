#!/usr/bin/env python3
"""
Скрипт для создания тестовых NPY файлов различных размеров
для проверки производительности и корректности загрузки.
"""

import numpy as np
import os

def create_test_files():
    """Создает набор тестовых NPY файлов"""
    
    print("Создание тестовых NPY файлов...")
    
    tests = [
        {
            'name': 'test_uint8_large.npy',
            'shape': (7958, 1280, 250),
            'dtype': np.uint8,
            'description': 'Большой uint8 куб (2.5 ГБ)'
        },
        {
            'name': 'test_float64_medium.npy',
            'shape': (512, 512, 31),
            'dtype': np.float64,
            'description': 'Средний float64 куб (64 МБ)'
        },
        {
            'name': 'test_uint16_medium.npy',
            'shape': (1024, 1024, 50),
            'dtype': np.uint16,
            'description': 'Средний uint16 куб (100 МБ)'
        },
        {
            'name': 'test_float32_small.npy',
            'shape': (256, 256, 10),
            'dtype': np.float32,
            'description': 'Малый float32 куб (2.5 МБ)'
        }
    ]
    
    for test in tests:
        filepath = test['name']
        print(f"\n{test['description']}")
        print(f"  Файл: {filepath}")
        print(f"  Размерность: {test['shape']}")
        print(f"  Тип данных: {test['dtype'].__name__}")
        
        total_elements = np.prod(test['shape'])
        size_bytes = total_elements * np.dtype(test['dtype']).itemsize
        size_mb = size_bytes / (1024 * 1024)
        print(f"  Размер: {size_mb:.1f} МБ")
        
        data = np.random.randint(0, 255, test['shape'], dtype=test['dtype'])
        
        np.save(filepath, data)
        print(f"  ✓ Создан")
    
    print("\n" + "="*60)
    print("Все тестовые файлы созданы!")
    print("="*60)

if __name__ == '__main__':
    create_test_files()

