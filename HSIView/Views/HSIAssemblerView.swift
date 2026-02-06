import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HSIAssemblerView: View {
    private struct SourceEntry: Identifiable, Equatable {
        let id: UUID
        let url: URL

        init(id: UUID = UUID(), url: URL) {
            self.id = id
            self.url = url.standardizedFileURL.resolvingSymlinksInPath()
        }

        var displayName: String { url.lastPathComponent }
    }

    private enum WavelengthNotation: String {
        case sequential
        case mapped

        var title: String {
            switch self {
            case .sequential: return "по строкам"
            case .mapped: return "name:value"
            }
        }
    }

    private struct WavelengthFileCandidate: Identifiable, Equatable {
        let id: UUID
        let url: URL
        let notation: WavelengthNotation

        init(id: UUID = UUID(), url: URL, notation: WavelengthNotation) {
            self.id = id
            self.url = url.standardizedFileURL
            self.notation = notation
        }
    }

    private enum ParsedWavelengthData {
        case sequential([Double])
        case mapped([(String, Double)])
    }

    private enum BulkBuildStrategy {
        case template
        case perSourceText
    }

    private enum WavelengthImportError: LocalizedError {
        case noMaterials
        case fileReadFailed
        case emptyFile
        case mixedNotation
        case invalidValue(line: Int)
        case countMismatch(expected: Int, actual: Int)
        case invalidMapping(line: Int)
        case noMatchingFiles

        var errorDescription: String? {
            switch self {
            case .noMaterials:
                return "Сначала добавьте материалы"
            case .fileReadFailed:
                return "Не удалось прочитать файл длин волн"
            case .emptyFile:
                return "Файл длин волн пуст"
            case .mixedNotation:
                return "В файле смешаны разные нотации. Используйте один формат на весь файл."
            case .invalidValue(let line):
                return "Некорректное значение длины волны в строке \(line)"
            case .countMismatch(let expected, let actual):
                return "Количество длин волн (\(actual)) не совпадает с количеством материалов (\(expected))"
            case .invalidMapping(let line):
                return "Некорректная строка сопоставления в строке \(line). Ожидается формат name:value"
            case .noMatchingFiles:
                return "В файле нет совпадений по именам материалов"
            }
        }
    }

    private enum SourceLoadError: LocalizedError {
        case noSupportedFiles
        case importFailure(String)

        var errorDescription: String? {
            switch self {
            case .noSupportedFiles:
                return "В источнике нет поддерживаемых файлов"
            case .importFailure(let message):
                return "Ошибка импорта источника: \(message)"
            }
        }
    }

    private struct SourceLoadBundle {
        let materials: [HSIAssemblyMaterial]
        let wavelengthCandidates: [WavelengthFileCandidate]
    }

    @EnvironmentObject var state: AppState

    @State private var sources: [SourceEntry] = []
    @State private var selectedSourceID: UUID?
    @State private var activeSourceID: UUID?
    @State private var sourceForEmptyAlert: SourceEntry?
    @State private var showEmptySourceAlert = false

    @State private var materials: [HSIAssemblyMaterial] = []
    @State private var isDropTargeted = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importProgressText: String?

    @State private var selectedMaterialID: UUID?
    @State private var hoveredMaterialID: UUID?
    @State private var previewImage: NSImage?
    @FocusState private var hasMaterialsFocus: Bool
    @FocusState private var hasSourcesFocus: Bool

    @State private var showWavelengthChoiceDialog = false
    @State private var wavelengthChoiceCandidates: [WavelengthFileCandidate] = []
    @State private var wavelengthChoiceSourceName: String?

    @State private var showBulkBuildModeDialog = false
    @State private var isBulkBuilding = false
    @State private var bulkBuildProgressText: String?

    private var selectedMaterial: HSIAssemblyMaterial? {
        guard let selectedMaterialID else { return nil }
        return materials.first(where: { $0.id == selectedMaterialID })
    }

    private var hasNonGrayscaleMaterials: Bool {
        materials.contains { !$0.isGrayscale }
    }

    private var hasInconsistentResolution: Bool {
        guard let first = materials.first else { return false }
        return materials.contains { $0.width != first.width || $0.height != first.height }
    }

    private var assembleValidationMessage: String? {
        if hasInconsistentResolution {
            return "Размеры материалов различаются. Приведите все изображения к одному разрешению."
        }
        if hasNonGrayscaleMaterials {
            return "Есть цветные материалы. Дважды кликните по «Палитра», чтобы разбить их на каналы."
        }
        return nil
    }

    private var canAssemble: Bool {
        !materials.isEmpty &&
        assembleValidationMessage == nil &&
        !state.isBusy &&
        !isImporting &&
        !isBulkBuilding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .top, spacing: 12) {
                sourcesPanel
                    .frame(width: 250)

                materialsPanel
                    .frame(maxWidth: .infinity)

                previewPanel
                    .frame(width: 300)
            }

            footer
        }
        .padding(16)
        .frame(minWidth: 1220, minHeight: 700)
        .onChange(of: materials) { _, newMaterials in
            syncSelection(with: newMaterials)
        }
        .onChange(of: selectedMaterialID) { _, _ in
            loadPreviewImage()
        }
        .alert("В источнике нет поддерживаемых файлов", isPresented: $showEmptySourceAlert, presenting: sourceForEmptyAlert) { source in
            Button("Убрать источник", role: .destructive) {
                removeSource(source)
            }
            Button("Оставить", role: .cancel) {}
        } message: { source in
            Text("В папке '\(source.displayName)' нет PNG/JPG/BMP файлов. Удалить этот источник из списка?")
        }
        .confirmationDialog(
            "Выберите файл длин волн\(wavelengthChoiceSourceName.map { " для '\($0)'" } ?? "")",
            isPresented: $showWavelengthChoiceDialog,
            titleVisibility: .visible
        ) {
            ForEach(wavelengthChoiceCandidates) { candidate in
                Button("\(candidate.url.lastPathComponent) (\(candidate.notation.title))") {
                    applyWavelengthCandidateToCurrent(candidate)
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog("Массовая сборка", isPresented: $showBulkBuildModeDialog, titleVisibility: .visible) {
            Button("Использовать настройки текущих материалов") {
                startBulkBuild(strategy: .template)
            }
            Button("Использовать txt каждого источника") {
                startBulkBuild(strategy: .perSourceText)
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Выберите стратегию сборки для остальных источников.")
        }
    }

    private var header: some View {
        HStack {
            Text("Сборщик ГСИ")
                .font(.system(size: 20, weight: .semibold))

            Spacer()

            Text("Материалов: \(materials.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private var sourcesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Источники")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    addSourcesFromPanel()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isImporting || isBulkBuilding)
            }

            if isBulkBuilding {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.linear)
                    Text(bulkBuildProgressText ?? "Массовая сборка…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                )
            }

            if sources.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Добавьте директории с материалами.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Двойной клик по источнику открывает его содержимое в «Материалах».")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
            } else {
                List {
                    ForEach(sources) { source in
                        sourceRow(source)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.inset)
                .focusable(true)
                .focusEffectDisabled(true)
                .focused($hasSourcesFocus)
                .onDeleteCommand(perform: removeSelectedSource)
            }

            HStack(spacing: 8) {
                Button("Открыть") {
                    guard let source = selectedSource else { return }
                    openSource(source)
                }
                .buttonStyle(.bordered)
                .disabled(selectedSource == nil || isImporting || isBulkBuilding)

                Button("Удалить") {
                    removeSelectedSource()
                }
                .buttonStyle(.bordered)
                .disabled(selectedSource == nil || isBulkBuilding)
            }

            Button("Массовая сборка") {
                presentBulkBuildOptions()
            }
            .buttonStyle(.borderedProminent)
            .disabled(sources.count < 2 || isImporting || isBulkBuilding)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
        )
    }

    private var selectedSource: SourceEntry? {
        guard let selectedSourceID else { return nil }
        return sources.first(where: { $0.id == selectedSourceID })
    }

    private func sourceRow(_ source: SourceEntry) -> some View {
        let isSelected = selectedSourceID == source.id
        let isActive = activeSourceID == source.id

        return VStack(alignment: .leading, spacing: 4) {
            Text(source.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? .accentColor : .primary)
                .lineLimit(1)
            Text(source.url.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color(NSColor.controlBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSourceID = source.id
            hasSourcesFocus = true
        }
        .onTapGesture(count: 2) {
            selectedSourceID = source.id
            hasSourcesFocus = true
            openSource(source)
        }
    }

    private var materialsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Материалы")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button("Импортировать…") {
                    importFromPanel()
                }
                .buttonStyle(.bordered)
                .disabled(isImporting || isBulkBuilding)

                Button("Загрузить λ…") {
                    loadWavelengthsFromPanel()
                }
                .buttonStyle(.bordered)
                .disabled(materials.isEmpty || isImporting || isBulkBuilding)

                Button("Сортировать λ") {
                    sortByWavelengths()
                }
                .buttonStyle(.bordered)
                .disabled(materials.isEmpty || isImporting || isBulkBuilding)

                Button("Очистить") {
                    materials.removeAll()
                    selectedMaterialID = nil
                    errorMessage = nil
                    infoMessage = nil
                }
                .buttonStyle(.bordered)
                .disabled(materials.isEmpty || isImporting || isBulkBuilding)
            }

            if isImporting {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: importProgress, total: 1.0)
                        .progressViewStyle(.linear)
                    Text(importProgressText ?? "Импорт…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                )
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : Color(NSColor.separatorColor),
                        style: StrokeStyle(lineWidth: 1, dash: isDropTargeted ? [] : [5, 4])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.35))
                    )

                if materials.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("Перетащите PNG, JPG или BMP сюда")
                            .font(.system(size: 13, weight: .medium))
                        Text("или нажмите «Импортировать…»")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach($materials) { $material in
                            materialRow($material)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                        }
                        .onMove(perform: moveMaterials)
                    }
                    .listStyle(.inset)
                    .focusable(true)
                    .focusEffectDisabled(true)
                    .focused($hasMaterialsFocus)
                    .onDeleteCommand(perform: removeSelectedMaterial)
                }
            }
            .frame(minHeight: 470)
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop(providers:))

            Text("Порядок строк соответствует порядку каналов при сборке.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Предпросмотр")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.45))

                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("Выберите материал")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 260)

            if let selectedMaterial {
                detailRow(label: "Файл", value: selectedMaterial.fileName)
                detailRow(label: "Разрешение", value: selectedMaterial.resolutionDescription)
                detailRow(label: "Палитра", value: selectedMaterial.colorPaletteDescription)
                detailRow(label: "Тип данных", value: selectedMaterial.dataTypeDescription)
                detailRow(
                    label: "Длина волны",
                    value: selectedMaterial.wavelengthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "не задана"
                        : "\(selectedMaterial.wavelengthText) нм"
                )
            } else {
                Spacer()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .lineLimit(3)
            } else if let infoMessage {
                Text(infoMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            } else if let validation = assembleValidationMessage {
                Text(validation)
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                    .lineLimit(3)
            } else {
                Text("Длина волны (нм) заполняется опционально для каждого материала.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Сборка") {
                assemble()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAssemble)
        }
    }

    private func materialRow(_ material: Binding<HSIAssemblyMaterial>) -> some View {
        let item = material.wrappedValue
        let isSelected = selectedMaterialID == item.id
        let isHovered = hoveredMaterialID == item.id
        let highlight = isSelected || isHovered

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(item.sourceURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            parameterBadge(label: "Разрешение", value: item.resolutionDescription)
            paletteBadge(for: item)
            parameterBadge(label: "Тип", value: item.dataTypeDescription)

            VStack(alignment: .leading, spacing: 4) {
                Text("Длина волны, нм")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                TextField("например 550", text: material.wavelengthText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .scaleEffect(highlight ? 1.01 : 1.0)
        .shadow(color: Color.accentColor.opacity(highlight ? 0.25 : 0.0), radius: highlight ? 6 : 0, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.12), value: highlight)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedMaterialID = item.id
            hasMaterialsFocus = true
        }
        .onHover { hovering in
            if hovering {
                hoveredMaterialID = item.id
            } else if hoveredMaterialID == item.id {
                hoveredMaterialID = nil
            }
        }
    }

    private func parameterBadge(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
    }

    private func paletteBadge(for material: HSIAssemblyMaterial) -> some View {
        let isWarning = !material.isGrayscale

        return VStack(alignment: .leading, spacing: 2) {
            Text("Палитра")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                if isWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                Text(material.colorPaletteDescription)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isWarning ? Color.red.opacity(0.16) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isWarning ? Color.red.opacity(0.65) : Color.clear, lineWidth: 1)
        )
        .onTapGesture(count: 2) {
            splitMaterialChannels(id: material.id)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
        }
    }

    private func addSourcesFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Добавить"

        guard panel.runModal() == .OK else { return }

        let existingPaths = Set(sources.map { $0.url.path })
        var added = 0

        for url in panel.urls {
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
            guard !existingPaths.contains(canonical.path), !sources.contains(where: { $0.url.path == canonical.path }) else { continue }
            sources.append(SourceEntry(url: canonical))
            added += 1
        }

        if added > 0 {
            infoMessage = "Добавлено источников: \(added)"
            errorMessage = nil
            if selectedSourceID == nil {
                selectedSourceID = sources.first?.id
            }
        }
    }

    private func openSource(_ source: SourceEntry) {
        guard !isImporting, !isBulkBuilding else { return }

        let imageURLs = imageFileURLs(in: source.url)
        guard !imageURLs.isEmpty else {
            sourceForEmptyAlert = source
            showEmptySourceAlert = true
            return
        }

        activeSourceID = source.id
        selectedSourceID = source.id
        infoMessage = "Открывается источник '\(source.displayName)'…"
        errorMessage = nil

        importMaterials(from: imageURLs, replacingExisting: true) { imported, firstError in
            guard !imported.isEmpty else {
                if let firstError {
                    errorMessage = firstError
                    infoMessage = nil
                }
                return
            }

            let candidates = wavelengthCandidates(in: source.url)
            if candidates.count == 1, let only = candidates.first {
                applyWavelengthCandidateToCurrent(only)
            } else if candidates.count > 1 {
                wavelengthChoiceCandidates = candidates
                wavelengthChoiceSourceName = source.displayName
                showWavelengthChoiceDialog = true
            }

            if let firstError {
                errorMessage = firstError
            }
        }
    }

    private func removeSource(_ source: SourceEntry) {
        sources.removeAll { $0.id == source.id }
        if selectedSourceID == source.id {
            selectedSourceID = sources.first?.id
        }
        if activeSourceID == source.id {
            activeSourceID = nil
        }
    }

    private func removeSelectedSource() {
        guard let selected = selectedSource else { return }
        removeSource(selected)
    }

    private func presentBulkBuildOptions() {
        guard activeSourceID != nil, !materials.isEmpty else {
            errorMessage = "Откройте один источник, настройте материалы и повторите массовую сборку"
            infoMessage = nil
            return
        }
        showBulkBuildModeDialog = true
    }

    private func startBulkBuild(strategy: BulkBuildStrategy) {
        guard let activeSourceID else { return }
        let activeMaterials = materials
        let targets = sources

        guard !targets.isEmpty else {
            infoMessage = "Нет источников для массовой сборки"
            errorMessage = nil
            return
        }

        var templateOrder: [String] = []
        var templateWavelengths: [String: String] = [:]
        var templateNameSet: Set<String> = []

        if strategy == .template {
            templateOrder = activeMaterials.map(\.fileName)
            templateNameSet = Set(templateOrder)
            guard templateNameSet.count == templateOrder.count else {
                errorMessage = "В текущих материалах есть дублирующиеся имена файлов, массовая сборка по шаблону невозможна"
                infoMessage = nil
                return
            }
            templateWavelengths = Dictionary(uniqueKeysWithValues: activeMaterials.map { ($0.fileName, $0.wavelengthText) })
        }

        isBulkBuilding = true
        bulkBuildProgressText = "Подготовка…"
        errorMessage = nil
        infoMessage = nil

        var successCount = 0
        var failures: [String] = []

        func finish() {
            isBulkBuilding = false
            bulkBuildProgressText = nil
            infoMessage = "Массовая сборка завершена: успешно \(successCount), пропущено \(failures.count)"
            if failures.isEmpty {
                errorMessage = nil
            } else {
                errorMessage = failures.joined(separator: " | ")
            }
        }

        func process(index: Int) {
            if index >= targets.count {
                finish()
                return
            }

            let source = targets[index]
            bulkBuildProgressText = "\(index + 1)/\(targets.count): \(source.displayName)"

            if source.id == activeSourceID {
                state.assembleCubeFromMaterials(activeMaterials, openAfterAssemble: false) { assembleResult in
                    switch assembleResult {
                    case .success:
                        successCount += 1
                    case .failure(let error):
                        failures.append("\(source.displayName): \(error.localizedDescription)")
                    }
                    process(index: index + 1)
                }
                return
            }

            loadSourceBundle(for: source) { result in
                switch result {
                case .failure(let error):
                    failures.append("\(source.displayName): \(error.localizedDescription)")
                    process(index: index + 1)

                case .success(let bundle):
                    switch strategy {
                    case .template:
                        guard bundle.materials.count == templateOrder.count else {
                            failures.append("\(source.displayName): отличается количество файлов")
                            process(index: index + 1)
                            return
                        }

                        let sourceNames = Set(bundle.materials.map(\.fileName))
                        guard sourceNames == templateNameSet else {
                            failures.append("\(source.displayName): отличаются имена файлов")
                            process(index: index + 1)
                            return
                        }

                        let byName = Dictionary(uniqueKeysWithValues: bundle.materials.map { ($0.fileName, $0) })
                        var arranged: [HSIAssemblyMaterial] = []
                        arranged.reserveCapacity(templateOrder.count)

                        for name in templateOrder {
                            guard var material = byName[name] else {
                                failures.append("\(source.displayName): отсутствует файл \(name)")
                                process(index: index + 1)
                                return
                            }
                            material.wavelengthText = templateWavelengths[name] ?? ""
                            arranged.append(material)
                        }

                        state.assembleCubeFromMaterials(arranged, openAfterAssemble: false) { assembleResult in
                            switch assembleResult {
                            case .success:
                                successCount += 1
                            case .failure(let error):
                                failures.append("\(source.displayName): \(error.localizedDescription)")
                            }
                            process(index: index + 1)
                        }

                    case .perSourceText:
                        var assembledMaterials: [HSIAssemblyMaterial]? = nil
                        let preferredCandidates = bundle.wavelengthCandidates.sorted { lhs, rhs in
                            if lhs.notation == rhs.notation {
                                return lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent) == .orderedAscending
                            }
                            return lhs.notation == .mapped
                        }

                        for candidate in preferredCandidates {
                            var candidateMaterials = bundle.materials
                            do {
                                let parsed = try parseWavelengthFile(url: candidate.url)
                                _ = try applyParsedWavelengths(parsed, to: &candidateMaterials)
                                candidateMaterials = sortMaterialsByWavelength(candidateMaterials)
                                assembledMaterials = candidateMaterials
                                break
                            } catch {
                                continue
                            }
                        }

                        guard let finalMaterials = assembledMaterials else {
                            failures.append("\(source.displayName): нет подходящего txt с длинами волн")
                            process(index: index + 1)
                            return
                        }

                        state.assembleCubeFromMaterials(finalMaterials, openAfterAssemble: false) { assembleResult in
                            switch assembleResult {
                            case .success:
                                successCount += 1
                            case .failure(let error):
                                failures.append("\(source.displayName): \(error.localizedDescription)")
                            }
                            process(index: index + 1)
                        }
                    }
                }
            }
        }

        process(index: 0)
    }

    private func loadSourceBundle(for source: SourceEntry, completion: @escaping (Result<SourceLoadBundle, SourceLoadError>) -> Void) {
        let sourceURL = source.url
        DispatchQueue.global(qos: .userInitiated).async {
            let imageURLs = imageFileURLs(in: sourceURL)
            guard !imageURLs.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(.noSupportedFiles))
                }
                return
            }

            var loaded: [HSIAssemblyMaterial] = []
            var firstError: String?

            for url in imageURLs {
                switch HSIAssemblyMaterialLoader.load(from: url) {
                case .success(let material):
                    loaded.append(material)
                case .failure(let error):
                    if firstError == nil {
                        firstError = "\(url.lastPathComponent): \(error.localizedDescription)"
                    }
                }
            }

            if let firstError {
                DispatchQueue.main.async {
                    completion(.failure(.importFailure(firstError)))
                }
                return
            }

            if loaded.isEmpty {
                DispatchQueue.main.async {
                    completion(.failure(.noSupportedFiles))
                }
                return
            }

            let candidates = wavelengthCandidates(in: sourceURL)
            let bundle = SourceLoadBundle(materials: loaded, wavelengthCandidates: candidates)
            DispatchQueue.main.async {
                completion(.success(bundle))
            }
        }
    }

    private func imageFileURLs(in directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { HSIAssemblyMaterialLoader.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func wavelengthCandidates(in directory: URL) -> [WavelengthFileCandidate] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [WavelengthFileCandidate] = []
        for url in contents where url.pathExtension.lowercased() == "txt" {
            do {
                let parsed = try parseWavelengthFile(url: url)
                let notation: WavelengthNotation
                switch parsed {
                case .sequential:
                    notation = .sequential
                case .mapped:
                    notation = .mapped
                }
                candidates.append(WavelengthFileCandidate(url: url, notation: notation))
            } catch {
                continue
            }
        }

        return candidates.sorted {
            $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }

    private func importFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Импортировать"
        panel.allowedContentTypes = HSIAssemblyMaterialLoader.supportedUTTypes

        guard panel.runModal() == .OK else { return }
        importMaterials(from: panel.urls, replacingExisting: false, completion: nil)
    }

    private func loadWavelengthsFromPanel() {
        guard !materials.isEmpty else {
            errorMessage = WavelengthImportError.noMaterials.localizedDescription
            infoMessage = nil
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Загрузить"
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "txt") ?? .plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let applied = try applyWavelengthFile(url: url, autoSort: true)
            infoMessage = "Длины волн загружены: обновлено \(applied) материалов"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            infoMessage = nil
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }

        let group = DispatchGroup()
        let lock = NSLock()
        var droppedURLs: [URL] = []

        for provider in fileProviders {
            group.enter()
            provider.loadObject(ofClass: NSURL.self) { object, _ in
                defer { group.leave() }
                guard let url = object as? URL else { return }
                lock.lock()
                droppedURLs.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            importMaterials(from: droppedURLs, replacingExisting: false, completion: nil)
        }

        return true
    }

    private func importMaterials(
        from urls: [URL],
        replacingExisting: Bool,
        completion: (([HSIAssemblyMaterial], String?) -> Void)?
    ) {
        guard !isImporting else { return }

        let normalizedURLs = urls.map { $0.standardizedFileURL }
        let existingPaths = replacingExisting ? Set<String>() : Set(materials.map { $0.sourceURL.standardizedFileURL.path })
        var seenPaths = Set<String>()
        let candidates = normalizedURLs
            .filter { !existingPaths.contains($0.path) }
            .filter { seenPaths.insert($0.path).inserted }

        guard !candidates.isEmpty else {
            infoMessage = "Новых файлов для импорта нет"
            errorMessage = nil
            completion?([], nil)
            return
        }

        isImporting = true
        importProgress = 0
        importProgressText = "Импорт: 0/\(candidates.count)"
        errorMessage = nil
        infoMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            var imported: [HSIAssemblyMaterial] = []
            var firstError: String?

            for (index, url) in candidates.enumerated() {
                switch HSIAssemblyMaterialLoader.load(from: url) {
                case .success(let material):
                    imported.append(material)
                case .failure(let error):
                    if firstError == nil {
                        firstError = "\(url.lastPathComponent): \(error.localizedDescription)"
                    }
                }

                let completed = index + 1
                DispatchQueue.main.async {
                    importProgress = Double(completed) / Double(candidates.count)
                    importProgressText = "Импорт: \(completed)/\(candidates.count)"
                }
            }

            DispatchQueue.main.async {
                isImporting = false
                importProgress = 0
                importProgressText = nil

                if !imported.isEmpty {
                    if replacingExisting {
                        materials = imported
                    } else {
                        materials.append(contentsOf: imported)
                    }

                    if selectedMaterialID == nil || replacingExisting {
                        selectedMaterialID = materials.first?.id
                    }

                    if let firstError {
                        infoMessage = "Добавлено: \(imported.count). Часть файлов пропущена"
                        errorMessage = firstError
                    } else {
                        infoMessage = "Добавлено файлов: \(imported.count)"
                        errorMessage = nil
                    }
                } else if let firstError {
                    errorMessage = firstError
                    infoMessage = nil
                }

                completion?(imported, firstError)
            }
        }
    }

    private func applyWavelengthCandidateToCurrent(_ candidate: WavelengthFileCandidate) {
        do {
            let applied = try applyWavelengthFile(url: candidate.url, autoSort: true)
            infoMessage = "Применён файл длин волн: \(candidate.url.lastPathComponent) (\(applied))"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            infoMessage = nil
        }
    }

    private func applyWavelengthFile(url: URL, autoSort: Bool) throws -> Int {
        var updated = materials
        let parsed = try parseWavelengthFile(url: url)
        let applied = try applyParsedWavelengths(parsed, to: &updated)
        materials = autoSort ? sortMaterialsByWavelength(updated) : updated
        return applied
    }

    private func parseWavelengthFile(url: URL) throws -> ParsedWavelengthData {
        guard let text = readTextFile(url: url) else {
            throw WavelengthImportError.fileReadFailed
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw WavelengthImportError.emptyFile
        }

        let colonFlags = lines.map { $0.contains(":") }
        let allWithColon = colonFlags.allSatisfy { $0 }
        let noneWithColon = colonFlags.allSatisfy { !$0 }

        if !allWithColon && !noneWithColon {
            throw WavelengthImportError.mixedNotation
        }

        if noneWithColon {
            var values: [Double] = []
            values.reserveCapacity(lines.count)
            for (idx, line) in lines.enumerated() {
                guard let value = parseWavelengthValue(line) else {
                    throw WavelengthImportError.invalidValue(line: idx + 1)
                }
                values.append(value)
            }
            return .sequential(values)
        }

        var mappings: [(String, Double)] = []
        mappings.reserveCapacity(lines.count)
        for (idx, line) in lines.enumerated() {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw WavelengthImportError.invalidMapping(line: idx + 1)
            }

            let name = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw WavelengthImportError.invalidMapping(line: idx + 1)
            }
            guard let value = parseWavelengthValue(rawValue) else {
                throw WavelengthImportError.invalidValue(line: idx + 1)
            }
            mappings.append((name, value))
        }

        return .mapped(mappings)
    }

    private func applyParsedWavelengths(_ parsed: ParsedWavelengthData, to materials: inout [HSIAssemblyMaterial]) throws -> Int {
        switch parsed {
        case .sequential(let values):
            guard values.count == materials.count else {
                throw WavelengthImportError.countMismatch(expected: materials.count, actual: values.count)
            }
            for idx in materials.indices {
                materials[idx].wavelengthText = normalizedWavelengthString(values[idx])
            }
            return materials.count

        case .mapped(let mappings):
            var updatedIndices: Set<Int> = []

            for (rawName, value) in mappings {
                let normalizedName = rawName.lowercased()
                for idx in materials.indices {
                    let displayName = materials[idx].fileName.lowercased()
                    let sourceName = materials[idx].sourceURL.lastPathComponent.lowercased()
                    if displayName == normalizedName || sourceName == normalizedName {
                        materials[idx].wavelengthText = normalizedWavelengthString(value)
                        updatedIndices.insert(idx)
                    }
                }
            }

            guard !updatedIndices.isEmpty else {
                throw WavelengthImportError.noMatchingFiles
            }

            return updatedIndices.count
        }
    }

    private func readTextFile(url: URL) -> String? {
        let encodings: [String.Encoding] = [.utf8, .utf16, .windowsCP1251, .isoLatin1]
        for encoding in encodings {
            if let text = try? String(contentsOf: url, encoding: encoding) {
                return text
            }
        }
        return nil
    }

    private func parseWavelengthValue(_ raw: String) -> Double? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private func normalizedWavelengthString(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    private func assemble() {
        errorMessage = nil
        infoMessage = nil

        state.assembleCubeFromMaterials(materials, openAfterAssemble: true) { result in
            switch result {
            case .success(let url):
                infoMessage = "Новый ГСИ добавлен в библиотеку: \(url.lastPathComponent)"
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func sortByWavelengths(showMessage: Bool = true) {
        materials = sortMaterialsByWavelength(materials)
        if showMessage {
            infoMessage = "Материалы отсортированы по длинам волн"
            errorMessage = nil
        }
    }

    private func sortMaterialsByWavelength(_ source: [HSIAssemblyMaterial]) -> [HSIAssemblyMaterial] {
        source.enumerated().sorted { lhs, rhs in
            let left = parsedWavelength(from: lhs.element.wavelengthText)
            let right = parsedWavelength(from: rhs.element.wavelengthText)

            switch (left, right) {
            case let (l?, r?):
                if l == r {
                    return lhs.offset < rhs.offset
                }
                return l < r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }
        .map(\.element)
    }

    private func parsedWavelength(from text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private func splitMaterialChannels(id: UUID) {
        guard let index = materials.firstIndex(where: { $0.id == id }) else { return }
        let material = materials[index]
        guard !material.isGrayscale else { return }

        switch HSIAssemblyMaterialLoader.splitIntoChannels(from: material) {
        case .success(let channels):
            guard channels.count > 1 else { return }
            materials.remove(at: index)
            materials.insert(contentsOf: channels, at: index)
            selectedMaterialID = channels.first?.id
            infoMessage = "\(material.fileName) разбит на каналы"
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
            infoMessage = nil
        }
    }

    private func moveMaterials(from source: IndexSet, to destination: Int) {
        materials.move(fromOffsets: source, toOffset: destination)
    }

    private func removeSelectedMaterial() {
        guard let selectedMaterialID else { return }
        removeMaterial(id: selectedMaterialID)
    }

    private func removeMaterial(id: UUID) {
        materials.removeAll { $0.id == id }
        if selectedMaterialID == id {
            selectedMaterialID = materials.first?.id
        }
    }

    private func syncSelection(with newMaterials: [HSIAssemblyMaterial]) {
        guard !newMaterials.isEmpty else {
            selectedMaterialID = nil
            previewImage = nil
            return
        }

        if let selectedMaterialID,
           newMaterials.contains(where: { $0.id == selectedMaterialID }) {
            return
        }

        self.selectedMaterialID = newMaterials[0].id
    }

    private func loadPreviewImage() {
        guard let selectedMaterial else {
            previewImage = nil
            return
        }

        let width = selectedMaterial.width
        let height = selectedMaterial.height
        let values = selectedMaterial.channelValues
        guard values.count == width * height else {
            previewImage = NSImage(contentsOf: selectedMaterial.sourceURL)
            return
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ), let bitmap = rep.bitmapData else {
            previewImage = NSImage(contentsOf: selectedMaterial.sourceURL)
            return
        }

        for i in 0..<values.count {
            let value = values[i]
            let pixelIndex = i * 4
            bitmap[pixelIndex] = value
            bitmap[pixelIndex + 1] = value
            bitmap[pixelIndex + 2] = value
            bitmap[pixelIndex + 3] = 255
        }

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        previewImage = image
    }
}
