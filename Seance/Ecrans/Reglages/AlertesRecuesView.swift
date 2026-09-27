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
    @AppStorage(AlertesALire.cleEffaceesAvant) private var effaceesAvant: Double = 0
    @AppStorage(AlertesALire.cleEffacees) private var effaceesBrut = ""
    /// Accusés de réception (8.2.14) : ce qui est lu ne compte plus dans la pastille.
    @AppStorage(AlertesALire.cleLuesAvant) private var luesAvant: Double = 0
    @AppStorage(AlertesALire.cleLues) private var luesBrut = ""
    @State private var confirmerToutEffacer = false

    /// Ce qui a vraiment été envoyé, et pas les rendez-vous encore à venir ; sans ce qui a été effacé.
    private var envoyees: [AlertePlanifiee] {
        AlertesALire.recues(alertes, effaceesAvant: effaceesAvant, effacees: effaceesBrut)
    }

    private var nonLues: Int {
        envoyees.filter { !AlertesALire.estLue($0, luesAvant: luesAvant, lues: luesBrut) }.count
    }

    private func effacer(_ alerte: AlertePlanifiee) {
        withAnimation { effaceesBrut = AlertesALire.ajouter(alerte, a: effaceesBrut) }
    }

    private func marquerLue(_ alerte: AlertePlanifiee) {
        withAnimation { luesBrut = AlertesALire.ajouter(alerte, a: luesBrut) }
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
                                    // Ouvrir l'alerte vaut accusé de réception.
                                    .simultaneousGesture(TapGesture().onEnded { marquerLue(alerte) })
                                    .swipeActions(edge: .trailing) {
                                        Button("Effacer", role: .destructive) { effacer(alerte) }
                                    }
                                    .swipeActions(edge: .leading) {
                                        if !AlertesALire.estLue(alerte, luesAvant: luesAvant, lues: luesBrut) {
                                            Button("Lu") { marquerLue(alerte) }.tint(Theme.accent)
                                        }
                                    }
                            }
                        } header: {
                            Text("Reçues")
                        } footer: {
                            Text("Toutes les alertes que cet appareil a envoyées, pour chaque personne de la famille. Un point orange : pas encore lue — l'ouvrir, ou la glisser vers la droite, en accuse réception. Vers la gauche, elle s'efface.")
                        }
                    }
                }
            }
        }
        .pageReglages("Alertes reçues")
        .toolbar {
            if nonLues > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tout lu") { withAnimation { luesAvant = Date.now.timeIntervalSince1970; luesBrut = "" } }
                }
            }
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
                Spacer(minLength: 0)
                if !prevue, !AlertesALire.estLue(alerte, luesAvant: luesAvant, lues: luesBrut) {
                    Circle().fill(Theme.accent).frame(width: 10, height: 10).accessibilityLabel("Pas encore lue")
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
