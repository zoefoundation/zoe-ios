//
//  zoeTests.swift
//  zoeTests
//
//  Created by Leo on 04/03/2026.
//

import AVFoundation
import Testing
@testable import zoe

struct zoeTests {

    @Test("Capture photo codec prefers JPEG over HEVC")
    func photoCodecPrefersJPEG() {
        let selected = CaptureViewModel.preferredPhotoCodec(from: [.hevc, .jpeg])
        #expect(selected == .jpeg)
    }

    @Test("Capture photo codec falls back to HEVC when JPEG unavailable")
    func photoCodecFallbacksToHEVC() {
        let selected = CaptureViewModel.preferredPhotoCodec(from: [.hevc])
        #expect(selected == .hevc)
    }
}
