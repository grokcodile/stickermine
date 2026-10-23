@testable import Stickermine

/// A ScreenProvider whose displays a test sets, to simulate unplugging,
/// replugging, mirroring and resolution changes.
@MainActor
final class FakeScreens: ScreenProvider {
    var all: [DisplayInfo]

    init(_ all: [DisplayInfo]) {
        self.all = all
    }

    func currentDisplays() -> [DisplayInfo] {
        DisplayRegistry.usable(all)
    }

    var mainDisplay: DisplayInfo? {
        currentDisplays().first
    }
}
