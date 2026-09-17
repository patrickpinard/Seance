import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// EF-67 : « ★ 8 » à côté de la note TMDB dans l'en-tête de la fiche, dès qu'une note est donnée.
struct BadgeTaNote: View {
    @Query private var suivis: [Suivi]

    init(reference: ReferenceTitre) {
        let id = reference.tmdbID
        let type = reference.type.rawValue
        _suivis = Query(filter: #Predicate<Suivi> { $0.tmdbID == id && $0.typeBrut == type })
    }

    var body: some View {
        if let note = suivis.first?.note {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: "star.fill").font(.caption.weight(.bold))
                    Text("\(note)").font(.title3.weight(.heavy))
                    Text("/10").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                .foregroundStyle(Theme.accentClair)
                Text("Ta note").font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ta note : \(note) sur 10")
        }
    }
}

/// Ta note du film ou de la série, dès qu'il est vu : le signal le plus sûr pour les goûts (EF-61).
/// Au-dessus de 6, Séance propose davantage de titres des mêmes genres et avec les mêmes acteurs ; en dessous, moins.
struct NoteTitre: View {
    let fiche: FicheAffichee

    @Environment(\.modelContext) private var contexte
    @Query private var suivis: [Suivi]
    @Query private var visionnages: [Visionnage]

    init(fiche: FicheAffichee) {
        self.fiche = fiche
        let id = fiche.reference.tmdbID
        let type = fiche.reference.type.rawValue
        _suivis = Query(filter: #Predicate<Suivi> { $0.tmdbID == id && $0.typeBrut == type })
        _visionnages = Query(filter: #Predicate<Visionnage> { $0.tmdbID == id && $0.typeBrut == type })
    }

    private var note: Int? {
        suivis.first?.note
    }

    /// Vu, même en partie pour une série, ou noté au premier lancement.
    private var vu: Bool {
        !visionnages.isEmpty || suivis.first?.statut == .termine
    }

    var body: some View {
        if vu {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(fiche.serie == nil ? "Ta note du film" : "Ta note de la série")
                        .font(.headline)
                    Spacer()
                    if note != nil {
                        Button("Effacer") { noter(nil) }
                            .font(.subheadline)
                            .tint(.secondary)
                    }
                }
                // Dix notes d'un geste, comme au premier lancement : 1 à gauche, 10 à droite.
                HStack(spacing: 5) {
                    ForEach(1...10, id: \.self) { valeur in
                        let choisie = valeur == note
                        Button { noter(choisie ? nil : valeur) } label: {
                            Text("\(valeur)")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .foregroundStyle(choisie ? Color.black : Color.primary)
                                .background(choisie ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(Theme.surface),
                                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Note \(valeur) sur 10")
                        .accessibilityAddTraits(choisie ? .isSelected : [])
                    }
                }
                .sensoryFeedback(.selection, trigger: note)
                Text(explication)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
        }
    }

    private var explication: String {
        let genres = fiche.genres.prefix(2).joined(separator: " et ").lowercased()
        let deCeGenre = genres.isEmpty ? "de ce genre" : "de type \(genres)"
        switch note {
        case nil: return "Note-le : Séance en déduit tes goûts et te propose des films et des séries du même type."
        case let n? where n >= 7: return "Séance te proposera davantage de titres \(deCeGenre), et avec ces acteurs."
        case let n? where n <= 5: return "Séance te proposera moins de titres \(deCeGenre)."
        default: return "Une note moyenne : elle ne change presque rien à tes goûts."
        }
    }

    private func noter(_ valeur: Int?) {
        let service = ServiceSuivi(contexte: contexte)
        if let film = fiche.film {
            try? service.noter(film: film, note: valeur)
        } else if let serie = fiche.serie {
            try? service.noter(serie: serie, note: valeur)
        }
    }
}
