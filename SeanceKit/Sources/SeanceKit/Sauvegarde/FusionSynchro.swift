import Foundation

// Synchronisation entre appareils : propager aussi les suppressions et les retours en arrière, sans horodater chaque
// donnée dans le magasin. À chaque synchronisation, un appareil compare son état à celui de sa synchronisation
// précédente (`dater`) : ce qui a changé prend la date du jour, ce qui a disparu devient une suppression datée.
// Entre deux appareils, le plus récent l'emporte (`PlanSynchro`). Une sauvegarde importée à la main ne porte ni dates
// ni suppressions : elle ne fait qu'ajouter.

extension Sauvegarde {
    /// Un élément supprimé sur un appareil, sous sa clé (« suivi:film:603 »), et quand.
    public struct Suppression: Codable, Sendable, Equatable {
        public var cle: String
        public var le: Date

        public init(cle: String, le: Date) {
            self.cle = cle
            self.le = le
        }
    }

    /// Les réglages qui suivent l'utilisateur d'un appareil à l'autre. L'apparence, le tri ou la grille restent propres
    /// à chaque appareil : ils ne sont repris que sur un appareil où ils n'ont jamais été touchés. L'e-mail de la semaine
    /// (8.0) : serveur, compte, destinataires, jours — jamais le mot de passe, qui passe par le transfert chiffré ;
    /// jusque-là, un changement fait ailleurs ne remplaçait pas des réglages déjà enregistrés ici.
    public static let preferencesPartagees: Set<String> = ["profil.prenom", "cesoir.nombreIdees", "alertes.reglages", "nas.reglages", "videos.reglages",
                                                           "lettre.reglages"]

    /// Les suppressions plus vieilles que cela sont oubliées : tous les appareils les ont vues depuis longtemps.
    static let memoireDesSuppressions: TimeInterval = 180 * 86_400

    /// Chaque élément synchronisé, sous sa clé, avec la « signature » de ce qui peut y changer.
    public func signatures() -> [String: String] {
        var resultat: [String: String] = [:]
        for s in suivis {
            resultat["suivi:\(s.reference)"] = [s.statut, s.note.map(String.init) ?? "-", String(s.masque ?? false), String(s.alertesActives ?? true),
                                                s.modeAlertes ?? "-", String(s.exclusionLangue)].joined(separator: "|")
        }
        for v in visionnages { resultat["visionnage:\(v.cle)"] = "" }
        for s in soirees ?? [] { resultat["soiree:\(s.reference)|\(s.soiree)"] = "" }
        for a in acteursSuivis ?? [] { resultat["acteur:\(a.personneID)"] = "" }
        for a in aimes ?? [] { resultat["aime:\(a.reference)"] = "" }
        for f in favoris ?? [] { resultat["favori:\(f.reference)"] = "" }
        for l in listes {
            resultat["liste:\(l.nom)"] = ""
            for titre in l.titres { resultat["listeTitre:\(l.nom)|\(titre)"] = "" }
        }
        for f in filtres { resultat["filtre:\(f.nom)"] = "" }
        for i in interets { resultat["interet:\(i.cle)"] = "" }
        for a in abonnements { resultat["abonnement:\(a.providerID)"] = String(a.actif) }
        for c in chaines { resultat["chaine:\(c.identifiantGuide)"] = String(c.active) }
        for (cle, valeur) in preferences ?? [:] where Self.preferencesPartagees.contains(cle) {
            resultat["pref:\(cle)"] = String(describing: valeur)
        }
        return resultat
    }

    /// Date cet état par rapport à celui de la synchronisation précédente de **cet appareil**.
    /// La première fois, rien n'est daté : sans point de comparaison, on ne sait pas ce qui est récent, et dater tout
    /// « aujourd'hui » ferait gagner un vieil état sur un changement fait hier ailleurs.
    public func dater(depuis precedente: Sauvegarde?, maintenant: Date) -> Sauvegarde {
        var datee = self
        guard let precedente else {
            datee.modifications = nil
            datee.suppressions = nil
            return datee
        }
        let actuelles = signatures()
        let avant = precedente.signatures()
        var modifications: [String: Date] = [:]
        for (cle, signature) in actuelles {
            if let ancienne = avant[cle], ancienne == signature {
                modifications[cle] = precedente.modifications?[cle]
            } else {
                modifications[cle] = maintenant
            }
        }
        // Les suppressions connues restent tant que l'élément n'est pas revenu ; ce qui a disparu depuis s'y ajoute.
        var suppressions = (precedente.suppressions ?? []).filter {
            actuelles[$0.cle] == nil && maintenant.timeIntervalSince($0.le) < Self.memoireDesSuppressions
        }
        let connues = Set(suppressions.map(\.cle))
        let ceSoir = DateTMDB(maintenant.addingTimeInterval(-6 * 3600)).description
        for cle in avant.keys where actuelles[cle] == nil && !connues.contains(cle) && !Self.expiree(cle, ceSoir: ceSoir) {
            suppressions.append(Suppression(cle: cle, le: maintenant))
        }
        datee.modifications = modifications.isEmpty ? nil : modifications
        datee.suppressions = suppressions.isEmpty ? nil : suppressions.sorted { ($0.le, $0.cle) < ($1.le, $1.cle) }
        return datee
    }

    /// Une soirée passée sort toute seule de la sauvegarde : ce n'est pas une suppression.
    private static func expiree(_ cle: String, ceSoir: String) -> Bool {
        guard cle.hasPrefix("soiree:"), let soiree = cle.split(separator: "|").last else { return false }
        return String(soiree) < ceSoir
    }
}

/// Ce que le fichier d'un autre appareil change ici : suppressions à appliquer, éléments à remplacer par leur version
/// plus récente, et le reste à ajouter — sans rien ramener de ce qui a été supprimé ici entre-temps.
public struct PlanSynchro: Sendable, Equatable {
    /// Supprimés ailleurs, et pas modifiés ici depuis : à supprimer ici, avec la date d'origine.
    public var aSupprimer: [Sauvegarde.Suppression] = []
    /// Modifiés plus récemment ailleurs (vu, non vu, note, cloche…) : leur version remplace la nôtre.
    public var suivisRemplaces: [Sauvegarde.Suivi] = []
    public var abonnementsActifs: [Int: Bool] = [:]
    public var chainesActives: [String: Bool] = [:]
    public var preferencesRemplacees: [String: Sauvegarde.Preference] = [:]
    /// Le fichier reçu, sans ce qui a été supprimé ici depuis, ni ce que nous avons modifié plus récemment.
    public var aAjouter: Sauvegarde
    /// Les dates de l'autre appareil pour ce qui vient de lui : elles restent les siennes chez nous.
    public var datesRecues: [String: Date] = [:]

    public var estVide: Bool {
        aSupprimer.isEmpty && suivisRemplaces.isEmpty && abonnementsActifs.isEmpty && chainesActives.isEmpty && preferencesRemplacees.isEmpty
    }

    /// `locale` : l'état de cet appareil, daté par `dater`.
    public init(recue: Sauvegarde, locale: Sauvegarde) {
        let miennes = locale.signatures()
        let leurs = recue.signatures()
        let mesDates = locale.modifications ?? [:]
        let leursDates = recue.modifications ?? [:]
        let mesSuppressions = Dictionary((locale.suppressions ?? []).map { ($0.cle, $0.le) }, uniquingKeysWith: max)

        aSupprimer = (recue.suppressions ?? []).filter { suppression in
            miennes[suppression.cle] != nil && (mesDates[suppression.cle] ?? .distantPast) < suppression.le
        }

        /// Supprimé ici, et pas recréé ailleurs depuis : ne revient pas.
        func refuse(_ cle: String) -> Bool {
            guard let supprimeLe = mesSuppressions[cle] else { return false }
            return (leursDates[cle] ?? .distantPast) <= supprimeLe
        }
        /// Leur version est datée, plus récente que la nôtre, et différente.
        func plusRecent(_ cle: String) -> Bool {
            guard let mienne = miennes[cle], let leur = leurs[cle], mienne != leur, let leurDate = leursDates[cle] else { return false }
            return leurDate > (mesDates[cle] ?? .distantPast)
        }
        /// Nous l'avons modifié sciemment, et au moins aussi récemment : leur version ne doit pas le « compléter ».
        func nousPrimons(_ cle: String) -> Bool {
            guard miennes[cle] != nil, let maDate = mesDates[cle] else { return false }
            return maDate >= (leursDates[cle] ?? .distantPast)
        }

        var filtree = recue
        filtree.suppressions = nil
        filtree.modifications = nil
        filtree.suivis = recue.suivis.filter { !refuse("suivi:\($0.reference)") && !nousPrimons("suivi:\($0.reference)") }
        filtree.visionnages = recue.visionnages.filter { !refuse("visionnage:\($0.cle)") }
        filtree.soirees = recue.soirees?.filter { !refuse("soiree:\($0.reference)|\($0.soiree)") }
        filtree.acteursSuivis = recue.acteursSuivis?.filter { !refuse("acteur:\($0.personneID)") }
        filtree.aimes = recue.aimes?.filter { !refuse("aime:\($0.reference)") }
        filtree.favoris = recue.favoris?.filter { !refuse("favori:\($0.reference)") }
        filtree.filtres = recue.filtres.filter { !refuse("filtre:\($0.nom)") }
        filtree.interets = recue.interets.filter { !refuse("interet:\($0.cle)") }
        filtree.listes = recue.listes.filter { !refuse("liste:\($0.nom)") }.map { liste in
            var liste = liste
            liste.titres = liste.titres.filter { !refuse("listeTitre:\(liste.nom)|\($0)") }
            liste.apercus = liste.apercus?.filter { !refuse("listeTitre:\(liste.nom)|\($0.reference)") }
            return liste
        }
        // Les réglages passent par `preferencesRemplacees` ; l'import simple ne touche que ceux jamais réglés ici.
        aAjouter = filtree

        for suivi in recue.suivis where plusRecent("suivi:\(suivi.reference)") {
            suivisRemplaces.append(suivi)
        }
        for abonnement in recue.abonnements where plusRecent("abonnement:\(abonnement.providerID)") {
            abonnementsActifs[abonnement.providerID] = abonnement.actif
        }
        for chaine in recue.chaines where plusRecent("chaine:\(chaine.identifiantGuide)") {
            chainesActives[chaine.identifiantGuide] = chaine.active
        }
        for (cle, valeur) in recue.preferences ?? [:] where Sauvegarde.preferencesPartagees.contains(cle) && plusRecent("pref:\(cle)") {
            preferencesRemplacees[cle] = valeur
        }
        // Ce qui arrive de l'autre appareil garde sa date à lui.
        for (cle, date) in leursDates where leurs[cle] != nil {
            if miennes[cle] == nil ? !refuse(cle) : plusRecent(cle) { datesRecues[cle] = date }
        }
    }
}
