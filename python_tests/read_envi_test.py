#!/usr/bin/env python3
"""
Тестовое чтение ENVI файлов с использованием spectral library
для проверки правильности нашей реализации
"""

import sys
import os
import numpy as np

def read_envi_manual(hdr_path, dat_path):
    """Читаем ENVI файл вручную, как это делает наш Swift код"""
    
    # Парсим header
    with open(hdr_path, 'r') as f:
        content = f.read()
    
    lines = content.split('\n')
    fields = {}
    current_key = None
    current_value = ""
    in_braces = False
    
    for line in lines[1:]:
        trimmed = line.strip()
        if not trimmed:
            continue
        
        if in_braces:
            current_value += " " + trimmed
            if '}' in trimmed:
                in_braces = False
                if current_key:
                    fields[current_key] = current_value
                current_key = None
                current_value = ""
        elif '=' in line:
            parts = line.split('=', 1)
            key = parts[0].strip().lower()
            value = parts[1].strip()
            
            if '{' in value and '}' not in value:
                in_braces = True
                current_key = key
                current_value = value
            else:
                fields[key] = value
    
    W = int(fields.get('samples', 0))
    H = int(fields.get('lines', 0))
    C = int(fields.get('bands', 0))
    dt = int(fields.get('data type', 0))
    interleave = fields.get('interleave', '').lower().replace('{', '').replace('}', '').strip()
    byte_order = int(fields.get('byte order', '0'))
    header_offset = int(fields.get('header offset', '0'))
    
    print(f"Header info:")
    print(f"  samples (W) = {W}")
    print(f"  lines (H) = {H}")
    print(f"  bands (C) = {C}")
    print(f"  data type = {dt}")
    print(f"  interleave = {interleave}")
    print(f"  byte order = {byte_order} ({'little' if byte_order == 0 else 'big'} endian)")
    print(f"  header offset = {header_offset}")
    
    # Определяем dtype
    dtype_map = {
        1: np.uint8,
        2: np.int16,
        3: np.int32,
        4: np.float32,
        5: np.float64,
        12: np.uint16,
        13: np.uint32,
    }
    
    if dt not in dtype_map:
        print(f"Неподдерживаемый data type: {dt}")
        return None
    
    dtype = dtype_map[dt]
    endian = '<' if byte_order == 0 else '>'
    dtype = np.dtype(endian + dtype().dtype.str[1:])
    
    print(f"  numpy dtype = {dtype}")
    
    # Читаем данные
    with open(dat_path, 'rb') as f:
        if header_offset > 0:
            f.seek(header_offset)
        data = np.fromfile(f, dtype=dtype)
    
    print(f"\nData info:")
    print(f"  Total elements read = {len(data)}")
    print(f"  Expected elements = {H * W * C}")
    print(f"  Match: {len(data) == H * W * C}")
    
    if len(data) != H * W * C:
        print(f"  WARNING: Size mismatch!")
        return None
    
    # Переупорядочиваем в зависимости от interleave
    if interleave == 'bsq':
        # BSQ: (C, H, W) в файле
        cube = data.reshape((C, H, W))
        print(f"\nBSQ: reshaped to (C={C}, H={H}, W={W})")
        
    elif interleave == 'bil':
        # BIL: (H, C, W) в файле
        cube = data.reshape((H, C, W))
        print(f"\nBIL: reshaped to (H={H}, C={C}, W={W})")
        # Переставляем оси в (C, H, W)
        cube = np.transpose(cube, (1, 0, 2))
        print(f"  transposed to (C={C}, H={H}, W={W})")
        
    elif interleave == 'bip':
        # BIP: (H, W, C) в файле
        cube = data.reshape((H, W, C))
        print(f"\nBIP: reshaped to (H={H}, W={W}, C={C})")
        # Переставляем оси в (C, H, W)
        cube = np.transpose(cube, (2, 0, 1))
        print(f"  transposed to (C={C}, H={H}, W={W})")
    else:
        print(f"Unknown interleave: {interleave}")
        return None
    
    print(f"\nFinal cube shape: {cube.shape}")
    print(f"  min = {cube.min()}")
    print(f"  max = {cube.max()}")
    print(f"  mean = {cube.mean():.6f}")
    
    # Показываем первый канал (corner 5x5)
    print(f"\nFirst channel [0:5, 0:5]:")
    print(cube[0, :5, :5])
    
    return cube

if len(sys.argv) < 2:
    print("Usage: python3 read_envi_test.py <file.hdr>")
    sys.exit(1)

hdr_path = sys.argv[1]
base = os.path.splitext(hdr_path)[0]

# Ищем dat файл
dat_path = None
for ext in ['dat', 'img', 'bsq', 'bil', 'bip', 'raw']:
    test_path = base + '.' + ext
    if os.path.exists(test_path):
        dat_path = test_path
        break

if not dat_path:
    print(f"Не найден бинарный файл для {hdr_path}")
    sys.exit(1)

print(f"Reading ENVI:")
print(f"  Header: {hdr_path}")
print(f"  Data:   {dat_path}")
print("="*70)

cube = read_envi_manual(hdr_path, dat_path)

if cube is not None:
    print("\n" + "="*70)
    print("✅ Успешно прочитан!")

