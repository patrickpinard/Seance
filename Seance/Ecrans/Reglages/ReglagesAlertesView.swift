import SeanceKit
import SwiftData
import SwiftUI
import UserNotifications

/// Réglages des alertes pop-up (EF-81 à EF-85) : autorisation, heure, types, rappel TV et essai.
struct ReglagesAlertesView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.openURL) private var openURL
    @State private var essaiEnvoye = false
    @State private var essaiAilleurs: String?
    /// Essai pour l'Apple Watch : le compte à rebours, et ce qui bloque dans les réglages d'iOS.
    @State private var secondesMontre: Int?
    @State private var obstaclesMontre: [String] = []

    private var alertes: EtatAlertes { etat.alertes }

    var body: some View {
        Form {
            Section {
                switch alertes.autorisation {
                case .authorized, .provisional, .ephemeral:
                    LabeledContent("Alertes", value: "Activées")
                case .denied:
                    Text("Les alertes de Séance sont désactivées dans iOS.")
                    Button("Ouvrir les réglages d'iOS") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                default:
                    Button("Activer les alertes") {
                        Task {
                            await alertes.demanderAutorisation()
                            await alertes.planifier(contexte: contexte, tmdb: etat.tmdb)
                        }
                    }
                }
                Button(essaiEnvoye ? "Alerte d'essai envoyée : elle arrive dans 5 secondes" : "Envoyer une alerte d'essai") {
                    Task {
                        await alertes.envoyerEssai()
                        essaiEnvoye = true
                    }
                }
                .disabled(alertes.autorisation == .denied)
                // Depuis l'iPad ou le Mac : faire sonner l'iPhone (et l'Apple Watch), par les dossiers de synchronisation.
                if etat.synchro.estPrete(nas: etat.nas.estConfigure) {
                    Button(essaiAilleurs ?? "Tester sur mes autres appareils") {
                        Task {
                            let depots = await etat.synchro.demanderEssaiAilleurs(etat: etat)
                            essaiAilleurs = depots.isEmpty ? "La demande n'a pas pu être déposée"
                                : "Demande déposée (\(depots.joined(separator: ", "))) : ouvre Séance sur l'autre appareil"
                        }
                    }
                }
            } footer: {
                Text("Les alertes s'affichent en pop-up, même quand Séance est ouverte. Les toucher ouvre la fiche du titre. Pour voir l'essai sur ton Apple Watch : envoie-le, puis verrouille l'iPhone — la montre ne prend le relais que lorsque l'iPhone est verrouillé. « Tester sur mes autres appareils » dépose une demande dans tes dossiers de synchronisation : l'autre appareil prévient dès qu'il ouvre Séance.")
            }

            #if !targetEnvironment(macCatalyst)
            Section {
                ForEach(obstaclesMontre, id: \.self) { obstacle in
                    Label(obstacle, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                }
                if !obstaclesMontre.isEmpty {
                    Button("Ouvrir les réglages de notification de Séance") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
                Button {
                    Task {
                        await alertes.envoyerEssaiMontre()
                        for reste in stride(from: Int(EtatAlertes.delaiEssaiMontre), through: 0, by: -1) {
                            secondesMontre = reste
                            try? await Task.sleep(for: .seconds(1))
                        }
                        secondesMontre = nil
                    }
                } label: {
                    Label(secondesMontre.map { "Verrouille l'iPhone maintenant · \($0) s" } ?? "Tester sur l'Apple Watch", systemImage: "applewatch")
                }
                .disabled(secondesMontre != nil || alertes.autorisation == .denied)
                .accessibilityIdentifier("essaiMontre")
            } header: {
                Text("Apple Watch")
            } footer: {
                Text("iOS ne transmet une alerte à la montre que si l'iPhone est verrouillé ou en veille : en main, il la garde pour lui. C'est pour cela qu'un essai immédiat n'arrive jamais au poignet. Touche « Tester », verrouille l'iPhone, et attends vingt secondes, la montre au poignet et déverrouillée. Si rien n'arrive : dans l'app Watch de l'iPhone › Notifications, active « Séance » sous « Recopier les alertes de l'iPhone », et vérifie qu'aucun mode de concentration (Ne pas déranger, Repos) n'est actif.")
            }
            .task { obstaclesMontre = await alertes.obstaclesMontre() }
            #endif

            Section {
                DatePicker("Heure des alertes", selection: Binding {
                    alertes.reglages.fuseau.date(heure: alertes.reglages.heure, minute: alertes.reglages.minute)
                } set: { date in
                    var calendrier = Calendar(identifier: .gregorian)
                    calendrier.timeZone = alertes.reglages.fuseau
                    let composants = calendrier.dateComponents([.hour, .minute], from: date)
                    alertes.modifier { $0.heure = composants.hour ?? 18; $0.minute = composants.minute ?? 0 }
                }, displayedComponents: .hourAndMinute)
            } footer: {
                Text("Nouveaux épisodes, sorties et passages à la TV sont annoncés le jour même, à cette heure-là.")
            }

            Section {
                ForEach(ReglagesAlertes.typesProposes, id: \.self) { type in
                    Toggle(type.libelle, isOn: Binding {
                        alertes.reglages.typesActifs.contains(type)
                    } set: { actif in
                        alertes.modifier { reglages in
                            if actif { reglages.typesActifs.insert(type) } else { reglages.typesActifs.remove(type) }
                        }
                    })
                    .tint(Theme.accent)
                }
                Toggle("La veille aussi", isOn: Binding { alertes.reglages.veille } set: { valeur in alertes.modifier { $0.veille = valeur } })
                    .tint(Theme.accent)
                Toggle("Dès qu'une saison ou une sortie est annoncée", isOn: Binding { alertes.reglages.annonces } set: { valeur in alertes.modifier { $0.annonces = valeur } })
                    .tint(Theme.accent)
                if alertes.reglages.typesActifs.contains(.diffusionTele) {
                    Stepper(value: Binding {
                        Int(alertes.reglages.rappelAvantDiffusion / 60)
                    } set: { minutes in
                        alertes.modifier { $0.rappelAvantDiffusion = TimeInterval(minutes * 60) }
                    }, in: 5...60, step: 5) {
                        LabeledContent("Rappel avant la diffusion", value: "\(Int(alertes.reglages.rappelAvantDiffusion / 60)) min")
                    }
                }
                // Ce que Séance a déjà envoyé, et ce qu'elle enverra (6.5) : une notification balayée ne laissait
                // aucune trace, et on ne pouvait plus retrouver le titre.
                NavigationLink(value: DestinationReglage.alertesRecues) {
                    Label("Alertes reçues", systemImage: "bell.badge.waveform")
                }
            } header: {
                Text("Me prévenir pour")
            } footer: {
                Text("Pour les titres dont la cloche 🔔 est activée sur la fiche. La cloche s'active quand tu ajoutes un titre ; une série peut ne prévenir qu'aux nouvelles saisons.")
            }

            Section {
                if alertes.enCours {
                    HStack {
                        Text("Calcul des alertes…")
                        Spacer()
                        ProgressView()
                    }
                }
                if !alertes.autorisees, alertes.autorisation != .notDetermined {
                    Text("Les alertes sont désactivées dans iOS : elles sont calculées mais ne s'afficheront pas.")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if alertes.prochaines.isEmpty, !alertes.enCours {
                    Text("Aucune alerte prévue pour l'instant.").foregroundStyle(.secondary)
                }
                ForEach(Array(alertes.prochaines.prefix(10).enumerated()), id: \.offset) { _, notification in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notification.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accentClair)
                        Text(notification.titre).font(.subheadline.weight(.semibold))
                        Text(notification.corps).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                if let erreur = alertes.erreur {
                    Label(erreur, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Mettre à jour maintenant") {
                    Task { await alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
                }
                .disabled(alertes.enCours || etat.tmdb == nil)
            } header: {
                Text("Prochaines alertes")
            }
        }
        .pageReglages("Alertes")
        .task { await alertes.actualiserAutorisation() }
        // Heure ou types modifiés : les alertes en attente sont recalculées en quittant la page.
        .onDisappear {
            Task { await alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
        }
    }
}

private extension TimeZone {
    /// Aujourd'hui à l'heure donnée, pour le sélecteur d'heure.
    func date(heure: Int, minute: Int) -> Date {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = self
        return calendrier.date(bySettingHour: heure, minute: minute, second: 0, of: .now) ?? .now
    }
}

/// Là où une alerte est attendue (cloche d'une fiche, acteurs suivis, À venir) : si les notifications de Séance
/// sont coupées, c'est dit tout de suite, avec de quoi les rallumer. Rien ne s'affiche quand elles marchent.
struct BandeauAlertesCoupees: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.openURL) private var openURL

    var body: some View {
        let autorisation = etat.alertes.autorisation
        if !etat.alertes.autorisees {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.slash.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Les notifications de Séance sont coupées")
                        .font(.subheadline.weight(.semibold))
                    Text("Aucune alerte ne partira : sorties, épisodes, passages à la TV et nouveaux films des acteurs suivis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if autorisation == .denied {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        } else {
                            Task {
                                await etat.alertes.demanderAutorisation()
                                await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb)
                            }
                        }
                    } label: {
                        // Un lien d'une ligne : il répond sur 44 points de haut (audit d'accessibilité).
                        Text(autorisation == .denied ? "Ouvrir les réglages des notifications" : "Activer les notifications").zoneDeToucher()
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(Theme.accentClair)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
            .task { await etat.alertes.actualiserAutorisation() }
        }
    }
}
