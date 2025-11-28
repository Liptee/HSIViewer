Ок, давай сделаем нормальную мини-спеку по ENVI, без воды.

⸻

1. Общая идея формата

ENVI-растр = два файла с одинаковым basename:
	•	cube.dat (или .img, .bsq, .raw и т.п.) — чистый бинарь с пикселями
	•	cube.hdr — текстовый header с метаданными

Основные параметры, без которых жить нельзя:
	•	samples — число колонок (W)
	•	lines — число строк (H)
	•	bands — число спектральных каналов (C)
	•	data type — тип пикселя (код ENVI)
	•	interleave — схема хранения: bsq, bil, bip
	•	byte order — порядок байт
	•	header offset — сколько байт пропустить в бинарнике перед данными

Эти поля в ENVI отмечены как обязательные.  ￼

⸻

2. Структура .hdr

Текстовый файл ASCII. Первая строка почти всегда:

ENVI

Дальше идут пары ключ = значение. Ключи регистронезависимы, пробелы вокруг = можно игнорить. Пример:  ￼

ENVI
description = {Some description}
samples = 512
lines   = 512
bands   = 31
header offset = 0
file type = ENVI Standard
data type = 4
interleave = bsq
byte order = 0
wavelength = {400.0, 410.0, ...}
fwhm = {10.0, 10.0, ...}
band names = {
 Band 1,
 Band 2,
 ...
}

2.1. Синтаксис значений
	1.	Скаляр (int/float/строка без пробелов):
samples = 512
file type = ENVI Standard
	2.	Список — в фигурных скобках {} через запятую:
wavelength = {400.0, 410.0, 420.0}
Может быть многострочным — парсить до } с учётом переносов.
	3.	Строки с пробелами — обычно тоже в {}:
description = {Hyper spectral cube}

Ключи, которые реально нужны для работы с кубом:
	•	samples (int) — ширина
	•	lines (int) — высота
	•	bands (int) — число каналов
	•	data type (int) — код типа данных
	•	interleave (str) — bsq / bil / bip
	•	byte order (int) — 0 или 1
	•	header offset (int) — байты перед данными

Полезные, но необязательные:
	•	wavelength — список длиной bands
	•	fwhm — список длиной bands
	•	wavelength units — строка (Micrometers, Nanometers и т.п.)  ￼
	•	data ignore value или bbl (bad band list)
	•	map info, coordinate system string, pixel size — геопривязка  ￼

⸻

3. data type → бинарный тип

Тип задаётся числом. Нормальный подмножество (из оф. док и тулзов MatLab/R/и т.д. ￼):

data type	смысл	байт
1	8-бит целое со знаком (int8)	1
2	16-бит целое со знаком (int16)	2
3	32-бит целое со знаком (int32)	4
4	32-бит float (float32)	4
5	64-бит float (float64)	8
6	комплекс из двух float32 (2×float)	
9	комплекс из двух float64	
12	16-бит беззнаковое (uint16)	2
13	32-бит беззнаковое (uint32)	4
14	64-бит со знаком (int64)	8
15	64-бит беззнаковое (uint64)	8

byte order:
	•	0 — little endian (PC)
	•	1 — big endian

⸻

4. Структура бинарника .dat

Обозначим:
	•	H = lines
	•	W = samples
	•	C = bands
	•	B = bytes_per_pixel (из data type)

Перед первым пикселем нужно пропустить header offset байт.

Дальше идёт чистый поток значений, упорядоченный по interleave. ENVI описывает это так:  ￼

4.1. BSQ (Band Sequential)

Хранение по полосам.

Порядок в файле:

Band0: line0 [W пикселей], line1, ..., line(H-1)
Band1: line0, line1, ...
...
Band(C-1)

Размер блока одной полосы: H * W * B байт.

Удобно читать как массив:
	•	сначала форма (C, H, W)
	•	если в софте хочешь (H, W, C) — просто переставляешь оси.

4.2. BIL (Band Interleaved by Line)

Хранение по строкам.

Порядок:

line 0, band 0: W значений
line 0, band 1: W значений
...
line 0, band C-1: W значений
line 1, band 0: ...
...
line H-1, band C-1

Удобно промежуточно читать как (H, C, W), потом перекинуть оси в (H, W, C).

4.3. BIP (Band Interleaved by Pixel)

Хранение по пикселям.

Порядок:

line 0:
  pixel (0,0): band0, band1, ..., band(C-1)
  pixel (0,1): band0, band1, ...
  ...
line 1:
  pixel (1,0): ...
...

Это уже фактически (H, W, C) по порядку. Читаешь подряд и reshape в (H, W, C).

⸻

5. Алгоритм парсинга ENVI-растра

5.1. Парсинг .hdr
	1.	Открыть .hdr как текст.
	2.	Убедиться, что первая строка начинается с ENVI (можно игнорить пробелы/переносы).
	3.	Для всех остальных строк:
	•	если встретился ключ = значение,
	•	нормализуешь ключ (к нижнему регистру, убираешь лишние пробелы).
	•	значение:
	•	если начинается с {, читаешь до соответствующей } (через несколько строк), режешь по запятым.
	•	иначе парсишь либо как int, либо как float, либо оставляешь строкой.
	4.	Обязательные поля проверяешь: samples, lines, bands, data type, interleave, byte order, header offset.
	5.	Опциональные (wavelength, fwhm, band names, map info и т.д.) сохраняешь как есть, они для визуализации/аналитики.

Рекомендация: завести внутреннюю структуру типа:

struct EnviHeader {
    int samples, lines, bands;
    int data_type;
    string interleave;
    int byte_order;
    int header_offset;
    vector<double> wavelength;
    ...
}

(Не обязательно буквально struct — суть понятна.)

5.2. Чтение .dat
	1.	Из data type → определить размер пикселя B и внутренний numeric type.
	2.	Из byte order → выставить правильный endianness при чтении.
	3.	Проверить, что размер файла (минус header offset) = H * W * C * B. Если нет — хотя бы вывалиться с ошибкой.
	4.	Пропустить header offset байт.
	5.	Прочитать всё остальное как 1D массив нужного типа длиной N = H * W * C.
	6.	Развернуть по interleave:
	•	bsq: reshape в (C, H, W) → при необходимости transpose в (H, W, C).
	•	bil: reshape в (H, C, W) → переставить оси в (H, W, C).
	•	bip: reshape прямо в (H, W, C).

⸻

6. Запись ENVI-растра

Чтобы сохранять твой гиперкуб в ENVI:
	1.	Внутри у тебя, скорее всего, куб (H, W, C).
	2.	Выбираешь interleave:
	•	для гиперспектров обычно bsq или bil. ENVI сам рекомендует bil как компромисс по производительности.  ￼
	3.	Преобразуешь куб под выбранный interleave:
	•	bsq: rearrange в (C, H, W) и дампишь по полосам.
	•	bil: rearrange в (H, C, W) и дампишь по строкам.
	•	bip: просто (H, W, C).
	4.	Пишешь бинарь без заголовка (или с нужным header offset, если вдруг тебе надо свои служебные данные в начале вставить).
	5.	Пишешь .hdr:
	•	samples = W
	•	lines = H
	•	bands = C
	•	data type = ... (в зависимости от твоего внутреннего типа)
	•	interleave = bsq/bil/bip
	•	byte order = 0 (если пишешь в little endian)
	•	header offset = ... (обычно 0)
	•	опциональные поля (wavelength, fwhm, description, band names, map info, wavelength units и т.п.)

⸻

7. Грабли, о которых лучше помнить
	•	Несовпадение order: ENVI считает samples = колонки, lines = строки. Старайся внутри держать (H, W, C) и каждый раз явно прописывать, как ты reshape делаешь.
	•	Не тот endian: если byte order = 1, а ты читаешь как little endian, значения будут мусор.
	•	Необновлённый header: часто забывают обновить bands, wavelength, interleave после своих манипуляций и потом удивляются, что ENVI показывает чушь.
	•	Комплексные типы (6, 9): это по сути [real, imag, real, imag, ...]. Если такие встретятся — нужен отдельный хэндлинг.

⸻

Если хочешь, дальше могу:
	•	расписать конкретно, как ты будешь хранить куб в памяти (какой порядок осей) и какие reshape/transpose делать под каждый interleave;
	•	или описать мини-формат поверх ENVI (типа твой .hsi плюс .hdr совместимый с ENVI).