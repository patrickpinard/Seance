import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Un titre choisi hors de sa fiche (clic droit, Mes listes, idées) : de quoi le prévoir pour une soirée
/// ou le ranger dans une liste, sans relire TMDB.
struct TitreChoisi: Identifiable, Hashable {
    let reference: ReferenceTitre
    let titre: String
    let cheminAffiche: String?

    var id: ReferenceTitre { reference }
}

/// Dates écrites comme on les dit : « ce soir », « demain », « samedi 20 septembre ».
@MainActor
enum LibelleSoiree {
    /// « Vendredi 18 septembre » : majuscule au jour seulement.
    static func jour(_ date: Date) -> String {
        let texte = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH")))
        return texte.prefix(1).uppercased() + texte.dropFirst()
    }

    static func soiree(_ soiree: String) -> String {
        if soiree == ServiceSoiree.soiree() { return "Ce soir" }
        if soiree == ServiceSoiree.soiree(jour: Date.now.addingTimeInterval(86_400)) { return "Demain" }
        return ServiceSoiree.jour(soiree).map(jour) ?? soiree
    }
}

/// Prévoir un titre pour la soirée d'un jour, depuis n'importe quel écran, avec confirmation et annulation.
@MainActor
enum PrevoirSoiree {
    static func prevoir(_ titre: TitreChoisi, le jour: Date, etat: EtatApp, contexte: ModelContext) {
        let service = ServiceSoiree(contexte: contexte)
        let soiree = ServiceSoiree.soiree(jour: jour)
        let avant = ((try? service.selection()) ?? []).first { $0.reference == titre.reference }?.soiree
            ?? ((try? service.aVenir()) ?? []).first { $0.reference == titre.reference }?.soiree
        try? service.retenir(titre.reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche, soiree: soiree)
        let quand = LibelleSoiree.soiree(max(soiree, ServiceSoiree.soiree())).lowercased()
        etat.confirmer("« \(titre.titre) » prévu \(quand)", symbole: "calendar") { [contexte] in
            let service = ServiceSoiree(contexte: contexte)
            if let avant {
                try? service.retenir(titre.reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche, soiree: avant)
            } else {
                try? service.retirer(titre.reference, soiree: max(soiree, ServiceSoiree.soiree()))
            }
        }
    }
}

/// Le calendrier d'une soirée : à partir d'aujourd'hui.
struct ChoixSoiree: View {
    let titre: String
    let choisir: (Date) -> Void

    @Environment(\.dismiss) private var fermer
    @State private var jour: Date

    init(titre: String, depart: Date, choisir: @escaping (Date) -> Void) {
        self.titre = titre
        self.choisir = choisir
        _jour = State(initialValue: max(depart, Calendar.current.startOfDay(for: .now)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Quel soir veux-tu regarder « \(titre) » ?")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                DatePicker("Soirée", selection: $jour, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.accent)
                    .environment(\.locale, Locale(identifier: "fr_CH"))
                Button {
                    choisir(jour)
                    fermer()
                } label: {
                    Text("Prévoir pour \(LibelleSoiree.jour(jour).lowercased())")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Theme.fond)
            .titreDeFeuille("Choisir la soirée")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { fermer() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.fond)
    }
}
