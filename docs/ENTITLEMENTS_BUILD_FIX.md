# Исправление ошибки Entitlements Build Error

## Проблема

```
Entitlements file "HSIView.entitlements" was modified during the build, 
which is not supported.
```

Эта ошибка возникает когда файл `.entitlements` изменяется во время сборки проекта.

---

## Причины

1. **Extended Attributes**: macOS добавляет метаданные к файлу
2. **Xcode Auto-modification**: Xcode пытается автоматически изменить entitlements
3. **Git Line Endings**: Проблемы с окончаниями строк
4. **Build System Cache**: Устаревший кэш DerivedData

---

## ✅ Решение 1: Очистка Extended Attributes (РЕКОМЕНДУЕТСЯ)

```bash
cd /Users/mac/Desktop/HSIView

# Очистить extended attributes
xattr -cr HSIView/HSIView.entitlements

# Проверить что @ исчез
ls -la HSIView/HSIView.entitlements
# Должно быть: -rw-r--r-- (без @)
```

**Когда использовать:** Если видите `@` в правах доступа

---

## ✅ Решение 2: Очистка DerivedData

```bash
# Удалить весь кэш проекта
rm -rf ~/Library/Developer/Xcode/DerivedData/HSIView-*

# Или удалить весь DerivedData (осторожно!)
rm -rf ~/Library/Developer/Xcode/DerivedData/*
```

**Когда использовать:** После изменения entitlements или Build Settings

---

## ✅ Решение 3: Настройка Xcode (Постоянное исправление)

### Через GUI:

1. Открыть `HSIView.xcodeproj` в Xcode
2. Выбрать проект в Project Navigator (слева)
3. Выбрать Target **"HSIView"**
4. Перейти в **Build Settings**
5. Выбрать **All** и **Combined**
6. Найти в поиске: `CODE_SIGN_ALLOW`
7. Найти **"Code Sign Allow Entitlements Modification"**
8. Установить значение: **YES**

### Через командную строку:

```bash
# Добавить настройку в xcodeproj
# (Требует установки xcodeproj gem)
```

---

## ✅ Решение 4: Пересоздание файла

Если ничего не помогает:

```bash
cd /Users/mac/Desktop/HSIView

# Бэкап старого
cp HSIView/HSIView.entitlements HSIView/HSIView.entitlements.backup

# Удалить оригинал
rm HSIView/HSIView.entitlements

# Создать новый (скопируйте содержимое)
cat > HSIView/HSIView.entitlements << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
</dict>
</plist>
EOF

# Проверить
cat HSIView/HSIView.entitlements
```

---

## 🚀 Быстрое исправление (Комбо)

Выполните все команды подряд:

```bash
cd /Users/mac/Desktop/HSIView

# 1. Очистить attributes
xattr -cr HSIView/HSIView.entitlements

# 2. Очистить DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/HSIView-*

# 3. Проверить результат
ls -la HSIView/HSIView.entitlements

# 4. Собрать проект
echo "Теперь соберите проект в Xcode (Cmd+B)"
```

---

## 📋 Проверка после исправления

### 1. Проверить права доступа:
```bash
ls -la HSIView/HSIView.entitlements
```
Должно быть: `-rw-r--r--` (БЕЗ `@`)

### 2. Проверить содержимое:
```bash
cat HSIView/HSIView.entitlements
```
Должно быть валидным XML с entitlements

### 3. Проверить Git статус:
```bash
git status HSIView/HSIView.entitlements
```
Должно быть: `nothing to commit, working tree clean`

### 4. Собрать проект:
- Откройте Xcode
- Product → Clean Build Folder (Cmd+Shift+K)
- Product → Build (Cmd+B)

---

## 🐛 Если проблема повторяется

### Добавьте в `.gitattributes`:

```bash
# В корне проекта
echo "*.entitlements text eol=lf" >> .gitattributes
git add .gitattributes
git commit -m "fix: add gitattributes for entitlements"
```

### Создайте Pre-build Script:

1. Xcode → Target → Build Phases
2. **"+"** → New Run Script Phase
3. Переместите в самое начало (выше Compile Sources)
4. Название: **"Clean Entitlements Attributes"**
5. Script:
```bash
xattr -cr "${PROJECT_DIR}/HSIView/HSIView.entitlements"
```

---

## 💡 Предотвращение

### 1. Не открывайте `.entitlements` в сторонних редакторах
- Используйте только Xcode для редактирования
- Избегайте TextEdit, VS Code для этого файла

### 2. После каждого изменения entitlements:
```bash
xattr -cr HSIView/HSIView.entitlements
```

### 3. Перед каждой сборкой из терминала:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/HSIView-*
```

---

## 📚 Дополнительная информация

### Что такое Extended Attributes?
macOS хранит метаданные о файлах (например, откуда скачан, кодировка, дата использования). Для `.entitlements` это может вызывать конфликты во время сборки.

### Почему это происходит?
Xcode проверяет `.entitlements` до и после сборки. Если хэш файла изменился (даже из-за metadata), возникает ошибка.

### Безопасно ли удалять attributes?
✅ Да! Extended attributes - это только metadata, не влияют на содержимое файла.

---

## 🆘 Крайняя мера

Если НИЧЕГО не помогает:

```bash
# 1. Полная очистка
rm -rf ~/Library/Developer/Xcode/DerivedData/*
rm -rf ~/Library/Caches/com.apple.dt.Xcode

# 2. Перезапуск Xcode
killall Xcode

# 3. Открыть заново
open HSIView.xcodeproj

# 4. Clean Build Folder (Cmd+Shift+K)
# 5. Build (Cmd+B)
```

---

**Версия:** v0.4+  
**Дата:** 2025-11-29  
**Статус:** Решено ✅


