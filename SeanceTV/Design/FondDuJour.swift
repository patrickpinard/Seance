import CoreImage
import CoreImage.CIFilterBuiltins
import SeanceDonnees
import SeanceKit
import SwiftData
import UIKit

/// Le fond des pages de la TV, préparé une fois (8.10, bilan de l'Apple TV) : chaque onglet relisait quatre listes du
/// magasin et floutait en direct une image de 1280 pixels, recalculée sous chaque animation du focus. Ici, une petite
/// image du jour est choisie, floutée et saturée une seule fois ; `FondTV` n'a plus qu'à l'afficher.
enum FondDuJour {
    /// Ta soirée d'abord, sinon ton NAS, sinon le programme TV ; une grande image si on en connaît une, sinon une affiche.
    /// Elle change chaque jour.
    @MainActor
    static func choisir(contexte: ModelContext, jour: Date = .now) -> URL? {
        let rang = Calendar.current.ordinality(of: .day, in: .era, for: jour) ?? 0
        func duJour(_ chemins: [String]) -> String? {
            let uniques = Array(Set(chemins)).sorted()
            return uniques.isEmpty ? nil : uniques[rang % uniques.count]
        }
        var fichiers = FetchDescriptor<FichierNAS>()
        fichiers.propertiesToFetch = [\.cheminFond, \.cheminAffiche]
        let lus = (try? contexte.fetch(fichiers)) ?? []
        let debut = Calendar.current.startOfDay(for: jour)
        var diffusions = FetchDescriptor<Diffusion>(predicate: #Predicate { $0.fin > debut })
        diffusions.propertiesToFetch = [\.cheminFond]
        let fonds = lus.compactMap(\.cheminFond) + ((try? contexte.fetch(diffusions)) ?? []).compactMap(\.cheminFond)
        if let fond = duJour(fonds) { return ImageTMDB.url(fond, .vignette) }
        let soirees = ((try? contexte.fetch(FetchDescriptor<SelectionSoir>())) ?? []).compactMap(\.cheminAffiche)
        let suivis = ((try? contexte.fetch(FetchDescriptor<Suivi>())) ?? []).compactMap(\.cheminAffiche)
        return duJour(soirees + lus.compactMap(\.cheminAffiche) + suivis).flatMap { ImageTMDB.url($0, .affiche) }
    }

    /// Télécharge la petite image et la floute une fois : le flou d'une image de 300 pixels étirée à l'écran donne le
    /// même voile qu'un flou de 34 points sur l'image entière.
    static func preparer(_ url: URL) async -> UIImage? {
        guard let (donnees, _) = try? await URLSession.shared.data(from: url), let source = CIImage(data: donnees) else { return nil }
        let couleurs = CIFilter.colorControls()
        couleurs.inputImage = source.clampedToExtent()
        couleurs.saturation = 1.35
        let flou = CIFilter.gaussianBlur()
        flou.inputImage = couleurs.outputImage
        flou.radius = 9
        guard let sortie = flou.outputImage?.cropped(to: source.extent),
              let image = CIContext().createCGImage(sortie, from: source.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}
