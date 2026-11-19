import AVFoundation
import SwiftUI

private final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
}
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var active: Bool = true

    func makeUIView(context: Context) -> UIView {
        let view = PreviewSurface()
        let layer = view.layer as! AVCaptureVideoPreviewLayer
        layer.session = session
        layer.videoGravity = .resizeAspectFill
        layer.connection?.isEnabled = active
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        let layer = uiView.layer as! AVCaptureVideoPreviewLayer
        if layer.session !== session {
            layer.session = session
        }
        if layer.connection?.isEnabled != active {
            layer.connection?.isEnabled = active
        }
    }
}
