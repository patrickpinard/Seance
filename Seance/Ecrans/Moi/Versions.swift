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
                               detail: "Titres à voir et suivi des séries épisode par épisode."),
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

/// Onglet « Versions » d'À propos : une section par version, la version installée signalée.
struct ListeVersions: View {
    let versionInstallee: String

    var body: some View {
        ForEach(NoteVersion.historique) { version in
            Section {
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
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Version \(version.numero)").font(.headline).foregroundStyle(.primary)
                    if version.numero == versionInstallee {
                        Text("installée")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    Spacer()
                    Text(version.date).font(.caption)
                }
                .textCase(nil)
            } footer: {
                Text(version.resume)
            }
        }
    }
}
