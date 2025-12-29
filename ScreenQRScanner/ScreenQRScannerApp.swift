//
//  ScreenQRScannerApp.swift
//  ScreenQRScanner
//
//  Created by haojieli on 2025/12/29.
//

import SwiftUI
import AppKit
import Vision
import Carbon // 需要引入 Carbon 框架来处理全局快捷键

// MARK: - 1. App 入口
@main
struct ScreenQRScannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - 2. 核心控制器
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var resultWindowController: NSWindowController?
    var hotKeyManager: HotKeyManager?
    
    // 新增：右键菜单
    var contextMenu: NSMenu!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A. 初始化右键菜单
        contextMenu = NSMenu()
        contextMenu.addItem(NSMenuItem(title: "关于 ScreenQRScanner", action: nil, keyEquivalent: ""))
        contextMenu.addItem(NSMenuItem.separator())
        contextMenu.addItem(NSMenuItem(title: "退出 (Quit)", action: #selector(quitApp), keyEquivalent: "q"))
        
        // B. 创建菜单栏图标
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem.button {
            button.image = NSImage(systemSymbolName: "qrcode.viewfinder", accessibilityDescription: "Scan QR")
            
            // 关键点 1: 设置点击事件的处理函数
            button.action = #selector(handleMouseClick)
            
            // 关键点 2: 告诉按钮，左键(.leftMouseUp) 和 右键(.rightMouseUp) 都要触发 action
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // C. 注册全局快捷键 (Command + Shift + X)
        hotKeyManager = HotKeyManager(
            key: kVK_ANSI_X,
            modifiers: cmdKey | shiftKey,
            handler: { [weak self] in
                self?.startScreenCapture()
            }
        )
    }
    
    // 统一处理鼠标点击
    @objc func handleMouseClick() {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // ---如果是右键：显示菜单---
            statusBarItem.menu = contextMenu   // 1. 临时挂载菜单
            statusBarItem.button?.performClick(nil) // 2. 模拟点击以弹出系统原生菜单
            statusBarItem.menu = nil           // 3. 立即卸载菜单（否则下次左键也会弹出菜单）
        } else {
            // ---如果是左键：执行扫描---
            startScreenCapture()
        }
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
    // --- 截图逻辑 ---
    func startScreenCapture() {
        // 如果已有窗口，先关闭
        closeResultWindow()
        
        let tempPath = NSTemporaryDirectory() + "temp_qr_scan.png"
        let tempURL = URL(fileURLWithPath: tempPath)
        try? FileManager.default.removeItem(at: tempURL)
        
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-i", "-x", tempPath]
        
        task.terminationHandler = { _ in
            if FileManager.default.fileExists(atPath: tempPath) {
                self.processImage(url: tempURL)
            }
        }
        try? task.run()
    }
    
    // --- 识别逻辑 (Vision) ---
    func processImage(url: URL) {
        guard let ciImage = CIImage(contentsOf: url) else { return }
        let requestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self = self else { return }
            
            // 结果处理
            guard let results = request.results as? [VNBarcodeObservation],
                  let firstCode = results.first?.payloadStringValue else {
                DispatchQueue.main.async { self.showNoDataAlert() }
                return
            }
            
            DispatchQueue.main.async { self.showResultWindow(content: firstCode) }
        }
        request.symbologies = [.qr]
        
        DispatchQueue.global(qos: .userInitiated).async {
            try? requestHandler.perform([request])
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    // --- UI 显示 ---
    func showResultWindow(content: String) {
        closeResultWindow()
        
        let resultView = ScanResultView(content: content) {
            self.closeResultWindow()
        }
        
        // 使用自定义的 HUDWindow 以支持 ESC 关闭
        let window = HUDWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: resultView)
        window.isMovableByWindowBackground = true
        
        // 关键：强制让无边框窗口可以成为 Key Window (接收键盘事件)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        self.resultWindowController = controller
    }
    
    func closeResultWindow() {
        resultWindowController?.close()
        resultWindowController = nil
    }
    
    func showNoDataAlert() {
        let alert = NSAlert()
        alert.messageText = "未识别到二维码"
        alert.informativeText = "请重试。"
        alert.addButton(withTitle: "好的")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - 3. 自定义窗口 (支持 ESC 关闭)
class HUDWindow: NSWindow {
    // 允许无边框窗口接收键盘输入
    override var canBecomeKey: Bool { true }
    
    // 监听键盘按下事件
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // 53 是 ESC 键的 KeyCode
            self.close()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - 4. 快捷键管理器 (Carbon)
class HotKeyManager {
    private var hotKeyID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let handler: () -> Void
    
    init(key: Int, modifiers: Int, handler: @escaping () -> Void) {
        self.handler = handler
        register(key: key, modifiers: modifiers)
    }
    
    deinit {
        unregister()
    }
    
    private func register(key: Int, modifiers: Int) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        // 安装事件处理器
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, userData) -> OSStatus in
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData!).takeUnretainedValue()
            manager.handler()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        
        // 注册快捷键
        let hotKeyID = EventHotKeyID(signature: 1, id: 1)
        RegisterEventHotKey(UInt32(key), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
    
    private func unregister() {
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
}

// MARK: - 5. SwiftUI 界面 (更新版)
struct ScanResultView: View {
    let content: String
    var onClose: () -> Void // 关闭回调
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // --- 顶部栏：标题 + 关闭按钮 ---
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title3)
                        .foregroundColor(.blue)
                    Text("扫描结果")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                // --- 这里的关闭按钮 ---
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1)) // 圆形背景
                        .clipShape(Circle())
                }
                .buttonStyle(.plain) // 移除默认按钮样式，使其更像图标
                .help("关闭 (ESC)")   // 鼠标悬停提示
            }
            
            // --- 内容区域 ---
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(8)
                    .textSelection(.enabled) // 允许选中文本
            }
            .frame(height: 110)
            
            // --- 底部操作栏 ---
            HStack(spacing: 12) {
                // 复制按钮
                Button(action: copyContent) {
                    HStack {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "已复制" : "复制")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ActionButtonStyle(color: isCopied ? .green : .gray))
                
                // 打开链接按钮 (如果是网址才显示)
                if let url = URL(string: content), content.lowercased().hasPrefix("http") {
                    Button(action: {
                        NSWorkspace.shared.open(url)
                        onClose()
                    }) {
                        HStack {
                            Image(systemName: "safari")
                            Text("打开链接")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActionButtonStyle(color: .blue))
                }
            }
        }
        .padding(16)
        .background(.thinMaterial) // 毛玻璃背景
        .cornerRadius(16)
        // 描边，增加精致感
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        withAnimation { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCopied = false }
    }
}

struct ActionButtonStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1.0))
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}
