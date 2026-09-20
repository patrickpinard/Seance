import XCTest

/// L'audit d'accessibilité d'Xcode sur les écrans principaux : un élément sans description est muet pour VoiceOver.
/// On n'arrête pas au premier défaut : tous sont listés, écran par écran, pour les corriger d'un coup.
@MainActor
final class AccessibiliteTests: XCTestCase {
    private var app = XCUIApplication()

    /// Ce que l'audit doit attraper ici : les éléments sans nom et les zones de toucher trop petites. Le contraste et la
    /// coupe du texte se jugent sur capture (tour en clair, tour en grand texte) : sur des images, l'audit se trompe.
    private func auditer(_ ecran: String) {
        do {
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion]) { defaut in
                let element = defaut.element.map { "\($0.elementType.rawValue) « \($0.label) » \($0.frame)" } ?? "?"
                print("AUDIT|\(ecran)|\(defaut.auditType.rawValue)|\(defaut.compactDescription)|\(element)")
                XCTFail("\(ecran) : \(defaut.compactDescription) — \(element)")
                return true   // noté ; on continue pour lister tous les défauts d'un coup
            }
        } catch {
            print("AUDIT|\(ecran)|erreur|\(error.localizedDescription)|")
            XCTFail("\(ecran) : l'audit n'a pas pu tourner — \(error.localizedDescription)")
        }
    }

    func testAuditDesEcrans() throws {
        continueAfterFailure = true
        Lancement.demonstration(app)
        app.launch()
        XCTAssertTrue(app.staticTexts["Nouveautés"].firstMatch.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3)
        auditer("Accueil")
        app.tabBars.buttons["Ce soir"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 3)
        auditer("Ce soir")
        app.tabBars.buttons["Mes listes"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        auditer("Mes listes")
        app.buttons["À venir"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        auditer("À venir")
        app.tabBars.buttons["Profil"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 3)
        auditer("Profil")
        app.navigationBars.buttons["Réglages"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        auditer("Réglages")
    }
}
