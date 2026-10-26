import AppKit
import SwiftUI

final class ShareViewController: NSViewController {
    override func loadView() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        view = NSHostingView(rootView: ShareView(providers: providers) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        preferredContentSize = NSSize(width: 380, height: 220)
    }
}
