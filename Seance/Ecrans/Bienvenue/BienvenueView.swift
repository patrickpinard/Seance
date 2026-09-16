import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Un goût proposé sur la grille illustrée du premier lancement (EF-60).
struct GoutPropose: Identifiable, Hashable {
    let nom: String
    let symbole: String
    let couleurs: [Color]
    /// Genres TMDB, films et séries confondus.
    let genres: [Int]
    let motsCles: [Int]

    var id: String { nom }

    static let catalogue: [GoutPropose] = [
        GoutPropose(nom: "Action", symbole: "flame.fill", couleurs: [.orange, .red], genres: [28, 10759], motsCles: []),
        GoutPropose(nom: "Thriller", symbole: "eye.fill", couleurs: [.indigo, .black], genres: [53, 9648], motsCles: []),
        GoutPropose(nom: "Policier", symbole: "magnifyingglass", couleurs: [.blue, .indigo], genres: [80], motsCles: []),
        GoutPropose(nom: "Science-fiction", symbole: "sparkles", couleurs: [.cyan, .blue], genres: [878, 10765], motsCles: []),
        GoutPropose(nom: "Aventure", symbole: "map.fill", couleurs: [.green, .teal], genres: [12, 10759], motsCles: []),
        GoutPropose(nom: "Guerre", symbole: "shield.fill", couleurs: [.brown, .gray], genres: [10752, 10768], motsCles: []),
        GoutPropose(nom: "Western", symbole: "sun.dust.fill", couleurs: [.yellow, .brown], genres: [37], motsCles: []),
        GoutPropose(nom: "Fantastique", symbole: "wand.and.stars", couleurs: [.purple, .indigo], genres: [14, 10765], motsCles: []),
        GoutPropose(nom: "Comédie", symbole: "face.smiling.fill", couleurs: [.yellow, .orange], genres: [35], motsCles: []),
        GoutPropose(nom: "Drame", symbole: "theatermasks.fill", couleurs: [.pink, .purple], genres: [18], motsCles: []),
        GoutPropose(nom: "Horreur", symbole: "moon.haze.fill", couleurs: [.red, .black], genres: [27], motsCles: []),
        GoutPropose(nom: "Animation", symbole: "paintpalette.fill", couleurs: [.mint, .teal], genres: [16], motsCles: []),
        GoutPropose(nom: "Arts martiaux", symbole: "figure.martial.arts", couleurs: [.red, .orange], genres: [], motsCles: [779, 780]),
        GoutPropose(nom: "Espionnage", symbole: "binoculars.fill", couleurs: [.gray, .indigo], genres: [], motsCles: [470, 5265]),
        GoutPropose(nom: "Braquage", symbole: "banknote.fill", couleurs: [.green, .black], genres: [], motsCles: [10051, 15363]),
        GoutPropose(nom: "Survie", symbole: "tent.fill", couleurs: [.brown, .green], genres: [], motsCles: [10349]),
        GoutPropose(nom: "Tueur à gages", symbole: "scope", couleurs: [.black, .red], genres: [], motsCles: [2708, 782]),
        GoutPropose(nom: "Super-héros", symbole: "bolt.fill", couleurs: [.blue, .red], genres: [], motsCles: [9715]),
    ]
}

/// Premier lancement (EF-60 à EF-62) : clé TMDB, plateformes, goûts sur une grille illustrée et
/// notation rapide de films connus. Rejouable depuis Moi › Mes goûts, sans les premières étapes.
struct BienvenueView: View {
    enum Mode { case premierLancement, gouts }
    enum Etape: Int, CaseIterable { case bienvenue, cle, plateformes, gouts, notation, fin }

    let mode: Mode
    let terminer: () -> Void

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var etape = Etape.bienvenue
    @State private var choisis: Set<String> = []
    @State private var aNoter: [TitreResume] = []
    @State private var position = 0
    @State private var notes = 0
    @State private var chargementNotation = false

    private var gouts: ServiceGouts { ServiceGouts(contexte: contexte) }

    var body: some View {
        NavigationStack {
            Group {
                switch etape {
                case .bienvenue: bienvenue
                case .cle: ReglagesTMDBView()
                case .plateformes: ReglagesPlateformesView()
                case .gouts: grilleGouts
                case .notation: notation
                case .fin: fin
                }
            }
            .background(Theme.fond.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { barreBas }
            .toolbar {
                if etape != .fin {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(mode == .premierLancement && etape == .bienvenue ? "Plus tard" : "Fermer") { terminer() }
                    }
                }
            }
        }
        .onAppear {
            choisis = (try? gouts.interetsDeclares()) ?? []
            if mode == .gouts { etape = .gouts }
        }
    }

    // MARK: Étapes

    private var bienvenue: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            Text("Bienvenue dans Séance").font(.largeTitle.weight(.heavy)).multilineTextAlignment(.center)
            Text("En une minute : tes plateformes, les genres que tu aimes et quelques films que tu connais. les suggestions « Pour toi » de l'accueil seront justes dès ce soir.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(28)
    }

    private var grilleGouts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Qu'aimes-tu regarder ?").font(.title.weight(.heavy))
                Text("Choisis autant de genres que tu veux. Tu pourras changer d'avis dans Moi › Mes goûts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(GoutPropose.catalogue) { gout in
                        carte(gout)
                    }
                }
            }
            .padding(20)
        }
    }

    private func carte(_ gout: GoutPropose) -> some View {
        let actif = choisis.contains(gout.nom)
        return Button {
            if actif { choisis.remove(gout.nom) } else { choisis.insert(gout.nom) }
        } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: gout.couleurs.map { $0.opacity(actif ? 0.95 : 0.45) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: gout.symbole)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white.opacity(actif ? 0.9 : 0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(14)
                Text(gout.nom)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(14)
            }
            .frame(height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topLeading) {
                if actif {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, Theme.accent)
                        .padding(10)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(actif ? Theme.accent : .clear, lineWidth: 2))
            .scaleEffect(actif ? 1 : 0.97)
            .animation(.snappy, value: actif)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(actif ? .isSelected : [])
    }

    @ViewBuilder
    private var notation: some View {
        if chargementNotation {
            ProgressView("Films connus dans tes genres…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if position < aNoter.count {
            let titre = aNoter[position]
            VStack(spacing: 16) {
                Text("As-tu vu ce film ?").font(.title2.weight(.heavy))
                Text(notes == 0 ? "Aucun film noté pour l'instant · une dizaine suffit" : "\(notes) noté\(notes > 1 ? "s" : "") · une dizaine suffit")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ImageDistante(url: ImageTMDB.url(titre.cheminAffiche, .afficheGrande), coins: 18)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(maxHeight: 330)
                    .shadow(radius: 20)
                    .id(titre.reference)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                Text(titre.titre).font(.title3.weight(.bold)).multilineTextAlignment(.center)
                Text(titre.date.map { String($0.annee) } ?? "").font(.subheadline).foregroundStyle(.secondary)

                // Dix notes d'un geste : 1 à gauche, 10 à droite.
                HStack(spacing: 5) {
                    ForEach(1...10, id: \.self) { note in
                        Button {
                            noter(titre, note)
                        } label: {
                            Text("\(note)")
                                .font(.subheadline.weight(.bold))
                                .frame(width: 30, height: 38)
                                .foregroundStyle(note >= 7 ? Color.black : Color.primary)
                                .background(note >= 7 ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(Theme.surface),
                                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Note \(note) sur 10")
                    }
                }
                Button("Je ne l'ai pas vu") { suivant() }
                    .font(.subheadline.weight(.semibold))
                    .tint(.secondary)
            }
            .padding(20)
            .animation(.snappy, value: position)
        } else {
            ContentUnavailableView("C'est noté", systemImage: "checkmark.seal.fill",
                                   description: Text(aNoter.isEmpty ? "Aucun film à noter pour l'instant." : "Tu as parcouru tous les films proposés."))
        }
    }

    private var fin: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(Theme.accent)
            Text("C'est prêt !").font(.largeTitle.weight(.heavy))
            Text("\(choisis.count) goût\(choisis.count > 1 ? "s" : "") et \(notes) note\(notes > 1 ? "s" : "") : les suggestions « Pour toi » en tiennent compte dès maintenant.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(28)
    }

    // MARK: Navigation

    private var barreBas: some View {
        Button {
            avancer()
        } label: {
            Text(libelleSuivant)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(.black)
                .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(etape == .cle && etat.tmdb == nil)
        .opacity(etape == .cle && etat.tmdb == nil ? 0.5 : 1)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Theme.fond)
    }

    private var libelleSuivant: String {
        switch etape {
        case .bienvenue: "Commencer"
        case .cle: etat.tmdb == nil ? "Enregistre d'abord la clé" : "Suivant"
        case .plateformes: "Suivant"
        case .gouts: choisis.isEmpty ? "Passer" : "Suivant · \(choisis.count) choisi\(choisis.count > 1 ? "s" : "")"
        case .notation: notes >= 10 || position >= aNoter.count ? "Terminer" : "Terminer plus tard"
        case .fin: "Découvrir Séance"
        }
    }

    private func avancer() {
        switch etape {
        case .bienvenue:
            etape = etat.tmdb == nil ? .cle : .plateformes
        case .cle:
            etape = .plateformes
        case .plateformes:
            etape = .gouts
        case .gouts:
            enregistrerGouts()
            etape = .notation
            Task { await chargerNotation() }
        case .notation:
            etape = .fin
            Task { await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
        case .fin:
            terminer()
        }
    }

    private func enregistrerGouts() {
        let interets = GoutPropose.catalogue.filter { choisis.contains($0.nom) }
            .map { ServiceGouts.InteretDeclare(libelle: $0.nom, genres: $0.genres, motsCles: $0.motsCles) }
        try? gouts.declarer(interets)
    }

    /// Des films très connus dans les genres choisis, que Patrick n'a pas encore notés.
    private func chargerNotation() async {
        guard aNoter.isEmpty, let client = etat.tmdb else { return }
        chargementNotation = true
        defer { chargementNotation = false }
        let retenus = GoutPropose.catalogue.filter { choisis.contains($0.nom) }
        var criteres = CriteresDecouverte()
        criteres.genresInclus = Array(Set(retenus.flatMap(\.genres).filter { $0 < 10_000 }))
        criteres.votesMin = 4000
        criteres.tri = .votes
        let dejaConnus = Set(((try? contexte.fetch(FetchDescriptor<Suivi>())) ?? []).map(\.reference))
        var titres: [TitreResume] = []
        for page in 1...2 {
            criteres.page = page
            let resultats = (try? await client.decouvrirFilms(criteres).resultats.map(\.titreResume)) ?? []
            titres += resultats.filter { !dejaConnus.contains($0.reference) && $0.cheminAffiche != nil }
        }
        aNoter = Array(titres.prefix(30))
        if aNoter.isEmpty {
            etat.journal.noter(.tmdb, "La notation rapide n'a trouvé aucun film à proposer.")
        }
    }

    private func noter(_ titre: TitreResume, _ note: Int) {
        _ = try? gouts.noterTitreConnu(titre, note: note)
        notes += 1
        suivant()
    }

    private func suivant() {
        withAnimation(.snappy) { position += 1 }
    }
}
