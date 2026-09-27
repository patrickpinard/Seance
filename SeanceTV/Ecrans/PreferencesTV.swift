import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Les Préférences de la TV (8.2.17, demande de Patrick) : les mêmes réglages « à toi » que sur l'iPhone et l'iPad —
/// langue et sous-titres, alertes, e-mail de la semaine, alertes à venir — pour la personne qui regarde. La TV n'envoie
/// ni alerte ni e-mail : ses choix partent vers l'iPhone, l'iPad et le Mac par la synchronisation du NAS.
enum PreferenceTV: Hashable {
    case langue, alertes, lettre, alertesAVenir
}

extension View {
    func destinationsPreferencesTV() -> some View {
        navigationDestination(for: PreferenceTV.self) { preference in
            switch preference {
            case .langue: PageLectureTV().pageOuverte()
            case .alertes: PageAlertesTV().pageOuverte()
            case .lettre: PageLettreTV().pageOuverte()
            case .alertesAVenir: PageAlertesAVenirTV().pageOuverte()
            }
        }
    }
}

/// Préférences › Alertes : ce dont on veut être prévenu, et quand — les mêmes réglages que sur l'iPhone.
struct PageAlertesTV: View {
    @Environment(EtatTV.self) private var etat
    private let profil = ConteneurTV.famille.actif.id
    @State private var reglages = ReglagesAlertes.lire(profil: ConteneurTV.famille.actif.id) ?? ReglagesAlertes()

    var body: some View {
        PageTV(titre: "Alertes",
               sousTitre: "L'Apple TV n'affiche pas d'alertes : ces réglages sont ceux de ton iPhone et de ton iPad, qui les reçoivent à la prochaine synchronisation.") {
            SectionTV(titre: "Me prévenir pour",
                      explication: "Pour les titres dont la cloche est activée sur la fiche. La cloche s'active quand tu ajoutes un titre ; une série peut ne prévenir qu'aux nouvelles saisons.") {
                ForEach(ReglagesAlertes.typesProposes, id: \.self) { type in
                    BasculeTV(titre: type.libelle, actif: Binding {
                        reglages.typesActifs.contains(type)
                    } set: { actif in
                        modifier { if actif { $0.typesActifs.insert(type) } else { $0.typesActifs.remove(type) } }
                    })
                }
                BasculeTV(titre: "La veille aussi", actif: Binding { reglages.veille } set: { valeur in modifier { $0.veille = valeur } })
                BasculeTV(titre: "Dès qu'une saison ou une sortie est annoncée",
                          actif: Binding { reglages.annonces } set: { valeur in modifier { $0.annonces = valeur } })
            }
            SectionTV(titre: "Quand", explication: "Nouveaux épisodes, sorties et passages à la TV sont annoncés le jour même, à cette heure-là. Un clic avance d'une heure.") {
                LigneTVReglage(titre: "Heure des alertes", symbole: "clock", action: {
                    modifier { $0.heure = $0.heure >= 22 ? 7 : $0.heure + 1; $0.minute = 0 }
                }) {
                    BoutTV(forme: .valeur(String(format: "%d:%02d", reglages.heure, reglages.minute)))
                }
                if reglages.typesActifs.contains(.diffusionTele) {
                    LigneTVReglage(titre: "Rappel avant la diffusion", symbole: "tv", action: {
                        modifier { let minutes = Int($0.rappelAvantDiffusion / 60); $0.rappelAvantDiffusion = TimeInterval((minutes >= 60 ? 5 : minutes + 5) * 60) }
                    }) {
                        BoutTV(forme: .valeur("\(Int(reglages.rappelAvantDiffusion / 60)) min"))
                    }
                }
            }
            SectionTV {
                LigneTVReglage(titre: "Tester une alerte", detail: "Ton iPhone sonne, et ta montre avec lui", symbole: "bell.badge.fill",
                               desactive: !etat.nasPret, action: { Task { await etat.demanderEssaiAlerte() } }) { EmptyView() }
                NavigationLink(value: PreferenceTV.alertesAVenir) {
                    LigneTVReglage(titre: "Tes alertes à venir", symbole: "bell.badge.waveform") { BoutTV(forme: .chevron) }
                }
                .buttonStyle(LigneTV())
            }
        }
    }

    private func modifier(_ changement: (inout ReglagesAlertes) -> Void) {
        changement(&reglages)
        UserDefaults.standard.set(try? JSONEncoder().encode(reglages), forKey: ReglagesAlertes.cle(profil: profil))
    }
}

/// Préférences › E-mail de la semaine : à qui, quoi, quelles plateformes et chaînes, quels jours. Le compte d'envoi se
/// règle sur l'iPhone, l'iPad ou le Mac — c'est l'un d'eux qui envoie.
struct PageLettreTV: View {
    @Query(filter: #Predicate<Abonnement> { $0.actif }, sort: \Abonnement.nom) private var abonnements: [Abonnement]
    @Query(filter: #Predicate<Chaine> { $0.active }, sort: \Chaine.nom) private var chaines: [Chaine]
    private let profil = ConteneurTV.famille.actif.id
    @State private var reglages = ReglagesLettre.lire(profil: ConteneurTV.famille.actif.id) ?? ReglagesLettre()

    private static let jours = [(2, "Lundi"), (3, "Mardi"), (4, "Mercredi"), (5, "Jeudi"), (6, "Vendredi"), (7, "Samedi"), (1, "Dimanche")]

    var body: some View {
        PageTV(titre: "E-mail de la semaine",
               sousTitre: "L'e-mail part de ton iPhone, de ton iPad ou de ton Mac, avec le compte d'envoi réglé là-bas. Ces choix y arrivent à la prochaine synchronisation.") {
            SectionTV(titre: "Destinataires", explication: "Plusieurs adresses : sépare-les par un point-virgule.") {
                BasculeTV(titre: "Recevoir l'e-mail de la semaine", actif: Binding { reglages.actif } set: { valeur in modifier { $0.actif = valeur } })
                ChampTV(titre: "Adresses", invite: "prenom@exemple.ch", texte: Binding { reglages.destinataires } set: { texte in modifier { $0.destinataires = texte } })
            }
            SectionTV(titre: "Ce que je veux recevoir", explication: "Décochée, une rubrique ne paraît pas dans l'e-mail.") {
                ForEach(ReglagesLettre.Rubrique.allCases) { rubrique in
                    BasculeTV(titre: rubrique.nom, actif: Binding { reglages.veut(rubrique) } set: { _ in
                        modifier { reglages in
                            var choisies = reglages.rubriques ?? Set(ReglagesLettre.Rubrique.allCases)
                            if choisies.contains(rubrique) { choisies.remove(rubrique) } else { choisies.insert(rubrique) }
                            reglages.rubriques = choisies
                        }
                    })
                }
            }
            if reglages.veut(.nouveautes), !abonnements.isEmpty {
                SectionTV(titre: "Nouveautés de quelles plateformes", explication: "Rien de coché : toutes celles de tes abonnements.") {
                    ForEach(abonnements, id: \.providerID) { abonnement in
                        BasculeTV(titre: abonnement.nom, actif: Binding { reglages.plateformes?.contains(abonnement.providerID) ?? false } set: { _ in
                            modifier { reglages in
                                var choisies = reglages.plateformes ?? []
                                if choisies.contains(abonnement.providerID) { choisies.remove(abonnement.providerID) } else { choisies.insert(abonnement.providerID) }
                                reglages.plateformes = choisies
                            }
                        })
                    }
                }
            }
            if reglages.veut(.passagesTele), !chaines.isEmpty {
                SectionTV(titre: "Passages sur quelles chaînes", explication: "Rien de coché : toutes tes chaînes.") {
                    ForEach(chaines, id: \.identifiantGuide) { chaine in
                        BasculeTV(titre: chaine.nom, actif: Binding { reglages.chaines?.contains(chaine.nom) ?? false } set: { _ in
                            modifier { reglages in
                                var choisies = reglages.chaines ?? []
                                if choisies.contains(chaine.nom) { choisies.remove(chaine.nom) } else { choisies.insert(chaine.nom) }
                                reglages.chaines = choisies
                            }
                        })
                    }
                }
            }
            SectionTV(titre: "Quels jours", explication: "Il reste toujours au moins un jour. Un clic sur l'heure avance d'une heure.") {
                ForEach(Self.jours, id: \.0) { numero, nom in
                    BasculeTV(titre: nom, actif: Binding { reglages.joursRetenus.contains(numero) } set: { _ in
                        modifier { reglages in
                            var choisis = reglages.joursRetenus
                            if choisis.contains(numero) {
                                guard choisis.count > 1 else { return }
                                choisis.remove(numero)
                            } else {
                                choisis.insert(numero)
                            }
                            reglages.jours = choisis
                            reglages.jour = choisis.min() ?? numero
                        }
                    })
                }
                LigneTVReglage(titre: "Heure", symbole: "clock", action: { modifier { $0.heure = $0.heure >= 22 ? 6 : $0.heure + 1 } }) {
                    BoutTV(forme: .valeur("\(reglages.heure) h"))
                }
            }
        }
    }

    private func modifier(_ changement: (inout ReglagesLettre) -> Void) {
        changement(&reglages)
        UserDefaults.standard.set(try? JSONEncoder().encode(reglages), forKey: ReglagesLettre.cle(profil: profil))
    }
}

/// Préférences › Tes alertes à venir : les rendez-vous de tes titres, calculés sur la TV comme sur l'iPhone.
struct PageAlertesAVenirTV: View {
    @Query private var echeances: [Echeance]

    init() {
        let maintenant = Date.now.addingTimeInterval(-3600)
        _echeances = Query(filter: #Predicate<Echeance> { $0.date >= maintenant }, sort: \Echeance.date)
    }

    var body: some View {
        PageTV(titre: "Tes alertes à venir",
               sousTitre: "Nouveaux épisodes, sorties et passages à la TV des titres que tu suis. Ton iPhone te prévient le moment venu.") {
            SectionTV {
                if echeances.isEmpty {
                    LigneTVReglage(titre: "Rien de prévu pour l'instant", symbole: "bell.slash")
                }
                ForEach(echeances.prefix(60)) { echeance in
                    NavigationLink(value: echeance.reference) {
                        LigneTVReglage(titre: echeance.titre,
                                       detail: [echeance.libelle, echeance.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()
                                           .locale(Locale(identifier: "fr_CH")))].filter { !$0.isEmpty }.joined(separator: " · "),
                                       symbole: symbole(echeance.nature)) { BoutTV(forme: .chevron) }
                    }
                    .buttonStyle(LigneTV())
                }
            }
        }
    }

    private func symbole(_ nature: EcheancePrevue.Nature) -> String {
        switch nature {
        case .episode, .saison: "play.tv"
        case .sortie: "sparkles"
        case .tele: "tv"
        }
    }
}
