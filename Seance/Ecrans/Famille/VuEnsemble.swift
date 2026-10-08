import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// « Vu avec qui ? » (6.1) : un film terminé, un épisode regardé à plusieurs s'inscrit aussi chez les autres personnes
/// de la famille — dans leurs Terminés, hors de leur « À voir » —, directement, sans leur demander. Leur magasin est
/// ouvert le temps de l'inscription, puis leur sous-dossier de synchronisation part tout de suite vers leurs appareils.
struct DemandeAvecQui: Identifiable {
    let id = UUID()
    let reference: ReferenceTitre
    let titre: String
    /// Ce qui s'inscrit chez chacun : le même geste que chez soi, sur son magasin à lui.
    let inscrire: @MainActor (ModelContext) async throws -> Void
}

@MainActor
enum VuEnsemble {
    /// La demande n'a de sens que dans une maison à plusieurs profils.
    static func demander(_ etat: EtatApp, reference: ReferenceTitre, titre: String, inscrire: @escaping @MainActor (ServiceSuivi) throws -> Void) {
        demander(etat, reference: reference, titre: titre, surLeMagasin: { contexte in try inscrire(ServiceSuivi(contexte: contexte)) })
    }

    /// 8.2 : un geste qui a besoin d'attendre — lire la fiche TMDB d'un épisode, par exemple — au bout d'une lecture,
    /// après « Vu aujourd'hui » dans le menu d'une carte, ou au retour d'une plateforme.
    static func demander(_ etat: EtatApp, reference: ReferenceTitre, titre: String,
                         surLeMagasin inscrire: @escaping @MainActor (ModelContext) async throws -> Void) {
        guard ProfilsFamille().aPlusieursProfils else { return }
        etat.avecQui = DemandeAvecQui(reference: reference, titre: titre, inscrire: inscrire)
    }

    /// Inscrit chez chaque personne choisie, retire le titre de sa soirée, puis synchronise son sous-dossier. Renvoie
    /// les prénoms chez qui l'inscription a réussi.
    static func inscrire(_ demande: DemandeAvecQui, chez profils: [ProfilFamille], etat: EtatApp) async -> [String] {
        var inscrits: [String] = []
        for profil in profils {
            guard let conteneur = ConteneurApp.conteneur(de: profil) else { continue }
            let contexte = conteneur.mainContext
            do {
                try await demande.inscrire(contexte)
                if demande.reference.type == .film { try? ServiceSoiree(contexte: contexte).retirer(demande.reference) }
                try contexte.save()
                inscrits.append(QuiRegardeActuel.nomDe(profil))
            } catch {
                etat.journal.noter(.general, "« \(demande.titre) » n'a pas pu s'inscrire chez \(QuiRegardeActuel.nomDe(profil)).", erreur: error)
                continue
            }
            // Ses appareils l'apprennent tout de suite : son sous-dossier, avec ses repères à lui.
            await EtatSynchro(profil: profil).synchroniser(etat: etat, contexte: contexte, pourUnAutre: true)
        }
        return inscrits
    }
}

/// La feuille : les autres personnes de la famille, cochées d'office si elles sont dans « Qui regarde ce soir ? ».
struct FeuilleAvecQui: View {
    let demande: DemandeAvecQui

    @Environment(EtatApp.self) private var etat
    @Environment(\.dismiss) private var fermer
    @State private var choisis: Set<String> = []
    @State private var enCours = false

    private var autres: [ProfilFamille] {
        let famille = ProfilsFamille()
        return famille.profils.filter { $0.id != famille.actif.id }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("« \(demande.titre) » compte aussi comme vu chez eux, et quitte leur liste « À voir ».")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Flux(espacement: 10) {
                    ForEach(autres) { profil in
                        let coche = choisis.contains(profil.id)
                        Button {
                            if coche { choisis.remove(profil.id) } else { choisis.insert(profil.id) }
                        } label: {
                            Label(QuiRegardeActuel.nomDe(profil), systemImage: coche ? "checkmark.circle.fill" : profil.symbole)
                                .font(.headline)
                                .foregroundStyle(coche ? Color.black : Color.primary)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(coche ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(Theme.surface), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(QuiRegardeActuel.nomDe(profil)) l'a vu aussi")
                        .accessibilityAddTraits(coche ? .isSelected : [])
                    }
                }
                Spacer(minLength: 0)
                Button {
                    Task { await valider() }
                } label: {
                    EtiquetteGrandBouton(symbole: "person.2.fill", texte: choisis.isEmpty ? "Juste moi" : "Aussi chez \(nomsChoisis)")
                }
                .buttonStyle(.plain)
                .disabled(enCours)
                .accessibilityIdentifier("validerAvecQui")
            }
            .padding(20)
            .background(Theme.fond)
            .titreDeFeuille("Qui regarde avec toi ?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Juste moi") { fermer() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.fond)
        .onAppear {
            let invites = Set(etat.invitesDuSoir.map(\.id))
            choisis = Set(autres.map(\.id).filter { invites.contains($0) })
        }
    }

    private var nomsChoisis: String {
        ListFormatter.localizedString(byJoining: autres.filter { choisis.contains($0.id) }.map(QuiRegardeActuel.nomDe))
    }

    private func valider() async {
        guard !choisis.isEmpty else { return fermer() }
        enCours = true
        let profils = autres.filter { choisis.contains($0.id) }
        let inscrits = await VuEnsemble.inscrire(demande, chez: profils, etat: etat)
        fermer()
        if !inscrits.isEmpty {
            etat.confirmer("Aussi chez \(ListFormatter.localizedString(byJoining: inscrits))", symbole: "person.2.fill")
        }
    }
}
