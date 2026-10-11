import UIKit

/// Keep large asset copies off the UI thread, with an explicit completion/error.
enum FileOperationProgress {
    static func perform(title: String, from presenter: UIViewController,
                        work: @escaping () throws -> Void, completion: @escaping (Error?) -> Void) {
        let progress = UIAlertController(title: title, message: "Preparing your files.", preferredStyle: .alert)
        let start = {
            presenter.present(progress, animated: true) {
                DispatchQueue.global(qos: .userInitiated).async {
                    let failure: Error?
                    do { try work(); failure = nil } catch { failure = error }
                    DispatchQueue.main.async {
                        progress.dismiss(animated: true) { completion(failure) }
                    }
                }
            }
        }
        if let previous = presenter.presentedViewController {
            previous.dismiss(animated: true, completion: start)
        } else { start() }
    }
}
