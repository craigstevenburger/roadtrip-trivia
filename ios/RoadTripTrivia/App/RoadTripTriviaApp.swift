import FirebaseCore
import SwiftUI

@main
struct RoadTripTriviaApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
