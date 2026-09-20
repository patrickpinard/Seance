import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// « Ce soir » sur la TV : la soirée en grandes affiches, puis les soirées à venir.
struct CeSoirTV: View {
    @Query(sort: \SelectionSoir.ajouteLe) private var soirees: [SelectionSoir]
    @Query private var fichiers: [FichierNAS]

    @State private var jourChoisi: String?

    var body: some View {
        let groupes = parSoiree
        let choisi = jourChoisi.flatMap { j in groupes.contains { $0.soiree == j } ? j : nil } ?? groupes.first?.soiree
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 44) {
                if groupes.isEmpty {
                    VideTV(symbole: "moon.stars.fill", titre: "Rien de prévu",
                           message: "Ajoute un titre à ta soirée depuis sa fiche, ici ou sur ton iPhone : il t'attendra sur cet écran.")
                } else {
                    // La même rangée de jours que sur l'iPhone : ce soir et les soirées déjà prévues.
                    ScrollView(.horizontal) {
                        HStack(spacing: 24) {
                            ForEach(groupes, id: \.soiree) { groupe in
                                Button { jourChoisi = groupe.soiree } label: {
                                    TuileJourTV(nom: Self.nomCourt(groupe.soiree), numero: Self.quantieme(groupe.soiree),
                                                detail: groupe.titres.count > 1 ? "\(groupe.titres.count) titres" : "1 titre")
                                }
                                .buttonStyle(BoutonTV(principal: groupe.soiree == choisi, hauteur: nil))
                            }
                        }
                        .padding(.horizontal, MargesTV.bord)
                        .padding(.vertical, 20)
                    }
                    .scrollClipDisabled()
                    .focusSection()

                    if let choisi, let groupe = groupes.first(where: { $0.soiree == choisi }) {
                        EtagereTV(titre: libelle(choisi), sousTitre: groupe.titres.count > 1 ? "\(groupe.titres.count) titres pour cette soirée" : "1 titre") {
                            ForEach(groupe.titres, id: \.reference) { selection in
                                NavigationLink(value: selection.reference) {
                                    AfficheTV(titre: selection.titre, sousTitre: surLeNAS(selection.reference) ? "Sur ton NAS" : nil,
                                              cheminAffiche: selection.cheminAffiche, marque: surLeNAS(selection.reference) ? "externaldrive.fill" : nil)
                                }
                                .buttonStyle(.card)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 40)
        }
    }

    private static func quantieme(_ soiree: String) -> Int {
        Calendar.current.component(.day, from: ServiceSoiree.jour(soiree) ?? .now)
    }

    private static func nomCourt(_ soiree: String) -> String {
        if soiree == ServiceSoiree.soiree() { return "Ce soir" }
        if soiree == ServiceSoiree.soiree(.now.addingTimeInterval(86_400)) { return "Demain" }
        guard let jour = ServiceSoiree.jour(soiree) else { return "" }
        return jour.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_CH"))).capitalized
    }

    private var parSoiree: [(soiree: String, titres: [SelectionSoir])] {
        let ceSoir = ServiceSoiree.soiree()
        return Dictionary(grouping: soirees.filter { $0.soiree >= ceSoir }, by: \.soiree)
            .map { (soiree: $0.key, titres: $0.value) }
            .sorted { $0.soiree < $1.soiree }
    }

    private func libelle(_ soiree: String) -> String {
        if soiree == ServiceSoiree.soiree() { return "Ce soir" }
        guard let jour = ServiceSoiree.jour(soiree) else { return soiree }
        if soiree == ServiceSoiree.soiree(.now.addingTimeInterval(86_400)) { return "Demain" }
        return jour.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH"))).capitalized(with: Locale(identifier: "fr_CH"))
    }

    private func surLeNAS(_ reference: ReferenceTitre) -> Bool {
        fichiers.contains { $0.reference == reference }
    }
}
