#!/bin/bash
# Скрипт для сброса Launch Services и регистрации файловых ассоциаций

echo "🔄 Сброс Launch Services для HSIView..."
echo ""

# Путь к приложению (после сборки)
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/HSIView-*/Build/Products/Debug/HSIView.app"

# Находим последнюю собранную версию
LATEST_APP=$(ls -t $APP_PATH 2>/dev/null | head -1)

if [ -z "$LATEST_APP" ]; then
    echo "❌ Приложение не найдено в DerivedData"
    echo "   Сначала соберите приложение в Xcode (Cmd+B)"
    exit 1
fi

echo "✅ Найдено приложение: $LATEST_APP"
echo ""

# Сброс Launch Services
echo "🧹 Сброс кеша Launch Services..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user

echo "📝 Регистрация типов файлов..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -r "$LATEST_APP"

echo ""
echo "✅ Готово!"
echo ""
echo "Теперь попробуйте:"
echo "1. Перезапустить Finder: Option+Right Click на иконке Finder → Relaunch"
echo "2. Или перезагрузить компьютер"
echo "3. Двойной клик на .dat или .hdr файл должен открыть HSIView"



