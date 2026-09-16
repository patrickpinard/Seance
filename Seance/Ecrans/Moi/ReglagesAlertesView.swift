import SeanceKit
import SwiftData
import SwiftUI
import UserNotifications

/// Réglages des alertes pop-up (EF-81 à EF-85) : autorisation, heure, types, rappel télé et essai.
struct ReglagesAlertesView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.openURL) private var openURL
    @State private var essaiEnvoye = false

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
            } footer: {
                Text("Les alertes s'affichent en pop-up, même quand Séance est ouverte. Les toucher ouvre la fiche du titre.")
            }

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
                Text("Nouveaux épisodes, sorties et passages à la télé sont annoncés le jour même, à cette heure-là.")
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
