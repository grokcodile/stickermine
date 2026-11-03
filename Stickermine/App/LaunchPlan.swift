import Foundation

/// What a launch does besides restoring the stickers, which every launch
/// does (spec section 13). Pure.
struct LaunchPlan: Equatable {
    /// A launch that isn't a login launch (Finder, Spotlight, `open`) opens Home.
    var opensHome: Bool
    /// First run: a user launch with `didFirstRun` false and no stickers in
    /// the library (never for a library saved by a newer build).
    var placesTutorials: Bool
    /// A login launch opens nothing, except that it checks for an update
    /// `loginUpdateCheckDelay` later and opens Home when one is found.
    var checksForUpdateAfterLogin: Bool

    /// After the login rush, so whichever login item activates next doesn't bury Home.
    static let loginUpdateCheckDelay: TimeInterval = 6

    static func decide(loginLaunch: Bool, didFirstRun: Bool, libraryIsEmpty: Bool, readOnly: Bool) -> LaunchPlan {
        if loginLaunch {
            return LaunchPlan(opensHome: false, placesTutorials: false, checksForUpdateAfterLogin: true)
        }
        return LaunchPlan(opensHome: true, placesTutorials: !didFirstRun && libraryIsEmpty && !readOnly,
                          checksForUpdateAfterLogin: false)
    }
}
