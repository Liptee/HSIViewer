#!/bin/bash

# Автоматическая регистрация типов файлов после сборки

APP_PATH="${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME}"

if [ -d "$APP_PATH" ]; then
    echo "Регистрация типов файлов для: $APP_PATH"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH"
    echo "✅ Типы файлов зарегистрированы"
else
    echo "⚠️ Приложение не найдено по пути: $APP_PATH"
fi

