// Mac-only: Quick Look preview of an Ableton Live set (Space on an .als in Finder). Data-based:
// the page is built by `AliveRender.PreviewPage`, the arrangement picture travels as an attachment.
import AliveCore
import AliveRender
import Foundation
import Quartz
import UniformTypeIdentifiers

@objc(AlivePreviewProvider)
public final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    public func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let model = PreviewModel.load(path: request.fileURL.path)
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
