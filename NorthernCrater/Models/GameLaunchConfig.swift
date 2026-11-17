//
//  GameLaunchConfig.swift
//  NorthernCrater
//

import Foundation

/// The player's graphics and control settings. FFNxConfigWriter turns them into FFNx.toml at each Play
/// (mods can override them), and `aspectCode` is passed to the engine as FF7_ASPECT.
struct GameLaunchConfig: Codable, Equatable {
    var internalResolutionScale: Int = 4
    var aspectRatio: String = "16:9"
    var enable60FPS: Bool = true
    /// FFNx's `enable_antialiasing`: 0 off, or 2, 4, 8, 16 samples. (An older version stored an unused
    /// `enableAntialiasing`; it is ignored so nobody silently gets 4x.)
    var antialiasing: Int = 0
    /// Forces FFNx's real-time lighting and shadows on. Off leaves it to the mods (Cosmos Gaia turns it on).
    var lighting: Bool = false
    var analogControls: Bool = true
    /// Controller tuning (FFNx): stick deadzones (0-1), walk/run by stick tilt, camera inversion in battles.
    var leftStickDeadzone: Double = 0.1
    var rightStickDeadzone: Double = 0.1
    var autoRun: Bool = false
    var invertCameraVertical: Bool = false
    var invertCameraHorizontal: Bool = false
    /// Exchanges the controller's A and B buttons (confirm <-> cancel). Passed to the engine as FF7_SWAP_AB.
    var swapConfirmCancel: Bool = false
    var vsync: Bool = true
    var showFPS: Bool = false

    init() {}

    /// Older saved states lack newer fields: a missing one keeps its default instead of failing the load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameLaunchConfig()
        internalResolutionScale = try c.decodeIfPresent(Int.self, forKey: .internalResolutionScale) ?? d.internalResolutionScale
        aspectRatio = try c.decodeIfPresent(String.self, forKey: .aspectRatio) ?? d.aspectRatio
        enable60FPS = try c.decodeIfPresent(Bool.self, forKey: .enable60FPS) ?? d.enable60FPS
        antialiasing = try c.decodeIfPresent(Int.self, forKey: .antialiasing) ?? d.antialiasing
        lighting = try c.decodeIfPresent(Bool.self, forKey: .lighting) ?? d.lighting
        analogControls = try c.decodeIfPresent(Bool.self, forKey: .analogControls) ?? d.analogControls
        leftStickDeadzone = try c.decodeIfPresent(Double.self, forKey: .leftStickDeadzone) ?? d.leftStickDeadzone
        rightStickDeadzone = try c.decodeIfPresent(Double.self, forKey: .rightStickDeadzone) ?? d.rightStickDeadzone
        autoRun = try c.decodeIfPresent(Bool.self, forKey: .autoRun) ?? d.autoRun
        invertCameraVertical = try c.decodeIfPresent(Bool.self, forKey: .invertCameraVertical) ?? d.invertCameraVertical
        invertCameraHorizontal = try c.decodeIfPresent(Bool.self, forKey: .invertCameraHorizontal) ?? d.invertCameraHorizontal
        swapConfirmCancel = try c.decodeIfPresent(Bool.self, forKey: .swapConfirmCancel) ?? d.swapConfirmCancel
        vsync = try c.decodeIfPresent(Bool.self, forKey: .vsync) ?? d.vsync
        showFPS = try c.decodeIfPresent(Bool.self, forKey: .showFPS) ?? d.showFPS
    }

    /// The engine's screen shape (FF7_ASPECT) and FFNx's `aspect_ratio` setting: 0 4:3, 2 16:9, 3 16:10, 4 21:9.
    var aspectCode: Int {
        switch aspectRatio {
        case "16:9": return 2
        case "16:10": return 3
        case "21:9": return 4
        default: return 0
        }
    }
}
