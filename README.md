# HSIView

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift">
  <img src="https://img.shields.io/badge/Xcode-15.0+-blue.svg" alt="Xcode">
  <img src="https://img.shields.io/badge/macOS-15.0+-green.svg" alt="macOS">
</p>

**Native macOS app for hyperspectral data viewing, processing, conversion, analysis, and batch workflows.**

HSIView is built to make hyperspectral work practical in day-to-day engineering and research: fast local processing, transparent pipelines, and native UX for large multi-format datasets.

---

## Motivation

Most hyperspectral workflows are split across scripts, notebooks, and multiple utilities. That slows down exploration, introduces reproducibility issues, and makes batch operations harder than they should be.

HSIView focuses on one goal: **a convenient native desktop tool for full hyperspectral workflows**:
- inspect and understand data quickly,
- process and convert cubes reliably,
- compare and study spectra interactively,
- run repeatable operations across many files.

---

## Features

### Data formats

Input:
- NumPy (`.npy`)
- MATLAB (`.mat`)
- TIFF (`.tiff`, `.tif`)
- ENVI (`.dat` + `.hdr`, also `.img`, `.bsq`, `.bil`, `.bip`, `.raw`)

Cube export:
- NumPy (`.npy`)
- MATLAB (`.mat`)
- TIFF (`.tiff`)
- PNG Channels (one channel per PNG, UInt8/UInt16)
- Quick PNG (RGB/PCA view)
- Wavelength list (`_wavelengths.txt`)

Mask export:
- PNG (color or grayscale)
- NumPy (`.npy`)
- MATLAB (`.mat`) with class metadata

### Visualization and analysis
- Grayscale channel viewer with interactive channel navigation
- RGB synthesis by wavelengths (true-color style mapping)
- Range-wide RGB synthesis
- PCA visualization
- Vegetation/spectral indices: NDVI, NDSI, WDVI
- WDVI soil-line auto estimation (OLS/Huber)
- Spectrum charts for point and ROI samples (mean/median aggregation)
- Zoom/pan and fast channel exploration
- Wavelength management: load from `.txt` or generate from range

### Processing pipeline
- Reorderable operation pipeline (drag and drop)
- Auto-apply and manual apply modes
- Normalization (including per-channel)
- Data type conversion (`Float64/32`, `Int8/16/32`, `UInt8/16`)
- Spatial transforms: rotate, resize, crop
- Spectral trim by channels or wavelengths
- Calibration using white/black references
- Spectral interpolation to custom wavelength grid
- Spectral alignment with visualization support

### Library and batch workflows
- Main library with drag-and-drop import
- Grid library for matrix-style organization of datasets
- Per-entry processing state and wavelengths
- Copy/paste processing and wavelengths between entries
- Batch export for the entire library
- Session-aware workflow for multi-file processing

### Annotation
- Mask editor with layers and classes
- Brush, eraser, and fill tools
- Export-ready mask outputs

---

## Quick start

### Requirements
- macOS 15.0+
- Apple Silicon
- Xcode 15.0+
- Swift 5.9+
- Homebrew

### Dependencies

```bash
brew install libmatio libtiff
```

### Build and run

```bash
git clone <repository-url>
cd HSIView
open HSIView.xcodeproj
```

Make sure Xcode build settings include:
- Header Search Paths: `/opt/homebrew/include`
- Library Search Paths: `/opt/homebrew/lib`

Then run:
- Product -> Build (`Cmd+B`)
- Product -> Run (`Cmd+R`)

---

## Usage overview

- Open data: `Cmd+O`
- Export: `Cmd+E`
- Graph window: `Cmd+Shift+G`
- Grid library: `Cmd+Shift+L`
- Main window: `Cmd+1` (View -> Main Window)

Typical flow:
1. Open cube(s) and verify wavelengths.
2. Inspect spectra (point/ROI) and choose visualization mode.
3. Build processing pipeline.
4. Copy/paste processing to library items if needed.
5. Export one file or batch export the full library.

---

## Release (share built app via GitHub)

This section answers how to deliver an already built `.app` to a customer and other users through GitHub.

### 1. Build Release app in Xcode
1. Select the `HSIView` scheme.
2. Set configuration to `Release`.
3. Product -> Build.

Typical output path:
`~/Library/Developer/Xcode/DerivedData/.../Build/Products/Release/HSIView.app`

### 2. Package the app
Use Finder (Compress) or terminal:

```bash
cd "<folder containing HSIView.app>"
ditto -c -k --sequesterRsrc --keepParent HSIView.app HSIView-macOS.zip
```

### 3. (Recommended) Add checksum

```bash
shasum -a 256 HSIView-macOS.zip
```

Publish this SHA256 in release notes so users can verify integrity.

### 4. Create GitHub Release
1. Open your repo on GitHub.
2. Go to **Releases** -> **Draft a new release**.
3. Create/select tag (for example `v1.2.0`).
4. Add release title and notes (changes, requirements, known limitations).
5. Upload `HSIView-macOS.zip` as an asset.
6. Publish release.

Users can now download the app directly from the Release page.

### 5. What customers will do
- Download zip from GitHub Release.
- Unzip and move `HSIView.app` to `/Applications`.
- First launch may require right-click -> Open if app is unsigned/not notarized.

### Optional but important for broad distribution
For smoother installation (without Gatekeeper warnings), use:
- Apple Developer ID signing
- Apple notarization + staple

If you want, I can add a dedicated `docs/RELEASE_GUIDE.md` with exact signing/notarization commands for your setup.

---

## Documentation

Main docs index: `docs/README_DOCS.md`

Recommended starting points:
- `docs/ARCHITECTURE.md`
- `docs/PROJECT_STRUCTURE.md`
- `docs/DEVELOPER_GUIDE.md`
- `docs/PIPELINE_SYSTEM.md`
- `docs/NORMALIZATION_FEATURE.md`

---

## Contributing

1. Fork repository
2. Create branch: `git checkout -b feature/my-feature`
3. Commit: `git commit -m "Add amazing feature"`
4. Push: `git push origin feature/my-feature`
5. Open Pull Request

Please update relevant documentation in `docs/` for functional changes.

---

## Changelog

Full history: `CHANGELOG.md`

---

## License

MIT License

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
