import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

enum ReglageTV: Hashable {
    case cle, plateformes, tele, nas, lecture, gouts, aPropos
}

/// Les Réglages de la TV, sur le modèle de l'iPhone (piste B, EF-169) : en tête, l'état — ce qui est en ordre en vert,
/// ce qui reste à régler en orange, chaque ligne s'ouvrant sur son réglage — puis en tuiles ce que l'état ne couvre
/// pas. Tout se modifie à la télécommande ; le plus simple reste de tout recevoir de l'iPhone.
struct ReglagesTV: View {
    @Environment(EtatTV.self) private var etat
    @Query(filter: #Predicate<Abonnement> { $0.actif }, sort: \Abonnement.nom) private var abonnements: [Abonnement]
    @Query(filter: #Predicate<Chaine> { $0.active }) private var chaines: [Chaine]
    @Query private var interets: [Interet]
    @State private var configuration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                etatDeSeance
                rubrique("Toi") {
                    tuile(.gouts, "Tes goûts", "heart.fill", interets.isEmpty ? "Genres à choisir" : interets.map(\.libelle).sorted().prefix(3).joined(separator: ", "))
                }
                rubrique("Cet appareil") {
                    Button { configuration = true } label: {
                        TuileTV(titre: "Configurer depuis mon iPhone", symbole: "iphone.and.arrow.forward", valeur: "Un code ici, et tout arrive : clé, NAS, listes")
                    }
                    .buttonStyle(.card)
                }
                rubrique("L'app") {
                    tuile(.aPropos, "À propos", "info.circle.fill", "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                }
            }
            .padding(.horizontal, MargesTV.bord)
            .padding(.vertical, 40)
        }
        .navigationDestination(for: ReglageTV.self) { PageReglageTV(reglage: $0) }
        .fullScreenCover(isPresented: $configuration) { ConfigurationTV() }
    }

    private var etatDeSeance: some View {
        let manques = [etat.tmdb == nil, abonnements.isEmpty, chaines.isEmpty, !etat.nasPret].filter { $0 }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) {
                Image(systemName: manques == 0 ? "checkmark.seal.fill" : "wrench.adjustable.fill").font(.system(size: 44))
                    .foregroundStyle(manques == 0 ? AnyShapeStyle(Color.green) : AnyShapeStyle(Theme.accentClair))
                VStack(alignment: .leading, spacing: 2) {
                    Text(manques == 0 ? "Séance est prête sur cette TV" : manques > 1 ? "\(manques) réglages à compléter" : "1 réglage à compléter")
                        .font(.system(size: 36, weight: .bold))
                    Text("Choisis une ligne pour l'ouvrir ; les orange restent à régler.").font(.system(size: 24)).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 10)
            ligne(.cle, "TMDB", etat.tmdb != nil ? "Fiches, affiches et plateformes" : "Les fiches et les affiches en viennent", etat.tmdb != nil)
            ligne(.plateformes, "Plateformes", abonnements.isEmpty ? "Pour savoir ce que tu peux regarder" : abonnements.map(\.nom).joined(separator: ", "), !abonnements.isEmpty)
            ligne(.tele, "Télévision", chaines.isEmpty ? "Choisis tes chaînes" : "\(chaines.count) chaînes · \(etat.derniereLectureTele.map { "guide lu \($0.formatted(.relative(presentation: .named)))" } ?? "guide jamais lu")", !chaines.isEmpty)
            ligne(.nas, "NAS", etat.nasPret ? "\(etat.nas.hote) · partage « \(etat.nas.partage) »" : "Tes films déjà téléchargés", etat.nasPret)
            ligne(.lecture, "Lecture", "Tes vidéos du NAS s'ouvrent dans \(etat.lecteur.nom)", true)
        }
        .padding(30)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .focusSection()
    }

    private func ligne(_ reglage: ReglageTV, _ titre: String, _ detail: String, _ enOrdre: Bool) -> some View {
        NavigationLink(value: reglage) {
            HStack(spacing: 20) {
                Image(systemName: enOrdre ? "checkmark.circle.fill" : "exclamationmark.circle.fill").font(.system(size: 32))
                    .foregroundStyle(enOrdre ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre).font(.system(size: 30, weight: .semibold))
                    Text(detail).font(.system(size: 23)).opacity(0.7).lineLimit(1)
                }
                Spacer()
                Text(enOrdre ? "›" : "À régler").font(.system(size: enOrdre ? 36 : 24, weight: .bold)).foregroundStyle(enOrdre ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.orange))
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        }
        .buttonStyle(LigneTV())
    }

    private func rubrique(_ titre: String, @ViewBuilder _ tuiles: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(titre).font(.system(size: 38, weight: .bold))
            HStack(spacing: 40) { tuiles() }.padding(.vertical, 20)
        }
        .focusSection()
    }

    private func tuile(_ reglage: ReglageTV, _ titre: String, _ symbole: String, _ valeur: String) -> some View {
        NavigationLink(value: reglage) { TuileTV(titre: titre, symbole: symbole, valeur: valeur) }.buttonStyle(.card)
    }
}

/// Une tuile de réglage : le symbole dans l'orange de Séance, le titre, l'état courant.
struct TuileTV: View {
    let titre: String
    let symbole: String
    let valeur: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbole).font(.system(size: 40, weight: .semibold)).foregroundStyle(Theme.accentClair)
            Text(titre).font(.system(size: 28, weight: .semibold)).lineLimit(2)
            Text(valeur).font(.system(size: 22)).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
        }
        .frame(width: 420, alignment: .leading)
        .padding(28)
        .background(Theme.surface)
    }
}

/// Une ligne qui se choisit : elle s'éclaire quand elle a le focus.
struct LigneTV: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Corps(configuration: configuration) }

    private struct Corps: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var aLeFocus

        var body: some View {
            configuration.label
                .foregroundStyle(aLeFocus ? .black : .white)
                .background(aLeFocus ? AnyShapeStyle(.white) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .scaleEffect(aLeFocus ? 1.02 : 1)
                .animation(.easeOut(duration: 0.15), value: aLeFocus)
        }
    }
}

// MARK: - Les pages

struct PageReglageTV: View {
    let reglage: ReglageTV

    var body: some View {
        switch reglage {
        case .cle: PageCleTV()
        case .plateformes: PagePlateformesTV()
        case .tele: PageChainesTV()
        case .nas: PageNASTV()
        case .lecture: PageLectureTV()
        case .gouts: PageGoutsTV()
        case .aPropos: PageAProposTV()
        }
    }
}

private struct PageCleTV: View {
    @Environment(EtatTV.self) private var etat
    @State private var cle = ""
    @State private var message: String?
    @State private var verification = false

    var body: some View {
        Form {
            Section {
                SecureField("Clé d'API ou jeton de lecture TMDB", text: $cle)
                Button(verification ? "Vérification…" : "Enregistrer et tester") {
                    verification = true
                    Task {
                        let erreur = await etat.enregistrerCleTMDB(cle)
                        verification = false
                        message = erreur ?? "Clé acceptée par TMDB et enregistrée."
                        if erreur == nil { cle = "" }
                    }
                }
                .disabled(cle.isEmpty || verification)
                if let message { Text(message).foregroundStyle(.secondary) }
            } header: {
                Text(etat.tmdb != nil ? "Clé TMDB — enregistrée" : "Clé TMDB")
            } footer: {
                Text("La même que sur ton iPhone ; elle reste dans le trousseau de cette Apple TV. Plus simple : Réglages › « Configurer depuis mon iPhone ».")
            }
        }
        .navigationTitle("TMDB")
    }
}

/// Les plateformes de streaming proposées en Suisse : on coche ses abonnements (EF-149).
private struct PagePlateformesTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var abonnements: [Abonnement]
    @State private var catalogue: [FournisseurCatalogue] = []

    var body: some View {
        Form {
            Section {
                if catalogue.isEmpty { Text(etat.tmdb == nil ? "Il faut d'abord la clé TMDB." : "Lecture du catalogue…").foregroundStyle(.secondary) }
                ForEach(catalogue) { plateforme in
                    Toggle(plateforme.nom, isOn: Binding { abonnements.contains { $0.providerID == plateforme.id && $0.actif } } set: { coche in
                        if let existant = abonnements.first(where: { $0.providerID == plateforme.id }) {
                            existant.actif = coche
                        } else if coche {
                            contexte.insert(Abonnement(providerID: plateforme.id, nom: plateforme.nom, cheminLogo: plateforme.cheminLogo))
                        }
                        contexte.sauver()
                    })
                }
            } header: {
                Text("Tes abonnements, en Suisse")
            } footer: {
                Text("Séance ne montre « dans tes abonnements » que les plateformes cochées. Disponibilités fournies par JustWatch, via TMDB.")
            }
        }
        .navigationTitle("Plateformes")
        .task {
            let lues = (try? await etat.tmdb?.catalogueFournisseurs(.film)) ?? []
            catalogue = lues.sorted { ($0.priorites["CH"] ?? 999, $0.nom) < ($1.priorites["CH"] ?? 999, $1.nom) }.prefix(40).map { $0 }
        }
    }
}

private struct PageChainesTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \Chaine.nom) private var chaines: [Chaine]

    var body: some View {
        Form {
            Section {
                ForEach(chaines) { chaine in
                    Toggle(chaine.nom.isEmpty ? chaine.identifiantGuide : chaine.nom, isOn: Binding { chaine.active } set: { chaine.active = $0; contexte.sauver() })
                }
            } header: {
                Text("Tes chaînes")
            }
            Section {
                Button(etat.teleEnCours ? "Lecture du guide…" : "Relire le programme maintenant") { Task { await etat.actualiserTele(contexte: contexte, force: true) } }
                    .disabled(etat.teleEnCours)
            } footer: {
                Text(etat.derniereLectureTele.map { "Guide lu \($0.formatted(.relative(presentation: .named))). Séance le relit deux fois par jour." } ?? "Le guide n'a pas encore été lu sur cette TV.")
            }
        }
        .navigationTitle("Télévision")
        .task { _ = try? ServiceProgrammesTV.preparerChaines(contexte) }
    }
}

private struct PageNASTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var hote = ""
    @State private var partage = ""
    @State private var dossiers = ""
    @State private var utilisateur = ""
    @State private var motDePasse = ""
    @State private var message: String?
    @State private var test = false

    var body: some View {
        Form {
            Section {
                TextField("Adresse du NAS (192.168.1.220)", text: $hote)
                TextField("Partage (Films)", text: $partage)
                TextField("Dossiers, séparés par des virgules", text: $dossiers)
                TextField("Compte", text: $utilisateur)
                SecureField(etat.motDePasseNAS ? "Mot de passe (déjà enregistré)" : "Mot de passe", text: $motDePasse)
                Button(test ? "Connexion au NAS…" : "Enregistrer, tester et lire le NAS") { enregistrer() }
                    .disabled(test || hote.isEmpty || partage.isEmpty || utilisateur.isEmpty)
                if let message { Text(message).foregroundStyle(.secondary) }
                if etat.analyseEnCours { Label("Lecture de la bibliothèque…", systemImage: "arrow.triangle.2.circlepath") }
                if let rapport = etat.rapport {
                    Text("\(rapport.filmsReconnus) films et \(rapport.seriesReconnues) séries reconnus, sur \(rapport.videosLues) vidéos lues.").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Pour lire avec Infuse, ajoute aussi ce partage dans Infuse sur cette Apple TV : Séance lui demande d'ouvrir le titre dans sa bibliothèque.")
            }
        }
        .navigationTitle("NAS")
        .onAppear {
            hote = etat.nas.hote; partage = etat.nas.partage
            dossiers = etat.nas.dossiers.joined(separator: ", "); utilisateur = etat.nas.utilisateur
        }
    }

    private func enregistrer() {
        let liste = dossiers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        etat.enregistrerNAS(ReglagesNAS(hote: hote.trimmingCharacters(in: .whitespaces), partage: partage.trimmingCharacters(in: .whitespaces),
                                        dossiers: liste, utilisateur: utilisateur.trimmingCharacters(in: .whitespaces)), motDePasse: motDePasse)
        motDePasse = ""
        test = true
        Task {
            switch await etat.testerNAS() {
            case .reussi(let comptes):
                message = "Connexion réussie : \(comptes.values.reduce(0, +)) vidéos dans \(comptes.count) dossier\(comptes.count > 1 ? "s" : "")."
                test = false
                await etat.analyserNAS(contexte: contexte)
            case .echec(let texte):
                message = texte
                test = false
            }
        }
    }
}

/// Un seul lecteur : « Lire » n'ouvre que celui-ci, partout dans l'app.
private struct PageLectureTV: View {
    @Environment(EtatTV.self) private var etat

    var body: some View {
        Form {
            Section {
                ForEach(LecteurVideo.allCases) { lecteur in
                    Button { etat.choisir(lecteur) } label: {
                        HStack {
                            Text(lecteur.nom)
                            Spacer()
                            if etat.lecteur == lecteur { Image(systemName: "checkmark").foregroundStyle(Theme.accentClair) }
                        }
                    }
                }
            } header: {
                Text("L'app qui lit tes vidéos")
            } footer: {
                Text("Infuse ouvre le titre dans sa bibliothèque : le partage du NAS doit y être ajouté, sur cette Apple TV. VLC lit le fichier directement sur le NAS, avec ton compte et ton mot de passe.")
            }
        }
        .navigationTitle("Lecture")
    }
}

private struct PageGoutsTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var interets: [Interet]
    @State private var genres: [Genre] = []

    var body: some View {
        Form {
            Section {
                if genres.isEmpty { Text(etat.tmdb == nil ? "Il faut d'abord la clé TMDB." : "Lecture des genres…").foregroundStyle(.secondary) }
                ForEach(genres) { genre in
                    Toggle(genre.nom, isOn: Binding { interets.contains { $0.genreID == genre.id } } set: { coche in
                        if coche {
                            contexte.insert(Interet(libelle: genre.nom, genreID: genre.id))
                        } else {
                            interets.filter { $0.genreID == genre.id }.forEach(contexte.delete)
                        }
                        contexte.sauver()
                    })
                }
            } header: {
                Text("Les genres que tu aimes")
            } footer: {
                Text("Ils orientent les idées du soir, ici comme sur ton iPhone.")
            }
        }
        .navigationTitle("Tes goûts")
        .task {
            let films = (try? await etat.tmdb?.genres(.film)) ?? []
            genres = films.filter { ![99, 10770].contains($0.id) }.sorted { $0.nom < $1.nom }
        }
    }
}

private struct PageAProposTV: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                Text("Avec un compte Apple gratuit, l'app cesse de s'ouvrir au bout de sept jours : relance l'installation depuis le Mac, tes réglages restent.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Ce produit utilise l'API TMDB mais n'est ni approuvé ni certifié par TMDB. Disponibilités en Suisse fournies par JustWatch, via TMDB. Programme TV : XML TV Fr.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("À propos")
    }
}
