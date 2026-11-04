import XCTest
@testable import Consentra

final class ActivityTests: XCTestCase {
    private func share(_ token: String, created: TimeInterval, views: [TimeInterval], revoked: TimeInterval?) -> Share {
        Share(token: token, label: "Dr. \(token)", categories: [.labs],
              createdAt: Date(timeIntervalSince1970: created),
              expiresAt: Date(timeIntervalSince1970: created + 86_400),
              revokedAt: revoked.map { Date(timeIntervalSince1970: $0) },
              status: revoked == nil ? .active : .revoked,
              url: URL(string: "http://x/s/\(token)")!,
              views: views.map { ShareViewEvent(at: Date(timeIntervalSince1970: $0), userAgent: "iPhone") })
    }

    func testEventsAreDerivedAndSortedNewestFirst() {
        let events = ActivityEvent.from(shares: [
            share("a", created: 100, views: [150, 300], revoked: 400),
            share("b", created: 200, views: [], revoked: nil),
        ])
        XCTAssertEqual(events.map(\.kind), [.revoked, .viewed, .created, .viewed, .created])
        XCTAssertEqual(events.map(\.shareToken), ["a", "a", "b", "a", "a"])
        XCTAssertEqual(Set(events.map(\.id)).count, events.count, "ids must be unique for ForEach")
    }

    func testNoSharesNoEvents() {
        XCTAssertTrue(ActivityEvent.from(shares: []).isEmpty)
    }
}
