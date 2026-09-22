import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

// Réglages › Où regarder : plateformes, télévision, lecture des vidéos du NAS.

/// EF-43 : plateformes auxquelles Patrick est abonné, parmi celles que TMDB connaît en Suisse.
struct ReglagesPlateformesView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var abonnements: [Abonnement]
    @State private var catalogue: [FournisseurCatalogue] = []

    var body: some View {
        Form {
            Section {
                if etat.tmdb == nil {
                    Text("Enregistre d'abord la clé TMDB.").foregroundStyle(.secondary)
                } else if catalogue.isEmpty {
                    ProgressView()
                }
                ForEach(catalogue) { fournisseur in
                    Toggle(fournisseur.nom, isOn: liaison(fournisseur))
                }
            } footer: {
                Text("Disponibilités en Suisse fournies par JustWatch, via TMDB.")
            }
        }
        .pageReglages("Plateformes")
        .task(id: etat.tmdb == nil) { await charger() }
    }

    private func charger() async {
        guard let client = etat.tmdb else { return }
        let liste = (try? await client.catalogueFournisseurs(.film)) ?? []
        catalogue = liste.sorted { ($0.priorites["CH"] ?? .max) < ($1.priorites["CH"] ?? .max) }
    }

    private func liaison(_ fournisseur: FournisseurCatalogue) -> Binding<Bool> {
        Binding {
            abonnements.contains { $0.providerID == fournisseur.id && $0.actif }
        } set: { actif in
            if let existant = abonnements.first(where: { $0.providerID == fournisseur.id }) {
                existant.actif = actif
            } else if actif {
                contexte.insert(Abonnement(providerID: fournisseur.id, nom: fournisseur.nom, cheminLogo: fournisseur.cheminLogo))
            }
            contexte.sauver()
        }
    }
}

/// EF-45 à EF-51 : chaînes reçues et lecture du guide.
struct ReglagesTeleView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var chaines: [Chaine]
    @State private var nonReconnusVisibles = false
    @AppStorage(BlueTV.cle) private var blueTV = true

    var body: some View {
        Form {
            Section {
                if etat.teleEnCours {
                    HStack {
                        Text("Lecture des programmes…")
                        Spacer()
                        ProgressView()
                    }
                } else if let derniere = etat.derniereLectureTele {
                    LabeledContent("Dernière lecture") {
                        Text(derniere, format: .relative(presentation: .named))
                    }
                }
                if let rapport = etat.rapportTele {
                    LabeledContent("Films reconnus", value: "\(rapport.filmsRattaches) sur \(rapport.filmsLus)")
                    LabeledContent("Diffusions à venir", value: "\(rapport.diffusionsEnregistrees)")
                    if !rapport.filmsNonRattaches.isEmpty {
                        DisclosureGroup("Films non reconnus (\(rapport.filmsNonRattaches.count))", isExpanded: $nonReconnusVisibles) {
                            ForEach(rapport.filmsNonRattaches, id: \.self) { titre in
                                Text(titre).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let erreur = etat.erreurTele {
                    Label(erreur, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Actualiser maintenant") {
                    Task { await etat.actualiserTele(contexte: contexte, force: true) }
                }
                .disabled(etat.teleEnCours || etat.tmdb == nil)
            } header: {
                Text("Guide des programmes")
            } footer: {
                Text("Le guide est relu toutes les 12 heures et dès que tu changes de chaînes. Un film n'apparaît que s'il est reconnu dans TMDB sans hésitation.")
            }

            Section {
                Toggle("Ouvrir les chaînes dans blue TV", isOn: $blueTV)
            } header: {
                Text("En direct")
            } footer: {
                Text("Quand un film ou une série passe en ce moment, ou dans le quart d'heure, son bouton ouvre la chaîne dans l'app blue TV de Swisscom (sur le Mac, dans le lecteur web tv.blue.ch).")
            }

            Section {
                ForEach(ChaineGuide.suisses) { chaine in
                    Toggle(chaine.nom, isOn: liaison(chaine))
                }
            } header: {
                Text("Suisse")
            } footer: {
                Text("Avec la RTS, Séance télécharge le guide complet (18 Mo) au lieu du guide TNT (1 Mo).")
            }

            Section {
                ForEach(ChaineGuide.tntParDefaut) { chaine in
                    Toggle(chaine.nom, isOn: liaison(chaine))
                }
            } header: {
                Text("France")
            } footer: {
                Text("Programmes : XML TV Fr, projet bénévole, sans garantie.")
            }
        }
        .pageReglages("Télévision")
        // Les chaînes ont pu changer : le guide est relu en quittant la page, si nécessaire.
        .onDisappear {
            Task { await etat.actualiserTele(contexte: contexte) }
        }
    }

    private func liaison(_ chaine: ChaineGuide) -> Binding<Bool> {
        Binding {
            chaines.contains { $0.identifiantGuide == chaine.id && $0.active }
        } set: { active in
            if let existante = chaines.first(where: { $0.identifiantGuide == chaine.id }) {
                existante.active = active
            } else if active {
                contexte.insert(Chaine(identifiantGuide: chaine.id, nom: chaine.nom, source: .xmltvfr))
            }
            contexte.sauver()
        }
    }
}

/// L'app qui lit les vidéos du NAS : Infuse ou VLC, avec pour chacune si elle est installée et ce qu'elle demande.
struct ReglagesLectureView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            #if targetEnvironment(macCatalyst)
            Section {
                Label("Le lecteur vidéo par défaut du Mac", systemImage: "play.rectangle.fill")
            } footer: {
                Text("Sur le Mac, Séance ouvre le fichier du NAS dans l'app que macOS associe aux vidéos (IINA, VLC, Infuse…). Pour en changer : dans le Finder, « Lire les informations » sur une vidéo, puis « Ouvrir avec » et « Tout modifier ».")
            }
            #else
            Section {
                ForEach(LecteurVideo.allCases) { lecteur in
                    let installe = UIApplication.shared.canOpenURL(URL(string: "\(lecteur.schema)://")!)
                    Button {
                        etat.nas.choisir(lecteur)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: etat.nas.lecteur == lecteur ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(etat.nas.lecteur == lecteur ? AnyShapeStyle(Theme.accentClair) : AnyShapeStyle(.tertiary))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lecteur.nom).font(.headline).foregroundStyle(Color.primary)
                                Text(installe ? "Installée" : "Pas installée sur cet appareil")
                                    .font(.caption)
                                    .foregroundStyle(installe ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.orange))
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(lecteur.nom), \(installe ? "installée" : "pas installée")")
                    .accessibilityAddTraits(etat.nas.lecteur == lecteur ? .isSelected : [])
                    if !installe {
                        Button("Installer \(lecteur.nom) depuis l'App Store") { openURL(lecteur.appStore) }
                            .font(.subheadline)
                    }
                }
            } header: {
                Text("Ouvrir les vidéos du NAS avec")
            } footer: {
                Text("Toucher un film ou un épisode « Sur ton NAS » l'ouvre dans cette app ; un appui long propose l'autre.")
            }

            Section("Ce que chaque app demande") {
                Label {
                    Text("**Infuse** ouvre le titre dans sa propre bibliothèque et démarre la lecture : ajoute d'abord le partage de ton NAS dans Infuse, et laisse-le indexer tes films. Un fichier qu'Infuse n'a pas reconnu ne s'ouvre pas ; Séance propose alors VLC.")
                } icon: { Image(systemName: "1.circle.fill").foregroundStyle(Theme.accentClair) }
                Label {
                    Text("**VLC** lit directement le fichier sur le NAS, avec l'adresse et le mot de passe enregistrés dans Réglages › NAS. Rien à préparer dans VLC.")
                } icon: { Image(systemName: "2.circle.fill").foregroundStyle(Theme.accentClair) }
                Label {
                    Text("Pour lire, VLC reçoit l'adresse de la vidéo **avec** le nom et le mot de passe du NAS. Le plus sûr : un compte du NAS en lecture seule, réservé à Séance, plutôt que ton compte d'administration.")
                } icon: { Image(systemName: "lock.shield.fill").foregroundStyle(.green) }
            }
            .font(.subheadline)
            #endif
        }
        .pageReglages("Lecture")
    }
}
