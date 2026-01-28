# HSIView

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift">
  <img src="https://img.shields.io/badge/Xcode-15.0+-blue.svg" alt="Xcode">
  <img src="https://img.shields.io/badge/macOS-11.0+-green.svg" alt="macOS">
</p>

**Нативный просмотрщик гиперспектральных изображений для macOS (Apple Silicon).**

HSIView позволяет быстро открывать, визуализировать, обрабатывать и экспортировать гиперспектральные кубы.

---

## ✨ Возможности

### 📂 Форматы

**Загрузка:**
- NumPy (.npy)
- MATLAB (.mat)
- TIFF (.tiff)
- ENVI (.dat + .hdr)

**Экспорт:**
- NumPy (.npy)
- MATLAB (.mat)
- PNG Channels (каждый канал в отдельный PNG, UInt8/UInt16)
- Quick PNG (RGB синтез)
- Wavelengths (экспорт длин волн в .txt)

### 🎨 Визуализация
- Grayscale с интерактивным переключением каналов
- RGB синтез по длинам волн
- Zoom & Pan
- Управление длинами волн (диапазон или загрузка из .txt)

### 🔧 Обработка
- Пайплайн операций с drag & drop
- Нормализация (Min-Max, Custom, Percentile, Z-Score, Log, Sqrt, None)
- Конвертация типов (Float64/32, Int8/16/32, UInt8/16)
- Повороты (90°, 180°, 270°)
- Обрезка диапазона каналов

---

## 🚀 Быстрый старт

### Требования
- macOS 11.0+ (рекомендуется 15.0+)
- Apple Silicon
- Xcode 15.0+
- Swift 5.9+
- Homebrew (для зависимостей)

### Зависимости

```bash
brew install libmatio libtiff
```

### Сборка

```bash
git clone <repository-url>
cd HSIView
open HSIView.xcodeproj
```

Убедитесь, что в Build Settings указаны пути:
- Header Search Paths: `/opt/homebrew/include`
- Library Search Paths: `/opt/homebrew/lib`

Сборка и запуск:
- Product → Build (Cmd+B)
- Product → Run (Cmd+R)

---

## 📖 Использование

### Открытие файла
- File → Open… (Cmd+O)
- Или из Finder: правый клик → Open With → HSIView

### Grayscale
1. Откройте куб
2. Режим: Gray
3. Используйте слайдер каналов

### RGB
1. Откройте куб с wavelengths (ENVI автоматически читает .hdr)
2. Или задайте диапазон/файл с длинами волн
3. Режим: RGB

### Pipeline
- Добавляйте операции кнопкой “+”
- Перетаскивайте для изменения порядка
- Режимы: автоматический (⚡) и ручной (✋)

### Экспорт
File → Export… (Cmd+E)

---

## 📚 Документация

Основной индекс: `docs/README_DOCS.md`

Рекомендуемые разделы:
- `docs/ARCHITECTURE.md`
- `docs/PROJECT_STRUCTURE.md`
- `docs/DEVELOPER_GUIDE.md`
- `docs/PIPELINE_SYSTEM.md`
- `docs/NORMALIZATION_FEATURE.md`

---

## 🤝 Контрибьюция

1. Fork репозиторий
2. Создайте ветку: `git checkout -b feature/my-feature`
3. Commit: `git commit -m 'Add amazing feature'`
4. Push: `git push origin feature/my-feature`
5. Откройте Pull Request

Перед PR обновляйте соответствующую документацию в `docs/`.

---

## 📝 Версии
Полная история: `CHANGELOG.md`

---

## 📄 Лицензия
MIT License

---

## 📧 Контакты
Вопросы или предложения: Telegram @Liptee

---

<p align="center">
  <strong>Made with ❤️ for hyperspectral imaging community</strong>
</p>
