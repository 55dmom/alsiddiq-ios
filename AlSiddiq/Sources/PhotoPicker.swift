import SwiftUI
import PhotosUI
import UIKit

enum PhotoSource: String, Identifiable {
    case library, camera
    var id: String { rawValue }
}

/// Photos (PHPicker, no library permission needed) or the camera, returning one UIImage (nil = cancelled).
struct PhotoPickerSheet: UIViewControllerRepresentable {
    let source: PhotoSource
    let onPick: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIViewController {
        if source == .camera && UIImagePickerController.isSourceTypeAvailable(.camera) {
            let p = UIImagePickerController()
            p.sourceType = .camera
            p.cameraDevice = .front
            p.allowsEditing = true
            p.delegate = context.coordinator
            return p
        }
        var cfg = PHPickerConfiguration()
        cfg.filter = .images
        cfg.selectionLimit = 1
        let p = PHPickerViewController(configuration: cfg)
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let item = results.first?.itemProvider, item.canLoadObject(ofClass: UIImage.self) else { onPick(nil); return }
            item.loadObject(ofClass: UIImage.self) { obj, _ in
                DispatchQueue.main.async { self.onPick(obj as? UIImage) }
            }
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPick((info[.editedImage] ?? info[.originalImage]) as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onPick(nil) }
    }
}
