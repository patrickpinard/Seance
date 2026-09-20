import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// « Ce soir » sur la TV : la soirée en grandes affiches, puis les soirées à venir.
struct CeSoirTV: View {
    @Query(sort: \SelectionSoir.ajouteLe) private var soirees: [SelectionSoir]
    @Query private var fichiers: [FichierNAS]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 50) {
                if parSoiree.isEmpty {
                    VideTV(symbole: "moon.stars.fill", titre: "Rien de prévu",
                           message: "Ajoute un titre à ta soirée depuis sa fiche, ici ou sur ton iPhone : il t'attendra sur cet écran.")
                }
                ForEach(parSoiree, id: \.soiree) { groupe in
                    EtagereTV(titre: libelle(groupe.soiree), sousTitre: groupe.titres.count > 1 ? "\(groupe.titres.count) titres" : "1 titre") {
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
            .padding(.vertical, 40)
        }
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
