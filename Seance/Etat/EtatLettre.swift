import Foundation
import Observation
import SeanceDonnees
import SeanceKit
import SwiftData

/// L'e-mail de la semaine (Séance 5.0) : une fois par semaine, ce qui sort et ce qui passe dans les sept jours — pour
/// tes titres, et sur tes plateformes — envoyé aux adresses de ton choix par ton propre compte de messagerie. Séance
/// n'a pas de serveur : l'e-mail part de cet appareil, à sa première ouverture (ou à son premier réveil en arrière-plan)
/// après le jour et l'heure choisis. Le mot de passe reste dans le trousseau et ne voyage pas.
@MainActor
@Observable
final class EtatLettre {
    /// Ce que la lettre peut contenir (6.5) : chacun choisit ce qu'il veut recevoir.
    enum Rubrique: String, Codable, CaseIterable, Identifiable, Sendable {
        case episodes, sorties, passagesTele, acteurs, nouveautes, soirees

        var id: String { rawValue }

        var nom: String {
            switch self {
            case .episodes: "Nouveaux épisodes de mes séries"
            case .sorties: "Sorties des titres que je suis"
            case .passagesTele: "Passages à la TV de mes titres"
            case .acteurs: "Nouveaux films de mes acteurs"
            case .nouveautes: "Nouveautés de mes plateformes"
            case .soirees: "Mes soirées prévues"
            }
        }

        var symbole: String {
            switch self {
            case .episodes: "play.tv"
            case .sorties: "sparkles"
            case .passagesTele: "tv"
            case .acteurs: "person.fill"
            case .nouveautes: "rectangle.stack.badge.play"
            case .soirees: "moon.stars"
            }
        }
    }

    struct Reglages: Codable, Equatable {
        var actif = false
        /// « a@x.ch ; b@y.ch » : tel que saisi.
        var destinataires = ""
        var compte = CompteSMTP()
        /// Jour de la semaine du calendrier (1 = dimanche … 7 = samedi) : gardé pour les réglages d'avant la 6.5.
        var jour = 6
        var heure = 17
        /// Les jours d'envoi (6.5) : un e-mail peut partir plusieurs fois par semaine. Vide : le seul `jour`.
        var jours: Set<Int>?
        /// Les rubriques retenues. Absent : tout, comme avant la 6.5.
        var rubriques: Set<Rubrique>?
        /// Les plateformes dont on veut les nouveautés (identifiants TMDB). Vide : toutes celles cochées.
        var plateformes: Set<Int>?
        /// Les chaînes dont on veut les passages (identifiants du guide). Vide : toutes celles cochées.
        var chaines: Set<String>?

        /// Les jours retenus, l'ancien réglage compris.
        var joursRetenus: Set<Int> { (jours?.isEmpty == false ? jours : nil) ?? [jour] }
        /// Vrai si cette rubrique doit paraître.
        func veut(_ rubrique: Rubrique) -> Bool { rubriques?.contains(rubrique) ?? true }
    }

    private(set) var reglages: Reglages
    private(set) var dernierEnvoi: Date?
    private(set) var enCours = false
    /// Ce que le dernier envoi (ou essai) a donné.
    private(set) var message: String?
    private(set) var aUnMotDePasse = false

    private let coffre: any CoffreCles
    var journal: Journal?
    /// Ces deux réglages voyagent dans la sauvegarde et la synchronisation (`PreferencesSauvegardees`) ; le mot de passe, non.
    static let cle = "lettre.reglages"
    static let cleDernier = "lettre.dernierEnvoi"

    init(coffre: any CoffreCles) {
        self.coffre = coffre
        reglages = UserDefaults.standard.data(forKey: Self.cle).flatMap { try? JSONDecoder().decode(Reglages.self, from: $0) } ?? Reglages()
        dernierEnvoi = UserDefaults.standard.object(forKey: Self.cleDernier) as? Date
        aUnMotDePasse = ((try? coffre.lire(.smtp)) ?? nil)?.isEmpty == false
    }

    var adresses: [String] { MessageMail.adresses(reglages.destinataires) }
    var pret: Bool { reglages.compte.estComplet && aUnMotDePasse && !adresses.isEmpty }

    /// `motDePasse` vide : on garde celui qui est déjà là.
    func enregistrer(_ nouveaux: Reglages, motDePasse: String = "") {
        reglages = nouveaux
        UserDefaults.standard.set(try? JSONEncoder().encode(nouveaux), forKey: Self.cle)
        if !motDePasse.isEmpty, (try? coffre.enregistrer(motDePasse, pour: .smtp)) != nil { aUnMotDePasse = true }
    }

    /// Les réglages à passer à un autre appareil (6.5), encodés : compte, destinataires, jours, rubriques. Le mot
    /// de passe voyage à part, dans le même message chiffré.
    var reglagesPourTransfert: Data? {
        reglages.compte.estComplet ? try? JSONEncoder().encode(reglages) : nil
    }

    /// Reçus d'un autre appareil : on les prend tels quels, mot de passe compris.
    func recevoir(_ donnees: Data, motDePasse: String?) {
        guard let recus = try? JSONDecoder().decode(Reglages.self, from: donnees) else { return }
        enregistrer(recus, motDePasse: motDePasse ?? "")
    }

    /// Un autre appareil a déjà envoyé l'e-mail de la semaine : celui-ci ne le renverra pas.
    func noterEnvoiAilleurs(_ date: Date) {
        guard date > (dernierEnvoi ?? .distantPast) else { return }
        dernierEnvoi = date
        UserDefaults.standard.set(date, forKey: Self.cleDernier)
    }

    /// Le moment prévu du dernier envoi : le plus récent « jour retenu à l'heure dite » déjà passé. Avec plusieurs
    /// jours dans la semaine (6.5), c'est le plus proche d'entre eux.
    static func echeance(jours: Set<Int>, heure: Int, maintenant: Date, calendrier: Calendar = .current) -> Date? {
        jours.compactMap { jour -> Date? in
            var composants = DateComponents()
            composants.weekday = jour
            composants.hour = heure
            composants.minute = 0
            return calendrier.nextDate(after: maintenant, matching: composants, matchingPolicy: .nextTime, direction: .backward)
        }.max()
    }

    /// Un seul jour : la forme d'avant la 6.5, gardée pour les tests et les anciens réglages.
    static func echeance(jour: Int, heure: Int, maintenant: Date, calendrier: Calendar = .current) -> Date? {
        echeance(jours: [jour], heure: heure, maintenant: maintenant, calendrier: calendrier)
    }

    var prochainEnvoi: Date? {
        reglages.joursRetenus.compactMap { jour -> Date? in
            var composants = DateComponents()
            composants.weekday = jour
            composants.hour = reglages.heure
            composants.minute = 0
            return Calendar.current.nextDate(after: .now, matching: composants, matchingPolicy: .nextTime)
        }.min()
    }

    /// Au lancement, au retour dans l'app et au réveil en arrière-plan : envoie si l'échéance de la semaine est passée.
    func envoyerSiDu(etat: EtatApp, contexte: ModelContext) async {
        #if DEBUG
        if Demonstration.coupeeDuMonde { return }
        #endif
        guard reglages.actif, pret, !enCours,
              let echeance = Self.echeance(jours: reglages.joursRetenus, heure: reglages.heure, maintenant: .now),
              (dernierEnvoi ?? .distantPast) < echeance else { return }
        await envoyer(etat: etat, contexte: contexte, essai: false)
    }

    func envoyer(etat: EtatApp, contexte: ModelContext, essai: Bool) async {
        guard !enCours else { return }
        guard pret, let motDePasse = (try? coffre.lire(.smtp)) ?? nil else {
            message = "Complète d'abord le compte d'envoi, son mot de passe et au moins un destinataire."
            return
        }
        enCours = true
        defer { enCours = false }
        let lettre = await composer(etat: etat, contexte: contexte, essai: essai)
        let mail = MessageMail(expediteur: reglages.compte.adresse, destinataires: adresses, sujet: lettre.sujet, texte: lettre.texte, html: lettre.html)
        do {
            try await ClientSMTP(compte: reglages.compte, motDePasse: motDePasse).envoyer(mail)
            if !essai {
                dernierEnvoi = .now
                UserDefaults.standard.set(Date.now, forKey: Self.cleDernier)
            }
            message = "\(essai ? "E-mail d'essai" : "E-mail de la semaine") envoyé à \(adresses.joined(separator: ", "))."
            journal?.noter(.general, message ?? "")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "L'envoi n'a pas abouti."
            journal?.noter(.general, "L'e-mail de la semaine n'a pas pu partir.", erreur: error, conseil: message)
        }
    }

    // MARK: Le contenu de la semaine

    func composer(etat: EtatApp, contexte: ModelContext, essai: Bool) async -> LettreHebdo {
        let maintenant = Date.now
        let fin = maintenant.addingTimeInterval(7 * 86_400)
        let locale = Locale(identifier: "fr_CH")
        func jour(_ date: Date) -> String {
            let texte = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
            return texte.prefix(1).uppercased() + texte.dropFirst()
        }
        // 8.1 : un clic ouvre la fiche dans Séance, sur l'iPhone, l'iPad ou le Mac où l'on lit l'e-mail — et non plus la
        // page de TMDB. `seance://film/603`, le même lien que les widgets et Spotlight.
        func lien(_ reference: ReferenceTitre) -> URL? {
            URL(string: "seance://\(reference.type.rawValue)/\(reference.tmdbID)")
        }

        // 1. Tes titres : épisodes, sorties et passages à la TV des sept prochains jours — chaque nature ne paraît
        // que si elle est cochée dans les réglages (6.5), et les passages seulement sur les chaînes retenues.
        let chainesVoulues = reglages.chaines ?? []
        let toutes: [Echeance] = (try? contexte.fetch(FetchDescriptor<Echeance>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let echeances = toutes
            .filter { $0.date >= maintenant.addingTimeInterval(-3600) && $0.date <= fin }
            .filter { echeance in
                switch echeance.nature {
                case .episode, .saison: reglages.veut(.episodes)
                case .sortie: reglages.veut(.sorties)
                case .tele:
                    // L'échéance ne garde pas l'identifiant de la chaîne, seulement son nom dans le libellé
                    // (« RTS 1, ce soir à 21:10 ») : c'est là qu'on la reconnaît.
                    reglages.veut(.passagesTele)
                        && (chainesVoulues.isEmpty || chainesVoulues.contains { echeance.libelle.localizedStandardContains($0) })
                }
            }
        var vues = Set<String>()
        let pourToi = echeances.filter { vues.insert("\($0.reference)|\($0.libelle)").inserted }.prefix(12).map {
            LettreHebdo.Ligne(titre: $0.titre, detail: $0.libelle, quand: jour($0.date), urlAffiche: ImageTMDB.url($0.cheminAffiche, .affiche), lien: lien($0.reference))
        }

        // 2. Sur tes plateformes : ce qui est sorti depuis sept jours ou sort d'ici sept jours.
        var nouveautes: [LettreHebdo.Ligne] = []
        // Les plateformes retenues pour la lettre (6.5) : toutes celles cochées, ou la sélection faite dans ses réglages.
        let cochees = ((try? contexte.fetch(FetchDescriptor<Abonnement>(predicate: #Predicate { $0.actif }))) ?? []).map(\.providerID)
        let voulues = reglages.plateformes ?? []
        let abonnements = voulues.isEmpty ? cochees : cochees.filter { voulues.contains($0) }
        if let tmdb = etat.tmdb, !abonnements.isEmpty, reglages.veut(.nouveautes) {
            let exclus = (try? ServiceGouts(contexte: contexte).contexteCandidats()).map { $0.exclus.union($0.dejaVus) } ?? []
            var criteres = CriteresDecouverte()
            criteres.fournisseurs = abonnements
            criteres.monetisations = [.abonnement, .gratuit, .avecPublicite]
            criteres.tri = .popularite
            criteres.votesMin = 5
            criteres.genresExclus = [99, 10770]
            criteres.sortieDepuis = DateTMDB(maintenant.addingTimeInterval(-7 * 86_400))
            criteres.sortieJusqua = DateTMDB(fin)
            let films = ((try? await tmdb.decouvrirFilms(criteres).resultats.map(\.titreResume)) ?? []).filter { !exclus.contains($0.reference) && $0.cheminAffiche != nil }
            var series = CriteresDecouverte()
            series.fournisseurs = abonnements
            series.monetisations = criteres.monetisations
            series.tri = .popularite
            series.votesMin = 5
            series.genresExclus = [99, 10763, 10764, 10767]
            series.sortieDepuis = criteres.sortieDepuis
            series.sortieJusqua = criteres.sortieJusqua
            let nouvellesSeries = ((try? await tmdb.decouvrirSeries(series).resultats.map(\.titreResume)) ?? []).filter { !exclus.contains($0.reference) && $0.cheminAffiche != nil }
            nouveautes = (films.prefix(6) + nouvellesSeries.prefix(4)).map { titre in
                LettreHebdo.Ligne(titre: titre.titre, detail: titre.reference.type == .film ? "Film · sur tes plateformes" : "Série · sur tes plateformes",
                                  quand: titre.date.map { jour($0.instant(heure: 12)) } ?? "Cette semaine",
                                  urlAffiche: ImageTMDB.url(titre.cheminAffiche, .affiche), lien: lien(titre.reference))
            }
        }

        // 3. Ce que tu as prévu : tes soirées de la semaine.
        let soirees = ((try? ServiceSoiree(contexte: contexte).aVenir()) ?? []).prefix(8).map { selection in
            LettreHebdo.Ligne(titre: selection.titre, detail: selection.reference.type == .film ? "Film prévu" : "Série prévue",
                              quand: ServiceSoiree.jour(selection.soiree).map(jour) ?? "", urlAffiche: ImageTMDB.url(selection.cheminAffiche, .affiche), lien: lien(selection.reference))
        }

        let debut = maintenant.formatted(.dateTime.day().month(.wide).locale(locale))
        let terme = fin.formatted(.dateTime.day().month(.wide).year().locale(locale))
        var sections: [LettreHebdo.Section] = []
        if !pourToi.isEmpty {
            sections.append(.init(titre: "Pour tes titres", sousTitre: "Épisodes, sorties et passages à la TV de ce que tu suis",
                                  lignes: Array(pourToi)))
        }
        if !nouveautes.isEmpty {
            sections.append(.init(titre: "Nouveau sur tes plateformes", sousTitre: "Sorti depuis une semaine, ou attendu dans les sept jours",
                                  lignes: nouveautes))
        }
        if reglages.veut(.soirees), !soirees.isEmpty {
            sections.append(.init(titre: "Tes soirées prévues", lignes: Array(soirees)))
        }
        return LettreHebdo(prenom: Prenom.lire(UserDefaults.standard.string(forKey: Prenom.cle) ?? ""),
                           periode: "Du \(debut) au \(terme)", sections: sections, essai: essai)
    }
}
