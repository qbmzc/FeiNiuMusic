import Cocoa
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {
  private var windows: [NSWindow] = []

  override func tearDown() {
    for window in windows {
      window.orderOut(nil)
      window.close()
    }
    windows = []
    super.tearDown()
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    windows.append(window)
    return window
  }

  private func reopenMainWindow(
    _ window: NSWindow,
    hasVisibleWindows: Bool
  ) throws -> Bool {
    let delegate = try XCTUnwrap(NSApplication.shared.delegate as? FlutterAppDelegate)
    let originalWindow = delegate.mainFlutterWindow
    delegate.mainFlutterWindow = window
    defer { delegate.mainFlutterWindow = originalWindow }
    let applicationDelegate: NSApplicationDelegate = delegate
    return try XCTUnwrap(
      applicationDelegate.applicationShouldHandleReopen?(
        NSApplication.shared,
        hasVisibleWindows: hasVisibleWindows))
  }

  func testDockReopenRestoresHiddenMainWindowWithVisibleLyricsWindow() throws {
    let mainWindow = makeWindow()
    let lyricsWindow = makeWindow()
    lyricsWindow.level = .floating
    lyricsWindow.orderFrontRegardless()
    mainWindow.orderOut(nil)
    XCTAssertTrue(lyricsWindow.isVisible)
    XCTAssertFalse(mainWindow.isVisible)

    XCTAssertFalse(try reopenMainWindow(mainWindow, hasVisibleWindows: true))

    XCTAssertTrue(mainWindow.isVisible)
    XCTAssertTrue(lyricsWindow.isVisible)
  }

  func testDockReopenRestoresHiddenMainWindowWithoutVisibleWindows() throws {
    let mainWindow = makeWindow()
    mainWindow.orderOut(nil)

    XCTAssertFalse(try reopenMainWindow(mainWindow, hasVisibleWindows: false))

    XCTAssertTrue(mainWindow.isVisible)
  }

  func testDockReopenRestoresMiniaturizedMainWindow() throws {
    let mainWindow = makeWindow()
    mainWindow.makeKeyAndOrderFront(nil)
    let miniaturized = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in mainWindow.isMiniaturized },
      object: mainWindow)
    mainWindow.miniaturize(nil)
    wait(for: [miniaturized], timeout: 5)

    let restored = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        !mainWindow.isMiniaturized && mainWindow.isVisible
      },
      object: mainWindow)
    XCTAssertFalse(try reopenMainWindow(mainWindow, hasVisibleWindows: true))

    wait(for: [restored], timeout: 5)
  }
}
