import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI
import UIKit

/// Le bilan de l'année en cartes plein écran (EF-36, EF-37) : chacune se partage en image.
struct BilanAnneeView: View {
    let annee: Int

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var fermer
    @State private var contenu: ContenuBilan?
    @State private var page = 0
    @State private var images: [Int: UIImage] = [:]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let contenu {
                let cartes = contenu.cartes
                TabView(selection: $page) {
                    ForEach(Array(cartes.enumerated()), id: \.offset) { index, carte in
                        CarteBilanVue(carte: carte, contenu: contenu)
                            .aspectRatio(9 / 16, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 44)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .task(id: contenu.annee) { rendre(cartes, contenu: contenu) }
            } else {
                ProgressView("Préparation de ton bilan…")
                    .tint(Theme.accent)
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                BoutonIcone(symbole: "xmark", libelle: "Fermer", taille: 40) { fermer() }
                Spacer()
                if let image = images[page] {
                    ShareLink(item: Image(uiImage: image),
                              preview: SharePreview("Mon bilan Séance \(String(annee))", image: Image(uiImage: image))) {
                        RondIcone(symbole: "square.and.arrow.up", principal: true, taille: 40)
                    }
                    .accessibilityLabel("Partager cette carte")
                    .help("Partager cette carte en image")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .task { await preparer() }
    }

    private func preparer() async {
        let service = ServiceStatistiques(contexte: contexte)
        guard let bilan = try? service.bilan(annee: annee) else { return }
        let meilleur = try? service.meilleurFilm(annee: annee)
        let vus = (try? service.visionnages()) ?? []
        let bornes = ServiceStatistiques.bornesAnnee(annee)
        let series = Set(vus.filter { $0.reference.type == .serie && bornes.contains($0.vuLe) }.map(\.reference)).count
        let films = Set(vus.filter { $0.reference.type == .film && bornes.contains($0.vuLe) }.map(\.reference)).count

        // Les images sont chargées d'avance : le rendu en image pour le partage ne sait pas attendre le réseau.
        async let affiche = Self.telecharger(ImageTMDB.url(meilleur?.cheminAffiche, .afficheGrande))
        async let portrait = portraitActeur(bilan.acteurs.first?.cle)
        var resultat = ContenuBilan(annee: annee, bilan: bilan, meilleur: meilleur, nombreSeries: series, nombreFilmsDifferents: films,
                                    nomsGenres: etat.nomsGenres)
        resultat.affiche = await affiche
        resultat.portrait = await portrait
        contenu = resultat
    }

    private func portraitActeur(_ acteur: ActeurStat?) async -> UIImage? {
        guard let id = acteur?.id, let tmdb = etat.tmdb, let fiche = try? await tmdb.personne(id) else { return nil }
        return await Self.telecharger(ImageTMDB.url(fiche.cheminPortrait, .affiche))
    }

    private static func telecharger(_ url: URL?) async -> UIImage? {
        guard let url, let (donnees, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: donnees)
    }

    /// Chaque carte en image 1080 × 1920, prête pour une story ou un message.
    private func rendre(_ cartes: [CarteBilan], contenu: ContenuBilan) {
        for (index, carte) in cartes.enumerated() {
            let rendu = ImageRenderer(content: CarteBilanVue(carte: carte, contenu: contenu)
                .frame(width: 360, height: 640)
                .environment(\.colorScheme, .dark))
            rendu.scale = 3
            if let image = rendu.uiImage { images[index] = image }
        }
    }
}

extension ServiceStatistiques {
    static func bornesAnnee(_ annee: Int) -> ClosedRange<Date> {
        let debut = DateTMDB(annee: annee, mois: 1, jour: 1).instant(fuseau: .suisse)
        let fin = DateTMDB(annee: annee + 1, mois: 1, jour: 1).instant(fuseau: .suisse).addingTimeInterval(-1)
        return debut...fin
    }
}

/// Ce que racontent les cartes, calculé une fois.
struct ContenuBilan {
    let annee: Int
    let bilan: BilanStatistiques
    let meilleur: ServiceStatistiques.MeilleurTitre?
    let nombreSeries: Int
    let nombreFilmsDifferents: Int
    let nomsGenres: [Int: String]
    var affiche: UIImage?
    var portrait: UIImage?

    private static let anneeCourante = Calendar.current.component(.year, from: .now)

    /// Avant décembre, l'année en cours se raconte « jusqu'ici ».
    var enCours: Bool {
        annee == Self.anneeCourante && !ServiceStatistiques.bilanOuvert()
    }

    var accroche: String {
        if enCours { return "Depuis le 1er janvier, tu as passé" }
        return annee == Self.anneeCourante ? "Cette année, tu as passé" : "En \(String(annee)), tu as passé"
    }

    var titre: String {
        enCours ? "Ton année \(String(annee)) jusqu'ici" : "Ton bilan \(String(annee))"
    }

    var cartes: [CarteBilan] {
        guard bilan.minutesTotales > 0 else { return [.vide] }
        var cartes: [CarteBilan] = [.heures, .titres]
        if !bilan.acteurs.isEmpty { cartes.append(.acteur) }
        if !bilan.genres.isEmpty { cartes.append(.genres) }
        if meilleur != nil { cartes.append(.meilleurFilm) }
        if let record = bilan.recordEpisodes, record.nombreEpisodes > 1 { cartes.append(.soiree) }
        cartes.append(.resume)
        return cartes
    }
}

enum CarteBilan: Hashable {
    case vide, heures, titres, acteur, genres, meilleurFilm, soiree, resume
}

/// Une carte du bilan : même fond, même en-tête, un chiffre ou un visage au centre.
struct CarteBilanVue: View {
    let carte: CarteBilan
    let contenu: ContenuBilan

    var body: some View {
        GeometryReader { geo in
            let echelle = geo.size.width / 360
            ZStack {
                fond
                VStack(spacing: 0) {
                    HStack {
                        Label("Séance", systemImage: "film.stack.fill")
                            .font(.system(size: 15, weight: .bold))
                        Spacer()
                        Text(contenu.titre.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .foregroundStyle(Theme.accentClair)
                    Spacer(minLength: 0)
                    centre
                    Spacer(minLength: 0)
                    Text("séance · films et séries d'action")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(26)
                .foregroundStyle(.white)
            }
            .frame(width: 360, height: 640)
            .scaleEffect(echelle, anchor: .topLeading)
        }
        .aspectRatio(9 / 16, contentMode: .fit)
    }

    private var fond: some View {
        ZStack {
            Color(red: 0.05, green: 0.04, blue: 0.06)
            RadialGradient(colors: [Theme.accent.opacity(0.55), .clear], center: .init(x: 0.85, y: 0.05), startRadius: 10, endRadius: 360)
            RadialGradient(colors: [Color.teal.opacity(0.25), .clear], center: .init(x: 0.1, y: 1), startRadius: 10, endRadius: 320)
        }
    }

    @ViewBuilder
    private var centre: some View {
        let bilan = contenu.bilan
        switch carte {
        case .vide:
            grandTexte(haut: "Rien de regardé", valeur: "0 h", bas: "en \(String(contenu.annee)) pour l'instant")
        case .heures:
            VStack(spacing: 12) {
                Text(contenu.accroche).font(.system(size: 20, weight: .semibold))
                Text("\(Format.heures(bilan.minutesTotales))")
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.degradeAccent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(Format.heures(bilan.minutesTotales) > 1 ? "heures" : "heure").font(.system(size: 30, weight: .bold))
                Text(["devant des films et des séries", Format.jours(bilan.minutesTotales)].compactMap { $0 }.joined(separator: ",\n"))
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 6)
            }
            .multilineTextAlignment(.center)
        case .titres:
            VStack(spacing: 26) {
                chiffre(bilan.nombreFilms, bilan.nombreFilms > 1 ? "films regardés" : "film regardé", couleur: Theme.accent)
                chiffre(bilan.nombreEpisodes, bilan.nombreEpisodes > 1 ? "épisodes" : "épisode", couleur: .teal)
                if contenu.nombreSeries > 0 {
                    Text("dans \(Format.pluriel(contenu.nombreSeries, "série"))")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        case .acteur:
            if let premier = bilan.acteurs.first {
                VStack(spacing: 14) {
                    Text("Ton acteur de l'année").font(.system(size: 20, weight: .semibold))
                    portrait
                    Text(premier.cle.nom)
                        .font(.system(size: 34, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                    Text("dans \(Format.pluriel(premier.nombreTitres, "de tes titres", "de tes titres"))")
                        .font(.system(size: 17)).foregroundStyle(.white.opacity(0.75))
                    let suivants = bilan.acteurs.dropFirst().prefix(2).map(\.cle.nom)
                    if !suivants.isEmpty {
                        Text("Puis " + suivants.joined(separator: " et "))
                            .font(.system(size: 15)).foregroundStyle(.white.opacity(0.55))
                            .padding(.top, 8)
                    }
                }
            }
        case .genres:
            VStack(alignment: .leading, spacing: 18) {
                Text("Tes genres favoris").font(.system(size: 24, weight: .bold))
                let maximum = max(1, bilan.genres.first?.nombreTitres ?? 1)
                ForEach(Array(bilan.genres.prefix(4).enumerated()), id: \.element.cle) { rang, genre in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(rang + 1)").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Theme.accent)
                            Text(contenu.nomsGenres[genre.cle] ?? "Genre").font(.system(size: 22, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                            Spacer()
                            Text(Format.pluriel(genre.nombreTitres, "titre")).font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                        }
                        Capsule().fill(Theme.degradeAccent)
                            .frame(width: 300 * CGFloat(genre.nombreTitres) / CGFloat(maximum), height: 8)
                    }
                }
            }
        case .meilleurFilm:
            if let meilleur = contenu.meilleur {
                VStack(spacing: 16) {
                    Text("Ton film préféré").font(.system(size: 20, weight: .semibold))
                    Group {
                        if let affiche = contenu.affiche {
                            Image(uiImage: affiche).resizable().scaledToFill()
                        } else {
                            Rectangle().fill(.white.opacity(0.1)).overlay(Image(systemName: "film").font(.largeTitle))
                        }
                    }
                    .frame(width: 190, height: 285)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Theme.accent.opacity(0.5), radius: 30)
                    Text(meilleur.titre)
                        .font(.system(size: 26, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Label("\(meilleur.note)/10", systemImage: "star.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.accentClair)
                }
            }
        case .soiree:
            if let record = bilan.recordEpisodes {
                grandTexte(haut: "Ta plus grosse soirée", valeur: "\(record.nombreEpisodes)", bas: "épisodes d'affilée,\nle \(Format.jour(record.jour))")
            }
        case .resume:
            VStack(alignment: .leading, spacing: 16) {
                Text(contenu.titre).font(.system(size: 28, weight: .heavy))
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 18) {
                    case2("Heures", "\(Format.heures(bilan.minutesTotales)) h")
                    case2("Films", "\(bilan.nombreFilms)")
                    case2("Épisodes", "\(bilan.nombreEpisodes)")
                    case2("Séries", "\(contenu.nombreSeries)")
                }
                if let acteur = bilan.acteurs.first { ligne("Acteur", acteur.cle.nom) }
                if let genre = bilan.genres.first { ligne("Genre", contenu.nomsGenres[genre.cle] ?? "—") }
                if let meilleur = contenu.meilleur { ligne("Film préféré", "\(meilleur.titre) · \(meilleur.note)/10") }
            }
        }
    }

    private var portrait: some View {
        Group {
            if let portrait = contenu.portrait {
                Image(uiImage: portrait).resizable().scaledToFill()
            } else {
                Circle().fill(.white.opacity(0.1)).overlay(Image(systemName: "person.fill").font(.system(size: 60)).foregroundStyle(.white.opacity(0.5)))
            }
        }
        .frame(width: 190, height: 190)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.degradeAccent, lineWidth: 4))
        .shadow(color: Theme.accent.opacity(0.4), radius: 24)
    }

    private func grandTexte(haut: String, valeur: String, bas: String) -> some View {
        VStack(spacing: 10) {
            Text(haut).font(.system(size: 22, weight: .semibold))
            Text(valeur)
                .font(.system(size: 130, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.degradeAccent)
            Text(bas).font(.system(size: 19)).foregroundStyle(.white.opacity(0.75))
        }
        .multilineTextAlignment(.center)
    }

    private func chiffre(_ nombre: Int, _ libelle: String, couleur: Color) -> some View {
        VStack(spacing: 0) {
            Text("\(nombre)")
                .font(.system(size: 96, weight: .heavy, design: .rounded))
                .foregroundStyle(couleur)
            Text(libelle).font(.system(size: 24, weight: .bold))
        }
    }

    private func case2(_ libelle: String, _ valeur: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valeur).font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Theme.accentClair)
            Text(libelle.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func ligne(_ libelle: String, _ valeur: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(libelle.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.6))
            Text(valeur).font(.system(size: 19, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}
