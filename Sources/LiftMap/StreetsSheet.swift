import SwiftUI
import LiftCore
import LiftMapCore

/// Says what a street download is, how large, from where and what that server
/// learns, before anything is asked for; the download starts only on
/// **Download**. A failed download keeps what it got: **Try again** picks up
/// where it stopped (`MapDownload.resume`).
///
/// `onDone` gets the finished area, or nil when the person cancels. The
/// presenter dismisses the sheet.
public struct StreetsSheet: View {
    enum Mode: Equatable {
        /// A new area.
        case new
        /// The same area again (Maps → Update): the radius is fixed.
        case update
        /// An area begun before and not finished: only Try again.
        case resume(UUID)
    }

    enum Phase: Equatable {
        case ready
        case downloading(done: Int, total: Int)
        case failed
    }

    static let source = "OpenStreetMap data from OpenFreeMap"
    static let serverLearns = "OpenFreeMap learns which area you asked for, once."
    static let failure = "Couldn't finish. Try again to pick up where it stopped."

    let name: String
    let store: StreetStore
    let note: String?
    let mode: Mode
    let onDone: (StreetArea?) -> Void

    @State private var plan: StreetAreaPlan
    @State private var phase: Phase
    /// The area this sheet is filling, once begun.
    @State private var areaID: UUID?
    @State private var task: Task<Void, Never>?

    /// - Parameter note: one more line under what the server learns, for
    ///   example Coach's "This asks for the area around your client's route."
    public init(plan: StreetAreaPlan, name: String, store: StreetStore, note: String? = nil,
                onDone: @escaping (StreetArea?) -> Void) {
        self.init(plan: plan, name: name, store: store, note: note, mode: .new, onDone: onDone)
    }

    init(plan: StreetAreaPlan, name: String, store: StreetStore, note: String? = nil, mode: Mode,
         onDone: @escaping (StreetArea?) -> Void) {
        self.name = name
        self.store = store
        self.note = note
        self.mode = mode
        self.onDone = onDone
        _plan = State(initialValue: plan)
        if case .resume(let id) = mode {
            _areaID = State(initialValue: id)
            _phase = State(initialValue: .failed)
        } else {
            _phase = State(initialValue: .ready)
        }
    }

    /// "About 40 MB".
    static func sizeText(bytes: Int) -> String {
        "About " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var isDownloading: Bool {
        if case .downloading = phase { return true }
        return false
    }

    /// A route plan is not a radius, and an update or a retry is the area it was.
    private var showsRadius: Bool { plan.detailKm != 0 && mode == .new }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(name)
                    if showsRadius {
                        Picker("Streets within", selection: radius) {
                            ForEach(StreetAreaPlan.detailChoices, id: \.self) { km in
                                Text("\(km) km").tag(km)
                            }
                        }
                        .disabled(isDownloading)
                    }
                    Text(Self.sizeText(bytes: plan.estimatedBytes))
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.source)
                        Text(Self.serverLearns)
                        if let note { Text(note) }
                    }
                }

                switch phase {
                case .ready:
                    EmptyView()
                case .downloading(let done, let total):
                    Section {
                        ProgressView(value: Double(done), total: Double(max(total, 1))) {
                            Text("Downloading streets")
                        }
                        .tint(Theme.accent)
                    }
                case .failed:
                    Section {
                        Text(Self.failure)
                        Button("Try again") { start() }
                    }
                }
            }
            .navigationTitle("Download streets")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                if phase == .ready {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Download") { start() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isDownloading)
    }

    private var radius: Binding<Int> {
        Binding(
            get: { plan.detailKm },
            set: { plan = StreetAreaPlan(latitude: plan.latitude, longitude: plan.longitude, detailKm: $0) }
        )
    }

    /// Begins the area (once) and fills it; a retry fills the same area.
    private func start() {
        guard !isDownloading else { return }
        let plan = plan
        let id: UUID
        if let areaID {
            id = areaID
        } else {
            guard let begun = try? store.beginArea(plan, name: name) else {
                phase = .failed
                return
            }
            id = begun
            areaID = begun
        }
        phase = .downloading(done: 0, total: plan.tiles.count)
        let download = MapDownload(store: store)
        task = Task {
            do {
                let area = try await download.resume(id, plan: plan) { done, total in
                    Task { @MainActor in
                        if case .downloading = phase { phase = .downloading(done: done, total: total) }
                    }
                }
                // Cancelled as it finished: the cancel removes the area.
                guard !Task.isCancelled else { return }
                phase = .ready
                onDone(area)
            } catch {
                if !Task.isCancelled { phase = .failed }
            }
        }
    }

    /// Stops a download in flight. An area this sheet began is removed, once
    /// the download has stopped writing to it; an area from before (a retry
    /// from the Maps list) is kept, unfinished, as it was.
    private func cancel() {
        let running = task
        running?.cancel()
        if mode == .new || mode == .update, let areaID {
            let store = store
            Task {
                _ = await running?.result
                try? store.deleteArea(areaID)
            }
        }
        onDone(nil)
    }
}

extension View {
    /// `.navigationBarTitleDisplayMode(.inline)` where it exists.
    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
