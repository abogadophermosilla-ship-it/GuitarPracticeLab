import Foundation
import SwiftData

enum LessonAttachmentKind: String, CaseIterable, Codable, Identifiable {
    case pdf = "PDF"
    case guitarPro = "Guitar Pro"
    case daw = "Archivo DAW"
    case audio = "Audio"
    case video = "Video"
    case other = "Otro"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pdf: "doc.richtext"
        case .guitarPro: "guitars"
        case .daw: "pianokeys"
        case .audio: "waveform"
        case .video: "video"
        case .other: "paperclip"
        }
    }
}

/// Un adjunto de una clase: un archivo local (PDF, Guitar Pro, proyecto de EZbass/EZkeys/EZdrummer/
/// Superior Drummer, audio, video) referenciado por bookmark de seguridad, o un enlace externo
/// pegado por el usuario (ej. un video de YouTube). Los audios marcados como tales pueden
/// transcribirse localmente; el resto de binarios se conserva sin modificar.
@Model
final class LessonAttachment {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var bookmarkData: Data?
    var kindRaw: String
    var externalURLString: String

    init(
        id: UUID = UUID(),
        fileName: String = "",
        bookmarkData: Data? = nil,
        kind: LessonAttachmentKind = .other,
        externalURLString: String = ""
    ) {
        self.id = id
        self.fileName = fileName
        self.bookmarkData = bookmarkData
        self.kindRaw = kind.rawValue
        self.externalURLString = externalURLString
    }

    var kind: LessonAttachmentKind {
        get { LessonAttachmentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var displayName: String {
        fileName.isEmpty ? externalURLString : fileName
    }

    /// Convierte el texto pegado en una URL web abrible. También acepta enlaces sin protocolo,
    /// algo frecuente al copiar `youtube.com/...` desde el navegador.
    static func normalizedExternalURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()
        let candidate: String
        if lowercased.hasPrefix("https://") || lowercased.hasPrefix("http://") {
            candidate = trimmed
        } else {
            guard !lowercased.contains("://") else { return nil }
            candidate = "https://\(trimmed)"
        }

        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host,
              !host.isEmpty else {
            return nil
        }
        return components.url
    }

    static func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be"
            || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com")
    }
}
