import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            guard let controller = storyboard.instantiateInitialViewController() as? MovieQuizViewController else {
                preconditionFailure("Не удалось создать экран викторины")
            }
            let suiteName = "ru.yandex.practicum.MovieQuiz.UITests"
            guard let storage = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("Не удалось создать тестовое хранилище")
            }
            storage.removePersistentDomain(forName: suiteName)
            controller.setup { view in
                MovieQuizPresenter(
                    viewController: view,
                    statisticService: StatisticService(storage: storage),
                    questionFactoryBuilder: { UITestQuestionFactory(delegate: $0) }
                )
            }
            window.rootViewController = controller
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            window.rootViewController = UIViewController()
        } else {
            window.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController()
        }
        #else
        window.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController()
        #endif
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {}
    func sceneDidEnterBackground(_ scene: UIScene) {}
}
