# Руководство разработчика HSIView

## Быстрый старт

### Требования
- macOS 11.0+
- Xcode 13.0+
- Swift 5.5+
- Homebrew (для зависимостей)

### Установка зависимостей

```bash
brew install libmatio libtiff
```

### Сборка проекта

1. Откройте `HSIView.xcodeproj` в Xcode
2. Выберите схему HSIView
3. Нажмите Cmd+B для сборки
4. Нажмите Cmd+R для запуска

## Структура кода

### Models (Модели данных)

Содержат структуры данных без бизнес-логики.

```swift
// Models/HyperCubeModel.swift
struct HyperCube {
    let dims: (Int, Int, Int)
    let data: [Double]
    
    func channelCount(for layout: CubeLayout) -> Int { ... }
}
```

### Services (Сервисы)

Выполняют операции загрузки/сохранения данных.

```swift
// Services/ImageLoader.swift
protocol ImageLoader {
    static var supportedExtensions: [String] { get }
    static func load(from url: URL) -> Result<HyperCube, ImageLoadError>
}
```

### Utilities (Утилиты)

Вспомогательные функции для обработки данных.

```swift
// Utilities/DataNormalization.swift
class DataNormalizer {
    static func normalize(_ data: [Double], type: NormalizationType) -> NormalizationResult
}
```

### Views (Представления)

SwiftUI views для отображения UI.

```swift
// ContentView.swift
struct ContentView: View {
    @EnvironmentObject var state: AppState
    var body: some View { ... }
}
```

### Extensions (Расширения)

Расширяют функциональность существующих типов.

```swift
// Extensions/HyperCube+Statistics.swift
extension HyperCube {
    func statistics() -> Statistics { ... }
    func pixelSpectrum(layout: CubeLayout, x: Int, y: Int) -> [Double]? { ... }
}
```

## Добавление нового формата

### Шаг 1: Создайте загрузчик

Создайте файл `Services/YourFormatImageLoader.swift`:

```swift
import Foundation

class YourFormatImageLoader: ImageLoader {
    static let supportedExtensions = ["ext1", "ext2"]
    
    static func load(from url: URL) -> Result<HyperCube, ImageLoadError> {
        // 1. Прочитайте данные из файла
        guard let data = try? Data(contentsOf: url) else {
            return .failure(.fileNotFound)
        }
        
        // 2. Распарсите формат
        guard let parsed = parseYourFormat(data) else {
            return .failure(.corruptedData)
        }
        
        // 3. Проверьте, что это 3D данные
        guard parsed.dimensions.count == 3 else {
            return .failure(.notA3DCube)
        }
        
        // 4. Конвертируйте в [Double]
        let doubleData = convertToDouble(parsed.rawData)
        
        // 5. Создайте HyperCube
        let cube = HyperCube(
            dims: (parsed.dimensions[0], 
                   parsed.dimensions[1], 
                   parsed.dimensions[2]),
            data: doubleData
        )
        
        return .success(cube)
    }
    
    private static func parseYourFormat(_ data: Data) -> ParsedData? {
        // Ваша логика парсинга
        return nil
    }
    
    private static func convertToDouble(_ raw: [Any]) -> [Double] {
        // Конвертация в Double
        return []
    }
}
```

### Шаг 2: Зарегистрируйте загрузчик

В `Services/ImageLoader.swift` добавьте в массив `loaders`:

```swift
class ImageLoaderFactory {
    private static let loaders: [ImageLoader.Type] = [
        MatImageLoader.self,
        TiffImageLoader.self,
        YourFormatImageLoader.self  // ← Добавьте эту строку
    ]
    ...
}
```

### Шаг 3: Обновите UI (опционально)

В `ContentView.swift` обновите список форматов в file picker:

```swift
panel.allowedFileTypes = ["mat", "tif", "tiff", "ext1", "ext2"]
```

Готово! Теперь ваш формат поддерживается.

## Добавление нового метода нормализации

### Шаг 1: Добавьте тип

В `Utilities/DataNormalization.swift`:

```swift
enum NormalizationType {
    case minMax
    case zScore
    case percentile(lower: Double, upper: Double)
    case yourMethod  // ← Добавьте
}
```

### Шаг 2: Реализуйте метод

```swift
class DataNormalizer {
    static func normalize(_ data: [Double], type: NormalizationType) -> NormalizationResult {
        switch type {
        case .minMax:
            return normalizeMinMax(data)
        case .zScore:
            return normalizeZScore(data)
        case .percentile(let l, let u):
            return normalizePercentile(data, lower: l, upper: u)
        case .yourMethod:  // ← Добавьте
            return normalizeYourMethod(data)
        }
    }
    
    private static func normalizeYourMethod(_ data: [Double]) -> NormalizationResult {
        // Ваша логика нормализации
        let normalized = data.map { /* ... */ }
        return NormalizationResult(
            normalized: normalized,
            min: /* ... */,
            max: /* ... */
        )
    }
}
```

## Добавление нового режима отображения

### Шаг 1: Добавьте в enum

В `Models/HyperCubeModel.swift`:

```swift
enum ViewMode: String, CaseIterable, Identifiable {
    case gray = "Gray"
    case rgb  = "RGB"
    case yourMode = "Your Mode"  // ← Добавьте
    
    var id: String { rawValue }
}
```

### Шаг 2: Реализуйте рендеринг

В `Utilities/ImageRenderer.swift`:

```swift
class ImageRenderer {
    static func renderYourMode(
        cube: HyperCube,
        layout: CubeLayout,
        /* дополнительные параметры */
    ) -> NSImage? {
        // Ваша логика рендеринга
        return nil
    }
}
```

### Шаг 3: Обновите UI

В `ContentView.swift` обновите switch:

```swift
switch state.viewMode {
case .gray:
    // ...
case .rgb:
    // ...
case .yourMode:  // ← Добавьте
    if let nsImage = ImageRenderer.renderYourMode(
        cube: cube,
        layout: state.layout
    ) {
        // Отображение
    }
}
```

## Работа с C-библиотеками

### Bridging Header

Для добавления новой C-библиотеки:

1. Создайте `.h` и `.c` файлы в папке проекта
2. Добавьте импорт в `Header.h`:

```c
#ifndef Header_h
#define Header_h

#include <tiffio.h>
#import "MatHelper.h"
#import "TiffHelper.h"
#import "YourHelper.h"  // ← Добавьте

#endif
```

3. Используйте в Swift:

```swift
var cStruct = YourCStruct(/* ... */)
let result = your_c_function(&cStruct)
```

### Управление памятью

**Важно:** Всегда освобождайте память, выделенную в C:

```swift
var cCube = MatCube3D(data: nil, dims: (0, 0, 0), rank: 0)

defer {
    free_cube(&cCube)  // ← Обязательно
}

let loaded = load_first_3d_double_cube(path, &cCube, ...)
```

## Тестирование

### Unit тесты (TODO)

Создайте файлы в `HSIViewTests/`:

```swift
import XCTest
@testable import HSIView

class DataNormalizerTests: XCTestCase {
    func testMinMaxNormalization() {
        let data = [0.0, 5.0, 10.0]
        let result = DataNormalizer.normalize(data, type: .minMax)
        
        XCTAssertEqual(result.normalized[0], 0.0)
        XCTAssertEqual(result.normalized[1], 0.5)
        XCTAssertEqual(result.normalized[2], 1.0)
    }
}
```

### Ручное тестирование

1. Подготовьте тестовые файлы (.mat, .tiff)
2. Запустите приложение
3. Откройте файл через UI
4. Проверьте:
   - Корректное отображение
   - Переключение каналов
   - RGB синтез
   - Работу с длинами волн

## Best Practices

### 1. Обработка ошибок

✅ **Хорошо:**
```swift
func load() -> Result<Data, Error> {
    guard fileExists else {
        return .failure(MyError.fileNotFound)
    }
    return .success(data)
}
```

❌ **Плохо:**
```swift
func load() -> Data? {
    guard fileExists else { return nil }
    return data
}
```

### 2. Именование

- Классы: `PascalCase`
- Функции/переменные: `camelCase`
- Константы: `camelCase` или `SCREAMING_SNAKE_CASE` для глобальных
- Протоколы: `PascalCase`, часто с суффиксом `-able` или `-ing`

### 3. Комментарии

Избегайте избыточных комментариев. Код должен быть самодокументируемым.

✅ **Хорошо:**
```swift
func closestWavelengthIndex(to target: Double) -> Int {
    // Complex algorithm explanation only when needed
}
```

❌ **Плохо:**
```swift
// This function adds two numbers
func add(_ a: Int, _ b: Int) -> Int {
    return a + b  // return the sum
}
```

### 4. Производительность

- Используйте `reserveCapacity` для массивов известного размера
- Избегайте копирования больших массивов
- Используйте `lazy` для отложенных вычислений
- Профилируйте с Instruments перед оптимизацией

### 5. SwiftUI

- Разделяйте большие View на smaller components
- Используйте `@EnvironmentObject` для shared state
- Избегайте тяжелых вычислений в `body`
- Используйте `.task` и `.onAppear` правильно

## Отладка

### Xcode Breakpoints

Используйте conditional breakpoints для больших данных:

```
Condition: channelIndex == 50
Actions: po cube.dims
```

### LLDB команды

```lldb
(lldb) po state.cube?.dims
(lldb) p state.channelCount
(lldb) expr state.loadError = nil
```

### Instruments

Для профилирования:
1. Product → Profile (Cmd+I)
2. Выберите "Time Profiler" или "Allocations"
3. Запишите сессию
4. Анализируйте горячие точки

## Часто задаваемые вопросы

### Q: Как добавить поддержку других типов данных (int16, float32)?

A: Сейчас все данные хранятся как `[Double]`. Для поддержки других типов:
1. Создайте enum `DataType` в `HyperCubeModel.swift`
2. Добавьте generic storage или protocol
3. Обновите все loader'ы

### Q: Можно ли открыть несколько файлов одновременно?

A: Сейчас нет. Для этого нужно:
1. Изменить `AppState` для хранения массива кубов
2. Добавить табы или список в UI
3. Обновить все View для работы с выбранным кубом

### Q: Как добавить экспорт в другие форматы?

A: Создайте протокол `ImageExporter` аналогично `ImageLoader`:

```swift
protocol ImageExporter {
    static func export(cube: HyperCube, to url: URL) -> Result<Void, Error>
}
```

### Q: Поддерживается ли многопоточность?

A: Частично. Для полной поддержки:
1. Оберните тяжелые операции в `Task { await ... }`
2. Используйте `actor` для shared mutable state
3. Обновите UI на main thread

## Полезные ресурсы

### Документация
- [Swift Documentation](https://swift.org/documentation/)
- [SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui)
- [libmatio](https://github.com/tbeu/matio)
- [libtiff](http://www.libtiff.org/)

### Инструменты
- [SwiftLint](https://github.com/realm/SwiftLint) - линтер для Swift
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) - форматтер

### Сообщество
- [Swift Forums](https://forums.swift.org/)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/swift)

## Контрибьюторам

См. CONTRIBUTING.md (TODO)

## Лицензия

См. LICENSE (TODO)

