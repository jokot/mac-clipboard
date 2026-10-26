import SwiftUI
import Combine

/// The accent color that MaClip draws now. Views that draw the accent observe this store,
/// so a new color shows at once, without a restart. While the color picker is open, the
/// store shows the color under the knob, and Settings keeps the saved color.
final class AccentStore: ObservableObject {
    static let shared = AccentStore()

    @Published private(set) var choice: AccentChoice
    private var isPreviewing = false
    private var cancellable: AnyCancellable?

    init(settings: AppSettings = .shared) {
        choice = AccentChoice(stored: settings.accentColor)
        cancellable = settings.$accentColor.dropFirst().sink { [weak self] value in
            guard let self, !self.isPreviewing else { return }
            self.choice = AccentChoice(stored: value)
        }
    }

    /// The color picker shows a color that Settings did not save yet.
    func showPreview(_ choice: AccentChoice) {
        isPreviewing = true
        self.choice = choice
    }

    /// Back to the saved color.
    func endPreview() {
        isPreviewing = false
        choice = AccentChoice(stored: AppSettings.shared.accentColor)
    }
}
