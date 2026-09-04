import SwiftUI
import SwiftData

struct StudioView: View {
    @Query(sort: \StudioAsset.assetTypeRaw) private var assets: [StudioAsset]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Estudio")
                        .font(.largeTitle.bold())
                    Text("Cómo participa tu hardware y software en la práctica")
                        .foregroundStyle(.secondary)
                }

                ForEach(AssetType.allCases) { type in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(type.rawValue)
                            .font(.title2.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                            ForEach(assets.filter { $0.assetType == type }) { asset in
                                CardContainer {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Image(systemName: type == .hardware ? "desktopcomputer" : "app.dashed")
                                                .font(.title2)
                                                .foregroundStyle(type == .hardware ? .orange : .purple)
                                            VStack(alignment: .leading) {
                                                Text(asset.name).font(.headline)
                                                Text(asset.category).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                        }
                                        Divider()
                                        Text(asset.usage.isEmpty ? "Sin uso definido" : asset.usage)
                                            .font(.callout)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}
