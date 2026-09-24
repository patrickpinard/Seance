#if DEBUG
import Foundation
import SeanceDonnees
import SeanceKit
import SwiftData

/// Données fictives pour relire les écrans dans le simulateur (`SEANCE_DEMO=1`) : un magasin en
/// mémoire, jamais le vrai. Les titres et leurs affiches sont réels, les visionnages inventés.
enum Demonstration {
    static var active: Bool {
        ProcessInfo.processInfo.environment["SEANCE_DEMO"] != nil
    }

    /// `SEANCE_DEMO=vide` : le même magasin en mémoire, sans rien dedans — ce que voit quelqu'un qui vient d'installer
    /// l'app. Pour relire les états vides de chaque écran.
    static var vide: Bool {
        ProcessInfo.processInfo.environment["SEANCE_DEMO"] == "vide"
    }

    /// Une démonstration hors du simulateur — sur le Mac, pour une capture : l'app y partage l'identifiant et les réglages
    /// de la vraie. Elle n'envoie alors rien au-dehors : synchroniser déposerait ses données fictives dans le vrai dossier,
    /// où l'absence des vrais titres passerait pour des suppressions ; l'e-mail de la semaine partirait pour de bon.
    static var coupeeDuMonde: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        active
        #endif
    }

    private struct Titre {
        let reference: ReferenceTitre
        let nom: String
        let duree: Int
        let genres: [Int]
        let affiche: String
        let acteurs: [(String, Int)]
    }

    private static let films = [
        Titre(reference: .init(type: .film, tmdbID: 245891), nom: "John Wick", duree: 101, genres: [28, 53],
              affiche: "/7yCzmVL0BI1aSvzgN3jCtXLtyFR.jpg", acteurs: [("Keanu Reeves", 6384), ("Michael Nyqvist", 6283)]),
        Titre(reference: .init(type: .film, tmdbID: 603692), nom: "John Wick : Chapitre 4", duree: 169, genres: [28, 53, 80],
              affiche: "/n1YTIyhAqqqFyDGFTzV7WaU1JfK.jpg", acteurs: [("Keanu Reeves", 6384), ("Donnie Yen", 1341)]),
        Titre(reference: .init(type: .film, tmdbID: 76341), nom: "Mad Max : Fury Road", duree: 120, genres: [28, 12, 878],
              affiche: "/oLy2V6AWSEfdPgKOtrSGnwB3Q2R.jpg", acteurs: [("Tom Hardy", 2524), ("Charlize Theron", 6885)]),
        Titre(reference: .init(type: .film, tmdbID: 94329), nom: "The Raid", duree: 101, genres: [28, 53, 80],
              affiche: "/e0EeE8Rc5weReJNpwOP78DuCxdH.jpg", acteurs: [("Iko Uwais", 113732), ("Joe Taslim", 592496)]),
        Titre(reference: .init(type: .film, tmdbID: 545609), nom: "Tyler Rake", duree: 116, genres: [28, 53],
              affiche: "/qVHWs56TvXCKGjsmghWHFRqtKlF.jpg", acteurs: [("Chris Hemsworth", 74568), ("Randeep Hooda", 6519)]),
        Titre(reference: .init(type: .film, tmdbID: 361743), nom: "Top Gun : Maverick", duree: 130, genres: [28, 18],
              affiche: "/uuwi4wwG6HAHVqaEvJDx6gI773N.jpg", acteurs: [("Tom Cruise", 500), ("Miles Teller", 996701)]),
        Titre(reference: .init(type: .film, tmdbID: 353081), nom: "Mission : Impossible - Fallout", duree: 147, genres: [28, 12],
              affiche: "/6JO3Oz685phBaADyJtf4wmaafYj.jpg", acteurs: [("Tom Cruise", 500), ("Henry Cavill", 73968)]),
        Titre(reference: .init(type: .film, tmdbID: 615457), nom: "Nobody", duree: 92, genres: [28, 53],
              affiche: "/jKRzh9y5YjYNISbeh55FQwetsSu.jpg", acteurs: [("Bob Odenkirk", 59410), ("Connie Nielsen", 935)]),
        Titre(reference: .init(type: .film, tmdbID: 562), nom: "Piège de cristal", duree: 132, genres: [28, 53],
              affiche: "/1nOVVjbf8ucbeLmIlK5D2kCQQST.jpg", acteurs: [("Bruce Willis", 62), ("Alan Rickman", 4566)]),
    ]

    private static let reacher = Titre(reference: .init(type: .serie, tmdbID: 108978), nom: "Reacher", duree: 50, genres: [10759, 80],
                                       affiche: "/qrJOCIAcvPmyZ63KajWTalQtqPT.jpg", acteurs: [("Alan Ritchson", 64295), ("Maria Sten", 1247604)])
    private static let jackRyan = Titre(reference: .init(type: .serie, tmdbID: 73375), nom: "Jack Ryan", duree: 55, genres: [10759, 18],
                                        affiche: "/sEAUJohzgehanmml9nul3sfIlVr.jpg", acteurs: [("John Krasinski", 17697), ("Wendell Pierce", 17859)])
    private static let nightAgent = Titre(reference: .init(type: .serie, tmdbID: 129552), nom: "The Night Agent", duree: 48, genres: [10759, 18, 9648],
                                          affiche: "/vxCFNBGQ9AeI6GLtnpML1gKuSSK.jpg", acteurs: [("Gabriel Basso", 222122), ("Luciane Buchanan", 1610713)])

    @MainActor
    static func remplir(_ contexte: ModelContext) {
        func jour(_ annee: Int, _ mois: Int, _ jour: Int, heure: Int = 21) -> Date {
            DateTMDB(annee: annee, mois: mois, jour: jour).instant(fuseau: .suisse).addingTimeInterval(TimeInterval(heure * 3600))
        }

        func suivre(_ titre: Titre, _ statut: StatutSuivi, note: Int? = nil) {
            let suivi = Suivi(reference: titre.reference, titre: titre.nom, statut: statut, cheminAffiche: titre.affiche)
            suivi.genres = titre.genres
            suivi.acteursPrincipaux = titre.acteurs.map(\.0)
            suivi.acteursPrincipauxIDs = titre.acteurs.map(\.1)
            suivi.note = note
            contexte.insert(suivi)
        }

        // Films : dates et notes inventées, étalées sur deux ans.
        let vus: [(Int, Date, Int?)] = [
            (0, jour(2025, 11, 8), 8), (8, jour(2025, 12, 24), 9),
            (1, jour(2026, 1, 17), 9), (2, jour(2026, 2, 7), 10), (3, jour(2026, 3, 21), 8),
            (4, jour(2026, 4, 25), 7), (5, jour(2026, 6, 6), 9), (6, jour(2026, 7, 11), 8), (7, jour(2026, 8, 29), 7),
        ]
        for (index, date, note) in vus {
            let film = films[index]
            suivre(film, .termine, note: note)
            let visionnage = Visionnage(reference: film.reference, dureeMinutes: film.duree, vuLe: date)
            visionnage.note = note
            contexte.insert(visionnage)
        }
        // Revu en 2026 : John Wick compte deux fois.
        contexte.insert(Visionnage(reference: films[0].reference, dureeMinutes: films[0].duree, vuLe: jour(2026, 5, 16)))

        // Séries : Reacher en cours, Jack Ryan et The Night Agent terminées.
        suivre(reacher, .enCours, note: 9)
        suivre(jackRyan, .termine, note: 8)
        suivre(nightAgent, .termine, note: 7)
        let soirees: [(Titre, Int, ClosedRange<Int>, Date)] = [
            (jackRyan, 1, 1...4, jour(2026, 1, 9)), (jackRyan, 1, 5...8, jour(2026, 1, 10)),
            (nightAgent, 1, 1...7, jour(2026, 2, 14, heure: 19)), (nightAgent, 1, 8...10, jour(2026, 2, 15)),
            (reacher, 1, 1...3, jour(2026, 3, 6)), (reacher, 1, 4...8, jour(2026, 3, 7)),
            (reacher, 2, 1...2, jour(2026, 5, 22)), (reacher, 2, 3...4, jour(2026, 7, 3)), (reacher, 2, 5...5, jour(2026, 9, 12)),
        ]
        for (serie, saison, episodes, date) in soirees {
            for (rang, episode) in episodes.enumerated() {
                contexte.insert(Visionnage(reference: serie.reference, saison: saison, episode: episode, dureeMinutes: serie.duree,
                                           vuLe: date.addingTimeInterval(TimeInterval(rang * 3000))))
            }
        }

        // Liste à voir, goûts et soirée du jour.
        let aVoir = Titre(reference: .init(type: .film, tmdbID: 324552), nom: "John Wick : Chapitre 2", duree: 122, genres: [28, 53],
                          affiche: "/r687UV1zQ5KDB9AxRokRscWIRvt.jpg", acteurs: [("Keanu Reeves", 6384)])
        suivre(aVoir, .aVoir)
        for (libelle, genre) in [("Action", 28), ("Thriller", 53)] {
            contexte.insert(Interet(libelle: libelle, genreID: genre))
        }
        // Les plateformes du foyer (6.3) : sans elles, « Où regarder » n'a rien à dire et les petits logos des
        // cartes restent vides — sur l'Apple TV comme sur l'iPhone.
        for (identifiant, nom, logo) in [(8, "Netflix", "/pbpMk2JmcoNnQwx5JGpXngfoWtp.jpg"),
                                         (337, "Disney Plus", "/7rwgEs15tFwyR9NPQ5vpzxTj19Q.jpg"),
                                         (119, "Amazon Prime Video", "/emthp39XA2YScoYL1p0sdbAH2WA.jpg")] {
            contexte.insert(Abonnement(providerID: identifiant, nom: nom, cheminLogo: logo))
        }
        let soiree = ServiceSoiree.soiree()
        contexte.insert(SelectionSoir(reference: reacher.reference, titre: reacher.nom, cheminAffiche: reacher.affiche, soiree: soiree))
        contexte.insert(SelectionSoir(reference: aVoir.reference, titre: aVoir.nom, cheminAffiche: aVoir.affiche, soiree: soiree))
        // Une liste nommée, pour sa page en grille.
        let liste = ListePerso(nom: "Soirées Keanu")
        liste.titres = [films[0].reference, films[1].reference, aVoir.reference]
        liste.apercus = [films[0], films[1], aVoir].map { ApercuTitre(reference: $0.reference, titre: $0.nom, cheminAffiche: $0.affiche) }
        contexte.insert(liste)
        // Hier soir, un film prévu dont on ne sait pas s'il a été regardé.
        let hier = ServiceSoiree.soiree(Date.now.addingTimeInterval(-86_400))
        contexte.insert(SelectionSoir(reference: ReferenceTitre(type: .film, tmdbID: 949), titre: "Heat", cheminAffiche: "/umSVjVdbVwtx5ryCA2QXL44Durm.jpg", soiree: hier))

        // Programme TV : un film en cours, la soirée, le reste de la journée et les jours suivants.
        let aujourdhui = DateTMDB(.now)
        func passage(_ titre: Titre, chaine: String, debut: Date, episode: (Int, Int)? = nil) {
            let programme = ProgrammeTV(chaine: chaine, debut: debut, fin: debut.addingTimeInterval(TimeInterval(titre.duree * 60)), titre: titre.nom)
            let diffusion = Diffusion(programme: programme, rattachement: nil)
            diffusion.typeBrut = titre.reference.type.rawValue
            diffusion.tmdbID = titre.reference.tmdbID
            diffusion.cheminAffiche = titre.affiche
            diffusion.anneeGuide = episode == nil ? 2014 : nil
            diffusion.saison = episode?.0
            diffusion.episode = episode?.1
            contexte.insert(diffusion)
        }
        func a(_ heure: Int, _ minute: Int, dans jours: Int = 0) -> Date {
            aujourdhui.instant(heure: heure).addingTimeInterval(TimeInterval(jours * 86_400 + minute * 60))
        }
        // Les passages TV se posent sur la journée TV, qui va de 6 h à 6 h (GrilleTele) : après minuit, « demain »
        // reste le lendemain de la soirée en cours, comme la rangée de jours du programme l'affiche.
        let jourTele = GrilleTele.jourTele(.now)
        func aTele(_ heure: Int, _ minute: Int, dans jours: Int = 0) -> Date {
            jourTele.instant(heure: heure).addingTimeInterval(TimeInterval(jours * 86_400 + minute * 60))
        }
        passage(films[3], chaine: "W9.fr", debut: Date.now.addingTimeInterval(-40 * 60))
        passage(films[5], chaine: "France2.fr", debut: Date.now.addingTimeInterval(95 * 60))
        passage(aVoir, chaine: "TF1.fr", debut: aTele(20, 55))
        passage(films[8], chaine: "M6.fr", debut: aTele(21, 5))
        passage(reacher, chaine: "RTSUn.ch", debut: aTele(21, 10), episode: (2, 6))
        passage(reacher, chaine: "RTSUn.ch", debut: aTele(22, 2), episode: (2, 7))
        passage(films[7], chaine: "Arte.fr", debut: aTele(23, 25))
        passage(films[2], chaine: "TMC.fr", debut: aTele(14, 5, dans: 1))
        passage(films[6], chaine: "France3.fr", debut: aTele(21, 5, dans: 1))
        // Deux épisodes qui s'enchaînent demain : toujours à venir, quelle que soit l'heure où l'on regarde.
        passage(jackRyan, chaine: "RTSDeux.ch", debut: aTele(20, 40, dans: 1), episode: (1, 3))
        passage(jackRyan, chaine: "RTSDeux.ch", debut: aTele(21, 37, dans: 1), episode: (1, 4))
        passage(films[1], chaine: "TF1.fr", debut: aTele(21, 10, dans: 2))
        passage(films[4], chaine: "M6.fr", debut: aTele(21, 10, dans: 3))

        // À venir : un épisode ce soir, une saison la semaine prochaine, une sortie dans un mois, un passage TV demain.
        func rendezVous(_ titre: Titre, dans jours: Int, _ libelle: String, _ nature: EcheancePrevue.Nature) {
            let date = a(20, 0, dans: jours)
            contexte.insert(Echeance(EcheancePrevue(reference: titre.reference, titre: titre.nom, date: date, libelle: libelle, nature: nature),
                                     cheminAffiche: titre.affiche))
        }
        rendezVous(reacher, dans: 0, "S02E06 · Nouvel épisode", .episode)
        rendezVous(films[6], dans: 1, "Sur France 3 à 21:05", .tele)
        rendezVous(jackRyan, dans: 6, "Saison 2", .saison)
        rendezVous(aVoir, dans: 33, "Sortie en streaming", .sortie)

        // NAS : quelques films, deux nouveautés du dossier NEW, une série en épisodes.
        func fichier(_ titre: Titre, dossier: String, qualite: String, episode: Int? = nil) {
            let nom = episode.map { "\(titre.nom) S01E0\($0).mkv" } ?? "\(titre.nom) (2014).mkv"
            let fichier = FichierNAS(chemin: "/\(dossier)/\(nom)", type: titre.reference.type, tmdbID: titre.reference.tmdbID,
                                     qualite: qualite, tailleOctets: 8_400_000_000)
            fichier.dossier = dossier
            fichier.titre = titre.nom
            fichier.annee = 2014
            fichier.cheminAffiche = titre.affiche
            fichier.noteMoyenne = 7.4
            fichier.nombreVotes = 1200
            fichier.saison = episode == nil ? nil : 1
            fichier.episode = episode
            contexte.insert(fichier)
        }
        fichier(aVoir, dossier: "NEW", qualite: "4K")
        fichier(films[4], dossier: "NEW", qualite: "1080p")
        for film in [films[0], films[2], films[5], films[8]] { fichier(film, dossier: "Films", qualite: "1080p") }
        for episode in 1...3 { fichier(nightAgent, dossier: "Séries", qualite: "1080p", episode: episode) }
        contexte.sauver()
    }
}
#endif
