import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let cacheSecurityChannel = "bimotc.com/cache_security"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerCacheSecurityChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func registerCacheSecurityChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: cacheSecurityChannel, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getCacheKey":
        do {
          result(try SecureCacheKeyStore.getOrCreateCacheKey())
        } catch {
          result(FlutterError(code: "CACHE_KEY_ERROR", message: "\(error)", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
