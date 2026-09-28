import SwiftUI
import UIKit

/// Un glissement du doigt sur la surface tactile de la télécommande, à gauche ou à droite (8.6, demande de Patrick :
/// « comme sur Netflix »). tvOS le traduit aussi en déplacement du focus, comme un appui : on ne distingue les deux qu'en
/// écoutant la surface tactile elle-même. Le reconnaisseur est posé sur la fenêtre le temps que la vue est affichée, et
/// n'écoute que les touchers indirects (le doigt sur la télécommande), pas les appuis sur ses bords.
struct GlissementTelecommande: UIViewRepresentable {
    /// `-1` vers la gauche, `1` vers la droite.
    let action: (Int) -> Void

    func makeUIView(context: Context) -> Ecouteur {
        let vue = Ecouteur()
        vue.action = action
        vue.isUserInteractionEnabled = false
        return vue
    }

    func updateUIView(_ vue: Ecouteur, context: Context) {
        vue.action = action
    }

    final class Ecouteur: UIView {
        var action: ((Int) -> Void)?
        private var reconnaisseurs: [UISwipeGestureRecognizer] = []

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reconnaisseurs.forEach { $0.view?.removeGestureRecognizer($0) }
            reconnaisseurs = []
            guard let window else { return }
            for (direction, pas) in [(UISwipeGestureRecognizer.Direction.left, -1), (.right, 1)] {
                let reconnaisseur = UISwipeGestureRecognizer(target: self, action: #selector(glisse(_:)))
                reconnaisseur.direction = direction
                reconnaisseur.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
                reconnaisseur.allowedPressTypes = []
                reconnaisseur.cancelsTouchesInView = false
                reconnaisseur.name = "seance.glissement.\(pas)"
                window.addGestureRecognizer(reconnaisseur)
                reconnaisseurs.append(reconnaisseur)
            }
        }

        /// Vers la droite, la suivante ; vers la gauche, la précédente — le sens des appuis, comme l'app TV d'Apple.
        @objc private func glisse(_ reconnaisseur: UISwipeGestureRecognizer) {
            action?(reconnaisseur.direction == .left ? -1 : 1)
        }
    }
}
