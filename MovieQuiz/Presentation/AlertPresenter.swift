import UIKit

@MainActor
protocol AlertPresenting {
    func show(model: AlertModel)
}

@MainActor
final class AlertPresenter: AlertPresenting {
    private weak var viewController: UIViewController?

    init(viewController: UIViewController) {
        self.viewController = viewController
    }

    func show(model: AlertModel) {
        let alert = UIAlertController(
            title: model.title,
            message: model.message,
            preferredStyle: .alert
        )
        let completion = model.completion
        let action = UIAlertAction(title: model.buttonText, style: .default) { _ in
            completion()
        }
        alert.addAction(action)
        viewController?.present(alert, animated: true)
    }
}
