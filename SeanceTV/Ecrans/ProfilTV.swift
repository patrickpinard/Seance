import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Le Profil sur la TV (EF-132) : tes dernières notes en affiches, tes acteurs en portraits, tes goûts, et tes chiffres
/// en bas de page, sans les mettre en avant.
struct ProfilTV: View {
    @Query(sort: \Suivi.ajouteLe, order: .reverse) private var suivis: [Suivi]
    @Query(sort: \ActeurSuivi.suiviLe, order: .reverse) private var acteurs: [ActeurSuivi]
    @Query(sort: \Interet.libelle) private var interets: [Interet]
    @Query private var visionnages: [Visionnage]
    /// 👍 Tes « J'aime », le plus récent d'abord.
    @Query(sort: \TitreAime.aimeLe, order: .reverse) private var aimes: [TitreAime]

    @Environment(EtatTV.self) private var etat
    /// Tes réalisateurs (8.2.15), comme sur l'iPhone : lus une fois sur TMDB, gardés sur la TV.
    @State private var reserve = ReserveRealisateurs(donnees: UserDefaults.standard.data(forKey: ReserveRealisateurs.cle))
    @State private var quiRegarde = false
    /// La personne qui regarde : son prénom s'écrit ici (8.2), à la place de « Moi » sur toute la TV.
    @State private var profilActif = ConteneurTV.famille.actif

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 44) {
                // Maquette 8.0, n° 17 : qui regarde, puis ce qui guide les suggestions.
                HStack(spacing: 28) {
                    Text(String(prenom.prefix(1)).uppercased())
                        .font(.system(size: 64, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(width: 130, height: 130)
                        .background(Theme.degradeAccent, in: Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        Text(prenom).font(.system(size: 52, weight: .heavy))
                        Text("Ce qui guide tes suggestions").font(.system(size: 26)).foregroundStyle(Theme.texte2)
                    }
                }
                .padding(.horizontal, MargesTV.bord)
                reglagesDeToi
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Tes goûts").font(.system(size: 38, weight: .bold))
                        Spacer()
                        NavigationLink(value: GoutsTVDemande()) { Text(interets.isEmpty ? "Choisir" : "Modifier") }
                            .buttonStyle(LienTV())
                    }
                    if interets.isEmpty {
                        Text("Choisis les genres que tu aimes : ils orientent tes suggestions.").font(.system(size: 26)).foregroundStyle(Theme.texte2)
                    } else {
                        FluxTV(espacement: 14) {
                            ForEach(interets) { interet in
                                Text(interet.libelle).font(.system(size: 26, weight: .semibold))
                                    .padding(.horizontal, 24).frame(height: 52)
                                    .background(Color.white.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }
                .padding(.horizontal, MargesTV.bord)
                .focusSection()
                if !notes.isEmpty {
                    EtagereTV(titre: "Tes dernières notes") {
                        ForEach(notes) { suivi in
                            NavigationLink(value: suivi.reference) {
                                CarteLargeTV(surtitre: "★ \(suivi.note ?? 0)/10 · ta note", titre: suivi.titre,
                                             detail: suivi.type == .film ? "Film" : "Série",
                                             cheminImage: suivi.cheminAffiche, largeur: CarteLargeTV.largeurGrille)
                            }
                            .buttonStyle(.card)
                            .menuCarteTV(suivi.reference, titre: suivi.titre, cheminAffiche: suivi.cheminAffiche)
                        }
                    }
                }
                if !aimes.isEmpty {
                    EtagereTV(titre: "Tu aimes") {
                        ForEach(aimes.prefix(30), id: \.reference) { aime in
                            NavigationLink(value: aime.reference) {
                                CarteLargeTV(surtitre: nil, titre: aime.titre, detail: aime.reference.type == .film ? "Film" : "Série",
                                             cheminImage: aime.cheminAffiche, largeur: CarteLargeTV.largeurGrille, reference: aime.reference)
                            }
                            .buttonStyle(.card)
                            .menuCarteTV(aime.reference, titre: aime.titre, cheminAffiche: aime.cheminAffiche)
                        }
                    }
                }
                if !acteurs.isEmpty {
                    EtagereTV(titre: "Tes acteurs") {
                        ForEach(acteurs, id: \.personneID) { acteur in
                            NavigationLink(value: PersonneTVRef(id: acteur.personneID, nom: acteur.nom)) {
                                AfficheTV(titre: acteur.nom, sousTitre: nil, cheminAffiche: acteur.cheminPortrait)
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
                let realisateurs = reserve.classement(filmsVus: Set(visionnages.filter { $0.type == .film }.map(\.tmdbID)))
                if !realisateurs.isEmpty {
                    EtagereTV(titre: "Tes réalisateurs") {
                        ForEach(realisateurs, id: \.realisateur.id) { classe in
                            NavigationLink(value: PersonneTVRef(id: classe.realisateur.id, nom: classe.realisateur.nom)) {
                                AfficheTV(titre: classe.realisateur.nom, sousTitre: "\(classe.films.count) films",
                                          cheminAffiche: classe.realisateur.cheminPortrait)
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
                // Tes chiffres ont leur page (maquette n° 18) : une ligne qui s'ouvre, que la télécommande atteint.
                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink(value: StatistiquesTVDemande()) {
                        LigneFiltreTVStat(titre: "Statistiques", valeur: "\(filmsVus) films · \(episodesVus) épisodes · \(heures) h")
                    }
                    .buttonStyle(LigneTV())
                }
                .frame(maxWidth: 900)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, MargesTV.bord)
                .focusSection()
            }
            .padding(.vertical, 40)
        }
        .task(id: visionnages.count) { await chargerRealisateurs() }
        .fullScreenCover(isPresented: $quiRegarde) {
            QuiRegardeTV { profil in
                quiRegarde = false
                ConteneurTV.changerDeProfil(vers: profil)
            }
        }
    }

    /// « Toi » (8.2.17) : les mêmes lignes que les Préférences de l'iPhone et de l'iPad — qui regarde, langue et
    /// sous-titres, alertes, e-mail de la semaine —, réglées pour la personne en cours.
    /// Combien de propositions défilent en tête de l'accueil (8.7) ; la même clé que sur l'iPhone, synchronisée.
    @AppStorage(NombrePropositions.cle) private var nombrePropositions = NombrePropositions.parDefaut

    private var reglagesDeToi: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TOI").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.texte2).padding(.leading, 8)
            VStack(spacing: 2) {
                ChampTV(titre: "Prénom", invite: "Ton prénom", texte: Binding { profilActif.prenom } set: { renommer($0) })
                Button { quiRegarde = true } label: {
                    LigneTVReglage.Contenu(titre: "Changer de personne", detail: prenom, symbole: "person.2.fill")
                }
                .buttonStyle(LigneTV())
                NavigationLink(value: PreferenceTV.langue) {
                    LigneTVReglage.Contenu(titre: "Langue et sous-titres", detail: libelleLangue, symbole: "captions.bubble.fill")
                }
                .buttonStyle(LigneTV())
                NavigationLink(value: PreferenceTV.alertes) {
                    LigneTVReglage.Contenu(titre: "Alertes", detail: libelleAlertes, symbole: "bell.fill")
                }
                .buttonStyle(LigneTV())
                NavigationLink(value: PreferenceTV.lettre) {
                    LigneTVReglage.Contenu(titre: "E-mail de la semaine", detail: libelleLettre, symbole: "envelope.fill")
                }
                .buttonStyle(LigneTV())
                NavigationLink(value: PreferenceTV.alertesAVenir) {
                    LigneTVReglage.Contenu(titre: "Tes alertes à venir", symbole: "bell.badge.waveform")
                }
                .buttonStyle(LigneTV())
                // 8.7, comme la ligne « Accueil » de l'iPhone : combien de propositions défilent en tête de l'accueil ; un
                // clic passe au choix suivant (1, 3, 5, 8).
                Button {
                    let choix = NombrePropositions.choix
                    nombrePropositions = choix[((choix.firstIndex(of: nombrePropositions) ?? 2) + 1) % choix.count]
                    UserDefaults.standard.set(true, forKey: NombrePropositions.cleChoisiIci)
                } label: {
                    LigneTVReglage.Contenu(titre: "Accueil",
                                           detail: nombrePropositions > 1 ? "\(nombrePropositions) propositions" : "1 proposition",
                                           symbole: "house.fill")
                }
                .buttonStyle(LigneTV())
            }
            .padding(8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.trait, lineWidth: 1))
        }
        .frame(maxWidth: 1100)
        .padding(.horizontal, MargesTV.bord)
        .focusSection()
    }

    private var libelleLangue: String {
        let pistes = PreferencesPistes.lire(profil: ConteneurTV.famille.actif.id)
        let langue = pistes.audio.isEmpty ? "VO" : (PreferencesPistes.langues.first { $0.code == pistes.audio }?.nom ?? pistes.audio)
        return "\(langue) · \(pistes.sousTitres.nom)"
    }

    private var libelleAlertes: String {
        let reglages = ReglagesAlertes.lire(profil: ConteneurTV.famille.actif.id) ?? ReglagesAlertes()
        let types = ReglagesAlertes.typesProposes.filter { reglages.typesActifs.contains($0) }.count
        return types == 0 ? "Aucune" : String(format: "%d:%02d", reglages.heure, reglages.minute)
    }

    private var libelleLettre: String {
        guard let reglages = ReglagesLettre.lire(profil: ConteneurTV.famille.actif.id), reglages.actif else { return "Désactivé" }
        return MessageMail.adresses(reglages.destinataires).isEmpty ? "À terminer" : "Activé"
    }

    /// Les réalisateurs des films vus qu'on ne connaît pas encore, trente à la fois.
    private func chargerRealisateurs() async {
        guard let tmdb = etat.tmdb else { return }
        let films = Array(Set(visionnages.filter { $0.type == .film }.map(\.tmdbID)))
        let manquants = Array(reserve.manquants(films).prefix(30))
        guard !manquants.isEmpty else { return }
        var lus: [Int: [ReserveRealisateurs.Realisateur]] = [:]
        for id in manquants {
            guard !Task.isCancelled else { return }
            if let fiche = try? await tmdb.film(id, complements: [.casting]) {
                lus[id] = (fiche.casting?.realisateurs ?? []).map {
                    ReserveRealisateurs.Realisateur(id: $0.id, nom: $0.nom, cheminPortrait: $0.cheminPortrait)
                }
            }
        }
        var nouvelle = reserve
        nouvelle.parFilm.merge(lus) { _, neuf in neuf }
        reserve = nouvelle
        UserDefaults.standard.set(nouvelle.encoder(), forKey: ReserveRealisateurs.cle)
    }

    private var prenom: String {
        let nom = QuiRegardeTV.nom(profilActif)
        return nom.isEmpty ? "Toi" : nom
    }

    /// Le prénom de la personne en cours, écrit dans le registre de la famille de la TV.
    private func renommer(_ texte: String) {
        var profil = profilActif
        profil.prenom = String(texte.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        ConteneurTV.famille.modifier(profil)
        profilActif = profil
    }

    private var notes: [Suivi] { suivis.filter { $0.note != nil }.prefix(20).map { $0 } }
    private var filmsVus: Int { Set(visionnages.filter { $0.type == .film }.map(\.tmdbID)).count }
    private var episodesVus: Int { visionnages.filter { $0.type == .serie && $0.episode != nil }.count }
    private var heures: Int { visionnages.reduce(0) { $0 + $1.dureeMinutes } / 60 }

}

/// Préférences › « Modifier mes goûts » (8.0) : la même page que Réglages › Tes goûts.
struct GoutsTVDemande: Hashable {}

/// Une ligne qui s'ouvre, avec sa valeur à droite (Préférences › Statistiques).
private struct LigneFiltreTVStat: View {
    let titre: String
    let valeur: String
    @Environment(\.isFocused) private var aLeFocus

    var body: some View {
        HStack {
            Image(systemName: "chart.bar").font(.system(size: 28, weight: .semibold)).frame(width: 44)
            Text(titre).font(.system(size: 30, weight: .semibold))
            Spacer()
            Text(valeur).font(.system(size: 24)).opacity(0.7)
            Image(systemName: "chevron.right").font(.system(size: 24, weight: .bold)).opacity(0.45)
        }
        .foregroundStyle(aLeFocus ? .black : .white)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}

/// Un lien orange, sans cadre (maquette 8.0 : « Modifier », « Programme complet », « Ajouts ») ; blanc au focus.
struct LienTV: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Corps(configuration: configuration) }

    private struct Corps: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var aLeFocus

        var body: some View {
            configuration.label
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(aLeFocus ? Color.black : Theme.accentClair)
                .padding(.horizontal, 20)
                .frame(height: 52)
                .background(aLeFocus ? Color.white : Color.clear, in: Capsule())
                .scaleEffect(aLeFocus ? 1.08 : 1)
                .animation(.easeOut(duration: 0.15), value: aLeFocus)
        }
    }
}

struct StatistiquesTVDemande: Hashable {}

/// Statistiques (maquette 8.0, n° 18) : l'année en quatre tuiles, puis tes genres en barres blanches ; l'orange reste
/// pour ce qui se touche.
struct StatistiquesTV: View {
    @Query private var visionnages: [Visionnage]
    @Query private var suivis: [Suivi]

    private var annee: Int { Calendar.current.component(.year, from: .now) }
    private var deLAnnee: [Visionnage] { visionnages.filter { Calendar.current.component(.year, from: $0.vuLe) == annee } }

    var body: some View {
        let liste = deLAnnee
        let films = liste.filter { $0.type == .film }.reduce(0) { $0 + $1.dureeMinutes } / 60
        let series = liste.filter { $0.type == .serie }.reduce(0) { $0 + $1.dureeMinutes } / 60
        let titres = Set(liste.map { "\($0.typeBrut)\($0.tmdbID)" }).count
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                Text("Statistiques · \(String(annee))").font(.system(size: 58, weight: .heavy))
                HStack(spacing: 28) {
                    tuile("\(films + series) h", "regardées")
                    tuile("\(titres)", titres > 1 ? "titres vus" : "titre vu")
                    tuile("\(films) h", "de films")
                    tuile("\(series) h", "de séries")
                }
                .focusSection()
                let genres = genresDeLAnnee(liste)
                if !genres.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Tes genres").font(.system(size: 38, weight: .bold))
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(genres, id: \.nom) { genre in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(genre.nom).font(.system(size: 26, weight: .semibold))
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(.white.opacity(0.14))
                                            Capsule().fill(.white).frame(width: geo.size.width * genre.part)
                                        }
                                    }
                                    .frame(height: 10)
                                }
                            }
                        }
                        .padding(30)
                        .frame(width: 900)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        // La page n'a que du texte : un élément focalisable pour que Retour et le défilement répondent.
                        .focusable()
                    }
                }
            }
            .padding(.horizontal, MargesTV.bord)
            .padding(.vertical, 40)
        }
    }

    private func tuile(_ valeur: String, _ libelle: String) -> some View {
        Button {} label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(valeur).font(.system(size: 54, weight: .heavy))
                Text(libelle).font(.system(size: 24)).foregroundStyle(Theme.texte2)
            }
            .frame(width: 330, alignment: .leading)
            .padding(28)
            .background(Theme.surface)
        }
        .buttonStyle(.card)
        .accessibilityLabel("\(valeur) \(libelle)")
    }

    /// Les cinq genres les plus regardés de l'année, en part du plus regardé.
    private func genresDeLAnnee(_ liste: [Visionnage]) -> [(nom: String, part: Double)] {
        var minutes: [Int: Int] = [:]
        for visionnage in liste {
            let genres = suivis.first { $0.tmdbID == visionnage.tmdbID && $0.typeBrut == visionnage.typeBrut }?.genres ?? []
            for genre in genres { minutes[genre, default: 0] += max(visionnage.dureeMinutes, 1) }
        }
        let tries = minutes.sorted { $0.value > $1.value }.prefix(5)
        guard let plus = tries.first?.value, plus > 0 else { return [] }
        return tries.compactMap { id, valeur in GenresParDefaut.noms[id].map { ($0, Double(valeur) / Double(plus)) } }
    }
}
