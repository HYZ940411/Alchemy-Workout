import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()

    // 這是手機 App，桌面版固定為手機比例的視窗（iPhone 邏輯尺寸 390×844）
    let size = NSSize(width: 390, height: 844)
    var frame = self.frame
    frame.size = size
    if let screen = NSScreen.main {
      frame.origin = NSPoint(
        x: screen.visibleFrame.midX - size.width / 2,
        y: screen.visibleFrame.midY - size.height / 2)
    }

    self.contentViewController = flutterViewController
    self.setFrame(frame, display: true)
    self.contentMinSize = size
    self.contentMaxSize = NSSize(width: size.width, height: 2000)
    self.title = "健金術 Alchemy Workout"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
