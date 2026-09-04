import SwiftUI
import SwiftData

struct InstrumentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Instrument.name) private var instruments: [Instrument]
    @State private var showingNewInstrument = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Instrumentos")
                            .font(.largeTitle.bold())
                        Text("Afinaciones, configuración y uso de cada instrumento")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Agregar instrumento", systemImage: "plus") { showingNewInstrument = true }
                        .buttonStyle(.borderedProminent)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                    ForEach(instruments) { instrument in
                        CardContainer {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: instrument.kind == "Bajo" ? "music.note" : "guitars.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading) {
                                        Text(instrument.name).font(.headline)
                                        Text(instrument.kind).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Bindable(instrument).isActive)
                                        .labelsHidden()
                                }
                                Divider()
                                LabeledContent("Afinación", value: instrument.tuning)
                                if !instrument.pickups.isEmpty { LabeledContent("Pastillas", value: instrument.pickups) }
                                if !instrument.notes.isEmpty { Text(instrument.notes).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .contextMenu {
                            Button("Eliminar", systemImage: "trash", role: .destructive) { modelContext.delete(instrument) }
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingNewInstrument) {
            NewInstrumentView()
                .frame(minWidth: 480, idealWidth: 560, minHeight: 440)
        }
    }
}

private struct NewInstrumentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var kind = "Guitarra eléctrica"
    @State private var pickups = ""
    @State private var tuning = "Estándar"
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $name)
                Picker("Tipo", selection: $kind) {
                    ForEach(["Guitarra eléctrica", "Guitarra electroacústica", "Guitarra clásica", "Bajo", "Otro"], id: \.self) { Text($0) }
                }
                TextField("Pastillas", text: $pickups)
                TextField("Afinación", text: $tuning)
                TextField("Notas", text: $notes, axis: .vertical).lineLimit(3...6)
            }
            .formStyle(.grouped)
            .navigationTitle("Nuevo instrumento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        modelContext.insert(Instrument(name: name, kind: kind, pickups: pickups, tuning: tuning, notes: notes))
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
