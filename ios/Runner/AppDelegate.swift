import Flutter
import UIKit
// Needed for FlutterLocalNotificationsPlugin.setPluginRegistrantCallback.
import flutter_local_notifications
// Needed to register the background companion check with BGTaskScheduler.
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Show medication reminders even while the app is in the foreground.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate

    // Must match the identifier in Info.plist (BGTaskSchedulerPermittedIdentifiers)
    // and BackgroundTasks.companionCheckTask in lib/services/background_tasks.dart.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.example.mudhkirApp.companionCheck",
      earliestBeginInSeconds: NSNumber(value: 30 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Lets notification actions (Take / Snooze / Skip) run Dart code in a background isolate.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
