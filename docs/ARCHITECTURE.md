# Архитектура HSIView

## Обзор

HSIView — нативный просмотрщик гиперспектральных изображений для macOS (Apple Silicon). Основные цели: быстрый просмотр, удобная обработка и экспорт без лишней подготовки данных.

---

## Ключевые компоненты

### AppState и поток данных
`AppState` хранит текущий куб, состояние UI, параметры визуализации и пайплайн обработки. Все изменения UI и пайплайна проходят через него.

### Models
- `HyperCubeModel.swift` — модель куба, layout, метаданные
- `CubeNormalization.swift` — типы нормализации
- `PipelineOperation.swift` — операции пайплайна
- `CubeSessionSnapshot.swift` — снимки сессии
- `CubeExportPayload.swift` — данные для экспорта

### Services (загрузка)
- `ImageLoader.swift` — протокол загрузчика и фабрика
- `MatImageLoader.swift`, `NpyImageLoader.swift`, `TiffImageLoader.swift`, `EnviImageLoader.swift`

### Exporters (экспорт)
- `MatExporter.swift`, `NpyExporter.swift`
- `PngChannelsExporter.swift`, `QuickPNGExporter.swift`
- `TiffExporter.swift`

### Utilities
- `ImageRenderer.swift` — рендеринг Gray/RGB
- `DataTypeConverter.swift` — конвертация типов
- `DataNormalization.swift` — нормализация данных
- `WavelengthManager.swift` — управление длинами волн

### Views (UI)
- `ContentView.swift` — основной интерфейс
- Панели: `PipelinePanel.swift`, `ImageInfoPanel.swift`, `ExportView.swift`, `LibraryPanel.swift`

### C Helpers
- `MatHelper.h/.c` (libmatio)
- `TiffHelper.h/.c` (libtiff)

---

## Поток обработки

1. **Открытие файла** → `ImageLoaderFactory` выбирает loader по расширению → `HyperCubeModel`.
2. **Визуализация** → `ImageRenderer` строит изображение (Gray/RGB).
3. **Пайплайн** → операции нормализации, конвертации типов, поворота и обрезки применяются последовательно.
4. **Экспорт** → `Exporters` сохраняют данные и изображения.

---

## Расширяемость

### Добавление нового формата
1. Создайте новый loader в `HSIView/Services/`.
2. Зарегистрируйте его в `ImageLoaderFactory`.
3. Обновите список типов файлов в UI (file picker).

### Новая операция пайплайна
1. Добавьте новый case в `PipelineOperation`.
2. Реализуйте применение в месте обработки пайплайна.
3. Добавьте UI конфигурацию операции.

---

## Зависимости

- **libmatio** — чтение/запись `.mat`
- **libtiff** — чтение TIFF

Установка:
```bash
brew install libmatio libtiff
```
