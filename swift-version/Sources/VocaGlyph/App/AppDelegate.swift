import Cocoa
import SwiftUI
import AppKit
import SwiftData
import Sparkle

public class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow!
    
    let stateManager = AppStateManager()
    var hotkeyService: HotkeyService!
    var audioRecorder: AudioRecorderService!
    var whisper: WhisperService!
    var output: OutputService!

    /// Manages microphone enumeration and selection.
    @MainActor let microphoneService = MicrophoneService()

    // NSMenuItem used as the container for the dynamic microphone sub-menu.
    private var microphoneMenuItem: NSMenuItem!
    
    public override init() {
        super.init()
    }

    /// Serial queue used exclusively for AVAudioEngine start/stop.
    /// Keeps audio operations off the main thread so a slow 
    /// `engine.start()` on first launch never blocks the main run loop.
    private let audioQueue = DispatchQueue(label: "com.vocaglyph.audioQueue", qos: .userInteractive)

    /// Signals that an async startRecording() is currently in flight.
    /// When .processing arrives while this is true we wait for recording
    /// to fully start before stopping (prevents a stop-before-start race).
    private var isStartingRecording = false

    /// Pending stop-and-process block queued while startRecording() was still
    /// in flight. Drained as soon as startRecording() finishes.
    private var pendingStopBlock: (() -> Void)?
    
    var sharedModelContainer: ModelContainer? = {
        let schema = Schema([
            TranscriptionItem.self,
            PostProcessingTemplate.self,
            TemplateRule.self,
            WordReplacement.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("Could not create ModelContainer: \(error)")
            return nil
        }
    }()
    
    lazy var permissionsService = PermissionsService()
    var onboardingWindow: NSWindow?

    // MARK: - Sparkle Auto-Update
    private var updaterController: SPUStandardUpdaterController!
    private var checkForUpdatesViewModel: CheckForUpdatesViewModel!
    private var checkForUpdatesMenuItem: NSMenuItem!

    /// Bump this ONLY when shipping a breaking change that makes old versions
    /// incompatible (e.g. new model format, changed storage schema).
    /// Users running a build < this number cannot start the app until updated.
    private let minimumRequiredBuild = 1

    public func applicationDidFinishLaunching(_ aNotification: Notification) {
        // ── Sparkle: initialise the updater as early as possible so background
        //    checks can begin and the forced-update guard below works correctly.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updaterController.updater)

        // ── Forced-update guard (Option D) ─────────────────────────────────
        // If the installed build is older than minimumRequiredBuild, block the
        // app from starting and let Sparkle immediately show the update dialog.
        // Once the user installs the update and the app relaunches, this check
        // passes and normal startup continues.
        let currentBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
        if currentBuild < minimumRequiredBuild {
            // Show the mandatory update sheet; do NOT call initializeCoreServices.
            // The app stays as a dormant menu-bar icon until the update installs.
            updaterController.updater.checkForUpdates()
            return
        }

        // Hide application from dock and cmd-tab switcher
        NSApp.setActivationPolicy(.accessory)

        if permissionsService.areAllCorePermissionsGranted {
            initializeCoreServices()
        } else {
            showOnboardingWindow()
        }
    }
    
    func showOnboardingWindow() {
        // Switch to .regular so the onboarding NSWindow can become a true key window.
        // With .accessory policy the app never fully activates and SwiftUI buttons
        // inside the window are completely unresponsive (they never receive key events).
        // We switch back to .accessory in initializeCoreServices() once onboarding is done.
        NSApp.setActivationPolicy(.regular)

        let onboardingView = OnboardingView(permissionsService: permissionsService, onComplete: { [weak self] in
            DispatchQueue.main.async {
                // orderOut hides the window WITHOUT firing windowWillClose.
                // This avoids the need for any "completed" flag gymnastics —
                // windowWillClose now only fires from the user's red ✕ button.
                self?.onboardingWindow?.orderOut(nil)
                self?.onboardingWindow = nil
                self?.initializeCoreServices()
                self?.toggleSettingsWindow(nil) // Open Settings after onboarding
            }
        })
        
        let hostingController = NSHostingController(rootView: onboardingView)
        onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        onboardingWindow?.center()
        onboardingWindow?.isReleasedWhenClosed = false
        onboardingWindow?.delegate = self
        onboardingWindow?.contentViewController = hostingController
        onboardingWindow?.title = "Welcome to VocaGlyph"
        onboardingWindow?.titleVisibility = .hidden
        onboardingWindow?.titlebarAppearsTransparent = true
        onboardingWindow?.isMovableByWindowBackground = true
        
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @MainActor func initializeCoreServices() {
        // Revert to accessory policy now that onboarding is done —
        // the app runs as a menu-bar agent with no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        // Seed default post-processing templates if this is a first launch
        if let container = sharedModelContainer {
            let context = container.mainContext
            TemplateSeederService.seedDefaultTemplatesIfNeeded(context: context)
            stateManager.modelContext = context
        }

        // Initialize Core Services
        // Setup Overlay Panel FIRST — must exist before startEngine() fires .initializing
        // state changes. Moving this below startEngine() means the panel is still nil
        // when the first updateVisibility(for:) call arrives on cold launch.
        OverlayPanelManager.shared.setupPanel(with: stateManager)

        stateManager.delegate = self
        audioRecorder = AudioRecorderService()
        audioRecorder.configChangeDelegate = self
        audioRecorder.microphoneService = microphoneService
        whisper = WhisperService()
        whisper.delegate = self
        stateManager.sharedWhisper = whisper // Let AppStateManager reuse this single instance
        stateManager.engineRouter = EngineRouter(engine: whisper) // initial default
        stateManager.startEngine() // Boot up whatever model is selected in UserDefaults
        output = OutputService()
        hotkeyService = HotkeyService(stateManager: stateManager)
        hotkeyService.start()
        
        // Setup Settings Window
        var anySettingsView: AnyView
        let settingsView = SettingsView(whisper: whisper, stateManager: stateManager, microphoneService: microphoneService)
        if let container = sharedModelContainer {
            anySettingsView = AnyView(settingsView.modelContainer(container))
        } else {
            anySettingsView = AnyView(settingsView)
        }
        let hostingController = NSHostingController(rootView: anySettingsView)
        
        settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        settingsWindow.center()
        settingsWindow.setFrameAutosaveName("SettingsWindow")
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.delegate = self
        settingsWindow.contentViewController = hostingController
        settingsWindow.title = "VocaGlyph Settings"
        
        // Hide native title bar completely for custom SwiftUI sidebar appearance
        settingsWindow.titleVisibility = .hidden
        settingsWindow.titlebarAppearsTransparent = true
        
        // Add an empty toolbar to ensure standard margin (~10-15px) for traffic light buttons
        let dummyToolbar = NSToolbar()
        dummyToolbar.showsBaselineSeparator = false
        settingsWindow.toolbar = dummyToolbar
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let imgUrl = Bundle.main.url(forResource: "appbaricon", withExtension: "png")
                      ?? Bundle.module.url(forResource: "appbaricon", withExtension: "png")
            Logger.shared.info("AppDelegate: appbaricon URL = \(imgUrl?.absoluteString ?? "nil")")
            if let imgUrl, let nsImage = NSImage(contentsOf: imgUrl) {
                // Resize to menu bar icon dimensions
                nsImage.size = NSSize(width: 18, height: 18)
                // isTemplate = false for full-color PNGs.
                // Use true only if the icon is a black+transparent template design.
                nsImage.isTemplate = false
                button.image = nsImage
            } else {
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VocaGlyph")
            }
        }
        
        let menu = NSMenu()
        menu.delegate = self

        let settingsMenuItem = NSMenuItem(title: "Settings...", action: #selector(toggleSettingsWindow(_:)), keyEquivalent: ",")
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)

        // ── Sparkle: Check for Updates item ───────────────────────────────
        checkForUpdatesMenuItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesMenuItem.target = self
        checkForUpdatesMenuItem.isEnabled = checkForUpdatesViewModel.canCheckForUpdates
        menu.addItem(checkForUpdatesMenuItem)

        // ── Microphone submenu ────────────────────────────────────────
        microphoneMenuItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        microphoneMenuItem.submenu = NSMenu(title: "Microphone")
        menu.addItem(microphoneMenuItem)
        // Populate once so the submenu isn't blank before first open.
        rebuildMicrophoneSubmenu()

        menu.addItem(NSMenuItem.separator())

        let quitMenuItem = NSMenuItem(title: "Quit VocaGlyph", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitMenuItem.target = NSApp
        menu.addItem(quitMenuItem)

        statusItem.menu = menu
    }
    
    /// Triggered by "Check for Updates…" in the status-bar menu.
    @objc private func checkForUpdates(_ sender: Any) {
        updaterController.checkForUpdates(sender)
    }

    @objc func simulateRecording() {
        stateManager.startRecording()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.stateManager.stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.stateManager.setIdle()
            }
        }
    }
    
    // MARK: - Window Actions
    @objc func toggleSettingsWindow(_ sender: AnyObject?) {
        if settingsWindow.isVisible {
            settingsWindow.orderOut(nil)
            // Revert to accessory so the app disappears from Cmd+Tab and Dock
            // now that no window is visible.
            NSApp.setActivationPolicy(.accessory)
        } else {
            // Switch to .regular so the app appears in Cmd+Tab and can become
            // a true key window. .accessory prevents the window from fully
            // activating and receiving keyboard focus on machines without prior
            // Launch Services registration (i.e. fresh DMG installs).
            NSApp.setActivationPolicy(.regular)
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Microphone Submenu

    /// Rebuilds the Microphone submenu with the current device list.
    /// Called once at setup and again from `menuWillOpen(_:)` so the
    /// list reflects any devices plugged in since the last open.
    @MainActor
    func rebuildMicrophoneSubmenu() {
        guard let submenu = microphoneMenuItem.submenu else { return }
        submenu.removeAllItems()

        let currentUID = microphoneService.selectedUID ?? ""

        for device in microphoneService.availableInputs {
            let isSeparatorMarker = (device == .systemDefault && microphoneService.availableInputs.count > 1)

            // Insert a visual separator between real devices and "System Default"
            if isSeparatorMarker && device == microphoneService.availableInputs.last {
                submenu.addItem(NSMenuItem.separator())
            }

            let item = NSMenuItem(
                title: device.name,
                action: #selector(selectMicrophone(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device
            item.state = (device.uid == currentUID) ? .on : .off
            submenu.addItem(item)

            if device == .systemDefault && microphoneService.availableInputs.count > 1 {
                submenu.addItem(NSMenuItem.separator())
            }
        }
    }

    @MainActor @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? MicrophoneDevice else { return }
        microphoneService.select(device)
        rebuildMicrophoneSubmenu()
    }
}

// MARK: - NSMenuDelegate
extension AppDelegate: NSMenuDelegate {
    public func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }

        // Keep "Check for Updates…" in sync with Sparkle's internal state.
        checkForUpdatesMenuItem?.isEnabled = checkForUpdatesViewModel.canCheckForUpdates

        // Refresh device list and rebuild the submenu each time the status-bar
        // menu is about to open, so newly connected devices are visible immediately.
        if let subMenu = microphoneMenuItem?.submenu {
            microphoneService.refreshDevices(reason: "menu-open")
            rebuildMicrophoneSubmenu()
            _ = subMenu // suppress unused warning
        }
    }
}


// MARK: - NSWindowDelegate
extension AppDelegate: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if window === onboardingWindow {
            // The user closed the onboarding window via the red ✕ button before completing
            // setup. Because the app runs with .accessory activation policy (no Dock icon,
            // no menu bar until core services are initialized), there is no other way for
            // the user to quit. Terminate cleanly.
            // NOTE: this fires ONLY for red-X closes because Continue now uses orderOut()
            // instead of close(), which does NOT trigger windowWillClose.
            NSApp.terminate(nil)
        } else if window === settingsWindow {
            // Settings closed via the red ✕ button — revert to .accessory so the
            // app disappears from Cmd+Tab and the Dock.
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

extension AppDelegate: AudioRecorderConfigChangeDelegate {
    func audioRecorderDidLoseConfiguration(_ recorder: AudioRecorderService) {
        // Already called on main thread from the handler's DispatchQueue.main.async.
        guard stateManager.currentState == .recording ||
              stateManager.currentState == .processing else { return }
        Logger.shared.info("AppDelegate: Audio engine lost configuration mid-recording — resetting to idle.")
        stateManager.setIdle()
    }
}

extension AppDelegate: AppStateManagerDelegate {
    // MARK: - AppStateManagerDelegate
    func appStateDidChange(newState: AppState) {
        let button = statusItem.button
        
        switch newState {
        case .idle:
            // Let HotkeyService know it can accept the next hotkey press.
            hotkeyService.resetToIdle()
            if let imgUrl = Bundle.main.url(forResource: "appbaricon", withExtension: "png")
                         ?? Bundle.module.url(forResource: "appbaricon", withExtension: "png"),
               let nsImage = NSImage(contentsOf: imgUrl) {
                nsImage.size = NSSize(width: 18, height: 18)
                nsImage.isTemplate = false
                button?.image = nsImage
            } else {
                button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VocaGlyph")
            }
        case .initializing:
            let img = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "initializing")
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemYellow])
            button?.image = img?.withSymbolConfiguration(config)
        case .recording:
            let img = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "recording")
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            button?.image = img?.withSymbolConfiguration(config)

            // Run AVAudioEngine.start() on a background serial queue so it never
            // blocks the main thread. On the very first launch the engine can take
            // hundreds of milliseconds to settle after mic permission is granted;
            // doing this on the main thread froze the run loop and prevented the
            // queued stopRecording() dispatch from ever executing.
            isStartingRecording = true
            audioQueue.async { [weak self] in
                guard let self else { return }
                do {
                    try self.audioRecorder.startRecording()
                } catch {
                    Logger.shared.error("AppDelegate: audioRecorder.startRecording() failed — \(error.localizedDescription). Resetting to idle.")
                    DispatchQueue.main.async {
                        self.isStartingRecording = false
                        self.pendingStopBlock = nil
                        self.stateManager.setIdle()
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.isStartingRecording = false
                    // Drain any stop request that arrived while we were starting.
                    if let stop = self.pendingStopBlock {
                        self.pendingStopBlock = nil
                        stop()
                    }
                }
            }

        case .processing:
            let img = NSImage(systemSymbolName: "hourglass.circle.fill", accessibilityDescription: "processing")
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            button?.image = img?.withSymbolConfiguration(config)

            // If startRecording() is still in flight (fast key tap), queue the
            // stop until it finishes. This prevents a stop-before-start race.
            // stopRecording() runs on the audio queue because bufferQueue.sync{}
            // and engine.stop() must not block the main thread.
            let doStop = { [weak self] in
                guard let self else { return }
                self.audioQueue.async {
                    let buffer = self.audioRecorder.stopRecording()
                    DispatchQueue.main.async {
                        if let buffer {
                            Logger.shared.info("AppDelegate: Finished capturing audio segment.")
                            self.stateManager.processAudio(buffer: buffer)
                        } else {
                            self.stateManager.setIdle()
                        }
                    }
                }
            }

            if isStartingRecording {
                // Store the stop block; it will be called when startRecording() completes.
                pendingStopBlock = doStop
            } else {
                doStop()
            }
        }
        
        // Update overlay panel
        OverlayPanelManager.shared.updateVisibility(for: newState)
    }

    func appStateManagerDidTranscribe(text: String) {
        // The transcription has successfully completed.
        print("Final transcription output bound in AppDelegate: \(text)")
        
        // Save to local history
        if !text.isEmpty, let container = sharedModelContainer {
            Task { @MainActor in
                let context = container.mainContext
                let newItem = TranscriptionItem(text: text)
                context.insert(newItem)
                
                self.cleanupOldHistoryItems(context: context)
                
                do {
                    try context.save()
                } catch {
                    print("Failed to save new transcription item: \(error)")
                }
            }
        }
        
        DispatchQueue.main.async {
            self.output.handleTranscriptionValue(text)
        }
    }
    
    @MainActor
    private func cleanupOldHistoryItems(context: ModelContext) {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return }
        
        let fetchDescriptor = FetchDescriptor<TranscriptionItem>(
            predicate: #Predicate { $0.timestamp < thirtyDaysAgo }
        )
        
        do {
            let oldItems = try context.fetch(fetchDescriptor)
            for item in oldItems {
                context.delete(item)
            }
        } catch {
            print("Failed to fetch old items for cleanup: \(error)")
        }
    }
}

extension AppDelegate: WhisperServiceDelegate {
    func whisperServiceDidUpdateState(_ state: String) {
        // e.g., "Ready" vs "Failed" to update UI visually later
        print("WhisperService state update: \(state)")
        
        DispatchQueue.main.async {
            switch state {
            case "Initializing Engine...", "Loading into memory...", "Warming up Neural Engine...", "Processing":
                if self.stateManager.currentState != .initializing {
                    self.stateManager.setInitializing()
                }
            case "Ready", "Model not downloaded.", "Failed", "Model warming up...":
                if self.stateManager.currentState == .initializing {
                    self.stateManager.setIdle()
                }
            default:
                if state.hasPrefix("Downloading") || state.hasPrefix("Falling back") {
                    if self.stateManager.currentState != .initializing {
                        self.stateManager.setInitializing()
                    }
                }
            }
        }
    }
}

// MARK: - SPUUpdaterDelegate (Sparkle)
extension AppDelegate: SPUUpdaterDelegate {
    /// Called by Sparkle before presenting an update to the user.
    public func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        return false // Install immediately; do not delay relaunch
    }

    /// Called by Sparkle right before it terminates the app to install the update.
    /// Close all windows so the process exits cleanly — an open Settings or onboarding
    /// window can prevent the app from fully terminating, which blocks the installer.
    public func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        NSApp.windows.forEach { $0.close() }
    }
}
