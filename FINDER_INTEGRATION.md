# Интеграция с Finder для открытия файлов

## ✅ Поддерживаемые форматы

HSIView зарегистрирован как обработчик по умолчанию для:
- `.mat` - MATLAB файлы
- `.tiff` / `.tif` - TIFF изображения
- `.npy` - NumPy массивы

## 🔧 Настройка в Info.plist

### 1. Объявление типов документов (CFBundleDocumentTypes)

Для каждого формата файла:

```xml
<dict>
    <key>CFBundleTypeName</key>
    <string>NumPy Array</string>
    <key>CFBundleTypeRole</key>
    <string>Viewer</string>
    <key>LSHandlerRank</key>
    <string>Owner</string>
    <key>LSItemContentTypes</key>
    <array>
        <string>com.hsiview.npy</string>
    </array>
</dict>
```

**Параметры:**
- `CFBundleTypeName` - отображаемое имя типа
- `CFBundleTypeRole` - `Viewer` (просмотр) или `Editor` (редактирование)
- `LSHandlerRank` - `Owner` (основной обработчик), `Default`, `Alternate`
- `LSItemContentTypes` - UTI (Uniform Type Identifier)

### 2. Экспорт UTI (UTExportedTypeDeclarations)

Регистрация собственных типов файлов:

```xml
<dict>
    <key>UTTypeConformsTo</key>
    <array>
        <string>public.data</string>
    </array>
    <key>UTTypeDescription</key>
    <string>NumPy Array File</string>
    <key>UTTypeIdentifier</key>
    <string>com.hsiview.npy</string>
    <key>UTTypeTagSpecification</key>
    <dict>
        <key>public.filename-extension</key>
        <array>
            <string>npy</string>
        </array>
    </dict>
</dict>
```

**Параметры:**
- `UTTypeConformsTo` - родительские типы (обычно `public.data`)
- `UTTypeDescription` - описание типа
- `UTTypeIdentifier` - уникальный идентификатор (reverse DNS)
- `UTTypeTagSpecification` - расширения файлов

### 3. Обработка в коде (AppDelegate)

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    static var sharedState: AppState?

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        Self.sharedState?.open(url: url)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            Self.sharedState?.open(url: url)
        }
    }
}
```

## 📱 Как это работает

### Открытие файла из Finder:

1. **Двойной клик** на .npy файл
2. macOS проверяет UTI файла
3. Находит зарегистрированное приложение (HSIView)
4. Запускает HSIView или передает URL открытому экземпляру
5. Вызывается `application(_:openFile:)` или `application(_:open:)`
6. `AppState.open(url:)` загружает файл

### Контекстное меню:

1. **Правый клик** на .npy файл
2. "Открыть с помощью" → HSIView отображается в списке
3. "Свойства" → HSIView указан как приложение по умолчанию

## 🧪 Тестирование

### Шаг 1: Сборка приложения

```bash
open HSIView.xcodeproj
# Product → Build (⌘B)
# Product → Run (⌘R)
```

### Шаг 2: Регистрация типов

После первого запуска macOS регистрирует типы файлов. Может потребоваться:

```bash
# Перезапустить Finder
killall Finder

# Пересобрать базу данных Launch Services (если не работает)
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
```

### Шаг 3: Проверка регистрации

```bash
# Проверить ассоциацию для .npy
mdls -name kMDItemContentType test_data/sponges.npy
# Должно показать: kMDItemContentType = "com.hsiview.npy"

# Проверить приложение по умолчанию
mdls -name kMDItemContentTypeTree test_data/sponges.npy
```

### Шаг 4: Тест открытия

1. **Из Finder:**
   - Двойной клик на `.npy` файл → должен открыться HSIView

2. **Drag & Drop:**
   - Перетащить `.npy` на иконку HSIView → должен открыться

3. **Командная строка:**
   ```bash
   open -a HSIView test_data/sponges.npy
   ```

4. **Контекстное меню:**
   - Правый клик → "Открыть с помощью" → HSIView

## 🐛 Решение проблем

### Файлы не открываются двойным кликом

**Причина:** Launch Services не обновил базу данных

**Решение:**
```bash
# 1. Убедитесь что приложение собрано
# 2. Перезапустите Finder
killall Finder

# 3. Если не помогло, пересоберите базу Launch Services
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user

# 4. Перезагрузите Mac (крайний случай)
```

### HSIView не отображается в "Открыть с помощью"

**Причина:** Неправильная регистрация UTI или CFBundleIdentifier

**Решение:**
1. Проверьте CFBundleIdentifier в Info.plist (должен быть уникальным)
2. Убедитесь что UTTypeIdentifier использует reverse DNS (com.yourname.app)
3. Пересоберите приложение полностью (Clean Build Folder)

### Открывается не HSIView, а другое приложение

**Причина:** Другое приложение имеет приоритет

**Решение:**
```bash
# Правый клик на файл → Свойства
# "Открывать в программе:" → выберите HSIView
# "Изменить все" → применить ко всем .npy файлам
```

Или через терминал:
```bash
# Установить HSIView как приложение по умолчанию для .npy
duti -s com.yourname.HSIView .npy all
```

### Файлы открываются в TextEdit или другом редакторе

**Причина:** UTI определяется как текстовый файл

**Решение:**
Убедитесь что `UTTypeConformsTo` указывает на `public.data`, а не на `public.text`:

```xml
<key>UTTypeConformsTo</key>
<array>
    <string>public.data</string>  <!-- НЕ public.text -->
</array>
```

## 📝 Регистрация типов файлов - полный чеклист

- [x] Добавить тип в `CFBundleDocumentTypes`
- [x] Установить `LSHandlerRank` = `Owner`
- [x] Создать UTI в `UTExportedTypeDeclarations`
- [x] Указать расширение в `UTTypeTagSpecification`
- [x] Реализовать обработку в `AppDelegate`
- [x] Пересобрать приложение
- [ ] Перезапустить Finder
- [ ] Протестировать двойной клик
- [ ] Проверить "Открыть с помощью"

## 🔒 Sandbox и разрешения

Если используется App Sandbox, убедитесь что в entitlements есть:

```xml
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

Это уже есть в `HSIView.entitlements`.

## 🎨 Добавление иконки для типа файла

Опционально можно добавить кастомную иконку для .npy файлов:

1. Создайте иконку (ICNS формат)
2. Добавьте в `UTTypeIcons`:

```xml
<key>UTTypeIcons</key>
<dict>
    <key>CFBundleTypeIconFile</key>
    <string>npy_icon</string>
</dict>
```

3. Добавьте `npy_icon.icns` в Resources проекта

## 📊 Поддерживаемые UTI в HSIView

| Формат | UTI | Расширение | Owner |
|--------|-----|------------|-------|
| MATLAB | `com.hsiview.mat` | `.mat` | ✅ |
| TIFF | `public.tiff` | `.tif`, `.tiff` | ✅ |
| NumPy | `com.hsiview.npy` | `.npy` | ✅ |

## 🔗 Дополнительная информация

- [Apple: Uniform Type Identifiers](https://developer.apple.com/documentation/uniformtypeidentifiers)
- [Apple: Core Services](https://developer.apple.com/documentation/coreservices)
- [Launch Services](https://developer.apple.com/documentation/coreservices/launch_services)

---

**Теперь .npy файлы можно открывать двойным кликом из Finder!** 🎉

