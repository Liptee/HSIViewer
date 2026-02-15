# HSIView

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/status-active-success.svg" alt="Status">
</p>

**HSIView is a native macOS application for practical hyperspectral work: viewing, processing, conversion, exploration, and batch operations.**

---

## Why HSIView

Hyperspectral data workflows are often fragmented across scripts and tools. HSIView brings everything into one native desktop app so you can:
- open data quickly,
- inspect spectra and images interactively,
- apply reproducible processing pipelines,
- convert/export to common formats,
- run the same operations across many files.

---

## What You Can Do

### 1. Open and organize hyperspectral datasets
- Load files from common formats:
  - NumPy (`.npy`)
  - MATLAB (`.mat`)
  - TIFF (`.tif`, `.tiff`)
  - ENVI (`.dat` + `.hdr`, plus `.img`, `.bsq`, `.bil`, `.bip`, `.raw`)
- Keep files in a built-in library for repeated work.
- Use Grid Library for matrix-like organization of many cubes.
- Store per-file processing and wavelength state in the session.

### 2. Visualize data fast
- Grayscale channel view with interactive channel navigation.
- RGB synthesis from wavelength mapping.
- Range-wide RGB synthesis.
- PCA-based visual rendering.
- Smooth zoom and pan for spatial inspection.

### 3. Analyze spectra interactively
- Point-based spectra extraction.
- ROI-based spectra extraction.
- ROI aggregation modes (mean/median).
- Built-in graph window for comparison across samples.
- Wavelength-aware viewing where wavelengths are available.

### 4. Process cubes with a configurable pipeline
- Reorder operations via drag-and-drop.
- Auto apply and manual apply modes.
- Available operations include:
  - normalization (including per-channel),
  - data type conversion (`Float64/32`, `Int8/16/32`, `UInt8/16`),
  - resize, rotate, crop,
  - spectral trim,
  - spectral interpolation,
  - spectral alignment,
  - calibration by white/black references.

### 5. Work with masks and annotation
- Create and edit masks with class/layer support.
- Brush, eraser, and fill tools.
- Export masks for downstream workflows.

### 6. Export and convert results
- Export cubes to:
  - NumPy (`.npy`)
  - MATLAB (`.mat`)
  - TIFF (`.tiff`)
  - PNG Channels
  - Quick PNG (RGB/PCA view)
- Export wavelengths to text (`_wavelengths.txt`).
- Export masks to PNG/NPY/MAT.
- Batch export entire library.

---

## Quick Start (for End Users)

### Step 1. Download the app from GitHub Releases
1. Open the repository page on GitHub.
2. Go to **Releases**.
3. Open the latest stable release (not marked as pre-release, unless you want testing builds).
4. Download the attached archive, usually `HSIView-macOS.zip`.

### Step 2. Install
1. Unzip the downloaded archive.
2. Drag `HSIView.app` to `/Applications`.

### Step 3. First launch
1. Open `HSIView.app`.
2. If macOS blocks launch (Gatekeeper):
   - Right-click the app -> **Open** -> confirm,
   - or go to **System Settings -> Privacy & Security** and allow launch.

### Step 4. Open your first cube
1. In HSIView, press `Cmd+O` and select your hyperspectral file.
2. Confirm visualization mode (Gray/RGB/PCA).
3. If needed, load or set wavelengths.
4. Start exploring spectra and applying pipeline operations.

### Useful shortcuts
- `Cmd+O` - Open file
- `Cmd+E` - Export
- `Cmd+Shift+G` - Graph window
- `Cmd+Shift+L` - Grid library
- `Cmd+1` - Main window

---

## Typical User Workflow

1. Add one or multiple cubes to the library.
2. Check wavelength data and visualization mode.
3. Explore spectral signatures (point/ROI).
4. Build and tune processing pipeline.
5. Apply same logic to other files in the library.
6. Batch export results in required format.

---

## Acknowledgments

- Valera Lobanov for app testing and icon design

---

## Contact

Questions or suggestions: Telegram `@Liptee`

---

<p align="center">
  <strong>Made with ❤️ for hyperspectral imaging community</strong>
</p>
