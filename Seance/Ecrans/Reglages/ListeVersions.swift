import SwiftUI

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
                                .font(.subheadline.weight(.semibold))
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
            // 8.1 : le jour et l'heure de son arrivée sur cet appareil.
            if let installee = InstallationsVersions.libelle(version.numero) {
                Label(installee, systemImage: "arrow.down.circle").font(.caption).foregroundStyle(.secondary)
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
