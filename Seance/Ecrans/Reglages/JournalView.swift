import SwiftUI

/// Onglet « Journal » d'À propos : les problèmes récents, expliqués simplement, jour par jour.
struct SectionsJournal: View {
    @Environment(EtatApp.self) private var etat
    @State private var confirmation = false

    private var journal: Journal { etat.journal }

    var body: some View {
        if journal.entrees.isEmpty {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    Text("Aucun problème enregistré").font(.headline)
                    Text("Si quelque chose ne fonctionne pas, l'explication s'affichera ici, avec ce que tu peux faire.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        } else {
            Section {
                // Une ligne par action : deux boutons sur une même ligne de liste se déclenchent ensemble.
                ShareLink(item: journal.texte, subject: Text("Journal de Séance")) {
                    Label("Partager le journal", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) { confirmation = true } label: {
                    Label("Effacer le journal (\(Format.pluriel(journal.entrees.count, "entrée")))", systemImage: "trash")
                }
                .confirmationDialog("Effacer le journal ?", isPresented: $confirmation, titleVisibility: .visible) {
                    Button("Effacer le journal", role: .destructive) { journal.effacer() }
                } message: {
                    Text("Les \(journal.entrees.count) entrées disparaissent de cet appareil. Rien d'autre n'est touché.")
                }
            } footer: {
                Text("Le journal reste sur cet appareil. Il ne contient ni clé ni mot de passe.")
            }

            ForEach(parJour, id: \.jour) { groupe in
                Section(groupe.jour) {
                    ForEach(groupe.entrees) { entree in
                        ligne(entree)
                    }
                }
            }
        }
    }

    private var parJour: [(jour: String, entrees: [Journal.Entree])] {
        let calendrier = Calendar.current
        let groupes = Dictionary(grouping: journal.entrees) { calendrier.startOfDay(for: $0.date) }
        return groupes.keys.sorted(by: >).map { jour in
            let libelle: String
            if calendrier.isDateInToday(jour) {
                libelle = "Aujourd'hui"
            } else if calendrier.isDateInYesterday(jour) {
                libelle = "Hier"
            } else {
                libelle = jour.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH"))).capitalized
            }
            return (libelle, groupes[jour] ?? [])
        }
    }

    private func ligne(_ entree: Journal.Entree) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entree.domaine.symbole)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(entree.domaine.couleur.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entree.domaine.libelle).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if entree.repetitions > 1 {
                        Text("×\(entree.repetitions)").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                    Text(entree.date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                }
                Text(entree.message).font(.subheadline.weight(.semibold))
                if let conseil = entree.conseil {
                    Label(conseil, systemImage: "lightbulb")
                        .font(.footnote)
                        .foregroundStyle(Theme.accentClair)
                }
                if let detail = entree.detail {
                    Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
