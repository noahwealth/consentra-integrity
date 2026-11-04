import XCTest
@testable import Consentra

final class ModelsTests: XCTestCase {
    // Captured from the server's GET /api/shares (Task 1 shape).
    let shareJSON = #"""
    {"token": "UmzQihlYsQHEZbQhb9mNFg", "label": "Dr. Rivera, Mass General", "categories": ["medications", "allergies", "labs"], "createdAt": "2026-10-31T15:24:06.229Z", "expiresAt": "2026-11-01T15:24:06.229Z", "revokedAt": null, "views": [{"at": "2026-10-31T15:30:01.123Z", "userAgent": "Safari"}], "status": "active", "url": "http://10.56.1.197:3000/s/UmzQihlYsQHEZbQhb9mNFg"}
    """#

    let recordJSON = #"""
    {"patient":{"name":"Noah Dixon","birthDate":"1988-04-12","homeCountry":"United Kingdom","nhsNumber":"999 123 4567"},"source":{"id":"thameside","name":"Thameside General Hospital","city":"London","country":"United Kingdom","flag":"🇬🇧","connected":true,"lastSynced":"2026-10-31T15:22:12.459Z"},"categories":{"labs":[{"id":"ob-1","title":"HbA1c","detail":"Ref: 20–41 mmol/mol","date":"2026-09-22","value":48,"unit":"mmol/mol","usValue":6.5,"usUnit":"%"}]}}
    """#

    func testShareDecodes() throws {
        let share = try API.decoder.decode(Share.self, from: Data(shareJSON.utf8))
        XCTAssertEqual(share.id, "UmzQihlYsQHEZbQhb9mNFg")
        XCTAssertEqual(share.categories, [.medications, .allergies, .labs])
        XCTAssertEqual(share.status, .active)
        XCTAssertNil(share.revokedAt)
        XCTAssertEqual(share.views.count, 1)
        XCTAssertEqual(share.expiresAt.timeIntervalSince(share.createdAt), 24 * 3600, accuracy: 1)
        XCTAssertEqual(share.url.absoluteString, "http://10.56.1.197:3000/s/UmzQihlYsQHEZbQhb9mNFg")
    }

    func testRecordDecodesAndGroupsByCategory() throws {
        let record = try API.decoder.decode(HealthRecord.self, from: Data(recordJSON.utf8))
        XCTAssertEqual(record.patient.name, "Noah Dixon")
        XCTAssertTrue(record.source.connected)
        XCTAssertNotNil(record.source.lastSynced)
        XCTAssertEqual(record.items(.labs).first?.usValue, 6.5)
        XCTAssertEqual(record.items(.medications), [])
        XCTAssertEqual(record.totalCount, 1)
        XCTAssertFalse(record.walletAvailable, "older servers omit the field → treat as unavailable")
    }

    func testRecordDecodesWalletAvailable() throws {
        let json = recordJSON.replacingOccurrences(of: #"{"patient""#, with: #"{"walletAvailable":true,"patient""#)
        XCTAssertTrue(try API.decoder.decode(HealthRecord.self, from: Data(json.utf8)).walletAvailable)
    }

    func testDecoderAcceptsDatesWithoutFractionalSeconds() throws {
        let json = #"{"at":"2026-10-31T15:30:01Z","userAgent":"x"}"#
        let v = try API.decoder.decode(ShareViewEvent.self, from: Data(json.utf8))
        XCTAssertEqual(v.userAgent, "x")
    }
}
