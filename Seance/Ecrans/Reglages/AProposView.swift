import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// À propos (EF-44) : l'application, ses sources et les droits d'auteur, et l'historique des versions.
struct AProposView: View {
    @Environment(EtatApp.self) private var etat

    enum Onglet: String, CaseIterable, Identifiable {
        case application = "Séance"
        case versions = "Versions"
        case journal = "Journal"

        var id: String { rawValue }
    }

    @State private var onglet = Onglet.application

    private var numeroVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.9"
    }

    private var version: String {
        let construction = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(numeroVersion) (\(construction))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Séance").font(.title.weight(.heavy))
                    Text(version).font(.footnote).foregroundStyle(.secondary)
                    // Compte Apple gratuit : l'installation expire au bout de 7 jours.
                    if let expiration = etat.expirationInstallation {
                        let bientot = expiration.timeIntervalSinceNow < 2 * 86_400
                        Label("Installation valable jusqu'au \(expiration.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(Locale(identifier: "fr_CH")))) · \(ProfilInstallation.libelle(expiration: expiration))",
                              systemImage: bientot ? "exclamationmark.triangle.fill" : "clock")
                            .font(.footnote.weight(bientot ? .semibold : .regular))
                            .foregroundStyle(bientot ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                            .multilineTextAlignment(.center)
                        if bientot {
                            Text("Relance outils/installer.sh sur le Mac pour prolonger de 7 jours : tes données restent.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    Picker("Onglet", selection: $onglet) {
                        ForEach(Onglet.allCases) { onglet in
                            Text(onglet.rawValue).tag(onglet)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            switch onglet {
            case .application:
                application
            case .versions:
                ListeVersions(versionInstallee: numeroVersion)
            case .journal:
                SectionsJournal()
            }

            Section {
                Text("© 2026 Patrick Pinard. Tous droits réservés.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.fond)
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var application: some View {
        Section("L'application") {
            Text("Séance est ton guide personnel des films et séries d'action. Elle te dit où regarder chaque titre en Suisse : sur tes plateformes, à la télévision ou sur ton NAS, ou comment l'obtenir légalement.")
            Text("Elle suit tes séries épisode par épisode, garde la trace de ce que tu as vu et te prévient des nouvelles saisons, des sorties et des passages à la télé. « Idées pour ce soir » propose des titres regardables sur tes plateformes, choisis selon tes goûts, et « Ma soirée » réunit ce que tu gardes pour ce soir.")
            Text("Tes données restent sur ton appareil. Une sauvegarde dans un fichier, depuis Réglages › Sauvegarde, les protège et permet de les reprendre sur un autre appareil.")
        }

        EspaceUtilise()

        Section("Sources des données") {
            Text("Cette application utilise TMDB et les API de TMDB, mais n'est ni approuvée, ni certifiée, ni validée par TMDB.")
            Text("Disponibilités sur les plateformes : JustWatch.")
            Text("Programmes TV de la RTS et des chaînes françaises : XML TV Fr, projet bénévole.")
            Text("Accès au NAS : AMSMB2 et libsmb2, sous licence LGPL.")
        }
    }
}

/// Espace occupé par Séance, par nature de données, et vidage des images en cache.
private struct EspaceUtilise: View {
    @State private var volumetrie: Volumetrie?
    @State private var enVidage = false

    var body: some View {
        Section {
            if let volumetrie {
                LabeledContent("Application", value: Self.format(volumetrie.application))
                LabeledContent("Tes données", value: Self.format(volumetrie.donnees))
                LabeledContent("Fiches, télé et NAS en cache", value: Self.format(volumetrie.cache))
                LabeledContent("Affiches en cache", value: Self.format(volumetrie.images))
                if volumetrie.divers > 0 {
                    LabeledContent("Widgets et journal", value: Self.format(volumetrie.divers))
                }
                LabeledContent {
                    Text(Self.format(volumetrie.total)).fontWeight(.semibold)
                } label: {
                    Text("Total").fontWeight(.semibold)
                }
                Button("Vider les affiches et les fiches en cache", role: .destructive) {
                    enVidage = true
                    CacheImages.partage.vider()
                    EtatApp.cacheTMDB.vider()
                    Task {
                        self.volumetrie = await Volumetrie.mesurer()
                        enVidage = false
                    }
                }
                .disabled(enVidage || (volumetrie.images == 0 && volumetrie.cache == 0))
            } else {
                HStack {
                    Text("Mesure en cours…").foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
            }
        } header: {
            Text("Espace utilisé")
        } footer: {
            Text("Tes données sont ce que la sauvegarde protège. Le reste se reconstruit tout seul : affiches et fiches se rechargent à l'affichage. Les fiches gardées servent aussi quand tu n'as pas de réseau.")
        }
        .task { volumetrie = await Volumetrie.mesurer() }
    }

    private static func format(_ octets: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: octets, countStyle: .file)
    }
}
