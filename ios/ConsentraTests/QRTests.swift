import XCTest
import CoreImage
@testable import Consentra

final class QRTests: XCTestCase {
    func testQRImageRoundTripsShareURL() throws {
        let url = "http://10.56.1.197:3000/s/UmzQihlYsQHEZbQhb9mNFg"
        let image = try XCTUnwrap(QR.image(for: url))
        let ci = try XCTUnwrap(CIImage(image: image))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let decoded = detector.features(in: ci).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(decoded, [url])
    }

    func testCountdownFormats() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(countdown(to: now.addingTimeInterval(23 * 3600 + 59 * 60), now: now), "23 h 59 min")
        XCTAssertEqual(countdown(to: now.addingTimeInterval(7 * 24 * 3600), now: now), "7 d 0 h")
        XCTAssertEqual(countdown(to: now.addingTimeInterval(-60), now: now), "0 min")
    }
}
