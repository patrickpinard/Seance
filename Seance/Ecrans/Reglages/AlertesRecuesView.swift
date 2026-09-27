import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Les alertes que Séance a envoyées (6.5) : une notification disparaît de l'écran verrouillé dès qu'on la balaie,
/// et il n'en restait aucune trace. Cette page les garde, la plus récente d'abord, et chacune ouvre la fiche du
/// titre — c'est là que se trouve « plus d'informations ».
///
/// Chaque appareil garde les siennes : ce sont ses propres notifications. L'iPhone prévient, le Mac et l'Apple TV
/// ont leur propre liste.
struct AlertesRecuesView: View {
    @Environment(EtatApp.self) private var etat
    @Query(sort: \AlertePlanifiee.date, order: .reverse) private var alertes: [AlertePlanifiee]
    /// La purge (8.2.11) : les alertes effacées sont masquées, pas détruites — Séance s'en sert pour ne pas prévenir
    /// deux fois de la même chose. « Tout effacer » masque tout ce qui a été reçu jusqu'ici.
    @AppStorage("alertes.effaceesAvant") private var effaceesAvant: Double = 0
    @AppStorage("alertes.effacees") private var effaceesBrut = ""
    @State private var confirmerToutEffacer = false

    private var effacees: Set<String> { Set(effaceesBrut.split(separator: "\n").map(String.init)) }

    private static func cle(_ alerte: AlertePlanifiee) -> String {
        "\(alerte.typeBrut)|\(alerte.tmdbID)|\(alerte.motif)|\(Int(alerte.date.timeIntervalSince1970))"
    }

    /// Ce qui a vraiment été envoyé, et pas les rendez-vous encore à venir ; sans ce qui a été effacé.
    private var envoyees: [AlertePlanifiee] {
        let effacees = effacees
        return alertes.filter {
            $0.envoyee && $0.date <= .now && $0.date.timeIntervalSince1970 > effaceesAvant && !effacees.contains(Self.cle($0))
        }
    }

    private func effacer(_ alerte: AlertePlanifiee) {
        var liste = effacees
        liste.insert(Self.cle(alerte))
        withAnimation { effaceesBrut = liste.joined(separator: "\n") }
    }

    private var aVenir: [AlertePlanifiee] {
        alertes.filter { !$0.envoyee && $0.date > .now }.reversed()
    }

    var body: some View {
        Group {
            if envoyees.isEmpty, aVenir.isEmpty {
                EtatVide(symbole: "bell.slash", titre: "Aucune alerte pour l'instant",
                         message: "Les alertes arrivent pour les titres dont la cloche est activée sur la fiche : sorties, nouveaux épisodes, passages à la TV.",
                         libelleAction: "Régler les alertes", symboleAction: "bell.badge") { etat.ongletDemande = .reglages }
            } else {
                List {
                    if !aVenir.isEmpty {
                        Section {
                            ForEach(aVenir) { alerte in ligne(alerte, prevue: true) }
                        } header: {
                            Text("Prévues")
                        } footer: {
                            Text("Séance te préviendra à ces dates, si la cloche du titre reste activée.")
                        }
                    }
                    if !envoyees.isEmpty {
                        Section {
                            ForEach(envoyees) { alerte in
                                ligne(alerte, prevue: false)
                                    .swipeActions(edge: .trailing) {
                                        Button("Effacer", role: .destructive) { effacer(alerte) }
                                    }
                            }
                        } header: {
                            Text("Reçues")
                        } footer: {
                            Text("Toutes les alertes que cet appareil a envoyées, pour chaque personne de la famille. Glisse une ligne vers la gauche pour l'effacer.")
                        }
                    }
                }
            }
        }
        .pageReglages("Alertes reçues")
        .toolbar {
            if !envoyees.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tout effacer", role: .destructive) { confirmerToutEffacer = true }
                }
            }
        }
        .confirmationDialog("Effacer les alertes reçues ?", isPresented: $confirmerToutEffacer, titleVisibility: .visible) {
            Button("Tout effacer", role: .destructive) {
                withAnimation {
                    effaceesAvant = Date.now.timeIntervalSince1970
                    effaceesBrut = ""
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La liste se vide ; les alertes à venir restent prévues.")
        }
    }

    @ViewBuilder
    private func ligne(_ alerte: AlertePlanifiee, prevue: Bool) -> some View {
        let reference = ReferenceTitre(type: TypeTitre(rawValue: alerte.typeBrut) ?? .film, tmdbID: alerte.tmdbID)
        NavigationLink(value: reference) {
            HStack(spacing: 12) {
                Image(systemName: Self.symbole(alerte.motif))
                    .font(.title3)
                    .foregroundStyle(prevue ? Color.secondary : Theme.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(alerte.titre.isEmpty ? Self.libelle(alerte.motif) : alerte.titre)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if !alerte.corps.isEmpty {
                        Text(alerte.corps).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text(alerte.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()
                        .locale(Locale(identifier: "fr_CH"))))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
            .frame(minHeight: 44)
        }
        .accessibilityHint("Ouvre la fiche du titre")
    }

    /// Le motif est écrit par le service d'alertes : « sortie », « episode », « tele »…
    static func symbole(_ motif: String) -> String {
        if motif.contains("tele") { return "tv.fill" }
        if motif.contains("episode") { return "play.tv.fill" }
        if motif.contains("acteur") { return "person.fill" }
        if motif.contains("soiree") { return "moon.stars.fill" }
        return "sparkles"
    }

    static func libelle(_ motif: String) -> String {
        if motif.contains("tele") { return "Passage à la TV" }
        if motif.contains("episode") { return "Nouvel épisode" }
        if motif.contains("acteur") { return "Un acteur que tu suis" }
        if motif.contains("soiree") { return "Ta soirée" }
        return "Sortie"
    }
}
