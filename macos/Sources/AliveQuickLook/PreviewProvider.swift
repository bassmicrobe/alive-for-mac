// Mac-only: Quick Look preview of an Ableton Live set (Space on an .als in Finder). Data-based:
// the page is built by `AliveRender.PreviewPage`, the arrangement picture travels as an attachment.
import AliveCore
import AliveRender
import Foundation
import os
import Quartz
import UniformTypeIdentifiers

@objc(AlivePreviewProvider)
public final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private static let log = Logger(subsystem: "io.github.bassmicrobe.alive-for-mac.quicklook", category: "preview")

    public func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let model = PreviewModel.load(path: request.fileURL.path)
        // The parser's own diagnostics (English) belong in the log, not on the page.
        if let diagnostic = model.info.error {
            Self.log.error("preview failed: \(diagnostic, privacy: .private) (\(String(describing: model.failure), privacy: .public))")
        }
        let language = PreviewLanguage.system()
        let picture = PreviewPage.pictureData(for: model.arrangement)
        let html = PreviewPage.html(model, language: language,
                                    pictureSource: picture == nil ? nil : "cid:\(PreviewPage.pictureID)")
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: PreviewPage.contentSize) { reply in
            if let picture {
                reply.attachments[PreviewPage.pictureID] = QLPreviewReplyAttachment(data: picture, contentType: .png)
            }
            return Data(html.utf8)
        }
        reply.title = model.name
        return reply
    }
}
