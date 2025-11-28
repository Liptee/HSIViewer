# Исправление: Открытие .hdr и .dat из Finder

## Проблема

ENVI файлы (.hdr и .dat) не открываются двойным кликом из Finder, хотя в Info.plist они зарегистрированы.

## Причина

macOS кеширует информацию о типах файлов в Launch Services. После изменения Info.plist нужно сбросить этот кеш.

## Решение

### Вариант 1: Автоматический скрипт (РЕКОМЕНДУЕТСЯ)

1. **Соберите приложение в Xcode:**
   ```bash
   cd /Users/mac/Desktop/HSIView
   open HSIView.xcodeproj
   # Нажмите Cmd+B (Build)
   ```

2. **Запустите скрипт сброса:**
   ```bash
   cd /Users/mac/Desktop/HSIView
   ./reset_launch_services.sh
   ```

3. **Перезапустите Finder:**
   - Option+Right Click на иконке Finder в Dock
   - Выберите "Relaunch"

4. **Проверьте:**
   - Двойной клик на файл `.hdr` → должен открыться HSIView
   - Двойной клик на файл `.dat` → должен открыться HSIView

### Вариант 2: Ручной сброс

**1. Соберите приложение:**
```bash
cd /Users/mac/Desktop/HSIView
xcodebuild -project HSIView.xcodeproj -scheme HSIView -configuration Debug
```

**2. Найдите путь к собранному приложению:**
```bash
find ~/Library/Developer/Xcode/DerivedData -name "HSIView.app" -type d | grep Debug
```

**3. Сбросьте Launch Services:**
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
```

**4. Зарегистрируйте приложение:**
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -r "/путь/к/HSIView.app"
```

**5. Перезапустите Finder или перезагрузите компьютер**

### Вариант 3: Clean Build (если предыдущие не помогли)

**1. В Xcode:**
```
Product → Clean Build Folder (Cmd+Shift+K)
Product → Build (Cmd+B)
```

**2. Запустите приложение один раз:**
```
Product → Run (Cmd+R)
```

**3. Закройте приложение**

**4. Выполните шаги из Варианта 1**

### Вариант 4: Архивная сборка (для полной регистрации)

Если нужно, чтобы работало на постоянной основе:

**1. Создайте Archive:**
```
Product → Archive
```

**2. Export приложения:**
```
Distribute → Copy App
```

**3. Переместите HSIView.app в /Applications:**
```bash
cp -R ~/Desktop/HSIView.app /Applications/
```

**4. Зарегистрируйте:**
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -r /Applications/HSIView.app
```

## Проверка регистрации

### Проверить, зарегистрирован ли тип:

```bash
mdls -name kMDItemContentTypeTree test_data/pre_katrina05.hdr
```

Должно показать `com.hsiview.envi-hdr` в списке.

### Проверить, какое приложение открывает файл:

```bash
open -a "HSIView" test_data/pre_katrina05.hdr
```

### Установить HSIView как приложение по умолчанию:

**Вручную в Finder:**
1. Right Click на файл .hdr или .dat
2. Get Info (Cmd+I)
3. Open with: → выберите HSIView
4. Нажмите "Change All..."

**Через командную строку:**
```bash
duti -s com.yourcompany.HSIView .hdr all
duti -s com.yourcompany.HSIView .dat all
```

## Проверка Info.plist

Убедитесь, что в Info.plist есть:

```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>ENVI Data</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Owner</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>com.hsiview.envi-dat</string>
        </array>
    </dict>
    <dict>
        <key>CFBundleTypeName</key>
        <string>ENVI Header</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Owner</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>com.hsiview.envi-hdr</string>
        </array>
    </dict>
</array>
```

И:

```xml
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.data</string>
        </array>
        <key>UTTypeIdentifier</key>
        <string>com.hsiview.envi-dat</string>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>dat</string>
            </array>
        </dict>
    </dict>
    <dict>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.text</string>
        </array>
        <key>UTTypeIdentifier</key>
        <string>com.hsiview.envi-hdr</string>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>hdr</string>
            </array>
        </dict>
    </dict>
</array>
```

✅ **Всё это уже есть в вашем Info.plist!**

## Возможные проблемы

### "Файл не может быть открыт"

**Решение:** Проверьте права доступа к приложению:
```bash
xattr -cr /Applications/HSIView.app
```

### "Файл открывается в другом приложении"

**Решение:** Установите HSIView как приложение по умолчанию (см. выше).

### "Ничего не происходит"

**Решение:** Проверьте консоль на наличие ошибок:
```bash
log stream --predicate 'subsystem == "com.apple.launchservices"' --level debug
```

## Дата

2025-11-28

