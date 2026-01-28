# Документация HSIView

Краткий индекс по документации. Если вы не уверены, с чего начать — смотрите раздел **Start Here**.

---

## Start Here
- **ARCHITECTURE.md** — обзор архитектуры и ключевых компонентов
- **PROJECT_STRUCTURE.md** — структура проекта и взаимосвязи модулей
- **DEVELOPER_GUIDE.md** — сборка, расширение функционала, практики разработки

---

## Форматы данных
- **NPY_SUPPORT.md** — поддержка NumPy (.npy)
- **MAT_INTEGER_SUPPORT.md** — поддержка целочисленных типов MATLAB
- **TIFF_CONTIG_SUPPORT.md** — поддержка TIFF CONTIG
- **ENVI_SUPPORT.md** — поддержка ENVI (.dat + .hdr)
- **ENVI_format.md** — спецификация ENVI

---

## Функции и UX
- **PIPELINE_SYSTEM.md** — пайплайн обработки
- **NORMALIZATION_FEATURE.md** — нормализация
- **CHANNELWISE_NORMALIZATION.md** — поканальная нормализация
- **ZOOM_NAVIGATION.md** — zoom/pan
- **CHANNEL_SLIDER_DESIGN.md** — дизайн слайдера каналов
- **INFO_PANEL_IMPLEMENTATION.md** — реализация info панели
- **INFO_PANEL_UPDATE.md** — автообновление info панели
- **UI_IMPROVEMENTS.md** — заметки по улучшениям UI

---

## Экспорт
- **EXPORT_SETUP.md** — экспорт данных
- **MAT_EXPORT.md** — экспорт в MATLAB

---

## Производительность
- **MEMORY_OPTIMIZATION.md** — оптимизация памяти
- **MEMORY_OPTIMIZATION_SUMMARY.md** — резюме оптимизаций
- **MEMORY_USAGE.md** — анализ потребления памяти

---

## Интеграции и настройки
- **FINDER_INTEGRATION.md** — интеграция с Finder
- **FINDER_OPEN_FIX.md** — открытие файлов из Finder
- **ENTITLEMENTS_BUILD_FIX.md** — entitlements и сборка
- **ICON_SETUP.md** — иконка приложения

---

## История изменений и fix-сводки (для справки)
Эти документы полезны как история решений, но обычно не нужны для ежедневной работы:
- **FIX_SUMMARY_RU.md**
- **FORTRAN_FIX_SUMMARY_RU.md**
- **REFACTORING_SUMMARY.md**
- **SESSION_SUMMARY.md**
- **SUMMARY_RU.md**
- **SIMPLE_FIX.md**
- **ENVI_COMPLETE_FIX_SUMMARY.md**
- **ENVI_ORDER_FIX.md**
- **ENVI_PAIR_FIX.md**
- **ENVI_SANDBOX_FIX.md**
- **ENVI_DIRECTORY_ACCESS.md**
- **MAT_FIX_SUMMARY.md**
- **MAT_MEMORY_OPTIMIZATION.md**
- **MAT_OPTIMIZATION_SUMMARY.md**
- **NPY_FIX.md**
- **NPY_FORTRAN_ORDER_FIX.md**
- **NPY_LARGE_FILES_FIX.md**
- **NPY_ORDER_FIX_SUMMARY.md**
- **NPY_ORDER_FIX_V2.md**
- **TIFF_FIX.md**
- **TIFF_CONTIG_FIX_SUMMARY.md**
- **TIFF_PARSING_ANALYSIS.md**
- **IMAGE_RENDERING_FIX.md**
- **ZOOM_SUMMARY.md**
- **SCREENSHOT_INFO.md**
- **2D_SUPPORT.md**

---

## Быстрый поиск

**Добавить новый формат?** → `DEVELOPER_GUIDE.md`  
**Как устроен пайплайн?** → `PIPELINE_SYSTEM.md`  
**Где описаны форматы?** → `NPY_SUPPORT.md`, `ENVI_SUPPORT.md`, `MAT_INTEGER_SUPPORT.md`, `TIFF_CONTIG_SUPPORT.md`  
**Экспорт?** → `EXPORT_SETUP.md`  
**Оптимизация памяти?** → `MEMORY_OPTIMIZATION.md`

---

## Соглашения по документации

1. Новые документы кладём в `docs/`
2. Имена файлов — `FEATURE_NAME.md`
3. Для фиксов — `FORMAT_FIX.md` или `FEATURE_FIX_SUMMARY.md`
4. Для спецификаций — `format_name.md`

---

Вернуться в корень: `../README.md`
