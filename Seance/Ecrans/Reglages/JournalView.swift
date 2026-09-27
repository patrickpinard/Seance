import SwiftUI

/// Onglet « Journal » d'À propos : les problèmes récents, expliqués simplement, jour par jour.
struct SectionsJournal: View {
    @Environment(EtatApp.self) private var etat
    @State private var confirmation = false
    /// « Effacer jusqu'au… » (8.2.17) : le jour choisi, compris.
    @State private var effacerJusqua = false
    @State private var jourLimite = Date.now
    /// Les jours ouverts : aujourd'hui au départ, les autres fermés.
    @State private var joursOuverts: Set<String> = ["Aujourd'hui"]

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
                Button(role: .destructive) { effacerJusqua = true } label: {
                    Label("Effacer jusqu'au…", systemImage: "calendar.badge.minus")
                }
                .sheet(isPresented: $effacerJusqua) {
                    NavigationStack {
                        Form {
                            Section {
                                DatePicker("Effacer jusqu'au", selection: $jourLimite, in: ...Date.now, displayedComponents: .date)
                                    .environment(\.locale, Locale(identifier: "fr_CH"))
                            } footer: {
                                Text("Les entrées de ce jour-là et d'avant disparaissent de cet appareil.")
                            }
                        }
                        .navigationTitle("Effacer le journal")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { effacerJusqua = false } }
                            ToolbarItem(placement: .destructiveAction) {
                                Button("Effacer", role: .destructive) {
                                    journal.effacer(jusqua: jourLimite)
                                    effacerJusqua = false
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium])
                }
                Button(role: .destructive) { confirmation = true } label: {
                    Label("Tout effacer (\(Format.pluriel(journal.entrees.count, "entrée")))", systemImage: "trash")
                }
                .confirmationDialog("Effacer le journal ?", isPresented: $confirmation, titleVisibility: .visible) {
                    Button("Effacer le journal", role: .destructive) { journal.effacer() }
                } message: {
                    Text("Les \(journal.entrees.count) entrées disparaissent de cet appareil. Rien d'autre n'est touché.")
                }
            } footer: {
                Text("Le journal reste sur cet appareil et garde deux semaines. Il ne contient ni clé ni mot de passe.")
            }

            // Une liste de jours (8.2.17) : chaque jour s'ouvre et se ferme, aujourd'hui ouvert au départ.
            Section {
                ForEach(parJour, id: \.jour) { groupe in
                    DisclosureGroup(isExpanded: Binding(get: { joursOuverts.contains(groupe.jour) },
                                                        set: { if $0 { joursOuverts.insert(groupe.jour) } else { joursOuverts.remove(groupe.jour) } })) {
                        ForEach(groupe.entrees) { entree in
                            ligne(entree)
                        }
                    } label: {
                        HStack {
                            Text(groupe.jour).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(Format.pluriel(groupe.entrees.count, "entrée")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(Theme.accent)
                }
            } header: {
                Text("Par jour")
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
                .font(.footnote.weight(.semibold))
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
