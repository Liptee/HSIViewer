# Архитектура HSIView

## Обзор

HSIView - нативный просмотрщик гиперспектральных изображений для macOS (Apple Silicon).

## Структура проекта

```
HSIView/
├── Models/                      # Модели данных
│   ├── HyperCubeModel.swift    # Структура гиперкуба и енумы
│   └── ImageLoadError.swift    # Типы ошибок
├── Services/                    # Сервисы
│   ├── ImageLoader.swift       # Протокол и фабрика загрузчиков
│   ├── MatImageLoader.swift    # Загрузчик .mat файлов
│   └── TiffImageLoader.swift   # Загрузчик .tiff файлов
├── Utilities/                   # Утилиты
│   ├── DataNormalization.swift # Нормализация данных
│   ├── ImageRenderer.swift     # Рендеринг изображений
│   └── WavelengthManager.swift # Работа с длинами волн
├── Views/
│   └── ContentView.swift       # Главный UI
├── AppState.swift              # State management
└── ImageViewerApp.swift        # Entry point
```

## Основные компоненты

### 1. Models

**HyperCube**
- Хранит 3D данные гиперспектрального изображения
- Поддерживает различные layout'ы (CHW, HWC, Auto)
- Методы для вычисления индексов и размерностей

**CubeLayout**
- `.auto` - автоматическое определение (минимальная ось = каналы)
- `.chw` - Channels × Height × Width
- `.hwc` - Height × Width × Channels

**ViewMode**
- `.gray` - поканальный просмотр (grayscale)
- `.rgb` - RGB синтез по длинам волн

### 2. Services

**ImageLoader Protocol**
```swift
protocol ImageLoader {
    static var supportedExtensions: [String] { get }
    static func load(from url: URL) -> Result<HyperCube, ImageLoadError>
}
```

**ImageLoaderFactory**
- Автоматически выбирает нужный загрузчик по расширению файла
- Легко расширяется для новых форматов (просто добавьте класс в `loaders`)

**Поддерживаемые форматы:**
- `.mat` - MATLAB файлы через libmatio
- `.tif/.tiff` - TIFF файлы через libtiff

### 3. Utilities

**DataNormalizer**
- Нормализация Min-Max
- Z-Score нормализация
- Percentile нормализация
- Конвертация в UInt8 для отображения

**ImageRenderer**
- Рендеринг grayscale изображений
- RGB синтез по длинам волн (630nm, 530nm, 450nm)
- Оптимизированная обработка данных

**WavelengthManager**
- Загрузка длин волн из файлов
- Генерация равномерных диапазонов
- Валидация данных

## Преимущества новой архитектуры

### 1. Разделение ответственности (Separation of Concerns)
- Модели отделены от логики
- UI отделен от обработки данных
- Каждый компонент имеет одну ответственность

### 2. Расширяемость
**Добавление нового формата** (например, .npy):

```swift
class NpyImageLoader: ImageLoader {
    static let supportedExtensions = ["npy"]
    
    static func load(from url: URL) -> Result<HyperCube, ImageLoadError> {
        // Реализация загрузки .npy
    }
}
```

Затем просто добавьте его в `ImageLoaderFactory.loaders`

### 3. Обработка ошибок
- Использование `Result<T, Error>` вместо опционалов
- Подробные сообщения об ошибках
- Централизованная обработка через `ImageLoadError`

### 4. Производительность
- Использование `UnsafeBufferPointer` для работы с C-данными
- Минимальное копирование данных
- Эффективная нормализация

### 5. Тестируемость
- Протоколы позволяют создавать mock'и
- Чистые функции без side effects
- Легко писать unit тесты

## Planned Features

### Ближайшие планы:
- [ ] Поддержка .npy формата
- [ ] Поддержка .hdr/.img формата (ENVI)
- [ ] Экспорт в различные форматы
- [ ] Графики спектра (выбор пикселя → график)
- [ ] Приведение к разным типам данных (float32/16/64, int8/16)
- [ ] Histogram equalization
- [ ] Zoom и Pan для изображений
- [ ] Keyboard shortcuts

### Долгосрочные:
- [ ] PCA визуализация
- [ ] False color композиты
- [ ] ROI (Region of Interest) выделение
- [ ] Batch processing
- [ ] Плагинная система для фильтров

## Как добавить новую функциональность

### Новый метод нормализации:
1. Добавьте case в `NormalizationType`
2. Реализуйте метод в `DataNormalizer`

### Новый режим отображения:
1. Добавьте case в `ViewMode`
2. Добавьте метод в `ImageRenderer`
3. Обновите switch в `ContentView.cubeView`

### Новая утилита для работы с данными:
1. Создайте файл в `Utilities/`
2. Используйте в `AppState` или `ImageRenderer`

## C Interop

Проект использует C библиотеки для работы с форматами:
- **libmatio** - для .mat файлов
- **libtiff** - для .tiff файлов

Bridge headers: `Header.h`, `ImageViewer-Bridging-Header.h`

## Dependencies

- libmatio (для .mat)
- libtiff (для .tiff)

Установка через Homebrew:
```bash
brew install libmatio libtiff
```

