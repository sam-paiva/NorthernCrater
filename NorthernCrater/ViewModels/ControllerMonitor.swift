//
//  ControllerMonitor.swift
//  NorthernCrater
//
//  Lists the connected game controllers and shows what they press, live, for the controller page. The game
//  uses the first controller that macOS reports as an extended gamepad (as the engine does).
//

import CoreGraphics
import GameController
import Observation

@MainActor
@Observable
final class ControllerMonitor {
    private(set) var controllerNames: [String] = []
    /// Pressed buttons, named as in `ControllerMonitor.layout`.
    private(set) var pressed: Set<String> = []
    private(set) var leftStick = CGPoint.zero
    private(set) var rightStick = CGPoint.zero
    private(set) var leftTrigger: Float = 0
    private(set) var rightTrigger: Float = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// macOS button -> the game's pad button (the engine's fixed mapping, ff7_platform_pad_state).
    static let layout: [(id: String, label: String, gamePad: String)] = [
        ("up", "D-pad up", "D-pad up"), ("down", "D-pad down", "D-pad down"),
        ("left", "D-pad left", "D-pad left"), ("right", "D-pad right", "D-pad right"),
        ("a", "A / Cross", "A (cancel)"), ("b", "B / Circle", "B (OK)"),
        ("x", "X / Square", "X (switch)"), ("y", "Y / Triangle", "Y (menu)"),
        ("lb", "Left shoulder", "L1"), ("rb", "Right shoulder", "R1"),
        ("lt", "Left trigger", "L2"), ("rt", "Right trigger", "R2"),
        ("start", "Menu / Start", "Start"), ("back", "Options / Back", "Select"),
        ("l3", "Left stick click", "L3"), ("r3", "Right stick click", "R3"),
    ]

    func start() {
        let center = NotificationCenter.default
        observers = [Notification.Name.GCControllerDidConnect, Notification.Name.GCControllerDidDisconnect].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        GCController.startWirelessControllerDiscovery {}
        refresh()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        GCController.stopWirelessControllerDiscovery()
        for controller in GCController.controllers() { controller.extendedGamepad?.valueChangedHandler = nil }
    }

    private func refresh() {
        let controllers = GCController.controllers()
        controllerNames = controllers.map { $0.vendorName ?? "Game controller" }
        for controller in controllers {
            controller.extendedGamepad?.valueChangedHandler = { [weak self] pad, _ in
                MainActor.assumeIsolated { self?.read(pad) }
            }
        }
        if controllers.isEmpty { pressed = []; leftStick = .zero; rightStick = .zero; leftTrigger = 0; rightTrigger = 0 }
    }

    private func read(_ pad: GCExtendedGamepad) {
        var now: Set<String> = []
        func add(_ id: String, _ down: Bool?) { if down == true { now.insert(id) } }
        add("up", pad.dpad.up.isPressed); add("down", pad.dpad.down.isPressed)
        add("left", pad.dpad.left.isPressed); add("right", pad.dpad.right.isPressed)
        add("a", pad.buttonA.isPressed); add("b", pad.buttonB.isPressed)
        add("x", pad.buttonX.isPressed); add("y", pad.buttonY.isPressed)
        add("lb", pad.leftShoulder.isPressed); add("rb", pad.rightShoulder.isPressed)
        add("lt", pad.leftTrigger.isPressed); add("rt", pad.rightTrigger.isPressed)
        add("start", pad.buttonMenu.isPressed); add("back", pad.buttonOptions?.isPressed)
        add("l3", pad.leftThumbstickButton?.isPressed); add("r3", pad.rightThumbstickButton?.isPressed)
        pressed = now
        leftStick = CGPoint(x: CGFloat(pad.leftThumbstick.xAxis.value), y: CGFloat(pad.leftThumbstick.yAxis.value))
        rightStick = CGPoint(x: CGFloat(pad.rightThumbstick.xAxis.value), y: CGFloat(pad.rightThumbstick.yAxis.value))
        leftTrigger = pad.leftTrigger.value
        rightTrigger = pad.rightTrigger.value
    }
}
