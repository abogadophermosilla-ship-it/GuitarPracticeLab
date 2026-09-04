import SwiftUI
import AppKit

struct PDFCropSelectionView: View {
    let image: NSImage
    let onCancel: () -> Void
    let onConfirm: (Data) -> Void

    @State private var dragStart: CGPoint?
    @State private var selection = CGRect.zero
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Recortar imagen de la página")
                    .font(.title2.bold())
                Spacer()
                Button("Cancelar", action: onCancel)
            }

            GeometryReader { geometry in
                let fitted = aspectFitRect(imageSize: image.size, in: geometry.size)
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.04)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: fitted.width, height: fitted.height)
                        .position(x: fitted.midX, y: fitted.midY)

                    if !selection.isEmpty {
                        Rectangle()
                            .stroke(.blue, style: StrokeStyle(lineWidth: 2, dash: [6]))
                            .background(.blue.opacity(0.12))
                            .frame(width: selection.width, height: selection.height)
                            .offset(x: selection.minX, y: selection.minY)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let point = clamped(value.location, to: fitted)
                            let start = dragStart ?? point
                            dragStart = start
                            selection = CGRect(
                                x: min(start.x, point.x),
                                y: min(start.y, point.y),
                                width: abs(point.x - start.x),
                                height: abs(point.y - start.y)
                            )
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .onAppear {
                    containerWidth = geometry.size.width
                    containerHeight = geometry.size.height
                }
                .onChange(of: geometry.size) { _, newSize in
                    containerWidth = newSize.width
                    containerHeight = newSize.height
                    selection = .zero
                }
            }

            if !errorMessage.isEmpty {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Text("Arrastrá sobre la página para seleccionar un diagrama, pentagrama o fragmento.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Usar recorte") { confirmCrop() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.width < 8 || selection.height < 8)
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 520)
    }

    private func confirmCrop() {
        guard let normalized = normalizedSelection(), let data = PDFPageRenderer.crop(image, normalizedRect: normalized) else {
            errorMessage = "No fue posible crear el recorte. Prueba con una selección más grande."
            return
        }
        onConfirm(data)
    }

    @State private var containerWidth: CGFloat = 1
    @State private var containerHeight: CGFloat = 1

    private func normalizedSelection() -> CGRect? {
        let fitted = aspectFitRect(
            imageSize: image.size,
            in: CGSize(width: containerWidth, height: containerHeight)
        )
        guard fitted.width > 0, fitted.height > 0 else { return nil }
        let clipped = selection.intersection(fitted)
        guard clipped.width > 0, clipped.height > 0 else { return nil }
        return CGRect(
            x: (clipped.minX - fitted.minX) / fitted.width,
            y: (clipped.minY - fitted.minY) / fitted.height,
            width: clipped.width / fitted.width,
            height: clipped.height / fitted.height
        )
    }

    private func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }
}
