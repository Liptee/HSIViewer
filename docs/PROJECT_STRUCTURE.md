# Структура проекта HSIView

## Краткая схема

```
HSIView/
├── HSIView/                          # Исходный код
│   ├── AppState.swift
│   ├── ImageViewerApp.swift
│   ├── ContentView.swift
│   ├── Assets.xcassets/
│   ├── Models/                       # Модели данных
│   ├── Services/                     # Загрузчики форматов
│   ├── Exporters/                    # Экспортёры
│   ├── Utilities/                    # Рендеринг и обработка
│   ├── Views/                        # SwiftUI интерфейс
│   ├── Extensions/
│   ├── MatHelper.h/.c
│   ├── TiffHelper.h/.c
│   ├── Header.h
│   └── ImageViewer-Bridging-Header.h
├── HSIView.xcodeproj/
├── docs/                             # Документация
├── README.md
├── CHANGELOG.md
```

---

## Основные папки

### HSIView/Models
- Модели куба и метаданных
- Типы нормализации
- Операции пайплайна

### HSIView/Services
- Протокол загрузчиков
- Реализации для MAT/NPY/TIFF/ENVI

### HSIView/Exporters
- Экспорт в MAT/NPY
- Экспорт в PNG (channels/quick)
- Экспорт в TIFF

### HSIView/Utilities
- Рендеринг изображений
- Конвертация типов
- Работа с длинами волн

### HSIView/Views
- Основной UI и панели (pipeline, info, export)

---

## Поток данных (упрощённо)

```
Open File
  → ImageLoaderFactory
  → HyperCubeModel
  → ImageRenderer
  → UI (SwiftUI)

Pipeline
  → PipelineOperation[]
  → DataNormalization / DataTypeConverter / Rotation

Export
  → Exporters
```
