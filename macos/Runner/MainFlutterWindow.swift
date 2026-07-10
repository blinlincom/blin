import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let localVaultChannel = "bimotc.com/local_vault"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerLocalVaultChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func registerLocalVaultChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: localVaultChannel, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getCacheKey":
        do {
          result(try LocalVaultKeyStore.getOrCreateCacheKey())
        } catch {
          result(FlutterError(code: "LOCAL_KEY_ERROR", message: "\(error)", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
