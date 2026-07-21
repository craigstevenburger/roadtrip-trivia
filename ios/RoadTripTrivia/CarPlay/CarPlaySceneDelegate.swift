import CarPlay
import UIKit

/// Entry point for the CarPlay scene declared in project.yml's
/// UIApplicationSceneManifest. This pass only connects the scene and
/// reflects live game state on the Now Playing template — narration and
/// spoken-answer capture are a separate follow-up pass (see docs/plan).
@MainActor
final class CarPlaySceneDelegate: UIResponder, @preconcurrency CPTemplateApplicationSceneDelegate {
    private var display: CarPlayGameDisplay?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        interfaceController.setRootTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
        let display = CarPlayGameDisplay()
        display.start()
        self.display = display
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        display?.stop()
        display = nil
    }
}
