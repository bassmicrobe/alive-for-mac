// Port of the camera part of nebula/Cloud.cs (CloudView: yaw/pitch/zoom/pan, Project, presets).
import Foundation
import CoreGraphics

/// Ready camera positions — a free angle by default and three orthographic views onto the cube,
/// as in CAD.
enum CameraPreset: Int, CaseIterable {
    case angle, front, side, top
}

struct CloudCamera: Equatable {
    /// Distance of the eye from the middle of the [-1, 1] cube.
    static let camDist = 3.4
    /// The tilt limit for both the Top preset and a manual drag: exactly 90° (π/2), with no skew.
    static let topPitch = Double.pi / 2
    static let zoomRange = 0.35...6.0
    /// Radians per pixel of drag, and the zoom step of one wheel notch.
    static let dragRadiansPerPoint = 0.0075
    static let wheelStep = 1.12

    var yaw = 0.0
    var pitch = 0.0
    var zoom = 1.0
    var panX = 0.0
    var panY = 0.0
    /// An orthographic preset switches perspective off: k = 1 always, with no division by depth —
    /// so that Front/Side/Top give a true parallel projection, as in CAD, rather than a
    /// perspective view from the same angle.
    var isOrtho = true
    private(set) var preset = CameraPreset.front

    /// It opens on the XY view (Front): flat, with no rotation, so that the first look at the
    /// cloud is a clear readable chart rather than a random angle.
    init() { setPreset(.front) }

    /// A free angle (perspective) or one of the three orthographic views onto the cube — square on
    /// the axes, with no perspective convergence. Zoom and pan are reset too: a preset means
    /// "show me exactly like this" rather than "turn what has already been shifted".
    mutating func setPreset(_ p: CameraPreset) {
        preset = p
        switch p {
        case .front: yaw = 0; pitch = 0; isOrtho = true
        case .side: yaw = Double.pi / 2; pitch = 0; isOrtho = true
        case .top: yaw = 0; pitch = CloudCamera.topPitch; isOrtho = true
        case .angle: yaw = 0.72; pitch = 0.34; isOrtho = false
        }
        zoom = 1; panX = 0; panY = 0
    }

    /// Inverted: drag to the right and the scene turns to the left, as though you were grabbing
    /// the object itself rather than swinging the camera around it.
    mutating func rotate(dx: Double, dy: Double) {
        yaw -= dx * CloudCamera.dragRadiansPerPoint
        setPitch(pitch - dy * CloudCamera.dragRadiansPerPoint)
    }

    mutating func setPitch(_ v: Double) {
        pitch = min(CloudCamera.topPitch, max(-CloudCamera.topPitch, v))
    }

    mutating func pan(dx: Double, dy: Double) { panX += dx; panY += dy }

    /// `steps` > 0 zooms in (a wheel notch is `wheelStep`); pinch passes a fractional value.
    mutating func zoomBy(steps: Double) {
        zoom = min(CloudCamera.zoomRange.upperBound,
                   max(CloudCamera.zoomRange.lowerBound, zoom * pow(CloudCamera.wheelStep, steps)))
    }

    func projector(size: CGSize) -> Projector { Projector(camera: self, size: size) }
}

/// The camera fixed for one frame: sines and cosines computed once for all the dots.
struct Projector {
    let cx: Double
    let cy: Double
    let scale: Double
    private let cosY: Double, sinY: Double, cosP: Double, sinP: Double
    private let isOrtho: Bool

    init(camera c: CloudCamera, size: CGSize) {
        scale = Double(min(size.width, size.height)) * 0.33 * c.zoom
        cx = Double(size.width) / 2 + c.panX
        cy = Double(size.height) / 2 + c.panY
        cosY = cos(c.yaw); sinY = sin(c.yaw)
        cosP = cos(c.pitch); sinP = sin(c.pitch)
        isOrtho = c.isOrtho
    }

    /// A point of the cube → screen x, screen y and `k`, the perspective factor (1 in ortho). The
    /// same k gives a dot its radius and haze, so in orthographic mode both stop depending on
    /// depth too — which is how a true parallel projection should be.
    func project(_ x: Double, _ y: Double, _ z: Double) -> (sx: Double, sy: Double, k: Double) {
        let rx = x * cosY + z * sinY
        let rz = -x * sinY + z * cosY
        let ry = y * cosP - rz * sinP
        let rz2 = y * sinP + rz * cosP
        let k = isOrtho ? 1 : CloudCamera.camDist / (CloudCamera.camDist + rz2)
        return (cx + rx * scale * k, cy - ry * scale * k, k)
    }
}
