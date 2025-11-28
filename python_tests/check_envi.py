#!/usr/bin/env python3
"""
Проверка ENVI файлов
"""

import sys
import os

def parse_envi_hdr(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    lines = content.split('\n')
    
    if not lines[0].strip().upper() == 'ENVI':
        print(f"❌ Не является ENVI файлом (первая строка: '{lines[0]}')")
        return None
    
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
    
    return fields

if len(sys.argv) < 2:
    print("Usage: python3 check_envi.py <file.hdr>")
    sys.exit(1)

hdr_path = sys.argv[1]
print(f"Анализ ENVI файла: {hdr_path}\n")

fields = parse_envi_hdr(hdr_path)
if not fields:
    sys.exit(1)

print("="*70)
print("ОБЯЗАТЕЛЬНЫЕ ПОЛЯ")
print("="*70)

required = ['samples', 'lines', 'bands', 'data type', 'interleave', 'byte order', 'header offset']
for key in required:
    value = fields.get(key, '❌ НЕ НАЙДЕНО')
    print(f"{key:20s} = {value}")

print("\n" + "="*70)
print("ОПЦИОНАЛЬНЫЕ ПОЛЯ")
print("="*70)

optional = ['wavelength', 'fwhm', 'wavelength units', 'description', 'band names', 'bbl']
for key in optional:
    if key in fields:
        value = fields[key]
        if len(value) > 60:
            value = value[:60] + "..."
        print(f"{key:20s} = {value}")

print("\n" + "="*70)
print("ИНТЕРПРЕТАЦИЯ")
print("="*70)

try:
    W = int(fields.get('samples', 0))
    H = int(fields.get('lines', 0))
    C = int(fields.get('bands', 0))
    dt = int(fields.get('data type', 0))
    interleave = fields.get('interleave', '').lower().replace('{', '').replace('}', '').strip()
    
    print(f"Размеры: {H} × {W} × {C} (H × W × C)")
    
    dt_names = {
        1: "int8 (1 байт)",
        2: "int16 (2 байта)",
        3: "int32 (4 байта)",
        4: "float32 (4 байта)",
        5: "float64 (8 байт)",
        12: "uint16 (2 байта)",
        13: "uint32 (4 байта)"
    }
    print(f"Тип данных: {dt} → {dt_names.get(dt, 'НЕИЗВЕСТНЫЙ')}")
    print(f"Interleave: {interleave.upper()}")
    
    bytes_per_pixel = {1: 1, 2: 2, 3: 4, 4: 4, 5: 8, 12: 2, 13: 4}.get(dt, 0)
    expected_size = H * W * C * bytes_per_pixel
    print(f"Ожидаемый размер .dat: {expected_size:,} байт ({expected_size/(1024**2):.1f} МБ)")
    
    base = os.path.splitext(hdr_path)[0]
    dat_path = base + '.dat'
    if os.path.exists(dat_path):
        actual_size = os.path.getsize(dat_path)
        print(f"Реальный размер .dat: {actual_size:,} байт ({actual_size/(1024**2):.1f} МБ)")
        
        if actual_size == expected_size:
            print("✅ Размер файла совпадает!")
        else:
            print(f"⚠️  Размер НЕ совпадает (разница: {actual_size - expected_size} байт)")
    else:
        print(f"❌ Файл {dat_path} не найден!")
    
    if 'wavelength' in fields:
        wl_str = fields['wavelength'].replace('{', '').replace('}', '').strip()
        wl_values = [float(x.strip()) for x in wl_str.split(',') if x.strip()]
        print(f"\nДлины волн: {len(wl_values)} значений")
        if wl_values:
            print(f"  Диапазон: {wl_values[0]:.1f} - {wl_values[-1]:.1f} нм")

except Exception as e:
    print(f"❌ Ошибка интерпретации: {e}")


