# Исправление поиска парного файла для ENVI

## Проблема

При загрузке ENVI файлов программа не могла найти парный файл (.dat ↔ .hdr).

### Причины:

**1. Ошибка в логике поиска .dat файла:**
```swift
// СТАРЫЙ КОД (НЕПРАВИЛЬНО):
if fileExt == "hdr" {
    hdrURL = url
    datURL = url.deletingPathExtension()  // ❌ Возвращает путь БЕЗ расширения!
}

// Пример:
// url = "/path/to/cube.hdr"
// datURL = "/path/to/cube"  ❌ НЕТ .dat!
```

**2. ENVI использует разные расширения:**

ENVI формат может иметь бинарный файл с разными расширениями:
- `.dat` (стандартный)
- `.img` (image)
- `.bsq` (Band Sequential)
- `.bil` (Band Interleaved by Line)
- `.bip` (Band Interleaved by Pixel)
- `.raw` (raw data)

Старый код искал только `.dat`!

## Решение

### 1. Добавлен метод `findDataFile`:

```swift
private static func findDataFile(basePath: URL) -> URL? {
    let possibleExtensions = ["dat", "img", "bsq", "bil", "bip", "raw"]
    
    for ext in possibleExtensions {
        let url = basePath.appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
    }
    
    return nil
}
```

### 2. Исправлена логика поиска:

```swift
// НОВЫЙ КОД (ПРАВИЛЬНО):
let basePath = url.deletingPathExtension()

if fileExt == "hdr" {
    hdrURL = url
    datURL = findDataFile(basePath: basePath) ?? basePath.appendingPathExtension("dat")
} else {
    datURL = url
    hdrURL = basePath.appendingPathExtension("hdr")
}
```

**Теперь:**
- Открываете `.hdr` → ищем `.dat`, `.img`, `.bsq` и т.д. ✅
- Открываете любой бинарный файл → ищем `.hdr` ✅

### 3. Обновлен список поддерживаемых расширений:

**EnviImageLoader.swift:**
```swift
static let supportedExtensions = ["dat", "hdr", "img", "bsq", "bil", "bip", "raw"]
```

**ImageViewerApp.swift:**
```swift
panel.allowedFileTypes = ["mat", "tif", "tiff", "npy", "dat", "hdr", "img", "bsq", "bil", "bip", "raw"]
```

**Info.plist:**
- Добавлены `UTTypeIdentifier` для всех расширений:
  - `com.hsiview.envi-dat`
  - `com.hsiview.envi-img`
  - `com.hsiview.envi-bsq`
  - `com.hsiview.envi-bil`
  - `com.hsiview.envi-bip`
  - `com.hsiview.envi-raw`

## Примеры использования

### Пример 1: Стандартные имена
```
cube.dat + cube.hdr
→ Открываете cube.hdr → находится cube.dat ✅
→ Открываете cube.dat → находится cube.hdr ✅
```

### Пример 2: Альтернативные расширения
```
image.img + image.hdr
→ Открываете image.hdr → находится image.img ✅
→ Открываете image.img → находится image.hdr ✅
```

### Пример 3: Interleave в имени файла
```
data.bsq + data.hdr
→ Открываете data.hdr → находится data.bsq ✅
→ Открываете data.bsq → находится data.hdr ✅
```

### Пример 4: Любой порядок
```
hypercube.bil + hypercube.hdr
→ Открываете любой → найдется парный ✅
```

## Тестирование

**1. Проверьте существующие файлы:**
```bash
cd /Users/mac/Desktop/HSIView/test_data
ls -la *.hdr *.dat *.img *.bsq *.bil *.bip 2>/dev/null
```

**2. Откройте через меню (Cmd+O):**
- Выберите `.hdr` файл → должен загрузиться
- Выберите `.dat` файл → должен загрузиться

**3. Откройте из Finder:**
- Двойной клик на `.hdr` → должен открыться
- Двойной клик на `.dat` (или `.img`, `.bsq`, и т.д.) → должен открыться

## Сообщения об ошибках

**Улучшены сообщения:**

Старое:
```
"Не найден .dat файл: cube"
```

Новое:
```
"Не найден бинарный файл. Ожидается: cube.dat"
```

## Совместимость

✅ **Все популярные ENVI форматы:**
- ENVI Classic (`.dat` + `.hdr`)
- ENVI BSQ (`.bsq` + `.hdr`)
- ENVI BIL (`.bil` + `.hdr`)
- ENVI BIP (`.bip` + `.hdr`)
- ENVI IMG (`.img` + `.hdr`)
- ENVI RAW (`.raw` + `.hdr`)

✅ **Открытие из любого места:**
- Меню File → Открыть... (Cmd+O)
- Drag & Drop (если поддерживается)
- Двойной клик из Finder

## Дата

2025-11-28 (v3 - исправлен поиск парного файла)


