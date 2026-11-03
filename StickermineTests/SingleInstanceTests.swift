import AppKit
import Carbon
import Testing
@testable import Stickermine

struct SingleInstanceTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func theEarlierLaunchStays() {
        let mine = SingleInstance.Copy(pid: 500, launchDate: now)
        let older = SingleInstance.Copy(pid: 900, launchDate: now.addingTimeInterval(-60))
        let newer = SingleInstance.Copy(pid: 300, launchDate: now.addingTimeInterval(5))
        #expect(SingleInstance.incumbent(among: [older], mine: mine, now: now) == older)
        #expect(SingleInstance.incumbent(among: [newer], mine: mine, now: now) == nil)
        #expect(SingleInstance.incumbent(among: [newer, older], mine: mine, now: now) == older)
        #expect(SingleInstance.incumbent(among: [], mine: mine, now: now) == nil)
    }

    @Test func aTieGoesToTheLowerPidSoBothCopiesAgree() {
        let low = SingleInstance.Copy(pid: 300, launchDate: now)
        let high = SingleInstance.Copy(pid: 700, launchDate: now)
        #expect(SingleInstance.incumbent(among: [low], mine: high, now: now) == low)
        #expect(SingleInstance.incumbent(among: [high], mine: low, now: now) == nil)
    }

    @Test func unknownDatesLeanTowardsYielding() {
        // Started by running the executable directly: no launch date of its own.
        let undated = SingleInstance.Copy(pid: 500, launchDate: nil)
        let other = SingleInstance.Copy(pid: 900, launchDate: now.addingTimeInterval(-1))
        #expect(SingleInstance.incumbent(among: [other], mine: undated, now: now) == other)
        // Another copy without a date counts as long running.
        let mine = SingleInstance.Copy(pid: 500, launchDate: now)
        let undatedOther = SingleInstance.Copy(pid: 900, launchDate: nil)
        #expect(SingleInstance.incumbent(among: [undatedOther], mine: mine, now: now) == undatedOther)
    }

    @Test func theNotificationNameIsTheSpecs() {
        #expect(SingleInstance.showHomeNotification.rawValue == "com.ethan.stickermine.showHome")
    }

    @Test func aLoginLaunchIsReadFromTheOpenApplicationEvent() {
        func event(_ id: AEEventID, loginItem: Bool) -> NSAppleEventDescriptor {
            let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: id,
                                               targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
                                               transactionID: AETransactionID(kAnyTransactionID))
            if loginItem {
                event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)),
                               forKeyword: AEKeyword(keyAEPropData))
            }
            return event
        }
        #expect(SingleInstance.isLoginLaunch(event(AEEventID(kAEOpenApplication), loginItem: true)))
        #expect(!SingleInstance.isLoginLaunch(event(AEEventID(kAEOpenApplication), loginItem: false)))
        #expect(!SingleInstance.isLoginLaunch(event(AEEventID(kAEReopenApplication), loginItem: true)))
        #expect(!SingleInstance.isLoginLaunch(nil))
    }
}
