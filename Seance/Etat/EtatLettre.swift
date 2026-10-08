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
    typealias Rubrique = ReglagesLettre.Rubrique
    typealias Reglages = ReglagesLettre

    private(set) var reglages: Reglages
    private(set) var dernierEnvoi: Date?
    private(set) var enCours = false
    /// Ce que le dernier envoi (ou essai) a donné.
    private(set) var message: String?
    private(set) var aUnMotDePasse = false

    private let coffre: any CoffreCles
    var journal: Journal?
    /// La personne de la famille dont ce sont les réglages (8.2.17) : vide pour le profil principal.
    let profil: String
    /// Noms des réglages dans la sauvegarde et la synchronisation (`PreferencesSauvegardees`) : chaque profil y dépose
    /// les siens sous ces noms, dans son sous-dossier ; le mot de passe ne voyage pas.
    static let cle = ReglagesLettre.cle
    static let cleDernier = "lettre.dernierEnvoi"

    /// Sur l'appareil (8.2.17) : une clé par personne de la famille — chacun ses destinataires, ses jours, ses
    /// rubriques, ses plateformes et ses chaînes. Le compte d'envoi reste celui de l'appareil, commun à tous.
    static func cle(profil: String) -> String { ReglagesLettre.cle(profil: profil) }
    static func cleDernier(profil: String) -> String { profil.isEmpty ? cleDernier : "\(cleDernier).\(profil)" }

    static func lire(profil: String, defauts: UserDefaults = .standard) -> Reglages {
        var reglages = defauts.data(forKey: cle(profil: profil)).flatMap { try? JSONDecoder().decode(Reglages.self, from: $0) } ?? Reglages()
        if !profil.isEmpty { reglages.compte = lire(profil: "", defauts: defauts).compte }
        return reglages
    }

    private static func ecrire(_ reglages: Reglages, profil: String, defauts: UserDefaults = .standard) {
        defauts.set(try? JSONEncoder().encode(reglages), forKey: cle(profil: profil))
        // Le compte d'envoi, changé depuis les préférences d'une autre personne, vaut pour tout l'appareil.
        guard !profil.isEmpty else { return }
        var principal = lire(profil: "", defauts: defauts)
        guard principal.compte != reglages.compte else { return }
        principal.compte = reglages.compte
        defauts.set(try? JSONEncoder().encode(principal), forKey: cle)
    }

    init(coffre: any CoffreCles, profil: String = ProfilsFamille().actif.id) {
        self.coffre = coffre
        self.profil = profil
        reglages = Self.lire(profil: profil)
        dernierEnvoi = UserDefaults.standard.object(forKey: Self.cleDernier(profil: profil)) as? Date
        aUnMotDePasse = ((try? coffre.lire(.smtp)) ?? nil)?.isEmpty == false
    }

    var adresses: [String] { MessageMail.adresses(reglages.destinataires) }
    var pret: Bool { reglages.compte.estComplet && aUnMotDePasse && !adresses.isEmpty }

    /// `motDePasse` vide : on garde celui qui est déjà là.
    func enregistrer(_ nouveaux: Reglages, motDePasse: String = "") {
        reglages = nouveaux
        Self.ecrire(nouveaux, profil: profil)
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
        UserDefaults.standard.set(date, forKey: Self.cleDernier(profil: profil))
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
    /// Pour chaque personne de la famille (8.2.17) : chacune a ses réglages, et sa lettre se compose depuis son magasin.
    func envoyerSiDu(etat: EtatApp, contexte: ModelContext) async {
        #if DEBUG
        if Demonstration.coupeeDuMonde { return }
        #endif
        guard !enCours else { return }
        for personne in ProfilsFamille().profils {
            let lesSiens = personne.id == profil ? reglages : Self.lire(profil: personne.id)
            let dernier = personne.id == profil ? dernierEnvoi : UserDefaults.standard.object(forKey: Self.cleDernier(profil: personne.id)) as? Date
            guard lesSiens.actif, lesSiens.compte.estComplet, aUnMotDePasse, !MessageMail.adresses(lesSiens.destinataires).isEmpty,
                  let echeance = Self.echeance(jours: lesSiens.joursRetenus, heure: lesSiens.heure, maintenant: .now),
                  (dernier ?? .distantPast) < echeance else { continue }
            if personne.id == profil {
                await envoyer(etat: etat, contexte: contexte, essai: false)
            } else if let conteneur = ConteneurApp.conteneur(de: personne) {
                await envoyer(etat: etat, contexte: conteneur.mainContext, essai: false, pour: personne, reglages: lesSiens)
            }
        }
    }

    /// `pour` : une autre personne de la famille que celle en cours, avec ses propres réglages.
    func envoyer(etat: EtatApp, contexte: ModelContext, essai: Bool, pour autre: ProfilFamille? = nil, reglages autres: Reglages? = nil) async {
        guard !enCours else { return }
        let reglages = autres ?? self.reglages
        let adresses = MessageMail.adresses(reglages.destinataires)
        guard reglages.compte.estComplet, aUnMotDePasse, !adresses.isEmpty, let motDePasse = (try? coffre.lire(.smtp)) ?? nil else {
            if autre == nil { message = "Complète d'abord le compte d'envoi, son mot de passe et au moins un destinataire." }
            return
        }
        enCours = true
        defer { enCours = false }
        let prenom = autre.map(\.prenom) ?? (UserDefaults.standard.string(forKey: Prenom.cle) ?? "")
        let lettre = await composer(etat: etat, contexte: contexte, essai: essai, reglages: reglages, prenom: prenom, autreProfil: autre != nil)
        let mail = MessageMail(expediteur: reglages.compte.adresse, destinataires: adresses, sujet: lettre.sujet, texte: lettre.texte, html: lettre.html)
        let qui = autre.map { " (\($0.prenom))" } ?? ""
        do {
            try await ClientSMTP(compte: reglages.compte, motDePasse: motDePasse).envoyer(mail)
            if !essai {
                UserDefaults.standard.set(Date.now, forKey: Self.cleDernier(profil: autre?.id ?? profil))
                if autre == nil { dernierEnvoi = .now }
            }
            let texte = "\(essai ? "E-mail d'essai" : "E-mail de la semaine")\(qui) envoyé à \(adresses.joined(separator: ", "))."
            if autre == nil { message = texte }
            journal?.noter(.general, texte)
        } catch {
            let explication = (error as? LocalizedError)?.errorDescription ?? "L'envoi n'a pas abouti."
            if autre == nil { message = explication }
            journal?.noter(.general, "L'e-mail de la semaine\(qui) n'a pas pu partir.", erreur: error, conseil: explication)
        }
    }

    // MARK: Le contenu de la semaine

    func composer(etat: EtatApp, contexte: ModelContext, essai: Bool) async -> LettreHebdo {
        await composer(etat: etat, contexte: contexte, essai: essai, reglages: reglages,
                       prenom: UserDefaults.standard.string(forKey: Prenom.cle) ?? "", autreProfil: false)
    }

    /// `autreProfil` : les échéances sont dans le cache commun, calculées pour la personne en cours ; pour une autre,
    /// on ne garde que celles de ses propres titres.
    func composer(etat: EtatApp, contexte: ModelContext, essai: Bool, reglages: Reglages, prenom: String, autreProfil: Bool) async -> LettreHebdo {
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
        let siens: Set<ReferenceTitre>? = autreProfil ? Set(((try? contexte.fetch(FetchDescriptor<Suivi>())) ?? []).map(\.reference)) : nil
        let echeances = toutes
            .filter { $0.date >= maintenant.addingTimeInterval(-3600) && $0.date <= fin }
            .filter { siens?.contains($0.reference) ?? true }
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
        var aLaUne: LettreHebdo.Ligne?
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
            // 8.11 : classées d'après tes goûts, comme les suggestions de l'app, avec la phrase qui dit pourquoi.
            let profil = (try? ServiceGouts(contexte: contexte).profil()) ?? ProfilGouts()
            let classees = ClassementLocal.classer((films.prefix(12) + nouvellesSeries.prefix(8)).map { CandidatSuggestion(titre: $0) },
                                                   profil: profil, nomsGenres: etat.nomsGenres)
            let lignes = classees.map { suggestion in
                let titre = suggestion.candidat.titre
                return LettreHebdo.Ligne(titre: titre.titre,
                                         detail: titre.reference.type == .film ? "Film · sur tes plateformes" : "Série · sur tes plateformes",
                                         quand: titre.date.map { jour($0.instant(heure: 12)) } ?? "Cette semaine",
                                         urlAffiche: ImageTMDB.url(titre.cheminAffiche, .affiche), lien: lien(titre.reference),
                                         resume: LettreHebdo.extrait(titre.synopsis),
                                         note: titre.nombreVotes >= 20 && titre.noteMoyenne > 0 ? titre.noteMoyenne : nil,
                                         pourquoi: suggestion.score.raisons.isEmpty ? nil : suggestion.phrase,
                                         urlFond: ImageTMDB.url(titre.cheminFond, .fond))
            }
            // À la une : la mieux classée qui a une image large et un résumé.
            if let rang = lignes.firstIndex(where: { $0.urlFond != nil && $0.resume != nil }) {
                aLaUne = lignes[rang]
            }
            nouveautes = Array(lignes.filter { $0.titre != aLaUne?.titre }.prefix(9))
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
        // 8.11 : le programme en une phrase, sous l'accueil.
        let morceaux = [
            pourToi.isEmpty ? nil : Format.pluriel(pourToi.count, "rendez-vous pour tes titres", "rendez-vous pour tes titres"),
            nouveautes.count + (aLaUne == nil ? 0 : 1) == 0 ? nil
                : Format.pluriel(nouveautes.count + (aLaUne == nil ? 0 : 1), "nouveauté sur tes plateformes", "nouveautés sur tes plateformes"),
            reglages.veut(.soirees) && !soirees.isEmpty ? Format.pluriel(soirees.count, "soirée prévue", "soirées prévues") : nil,
        ].compactMap { $0 }
        let enUneLigne = morceaux.count > 1 ? morceaux.dropLast().joined(separator: ", ") + " et " + morceaux.last! : morceaux.first
        let auProgramme = enUneLigne.map { "Au programme : \($0)." }
        return LettreHebdo(prenom: Prenom.lire(prenom),
                           periode: "Du \(debut) au \(terme)", sections: sections, essai: essai,
                           aLaUne: aLaUne, auProgramme: auProgramme)
    }
}
