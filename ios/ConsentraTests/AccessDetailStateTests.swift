import XCTest
@testable import Consentra

final class AccessDetailStateTests: XCTestCase {
    let share = Share(token: "t", label: "Dr. X", categories: [.labs], createdAt: .now, expiresAt: .now.addingTimeInterval(3600),
                      revokedAt: nil, status: .active, url: URL(string: "http://x/s/t")!, views: [])

    func testShowsShareWhenPresentEvenIfLastRefreshFailed() {
        XCTAssertEqual(AccessDetailState.resolve(share: share, error: "down", hasLoaded: true), .loaded(share))
    }

    func testServerDownWithNoShareShowsErrorNotSpinner() {
        XCTAssertEqual(AccessDetailState.resolve(share: nil, error: "Can't reach server", hasLoaded: false), .failed("Can't reach server"))
    }

    func testShareMissingAfterSuccessfulRefreshIsNotFound() {
        // e.g. the demo server was reset while this screen was open
        XCTAssertEqual(AccessDetailState.resolve(share: nil, error: nil, hasLoaded: true), .notFound)
    }

    func testFirstLoadIsLoading() {
        XCTAssertEqual(AccessDetailState.resolve(share: nil, error: nil, hasLoaded: false), .loading)
    }
}
