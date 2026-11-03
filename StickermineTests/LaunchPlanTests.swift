import Testing
@testable import Stickermine

struct LaunchPlanTests {
    @Test func aUserLaunchOpensHomeAndTheFirstOnePlacesTheTutorials() {
        #expect(LaunchPlan.decide(loginLaunch: false, didFirstRun: false, libraryIsEmpty: true, readOnly: false)
                == LaunchPlan(opensHome: true, placesTutorials: true, checksForUpdateAfterLogin: false))
        #expect(LaunchPlan.decide(loginLaunch: false, didFirstRun: true, libraryIsEmpty: true, readOnly: false)
                == LaunchPlan(opensHome: true, placesTutorials: false, checksForUpdateAfterLogin: false))
    }

    @Test func aLibraryWithStickersOrFromANewerBuildGetsNoTutorials() {
        #expect(!LaunchPlan.decide(loginLaunch: false, didFirstRun: false, libraryIsEmpty: false, readOnly: false)
            .placesTutorials)
        #expect(!LaunchPlan.decide(loginLaunch: false, didFirstRun: false, libraryIsEmpty: true, readOnly: true)
            .placesTutorials)
    }

    @Test func aLoginLaunchOpensNothingAndChecksForAnUpdateLater() {
        for didFirstRun in [false, true] {
            #expect(LaunchPlan.decide(loginLaunch: true, didFirstRun: didFirstRun, libraryIsEmpty: true, readOnly: false)
                    == LaunchPlan(opensHome: false, placesTutorials: false, checksForUpdateAfterLogin: true))
        }
        #expect(LaunchPlan.loginUpdateCheckDelay == 6)
    }
}
