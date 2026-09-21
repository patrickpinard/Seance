import SwiftData
import SwiftUI

/// Réglages › Centrale de la maison (Mac seulement) : ce Mac reste allumé, Séance y veille pour toute la maison.
struct ReglagesCentraleView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte

    private var centrale: EtatCentrale { etat.centrale }

    var body: some View {
        Form {
            Section {
                Toggle("Séance veille sur la maison", isOn: Binding { centrale.active } set: { valeur in
                    centrale.regler(active: valeur, etat: etat) { ConteneurApp.conteneur }
                })
                .tint(Theme.accent)
                Toggle("Ouvrir Séance à l'ouverture de session", isOn: Binding { centrale.ouvertureDeSession } set: { centrale.reglerOuvertureDeSession($0) })
                    .tint(Theme.accent)
                if let erreur = centrale.erreurOuverture {
                    Label(erreur, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                }
            } footer: {
                Text("Séance n'a pas de serveur : sans app ouverte, rien n'avance. Sur ce Mac, elle passe tous les quarts d'heure : elle synchronise le dossier d'iCloud Drive et celui du NAS — et fait ainsi le pont entre l'Apple TV et tes autres appareils —, relit le guide TV et le NAS, recalcule les alertes, et envoie l'e-mail de la semaine à l'heure dite. Tant qu'elle veille, le Mac ne se met pas en veille de lui-même (l'écran, lui, peut s'éteindre). Laisse simplement Séance ouverte.")
            }

            if centrale.active {
                Section("Dernier passage") {
                    if let dernier = centrale.dernierPassage {
                        LabeledContent("Quand") { Text(dernier, format: .relative(presentation: .named)) }
                    }
                    if let bilan = centrale.bilan { Text(bilan).font(.footnote).foregroundStyle(.secondary) }
                    Button {
                        Task { await centrale.passer(etat: etat, contexte: contexte) }
                    } label: {
                        HStack {
                            Label("Passer maintenant", systemImage: "arrow.triangle.2.circlepath")
                            if centrale.enCours { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(centrale.enCours)
                }
            }
        }
        .pageReglages("Centrale de la maison")
    }
}
