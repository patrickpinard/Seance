import SwiftUI
import UIKit

/// Un glissement du doigt sur la surface tactile de la télécommande, à gauche ou à droite (8.6, demande de Patrick :
/// « comme sur Netflix »). tvOS le traduit aussi en déplacement du focus, comme un appui : on ne distingue les deux qu'en
/// écoutant la surface tactile elle-même. Le détecteur est posé sur la fenêtre le temps que la vue est affichée, et
/// n'écoute que les touchers indirects (le doigt sur la télécommande), pas les appuis sur ses bords.
///
/// 8.6, deuxième essai : un simple reconnaisseur de « swipe » ne recevait rien — le moteur du focus gardait le geste pour
/// lui. Celui-ci suit le doigt (pan) *en même temps* que le focus (`shouldRecognizeSimultaneouslyWith`), et décide à la
/// fin du geste : assez loin, ou assez vite, vers la droite ou la gauche.
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

    static func dismantleUIView(_ vue: Ecouteur, coordinator: ()) {
        vue.retirer()
    }

    final class Ecouteur: UIView, UIGestureRecognizerDelegate {
        var action: ((Int) -> Void)?
        private var suivi: UIPanGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            retirer()
            guard let window else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(glisse(_:)))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            pan.allowedPressTypes = []
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self
            window.addGestureRecognizer(pan)
            suivi = pan
        }

        func retirer() {
            if let suivi { suivi.view?.removeGestureRecognizer(suivi) }
            suivi = nil
        }

        /// Le moteur du focus garde ses propres reconnaisseurs : les deux travaillent ensemble.
        func gestureRecognizer(_ reconnaisseur: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith autre: UIGestureRecognizer) -> Bool { true }

        /// À la fin du geste : un vrai glissement horizontal (plus large que haut, assez long ou assez vif).
        @objc private func glisse(_ pan: UIPanGestureRecognizer) {
            guard pan.state == .ended, let vue = pan.view else { return }
            let deplacement = pan.translation(in: vue)
            let vitesse = pan.velocity(in: vue)
            guard abs(deplacement.x) > abs(deplacement.y) * 1.5,
                  abs(deplacement.x) > 250 || abs(vitesse.x) > 900,
                  focusDansLaZone else { return }
            action?(deplacement.x > 0 ? 1 : -1)
        }

        /// Le bouton qui a le focus est dans la zone de cette vue (la proposition) : ailleurs sur la page — une étagère
        /// plus bas —, le glissement garde son rôle ordinaire.
        private var focusDansLaZone: Bool {
            guard let window, let focus = window.windowScene?.focusSystem?.focusedItem,
                  let espace = focus.parentFocusEnvironment?.focusItemContainer?.coordinateSpace else { return false }
            // Le cadre d'un élément du focus est donné dans l'espace de son conteneur.
            let cadreFocus = espace.convert(focus.frame, to: window.coordinateSpace)
            let zone = convert(bounds, to: window).insetBy(dx: -40, dy: -40)
            return zone.intersects(cadreFocus)
        }
    }
}
