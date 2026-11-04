import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum QR {
    /// Crisp QR for `string`. Correction "H" leaves room for the logo overlay on the Present screen.
    static func image(for string: String, correction: String = "H", scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = correction
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        guard let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
