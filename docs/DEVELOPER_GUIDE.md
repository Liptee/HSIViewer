# Руководство разработчика HSIView

## Быстрый старт

### Требования
- macOS 11.0+
- Xcode 15.0+
- Swift 5.9+
- Homebrew (для зависимостей)

### Установка зависимостей

```bash
brew install libmatio libtiff
```

### Сборка проекта

1. Откройте `HSIView.xcodeproj` в Xcode
2. Выберите схему HSIView
3. Cmd+B для сборки
4. Cmd+R для запуска

Пути в Build Settings:
- Header Search Paths: `/opt/homebrew/include`
- Library Search Paths: `/opt/homebrew/lib`

---

## Структура кода (высокий уровень)

- **Models** — модели куба, типы нормализации, операции пайплайна
- **Services** — загрузчики форматов
- **Exporters** — экспортёры
- **Utilities** — рендеринг и обработка
- **Views** — SwiftUI интерфейс

Подробнее: `PROJECT_STRUCTURE.md` и `ARCHITECTURE.md`.

---

## Добавление нового формата

### Шаг 1: Создайте загрузчик

Создайте файл `HSIView/Services/YourFormatImageLoader.swift`:

```swift
import Foundation

final class YourFormatImageLoader: ImageLoader {
    static let supportedExtensions = ["ext1", "ext2"]

    static func load(from url: URL) -> Result<HyperCube, ImageLoadError> {
        // 1) Прочитать файл
        // 2) Распарсить формат
        // 3) Проверить размерности
        // 4) Сконвертировать в [Double]
        // 5) Вернуть HyperCube
        return .failure(.unsupportedFormat)
    }
}
```

### Шаг 2: Зарегистрируйте загрузчик

В `HSIView/Services/ImageLoader.swift` добавьте класс в список фабрики `ImageLoaderFactory`.

### Шаг 3: Обновите список типов в UI

Обновите список расширений в file picker (там, где задаётся `allowedFileTypes`).

---

## Добавление новой операции пайплайна

1. Добавьте новый case в `Models/PipelineOperation.swift`.
2. Реализуйте применение операции в пайплайн-обработке.
3. Добавьте UI для конфигурации параметров операции.

---

## Добавление нового режима визуализации

1. Добавьте case в enum `ViewMode`.
2. Реализуйте рендеринг в `Utilities/ImageRenderer.swift`.
3. Обновите UI переключатель режима.

---

## Работа с C-библиотеками

### Bridging Header

Добавьте `.h/.c` файлы и подключите их в `Header.h`.

### Управление памятью

Всегда освобождайте память, выделенную в C:

```swift
var cCube = MatCube3D(data: nil, dims: (0, 0, 0), rank: 0)

defer {
    free_cube(&cCube)
}
```

---

## Тестирование

### Unit тесты
Создавайте тесты в `HSIViewTests/` (если добавите таргет). Рекомендуется покрывать:
- нормализацию
- конвертацию типов
- пайплайн-операции

### Ручные проверки
1. Открыть `.mat`, `.npy`, `.tiff`, `.dat+.hdr`
2. Проверить Gray/RGB
3. Протестировать пайплайн (нормализация + конвертация + экспорт)

---

## Best Practices

### Производительность
- Используйте `reserveCapacity` для массивов известного размера
- Минимизируйте копирование больших массивов
- Профилируйте в Instruments перед оптимизацией

### SwiftUI
- Дробите крупные View на компоненты
- Избегайте тяжёлых вычислений в `body`
- Обновляйте UI на main thread

---

## Отладка

### LLDB команды

```lldb
(lldb) po state.cube?.dims
(lldb) p state.channelCount
```

### Instruments
1. Product → Profile (Cmd+I)
2. Time Profiler / Allocations
3. Анализ горячих точек

---

## Лицензия
MIT License
