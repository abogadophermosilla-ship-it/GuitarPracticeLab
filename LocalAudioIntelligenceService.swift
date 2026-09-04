import Foundation
import AppKit

enum LocalAITool: String, CaseIterable, Identifiable {
    case whisper = "MLX Whisper"
    case basicPitch = "Basic Pitch"
    case demucs = "Demucs"
    case essentia = "Essentia"
    case ffmpeg = "FFmpeg"

    var id: String { rawValue }

    fileprivate var executableNames: [String] {
        switch self {
        case .whisper: ["mlx_whisper", "mlx-whisper"]
        case .basicPitch: ["basic-pitch"]
        case .demucs: ["demucs"]
        case .essentia: ["essentia_streaming_extractor_music", "python3.11", "python"]
        case .ffmpeg: ["ffmpeg"]
        }
    }

    fileprivate var environmentFolder: String? {
        switch self {
        case .whisper: "whisper"
        case .basicPitch: "basic-pitch"
        case .demucs: "demucs"
        case .essentia: "essentia"
        case .ffmpeg: nil
        }
    }
}

struct LocalAIToolStatus: Identifiable {
    let tool: LocalAITool
    let executableURL: URL?

    var id: String { tool.id }
    var isAvailable: Bool { executableURL != nil }
}

struct AudioTranscriptionResult {
    let text: String
    let timestampedText: String
    let language: String
    let segmentCount: Int
}

struct PerformanceAnalysisResult {
    let summary: String
    let midiURL: URL?
    let noteCSVURL: URL?
    let metadataJSON: String
}

struct StemSeparationResult {
    let outputFolder: URL
    let stemURLs: [URL]
}

enum LocalAudioIntelligenceError: LocalizedError {
    case toolUnavailable(LocalAITool)
    case unsupportedFile(String)
    case cannotAccessSource
    case externalMaterialsUnavailable
    case logicIsRunning
    case systemBusy
    case processFailed(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .toolUnavailable(let tool):
            "\(tool.rawValue) no está instalado. Revisa el estado de motores en Configuración."
        case .unsupportedFile(let extensionName):
            "El archivo .\(extensionName) no es audio procesable. Expórtalo desde Logic como WAV, AIFF, M4A o MP3."
        case .cannotAccessSource:
            "No fue posible acceder al archivo de audio."
        case .externalMaterialsUnavailable:
            "Conecta el disco externo: los MIDI y stems se guardan dentro de VST/Clases/Proyectos/IA GuitarPracticeLab."
        case .logicIsRunning:
            "Logic Pro está abierto. El procesamiento pesado se pausó para evitar dropouts; puedes permitirlo explícitamente en Configuración."
        case .systemBusy:
            "El Mac está muy cargado o caliente. Espera un momento antes de procesar audio."
        case .processFailed(let details):
            details
        case .invalidOutput(let details):
            details
        }
    }
}

enum LocalAudioIntelligenceService {
    static let supportedAudioExtensions: Set<String> = [
        "wav", "aif", "aiff", "mp3", "m4a", "caf", "flac"
    ]

    static var environmentRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GuitarPracticeLab", isDirectory: true)
            .appendingPathComponent("AI", isDirectory: true)
    }

    static var statuses: [LocalAIToolStatus] {
        LocalAITool.allCases.map {
            LocalAIToolStatus(tool: $0, executableURL: executable(for: $0))
        }
    }

    static func executable(for tool: LocalAITool) -> URL? {
        var candidates: [URL] = []
        if let folder = tool.environmentFolder {
            for name in tool.executableNames {
                candidates.append(
                    environmentRoot
                        .appendingPathComponent(folder, isDirectory: true)
                        .appendingPathComponent("bin", isDirectory: true)
                        .appendingPathComponent(name)
                )
            }
        }
        for prefix in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            for name in tool.executableNames {
                candidates.append(URL(fileURLWithPath: prefix).appendingPathComponent(name))
            }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func transcribe(
        bookmarkData: Data,
        language: String = "es"
    ) async throws -> AudioTranscriptionResult {
        guard let whisper = executable(for: .whisper) else {
            throw LocalAudioIntelligenceError.toolUnavailable(.whisper)
        }
        let source = try accessibleAudioURL(from: bookmarkData)
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }
        try guardResources(isHeavy: false)

        let outputFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuitarPracticeLab-Whisper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputFolder) }

        let model = UserDefaults.standard.string(forKey: "whisperModel")
            .flatMap { $0.isEmpty ? nil : $0 } ?? "mlx-community/whisper-large-v3-turbo"
        let result = try await run(
            executable: whisper,
            arguments: [
                source.path,
                "--language", language,
                "--model", model,
                "--output-dir", outputFolder.path,
                "--output-format", "json"
            ]
        )

        let jsonURLs = recursiveFiles(in: outputFolder).filter {
            $0.pathExtension.caseInsensitiveCompare("json") == .orderedSame
        }
        guard let jsonURL = jsonURLs.first,
              let data = try? Data(contentsOf: jsonURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalAudioIntelligenceError.invalidOutput(
                "MLX Whisper terminó sin crear una transcripción JSON. \(result.output)"
            )
        }
        let text = (object["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw LocalAudioIntelligenceError.invalidOutput("MLX Whisper devolvió una transcripción vacía.")
        }
        let segments = object["segments"] as? [[String: Any]] ?? []
        let timestampedText = segments.compactMap { segment -> String? in
            guard let segmentText = segment["text"] as? String else { return nil }
            let cleanText = segmentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanText.isEmpty else { return nil }
            let start = (segment["start"] as? NSNumber)?.doubleValue ?? 0
            let end = (segment["end"] as? NSNumber)?.doubleValue ?? start
            return "[\(timestamp(start))–\(timestamp(end))] \(cleanText)"
        }.joined(separator: "\n")
        return AudioTranscriptionResult(
            text: text,
            timestampedText: timestampedText.isEmpty ? text : timestampedText,
            language: object["language"] as? String ?? language,
            segmentCount: segments.count
        )
    }

    static func analyzePerformance(
        bookmarkData: Data,
        targetBPM: Int?
    ) async throws -> PerformanceAnalysisResult {
        let source = try accessibleAudioURL(from: bookmarkData)
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }
        try guardResources(isHeavy: true)
        guard LearningMaterialsService.isAvailable else {
            throw LocalAudioIntelligenceError.externalMaterialsUnavailable
        }

        let destination = try uniqueOutputFolder(
            category: "Análisis",
            sourceName: source.deletingPathExtension().lastPathComponent
        )
        var lines: [String] = []
        var metadata: [String: Any] = [:]
        var midiURL: URL?
        var csvURL: URL?

        if let ffprobe = executableForFFprobe() {
            let probe = try await run(
                executable: ffprobe,
                arguments: [
                    "-v", "quiet",
                    "-print_format", "json",
                    "-show_format",
                    "-show_streams",
                    source.path
                ]
            )
            if let data = probe.output.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                metadata["ffprobe"] = object
                if let format = object["format"] as? [String: Any],
                   let durationRaw = format["duration"] as? String,
                   let duration = Double(durationRaw) {
                    lines.append("Duración analizada: \(formatSeconds(duration)).")
                }
            }
        }

        if let basicPitch = executable(for: .basicPitch) {
            _ = try await run(
                executable: basicPitch,
                arguments: [
                    "--model-serialization", "onnx",
                    "--save-midi",
                    "--save-note-events",
                    "--multiple-pitch-bends",
                    destination.path,
                    source.path
                ]
            )
            let outputs = recursiveFiles(in: destination)
            midiURL = outputs.first { ["mid", "midi"].contains($0.pathExtension.lowercased()) }
            csvURL = outputs.first { $0.pathExtension.caseInsensitiveCompare("csv") == .orderedSame }
            if let csvURL {
                let noteSummary = summarizeNoteCSV(csvURL)
                lines.append(contentsOf: noteSummary.lines)
                metadata["notes"] = noteSummary.metadata
            }
        } else {
            lines.append("Basic Pitch no está disponible: se omitió la detección de notas y pitch bends.")
        }

        if let essentia = executable(for: .essentia) {
            let output = destination.appendingPathComponent("essentia.json")
            let arguments = essentia.lastPathComponent.hasPrefix("python")
                ? ["-c", essentiaPythonScript, source.path, output.path]
                : [source.path, output.path]
            _ = try await run(executable: essentia, arguments: arguments)
            if let data = try? Data(contentsOf: output),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                metadata["essentia"] = object
                let bpm = nestedNumber(object, path: ["rhythm", "bpm"])
                if let bpm {
                    lines.append("Tempo detectado: \(Int(bpm.rounded())) BPM.")
                    if let targetBPM, targetBPM > 0 {
                        let delta = Int((bpm - Double(targetBPM)).rounded())
                        lines.append(delta == 0
                                     ? "Coincide con el tempo objetivo."
                                     : "Diferencia frente al objetivo: \(delta > 0 ? "+" : "")\(delta) BPM.")
                    }
                }
                if let key = nestedString(object, path: ["tonal", "key_key"]),
                   let scale = nestedString(object, path: ["tonal", "key_scale"]) {
                    lines.append("Centro tonal estimado: \(key) \(scale).")
                }
            }
        } else {
            lines.append("Essentia no está disponible: se omitieron tempo y centro tonal automáticos.")
        }

        let metadataJSON: String
        if JSONSerialization.isValidJSONObject(metadata),
           let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]) {
            metadataJSON = String(data: data, encoding: .utf8) ?? ""
        } else {
            metadataJSON = ""
        }
        return PerformanceAnalysisResult(
            summary: lines.joined(separator: "\n"),
            midiURL: midiURL,
            noteCSVURL: csvURL,
            metadataJSON: metadataJSON
        )
    }

    static func separateStems(bookmarkData: Data) async throws -> StemSeparationResult {
        guard let demucs = executable(for: .demucs) else {
            throw LocalAudioIntelligenceError.toolUnavailable(.demucs)
        }
        let source = try accessibleAudioURL(from: bookmarkData)
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }
        try guardResources(isHeavy: true)
        guard LearningMaterialsService.isAvailable else {
            throw LocalAudioIntelligenceError.externalMaterialsUnavailable
        }

        let destination = try uniqueOutputFolder(
            category: "Stems",
            sourceName: source.deletingPathExtension().lastPathComponent
        )
        _ = try await run(
            executable: demucs,
            arguments: [
                "--out", destination.path,
                "--name", "htdemucs",
                source.path
            ],
            extraEnvironment: [
                "OMP_NUM_THREADS": "4",
                "PYTORCH_ENABLE_MPS_FALLBACK": "1"
            ]
        )
        let stems = recursiveFiles(in: destination).filter {
            ["wav", "mp3", "flac"].contains($0.pathExtension.lowercased())
        }
        guard !stems.isEmpty else {
            throw LocalAudioIntelligenceError.invalidOutput("Demucs terminó sin crear stems de audio.")
        }
        return StemSeparationResult(outputFolder: destination, stemURLs: stems)
    }

    private static func accessibleAudioURL(from bookmarkData: Data) throws -> URL {
        guard let url = SecurityScopedFile.resolve(bookmarkData) else {
            throw LocalAudioIntelligenceError.cannotAccessSource
        }
        let ext = url.pathExtension.lowercased()
        guard supportedAudioExtensions.contains(ext) else {
            throw LocalAudioIntelligenceError.unsupportedFile(ext)
        }
        return url
    }

    private static func guardResources(isHeavy: Bool) throws {
        let snapshot = ResourceMonitor.snapshot()
        guard snapshot.thermalState != .critical, snapshot.thermalState != .serious else {
            throw LocalAudioIntelligenceError.systemBusy
        }
        let cores = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
        guard snapshot.loadAverage1m < cores * (isHeavy ? 0.70 : 0.90) else {
            throw LocalAudioIntelligenceError.systemBusy
        }
        let allowWithLogic = UserDefaults.standard.bool(forKey: "allowHeavyAIWithLogic")
        if !allowWithLogic,
           NSWorkspace.shared.runningApplications.contains(where: {
               $0.bundleIdentifier == "com.apple.logic10" ||
                   $0.localizedName?.localizedCaseInsensitiveContains("Logic Pro") == true
           }) {
            throw LocalAudioIntelligenceError.logicIsRunning
        }
    }

    private static func uniqueOutputFolder(category: String, sourceName: String) throws -> URL {
        let safeName = sourceName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let destination = LearningMaterialsService.projectsURL
            .appendingPathComponent("IA GuitarPracticeLab", isDirectory: true)
            .appendingPathComponent(category, isDirectory: true)
            .appendingPathComponent("\(safeName)-\(formatter.string(from: .now))", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        return destination
    }

    private static func executableForFFprobe() -> URL? {
        for path in ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/usr/bin/ffprobe"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private static func run(
        executable: URL,
        arguments: [String],
        extraEnvironment: [String: String] = [:]
    ) async throws -> (output: String, status: Int32) {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/taskpolicy")
            process.arguments = ["-b", executable.path] + arguments
            process.standardOutput = pipe
            process.standardError = pipe
            var environment = ProcessInfo.processInfo.environment
            extraEnvironment.forEach { environment[$0.key] = $0.value }
            process.environment = environment
            do {
                try process.run()
            } catch {
                throw LocalAudioIntelligenceError.processFailed(
                    "No se pudo iniciar \(executable.lastPathComponent): \(error.localizedDescription)"
                )
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw LocalAudioIntelligenceError.processFailed(
                    "\(executable.lastPathComponent) falló (código \(process.terminationStatus)). \(output.suffix(1200))"
                )
            }
            return (output, process.terminationStatus)
        }.value
    }

    private static func recursiveFiles(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private static func summarizeNoteCSV(_ url: URL) -> (lines: [String], metadata: [String: Any]) {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return (["No fue posible leer los eventos de notas."], [:])
        }
        let rows = raw.split(whereSeparator: \.isNewline).map {
            $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
        guard let headers = rows.first else { return (["No se detectaron notas."], [:]) }

        func index(_ candidates: [String]) -> Int? {
            headers.firstIndex { header in
                candidates.contains(header.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        let pitchIndex = index(["pitch_midi", "pitch"])
        let startIndex = index(["start_time_s", "start_time"])
        let bendIndex = index(["pitch_bend", "pitch_bends"])
        let dataRows = Array(rows.dropFirst())
        let pitches = dataRows.compactMap { row -> Int? in
            guard let pitchIndex, row.indices.contains(pitchIndex) else { return nil }
            return Int(Double(row[pitchIndex]) ?? -1)
        }.filter { $0 >= 0 }
        let starts = dataRows.compactMap { row -> Double? in
            guard let startIndex, row.indices.contains(startIndex) else { return nil }
            return Double(row[startIndex])
        }.sorted()
        let bendValues = dataRows.flatMap { row -> [Int] in
            guard let bendIndex, row.indices.contains(bendIndex) else { return [] }
            return row[bendIndex...].compactMap {
                Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        let bendCount = dataRows.filter { row in
            guard let bendIndex, row.indices.contains(bendIndex) else { return false }
            return row[bendIndex...].contains {
                (Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) != 0
            }
        }.count

        var metadata: [String: Any] = [
            "count": pitches.count,
            "pitchSequence": pitches,
            "startTimes": starts,
            "pitchBendEvents": bendCount,
            "meanAbsolutePitchBendUnits": bendValues.isEmpty
                ? 0
                : bendValues.reduce(0.0) { $0 + abs(Double($1)) } / Double(bendValues.count)
        ]
        var lines = ["Notas detectadas: \(pitches.count)."]
        if let low = pitches.min(), let high = pitches.max() {
            lines.append("Rango MIDI: \(low)–\(high).")
        }
        if bendCount > 0 {
            lines.append("Eventos con pitch bend: \(bendCount).")
        }
        if !bendValues.isEmpty {
            let meanUnits = bendValues.reduce(0.0) { $0 + abs(Double($1)) } / Double(bendValues.count)
            let cents = Int((meanUnits * (100.0 / 3.0)).rounded())
            lines.append("Desvío medio de altura estimado: \(cents) cents (incluye bends y vibrato).")
        }
        if starts.count > 2 {
            let intervals = zip(starts.dropFirst(), starts).map { later, earlier in
                later - earlier
            }
            let mean = intervals.reduce(0, +) / Double(intervals.count)
            if mean > 0 {
                let variance = intervals.reduce(0) { $0 + pow($1 - mean, 2) } / Double(intervals.count)
                let variation = sqrt(variance) / mean
                lines.append("Variación relativa entre ataques: \(Int((variation * 100).rounded()))%.")
                metadata["attackIntervalVariation"] = variation
            }
        }
        if let low = pitches.min() { metadata["lowestMIDIPitch"] = low }
        if let high = pitches.max() { metadata["highestMIDIPitch"] = high }
        return (lines, metadata)
    }

    private static func nestedNumber(_ object: [String: Any], path: [String]) -> Double? {
        var value: Any = object
        for key in path {
            guard let dictionary = value as? [String: Any], let next = dictionary[key] else { return nil }
            value = next
        }
        return value as? Double
    }

    private static func nestedString(_ object: [String: Any], path: [String]) -> String? {
        var value: Any = object
        for key in path {
            guard let dictionary = value as? [String: Any], let next = dictionary[key] else { return nil }
            value = next
        }
        return value as? String
    }

    private static func formatSeconds(_ seconds: Double) -> String {
        let value = Int(seconds.rounded())
        return "\(value / 60) min \(value % 60) s"
    }

    private static func timestamp(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static let essentiaPythonScript = """
    import json
    import sys
    import essentia.standard as es

    audio = es.MonoLoader(filename=sys.argv[1], sampleRate=44100)()
    bpm, ticks, confidence, estimates, intervals = es.RhythmExtractor2013(method="multifeature")(audio)
    key, scale, strength = es.KeyExtractor()(audio)
    result = {
        "rhythm": {"bpm": float(bpm), "confidence": float(confidence)},
        "tonal": {
            "key_key": str(key),
            "key_scale": str(scale),
            "key_strength": float(strength)
        }
    }
    with open(sys.argv[2], "w", encoding="utf-8") as handle:
        json.dump(result, handle)
    """
}
