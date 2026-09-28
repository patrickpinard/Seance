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
    @State private var aIdentifier: DemandeIdentification?
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
                    if !rapport.filmsNonReconnus.isEmpty {
                        DisclosureGroup("Films non reconnus (\(rapport.filmsNonReconnus.count))", isExpanded: $nonReconnusVisibles) {
                            // 8.4 : chacun s'identifie parmi ce que TMDB propose, et passe alors dans le programme.
                            ForEach(rapport.filmsNonReconnus) { film in
                                Button { aIdentifier = .guide(titre: film.titre, annee: film.annee) } label: {
                                    LabeledContent {
                                        Text("Identifier").foregroundStyle(Theme.accent)
                                    } label: {
                                        Text(film.annee.map { "\(film.titre) (\($0))" } ?? film.titre).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                IdentifiesALaMain(guide: true, demande: $aIdentifier)
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
                Text("Le guide est relu toutes les 12 heures et dès que tu changes de chaînes. Un film n'apparaît que s'il est reconnu dans TMDB sans hésitation ; sinon, identifie-le parmi les films non reconnus.")
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
        .pageReglages("TV")
        .sheet(item: $aIdentifier) { demande in
            FeuilleIdentification(demande: demande)
        }
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

/// Le lecteur des films du NAS : Séance même par VLCKit (7.0, par défaut) ou Infuse, et ce que chacun demande.
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
                choix(titre: "Séance (VLCKit)", detail: "Par défaut · intégré, rien à installer", actif: etat.nas.dansSeance) {
                    etat.nas.lireDansSeance(true)
                }
                let infuse = LecteurVideo.infuse
                let installee = UIApplication.shared.canOpenURL(URL(string: "\(infuse.schema)://")!)
                choix(titre: infuse.nom, detail: installee ? "Installée" : "Pas installée sur cet appareil",
                      alerte: !installee, actif: !etat.nas.dansSeance) {
                    etat.nas.choisir(infuse)
                }
                if !installee {
                    Button("Installer Infuse depuis l'App Store") { openURL(infuse.appStore) }
                        .font(.subheadline)
                }
            } header: {
                Text("Lire les films du NAS avec")
            } footer: {
                Text("Toucher ▶︎ sur un film ou un épisode « Sur ton NAS » le lance avec ce lecteur.")
            }

            Section("Ce que chaque lecteur demande") {
                Label {
                    Text("**VLCKit** est le moteur de VLC, intégré à Séance : il lit tous les formats (MKV, AVI, WMV, DV…) directement sur le NAS, avec l'adresse et le mot de passe de Réglages › NAS. La touche de fermeture ramène là où tu étais.")
                } icon: { Image(systemName: "1.circle.fill").foregroundStyle(Theme.accentClair) }
                Label {
                    Text("**Infuse** ouvre le titre dans sa propre bibliothèque et démarre la lecture : ajoute d'abord le partage de ton NAS dans Infuse, et laisse-le indexer tes films. À la fin, c'est Infuse qui reste à l'écran.")
                } icon: { Image(systemName: "2.circle.fill").foregroundStyle(Theme.accentClair) }
                Label {
                    Text("Le mot de passe du NAS reste dans le trousseau de cet appareil. Le plus sûr : un compte du NAS en lecture seule, réservé à Séance.")
                } icon: { Image(systemName: "lock.shield.fill").foregroundStyle(.green) }
            }
            .font(.subheadline)
            #endif
        }
        .pageReglages("Lecture")
    }

    private func choix(titre: String, detail: String, alerte: Bool = false, actif: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: actif ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(actif ? AnyShapeStyle(Theme.accentClair) : AnyShapeStyle(.tertiary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre).font(.headline).foregroundStyle(Color.primary)
                    Text(detail).font(.caption)
                        .foregroundStyle(alerte ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(titre), \(detail)")
        .accessibilityAddTraits(actif ? .isSelected : [])
    }
}

/// Langue et sous-titres (8.2.15) : ce que le lecteur de Séance choisit tout seul à chaque film, pour la personne qui
/// regarde. Dans les Préférences — c'est un goût à toi —, plus dans Réglages › Lecture.
struct ReglagesLangueView: View {
    @State private var pistes = PreferencesPistes.lire(profil: ProfilsFamille().actif.id)

    private func enregistrer() {
        pistes.enregistrer(profil: ProfilsFamille().actif.id)
    }

    var body: some View {
        Form {
            // 8.1 : ce que le lecteur de Séance choisit tout seul à chaque film, pour la personne qui regarde.
            Section {
                Picker("Langue", selection: Binding { pistes.audio } set: { pistes.audio = $0; enregistrer() }) {
                    ForEach(PreferencesPistes.langues, id: \.code) { Text($0.nom).tag($0.code) }
                    Text("Version originale").tag("")
                }
                Picker("Sous-titres", selection: Binding { pistes.sousTitres } set: { pistes.sousTitres = $0; enregistrer() }) {
                    ForEach(PreferencesPistes.SousTitres.allCases, id: \.self) { Text($0.nom).tag($0) }
                }
                if pistes.sousTitres != .jamais {
                    Picker("Langue des sous-titres", selection: Binding { pistes.langueSousTitres } set: { pistes.langueSousTitres = $0; enregistrer() }) {
                        ForEach(PreferencesPistes.langues, id: \.code) { Text($0.nom).tag($0.code) }
                    }
                }
            } header: {
                Text("Langue et sous-titres")
            } footer: {
                Text("Choisis à chaque film par le lecteur de Séance, quand le fichier les propose\(ProfilsFamille().aPlusieursProfils ? ", pour \(QuiRegardeActuel.nom ?? "toi")" : "").")
            }

        }
        .pageReglages("Langue et sous-titres")
    }
}
