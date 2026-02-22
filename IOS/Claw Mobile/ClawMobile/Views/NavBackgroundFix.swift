import SwiftUI
import UIKit

/// Injects a zero-size UIViewController into the hierarchy so we can walk up
/// to the UINavigationController and set its view.backgroundColor to purple.
private struct NavBackgroundFixVC: UIViewControllerRepresentable {
    let color: UIColor

    func makeUIViewController(context: Context) -> _FixVC {
        _FixVC(color: color)
    }
    func updateUIViewController(_ vc: _FixVC, context: Context) {}

    class _FixVC: UIViewController {
        let color: UIColor
        init(color: UIColor) {
            self.color = color
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyBackground()
        }

        private func applyBackground() {
            // Walk every ancestor VC and set its view background to purple
            var vc: UIViewController? = self
            while let current = vc {
                current.view.backgroundColor = color
                vc = current.parent
            }
            // Fix the window itself
            view.window?.backgroundColor = color
            // Fix every subview of the window's root that has a black background
            if let root = view.window?.rootViewController {
                paintViews(root.view)
            }
        }

        private func paintViews(_ view: UIView) {
            if view.backgroundColor == .black || view.backgroundColor == UIColor(white: 0, alpha: 1) {
                view.backgroundColor = color
            }
            for sub in view.subviews {
                paintViews(sub)
            }
        }
    }
}

/// Apply as a background modifier on any view that lives inside a NavigationStack.
struct NavBackgroundFix: ViewModifier {
    let color = UIColor(red: 0.08, green: 0.04, blue: 0.12, alpha: 1)
    func body(content: Content) -> some View {
        content.background(
            NavBackgroundFixVC(color: color)
                .frame(width: 0, height: 0)
        )
    }
}

extension View {
    func fixNavBackground() -> some View {
        modifier(NavBackgroundFix())
    }
}
