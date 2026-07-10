import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let localVaultChannel = "bimotc.com/local_vault"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerLocalVaultChannel(messenger: engineBridge.applicationRegistrar.messenger())
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
