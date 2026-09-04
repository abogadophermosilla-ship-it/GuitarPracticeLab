import SwiftUI

/// Elementos visuales compartidos. Mantenerlos aquí evita que cada pantalla invente
/// sus propios radios, bordes y sombras y hace que la aplicación se sienta unificada.
enum PracticeTheme {
    static let accent = Color.indigo
    static let softSurface = Color(nsColor: .controlBackgroundColor)
    static let windowSurface = Color(nsColor: .windowBackgroundColor)
}

struct CardContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        LinearGradient(
                            colors: [.white.opacity(0.10), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.primary.opacity(0.14), .primary.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.07), radius: 16, y: 7)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        CardContainer {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint.gradient)
                    .frame(width: 46, height: 46)
                    .background {
                        Circle()
                            .fill(tint.opacity(0.14))
                            .overlay {
                                Circle().strokeBorder(tint.opacity(0.14), lineWidth: 1)
                            }
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(value)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(tint.gradient)
                .frame(width: 4, height: 46)
                .padding(.leading, 1)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(PracticeTheme.softSurface.opacity(0.72), in: Capsule())
            }
        }
    }
}

struct StatusPill: View {
    let text: String
    var tint: Color = .blue

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.16), lineWidth: 1)
            }
    }
}

/// Campo de tempo (BPM) que permite escribir el número directamente en vez de
/// depender solo de las flechas del Stepper, que son lentas para saltos grandes.
struct BPMField: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...300
    var placeholder: String = "0"

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if !label.isEmpty {
                Text(label)
                Spacer(minLength: 8)
            }

            Stepper("", value: $value, in: range)
                .labelsHidden()
                .fixedSize()

            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .focused($isFocused)
                .onSubmit(commitText)
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitText() }
                }

            Text("BPM")
                .foregroundStyle(.secondary)
        }
        .onAppear { text = value == 0 ? "" : String(value) }
        .onChange(of: value) { _, newValue in
            guard !isFocused else { return }
            text = newValue == 0 ? "" : String(newValue)
        }
    }

    private func commitText() {
        guard let parsed = Int(text) else {
            text = value == 0 ? "" : String(value)
            return
        }
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        value = clamped
        text = clamped == 0 ? "" : String(clamped)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2.weight(.medium))
                .foregroundStyle(PracticeTheme.accent)
                .frame(width: 46, height: 46)
                .background(PracticeTheme.accent.opacity(0.12), in: Circle())
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 310)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(PracticeTheme.softSurface.opacity(0.46), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
