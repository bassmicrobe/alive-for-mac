import XCTest
@testable import AliveCore

final class VolumeStateTests: XCTestCase {
    func testVolumeNameOfPaths() {
        XCTAssertEqual(VolumeState.volumeName(of: "/Volumes/LaCie RAID 8TB/sounds/kick.wav"), "LaCie RAID 8TB")
        XCTAssertEqual(VolumeState.volumeName(of: "/private/Volumes/NAS/a.wav"), "NAS")
        XCTAssertEqual(VolumeState.volumeName(of: "/Volumes/NAS"), "NAS")
        XCTAssertNil(VolumeState.volumeName(of: "/Users/me/Music/a.wav"))
        XCTAssertNil(VolumeState.volumeName(of: "/Volumes/"))
    }

    func testOfflineOnlyWhenTheVolumeIsNotMounted() {
        let mounted: Set<String> = ["Macintosh HD", "personal_folder"]
        XCTAssertTrue(VolumeState.isOffline("/Volumes/LaCie RAID 8TB/x.wav", mounted: mounted))
        XCTAssertFalse(VolumeState.isOffline("/Volumes/personal_folder/x.wav", mounted: mounted))
        XCTAssertFalse(VolumeState.isOffline("/Users/me/x.wav", mounted: mounted))
    }

    func testMountedVolumesIncludeNothingBogus() {
        XCTAssertFalse(VolumeState.mountedVolumeNames().contains(""))
    }
}
