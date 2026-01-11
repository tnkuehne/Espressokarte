//
//  ShareViewController.swift
//  EspressokarteShare
//
//  Created by Timo Kuehne on 10.01.26.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share extension view controller that hosts the SwiftUI view
class ShareViewController: UIViewController {

    private var viewModel: ShareExtensionViewModel!

    override func viewDidLoad() {
        super.viewDidLoad()

        viewModel = ShareExtensionViewModel()

        let shareView = ShareExtensionView(
            viewModel: viewModel,
            onComplete: { [weak self] in
                self?.completeRequest()
            },
            onCancel: { [weak self] in
                self?.cancelRequest()
            }
        )

        let hostingController = UIHostingController(rootView: shareView)
        addChild(hostingController)
        view.addSubview(hostingController.view)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        hostingController.didMove(toParent: self)

        // Extract URL from extension context and process
        Task {
            await extractAndProcessURL()
        }
    }

    private func extractAndProcessURL() async {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
            let attachments = extensionItem.attachments
        else {
            await MainActor.run {
                viewModel.state = .error("No content found to import.")
            }
            return
        }

        // Look for a URL in the attachments
        for attachment in attachments {
            // Try URL type first
            if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                do {
                    let item = try await attachment.loadItem(
                        forTypeIdentifier: UTType.url.identifier,
                        options: nil
                    )

                    if let url = item as? URL {
                        await viewModel.processURL(url)
                        return
                    }
                } catch {
                    continue
                }
            }

            // Also try plain text (URLs can come as text)
            if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                do {
                    let item = try await attachment.loadItem(
                        forTypeIdentifier: UTType.plainText.identifier,
                        options: nil
                    )

                    if let urlString = item as? String,
                        let url = URL(string: urlString)
                    {
                        await viewModel.processURL(url)
                        return
                    }
                } catch {
                    continue
                }
            }
        }

        await MainActor.run {
            viewModel.state = .error("Could not find a Google Maps link in the shared content.")
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancelRequest() {
        extensionContext?.cancelRequest(
            withError: NSError(
                domain: "EspressokarteShare",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "User cancelled"]
            ))
    }
}
