import AVFoundation
import SwiftUI

@MainActor
struct ApplePlaybackInfoView: View {
    private let report = AppleCapabilityProbe.current()

    var body: some View {
        Form {
            Section("Device") {
                LabeledContent("Platform", value: report.platform)
                LabeledContent("HDR Playback", value: report.hdrEligible ? "Eligible" : "Unavailable")
            }

            Section("Dynamic Range") {
                ForEach(OpenStreamDynamicRange.allCases, id: \.self) { range in
                    LabeledContent(
                        range.displayName,
                        value: (report.dynamicRange[range] ?? .unsupported).displayName
                    )
                }
            }

            #if os(iOS) || os(tvOS)
            Section("Audio") {
                LabeledContent("Output", value: audioOutput)
                LabeledContent("AirPlay", value: isUsingAirPlay ? "Active" : "Available")
            }
            #endif

            let immersive = OpenStreamProjection.allCases.filter {
                $0 != .flat && $0 != .unknown && report.projections[$0] != .unsupported
            }
            if !immersive.isEmpty {
                Section("Immersive Video") {
                    ForEach(immersive, id: \.self) { projection in
                        LabeledContent(
                            projection.displayName,
                            value: (report.projections[projection] ?? .unsupported).displayName
                        )
                    }
                }
            }
        }
        .navigationTitle("Playback Info")
    }

    #if os(iOS) || os(tvOS)
    private var outputs: [AVAudioSessionPortDescription] {
        AVAudioSession.sharedInstance().currentRoute.outputs
    }

    private var audioOutput: String {
        let names = outputs.map(\.portName).filter { !$0.isEmpty }
        return names.isEmpty ? "System Default" : names.joined(separator: ", ")
    }

    private var isUsingAirPlay: Bool {
        outputs.contains { $0.portType == .airPlay }
    }
    #endif
}

private extension OpenStreamDynamicRange {
    var displayName: String {
        switch self {
        case .sdr: "SDR"
        case .hdr10: "HDR10"
        case .hdr10Plus: "HDR10+"
        case .hlg: "HLG"
        case .dolbyVision: "Dolby Vision"
        }
    }
}

private extension OpenStreamProjection {
    var displayName: String {
        switch self {
        case .flat: "Flat"
        case .spatial: "Spatial"
        case .stereo180: "Stereo 180°"
        case .mono180: "Mono 180°"
        case .stereo360: "Stereo 360°"
        case .mono360: "Mono 360°"
        case .wideFOV: "Wide Field of View"
        case .appleImmersive: "Apple Immersive Video"
        case .unknown: "Unknown"
        }
    }
}

private extension OpenStreamSupport {
    var displayName: String {
        switch self {
        case .supported: "Supported"
        case .runtimeCheck: "Checked Per Title"
        case .unsupported: "Unsupported"
        }
    }
}
