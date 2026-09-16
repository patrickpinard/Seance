import SwiftUI

/// Une version de Séance et ce qu'elle apporte, vu de haut. La plus récente en premier ;
/// son numéro doit correspondre à `MARKETING_VERSION` dans `project.yml`.
struct NoteVersion: Identifiable {
    struct Fonctionnalite: Identifiable {
        let symbole: String
        let titre: String
        let detail: String

        var id: String { titre }
    }

    let numero: String
    let date: String
    let resume: String
    let fonctionnalites: [Fonctionnalite]

    var id: String { numero }

    static let historique: [NoteVersion] = [
        NoteVersion(
            numero: "1.2",
            date: "17 septembre 2026",
            resume: "Statistiques et bilan de l'année, widgets, Siri, fiche acteur et premier lancement guidé.",
            fonctionnalites: [
                Fonctionnalite(symbole: "chart.bar.fill", titre: "Statistiques",
                               detail: "Heures regardées, mois par mois, acteurs et genres favoris, plus grosse soirée ; le bilan de l'année en cartes à partager."),
                Fonctionnalite(symbole: "square.grid.2x2.fill", titre: "Widgets",
                               detail: "Ma soirée, prochains épisodes à cocher d'un ✓ et À venir, sur l'écran d'accueil et l'écran verrouillé."),
                Fonctionnalite(symbole: "mic.fill", titre: "Siri et Raccourcis",
                               detail: "« Qu'est-ce que je regarde ce soir avec Séance ? » et « Ajoute Reacher à ma soirée dans Séance »."),
                Fonctionnalite(symbole: "person.crop.rectangle.stack", titre: "Fiche acteur",
                               detail: "Sa filmographie avec ce que tu as vu, ce qui reste et ce qui est regardable ce soir."),
                Fonctionnalite(symbole: "hand.wave.fill", titre: "Premier lancement",
                               detail: "Plateformes, genres préférés et une dizaine de films à noter : les suggestions sont justes dès le départ."),
                Fonctionnalite(symbole: "checkmark.circle", titre: "Après le NAS",
                               detail: "De retour d'Infuse ou de VLC, Séance propose de marquer le film ou l'épisode comme vu."),
                Fonctionnalite(symbole: "moon.stars", titre: "Ce soir allégé",
                               detail: "La page se concentre sur ta soirée, tes épisodes et ta liste ; la recherche d'un titre se fait dans Explorer."),
            ]
        ),
        NoteVersion(
            numero: "1.1",
            date: "17 septembre 2026",
            resume: "Suivi des séries, alertes complètes et version Mac.",
            fonctionnalites: [
                Fonctionnalite(symbole: "checklist", titre: "Épisodes",
                               detail: "Cases à cocher par saison, « vu jusqu'ici », notes, prochain épisode à regarder et progression."),
                Fonctionnalite(symbole: "bell.badge.fill", titre: "Alertes",
                               detail: "Cloche sur chaque fiche : annonce d'une saison ou d'une sortie, la veille, le jour même, arrivée sur tes plateformes ou en location, passages à la télé."),
                Fonctionnalite(symbole: "calendar", titre: "À venir",
                               detail: "Le calendrier des prochains épisodes, sorties et passages télé de tes titres surveillés."),
                Fonctionnalite(symbole: "play.tv", titre: "Accueil par plateforme",
                               detail: "Choisir Netflix ou Prime Video filtre les nouveautés, les titres populaires et les suggestions ; « Tout voir » ouvre chaque liste complète."),
                Fonctionnalite(symbole: "list.bullet.rectangle", titre: "Mes listes",
                               detail: "Glisser pour marquer terminé, retirer ou couper les alertes ; progression et prochaine date sur chaque titre."),
                Fonctionnalite(symbole: "desktopcomputer", titre: "Version Mac",
                               detail: "La même app sur le Mac, avec lecture directe des films du NAS monté."),
                Fonctionnalite(symbole: "stethoscope", titre: "Journal",
                               detail: "Les problèmes rencontrés, expliqués simplement avec ce que tu peux faire, dans À propos."),
            ]
        ),
        NoteVersion(
            numero: "1.0",
            date: "16 septembre 2026",
            resume: "Première version stable : NAS, Explorer et fiches fiabilisés à l'usage sur l'iPhone.",
            fonctionnalites: [
                Fonctionnalite(symbole: "externaldrive.fill", titre: "NAS fiable",
                               detail: "Dossiers retrouvés quelle que soit l'écriture des accents, accès au réseau local demandé proprement, bibliothèque relue dès que les réglages changent."),
                Fonctionnalite(symbole: "line.3.horizontal.decrease", titre: "Explorer vérifié",
                               detail: "Chaque filtre réduit bien les résultats ; NAS, télé et titres vus partent de ta liste."),
                Fonctionnalite(symbole: "calendar", titre: "Nouveautés datées",
                               detail: "Date de sortie des films et des nouveaux épisodes du jour ou de la semaine."),
                Fonctionnalite(symbole: "circle.grid.2x1.fill", titre: "Actions en icônes",
                               detail: "À voir, vu, bande-annonce, lecture : des boutons compacts partout."),
                Fonctionnalite(symbole: "info.circle", titre: "Versions",
                               detail: "L'historique des versions et de leurs fonctionnalités, ici même."),
            ]
        ),
        NoteVersion(
            numero: "0.9",
            date: "16 septembre 2026",
            resume: "Première version complète à l'essai sur l'iPhone de Patrick.",
            fonctionnalites: [
                Fonctionnalite(symbole: "house.fill", titre: "Accueil",
                               detail: "Tendances, nouveautés du jour et de la semaine, action sur tes plateformes, idées « Pour toi », télé du soir et aperçu du NAS."),
                Fonctionnalite(symbole: "sparkles", titre: "Ce soir",
                               detail: "Des suggestions selon ton envie et tes goûts, toutes vérifiées dans TMDB, avec Claude en option."),
                Fonctionnalite(symbole: "magnifyingglass", titre: "Explorer",
                               detail: "Recherche de films, séries et personnes, filtres détaillés et filtres enregistrés."),
                Fonctionnalite(symbole: "film", titre: "Fiches",
                               detail: "Où regarder en Suisse, bandes-annonces en streaming, casting et lecture depuis le NAS."),
                Fonctionnalite(symbole: "bookmark.fill", titre: "Mes listes",
                               detail: "Titres à voir, en cours et terminés."),
                Fonctionnalite(symbole: "tv.fill", titre: "Télévision",
                               detail: "Programmes de la RTS et des chaînes françaises, reconnus dans TMDB."),
                Fonctionnalite(symbole: "externaldrive.fill", titre: "NAS",
                               detail: "Bibliothèque du Synology lue en SMB, films reconnus, lecture dans Infuse ou VLC."),
                Fonctionnalite(symbole: "gearshape.fill", titre: "Réglages",
                               detail: "Classés par thème ; données sur l'iPhone, clés et mots de passe dans le trousseau."),
            ]
        ),
    ]
}

/// Onglet « Versions » d'À propos : une ligne repliable par version, toutes fermées au départ
/// pour garder la page courte.
struct ListeVersions: View {
    let versionInstallee: String

    @State private var ouvertes: Set<String> = []

    var body: some View {
        Section {
            ForEach(NoteVersion.historique) { version in
                DisclosureGroup(isExpanded: Binding(
                    get: { ouvertes.contains(version.numero) },
                    set: { ouverte in
                        if ouverte { ouvertes.insert(version.numero) } else { ouvertes.remove(version.numero) }
                    }
                )) {
                    ForEach(version.fonctionnalites) { fonctionnalite in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: fonctionnalite.symbole)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 28, height: 28)
                                .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fonctionnalite.titre).font(.subheadline.weight(.semibold))
                                Text(fonctionnalite.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } label: {
                    entete(version)
                }
                .tint(Theme.accent)
            }
        } footer: {
            Text("Touche une version pour voir ce qu'elle apporte.")
        }
    }

    private func entete(_ version: NoteVersion) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Version \(version.numero)").font(.headline)
                if version.numero == versionInstallee {
                    Text("installée")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(.black)
                }
                Spacer()
                Text(version.date).font(.caption).foregroundStyle(.secondary)
            }
            Text(version.resume)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
