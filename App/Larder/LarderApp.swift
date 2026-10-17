import FeatureRecipes
import LarderDesign
import OSLog
import SwiftUI

@main
struct LarderApp: App {
    private let dependencies: AppDependencies?

    init() {
        LarderFont.registerBundledFonts()
        TimerNotificationPresenter.shared.install()
        do {
            dependencies = try AppDependencies.makeShared(launch: .current)
        } catch {
            Logger(subsystem: "com.larder.Larder", category: "Startup")
                .fault("Could not build dependencies: \(String(describing: error), privacy: .public)")
            dependencies = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let dependencies {
                RootView(dependencies: dependencies)
            } else {
                StartupFailureView()
                    .larderTheme()
            }
        }
    }
}
