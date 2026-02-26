import Sparkle
import Combine

/// Observable bridge between Sparkle's SPUUpdater and the status-bar NSMenu.
///
/// Publishes `canCheckForUpdates` so the "Check for Updates…" menu item
/// is automatically disabled while an update is already downloading/installing.
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }
}
