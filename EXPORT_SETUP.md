# Настройка экспорта в Xcode

## Проблема
Созданы файлы экспортёров, но они требуют настройки в Xcode для работы с C библиотеками (matio, libtiff).

## Решение

### Шаг 1: Добавить файлы в проект Xcode

1. Откройте `HSIView.xcodeproj` в Xcode
2. В Project Navigator (слева), найдите папку `HSIView`
3. Перетащите эти файлы в Xcode:
   - `HSIView/TiffHelper_Export.h`
   - `HSIView/TiffHelper_Export.c`
4. В диалоге выберите:
   - ☑️ "Copy items if needed"
   - ☑️ "HSIView" target
   - Нажмите "Finish"

### Шаг 2: Обновить Bridging Header

1. В Xcode, выберите проект `HSIView` в Project Navigator
2. Выберите Target `HSIView`
3. Перейдите на вкладку "Build Settings"
4. Найдите "Objective-C Bridging Header"
5. Установите значение: `HSIView/HSIView-Bridging-Header.h`

### Шаг 3: Проверить Header Search Paths

1. В "Build Settings" найдите "Header Search Paths"
2. Убедитесь, что есть пути к matio и libtiff:
   ```
   /opt/homebrew/include
   /usr/local/include
   $(inherited)
   ```

### Шаг 4: Проверить Library Search Paths

1. В "Build Settings" найдите "Library Search Paths"
2. Убедитесь, что есть:
   ```
   /opt/homebrew/lib
   /usr/local/lib
   $(inherited)
   ```

### Шаг 5: Чистая пересборка

1. Product → Clean Build Folder (Cmd+Shift+K)
2. Product → Build (Cmd+B)

---

## Альтернативное решение: Упрощённая версия без C хелперов

Если настройка не работает, используйте упрощённую версию экспортёров (без C хелперов).


