import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

// Le programme télé : grandes cartes pour ce qui passe et pour la soirée, lignes à l'heure pour le reste.

/// Ce que Patrick sait déjà d'un titre qui passe à la télé.
enum MarqueListe {
    case dansTaListe, dejaVu

    static func marques(_ suivis: [Suivi]) -> [ReferenceTitre: MarqueListe] {
        var marques: [ReferenceTitre: MarqueListe] = [:]
        for suivi in suivis {
            switch suivi.statut {
            case .aVoir, .enCours: marques[suivi.reference] = .dansTaListe
            case .termine: marques[suivi.reference] = .dejaVu
            case .exclu: break
            }
        }
        return marques
    }
}

/// « 20:55 », « dans 35 min », « 1 h 45 » : les heures d'un programme, écrites court.
enum HeuresTele {
    static func heure(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "fr_CH")))
    }

    static func duree(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : (minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(String(format: "%02d", minutes % 60))")
    }

    /// Seulement dans les trois heures qui viennent : au-delà, l'heure suffit.
    static func dans(_ debut: Date, maintenant: Date) -> String? {
        let minutes = Int(debut.timeIntervalSince(maintenant) / 60)
        guard minutes > 0, minutes <= 180 else { return nil }
        return "Dans \(duree(minutes))"
    }

    /// « sam. 20 » pour un autre jour qu'aujourd'hui.
    static func jourCourt(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().locale(Locale(identifier: "fr_CH")))
    }
}

/// Le nom d'une chaîne du guide : celui de la chaîne cochée, sinon celui que le guide connaît, sinon « W9 » pour « W9.fr ».
enum NomChaine {
    static func lire(_ identifiant: String, parmi chaines: [Chaine]) -> String {
        chaines.first { $0.identifiantGuide == identifiant }?.nom
            ?? (ChaineGuide.suisses + ChaineGuide.tntParDefaut).first { $0.id == identifiant }?.nom
            ?? identifiant.split(separator: ".").first.map(String.init) ?? identifiant
    }
}

/// Le nom de la chaîne, comme un logo : noir sur blanc.
struct PastilleChaine: View {
    let nom: String

    var body: some View {
        Text(nom)
            .font(.caption.weight(.heavy))
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(.black)
    }
}

/// « FILM » en couleur, « SÉRIE » en retrait : le film du soir se repère d'un coup d'œil.
struct PastilleType: View {
    let film: Bool

    var body: some View {
        Text(film ? "FILM" : "SÉRIE")
            .font(.caption2.weight(.black))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(film ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(Color.gray.opacity(0.55)),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .foregroundStyle(film ? Color.black : Color.white)
    }
}

private struct PastilleMarque: View {
    let marque: MarqueListe
    /// Sur une image : blanc atténué plutôt que le gris du système, illisible sur une photo.
    var surImage = false

    var body: some View {
        switch marque {
        case .dansTaListe:
            Label("Dans ta liste", systemImage: "bookmark.fill")
                .font(.caption2.weight(.bold))
                .fixedSize()
                .foregroundStyle(Theme.accentClair)
        case .dejaVu:
            Label("Déjà vu", systemImage: "eye.fill")
                .font(.caption2.weight(.bold))
                .fixedSize()
                .foregroundStyle(surImage ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
        }
    }
}

/// Actions d'un passage télé sans ouvrir la fiche : le prévoir pour ce soir-là, le ranger dans une liste.
private struct MenuDiffusion: View {
    let bloc: BlocDiffusion
    let reference: ReferenceTitre

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte

    var body: some View {
        let soir = GrilleTele.soir(bloc)
        let ceSoir = ServiceSoiree.soiree(jour: soir) == ServiceSoiree.soiree()
        Button {
            PrevoirSoiree.prevoir(choisi, le: soir, etat: etat, contexte: contexte)
        } label: {
            Label(ceSoir ? "Ajouter à ma soirée" : "Prévoir pour ce soir-là", systemImage: ceSoir ? "moon.stars" : "calendar")
        }
        Button { etat.titrePourListe = choisi } label: { Label("Ajouter à une liste…", systemImage: "list.bullet.rectangle.portrait") }
    }

    private var choisi: TitreChoisi {
        TitreChoisi(reference: reference, titre: bloc.premiere.titreGuide, cheminAffiche: bloc.premiere.cheminAffiche)
    }
}

private extension BlocDiffusion {
    /// L'image de fond TMDB en priorité, puis l'affiche, puis la vignette du guide.
    var image: URL? {
        ImageTMDB.url(premiere.cheminFond, .fond)
            ?? ImageTMDB.url(premiere.cheminAffiche, .fond)
            ?? premiere.imageGuide.flatMap(URL.init(string:))
    }

    /// « 2000 · 2 h 35 », « S08E01 et E02 · 42 min ».
    var detail: String {
        var morceaux: [String] = []
        if let episodes = libelleEpisodes {
            morceaux.append(episodes)
        } else if let annee = premiere.anneeGuide {
            morceaux.append(String(annee))
        }
        morceaux.append(HeuresTele.duree(dureeMinutes))
        return morceaux.joined(separator: " · ")
    }

    func descriptionVocale(chaine: String, marque: MarqueListe?) -> String {
        var morceaux = [premiere.titreGuide, estFilm ? "film" : "série", "sur \(chaine)", "à \(HeuresTele.heure(debut))", detail]
        if marque == .dansTaListe { morceaux.append("dans ta liste") }
        if marque == .dejaVu { morceaux.append("déjà vu") }
        return morceaux.joined(separator: ", ")
    }
}

/// La cloche d'un passage télé : « me le rappeler un quart d'heure avant », pour n'importe quel titre du programme.
struct ClocheDiffusion: View {
    let bloc: BlocDiffusion
    let chaine: String
    /// Sur une image : pastille sombre. Sur une ligne : pastille de surface.
    var surImage = true
    /// Sur le Mac, un clic sur la cloche traverserait jusqu'à la carte du dessous : elle se rend insensible au survol.
    @Binding var survol: Bool

    @Environment(EtatApp.self) private var etat

    var body: some View {
        let actif = etat.alertes.aUnRappel(chaine: bloc.premiere.chaine, debut: bloc.debut)
        Button {
            Task { await basculer() }
        } label: {
            Image(systemName: actif ? "bell.fill" : "bell")
                .font(.system(size: 14, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(actif ? AnyShapeStyle(Color.black) : surImage ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
                .frame(width: 34, height: 34)
                .background(actif ? AnyShapeStyle(Theme.degradeAccent) : surImage ? AnyShapeStyle(.black.opacity(0.65)) : AnyShapeStyle(Theme.surface), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .onDisappear { survol = false }
        .help(actif ? "Retirer le rappel" : "Me le rappeler un quart d'heure avant")
        .accessibilityLabel(actif ? "Retirer le rappel de \(bloc.premiere.titreGuide)" : "Me rappeler \(bloc.premiere.titreGuide) un quart d'heure avant")
        .sensoryFeedback(.selection, trigger: actif)
    }

    private func basculer() async {
        let pose = await etat.alertes.basculerRappelTele(titre: bloc.premiere.titreGuide, nomChaine: chaine, chaine: bloc.premiere.chaine,
                                                         debut: bloc.debut, reference: bloc.reference)
        switch pose {
        case true?:
            let quand = HeuresTele.heure(max(.now, bloc.debut.addingTimeInterval(-EtatAlertes.avanceRappelTele)))
            etat.confirmer("Rappel à \(quand) pour « \(bloc.premiere.titreGuide) »", symbole: "bell.fill")
        case false?:
            etat.confirmer("Rappel retiré", symbole: "bell.slash")
        case nil:
            etat.confirmer("Active les notifications de Séance pour recevoir ce rappel", symbole: "bell.slash")
        }
    }
}

/// Un lien vers la fiche quand le passage est rattaché à TMDB, avec son menu ; la carte seule sinon.
private struct LienDiffusion<Contenu: View>: View {
    let bloc: BlocDiffusion
    @ViewBuilder var contenu: Contenu

    var body: some View {
        if let reference = bloc.reference {
            NavigationLink(value: reference) { contenu }
                .buttonStyle(.plain)
                .contextMenu { MenuDiffusion(bloc: bloc, reference: reference) }
        } else {
            contenu
        }
    }
}

/// La grande carte : l'image en 16/9, la chaîne, l'heure en grand, le titre ; en direct, l'avancement.
/// Elle prend la largeur qu'on lui donne.
struct CarteDiffusion: View {
    let bloc: BlocDiffusion
    let chaine: String
    let marque: MarqueListe?
    let maintenant: Date
    /// Hors d'une page classée par jour : « sam. 20 » devant l'heure quand ce n'est pas aujourd'hui.
    var jourVisible = false

    @State private var survolCloche = false

    var body: some View {
        let avancement = bloc.avancement(maintenant: maintenant)
        carte(avancement)
            #if targetEnvironment(macCatalyst)
            .allowsHitTesting(!survolCloche)
            #endif
            .overlay(alignment: .bottomTrailing) {
                if bloc.debut > maintenant {
                    ClocheDiffusion(bloc: bloc, chaine: chaine, survol: $survolCloche).padding(10)
                }
            }
    }

    private func carte(_ avancement: Double?) -> some View {
        LienDiffusion(bloc: bloc) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { ImageDistante(url: bloc.image, coins: 0) }
                .overlay {
                    LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .clear, location: 0.35),
                                           .init(color: .black.opacity(0.92), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        PastilleChaine(nom: chaine)
                        Spacer(minLength: 4)
                        if avancement != nil {
                            HStack(spacing: 5) {
                                Circle().fill(.white).frame(width: 6, height: 6)
                                Text("EN DIRECT")
                            }
                            .font(.caption2.weight(.black))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.red, in: Capsule())
                        } else if let dans = HeuresTele.dans(bloc.debut, maintenant: maintenant) {
                            Text(dans)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.black.opacity(0.6), in: Capsule())
                        }
                    }
                    .padding(12)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            if jourVisible, !Calendar.current.isDate(bloc.debut, inSameDayAs: maintenant) {
                                Text(HeuresTele.jourCourt(bloc.debut))
                                    .font(.subheadline.weight(.bold))
                            }
                            Text(HeuresTele.heure(bloc.debut))
                                .font(.system(.title, design: .rounded).weight(.heavy))
                                .foregroundStyle(Theme.accentClair)
                            Text("→ \(HeuresTele.heure(bloc.fin))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Text(bloc.premiere.titreGuide)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 7) {
                            PastilleType(film: bloc.estFilm)
                            Text(bloc.detail)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(1)
                            if let marque {
                                PastilleMarque(marque: marque, surImage: true)
                            }
                        }
                        if let avancement {
                            HStack(spacing: 8) {
                                ProgressView(value: avancement)
                                    .tint(.red)
                                Text("Reste \(HeuresTele.duree(max(1, Int(bloc.fin.timeIntervalSince(maintenant) / 60))))")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .fixedSize()
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(12)
                    .padding(.trailing, avancement == nil ? 40 : 0)
                }
                .foregroundStyle(.white)
                .surImage()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    // Un titre de ta liste qui passe à la télé : le liseré le fait ressortir du lot.
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(marque == .dansTaListe ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(.white.opacity(0.1)),
                                      lineWidth: marque == .dansTaListe ? 2 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bloc.descriptionVocale(chaine: chaine, marque: marque))
        .accessibilityAddTraits(bloc.reference == nil ? [] : .isButton)
    }
}

/// La ligne compacte du reste de la journée : l'heure d'abord, puis la vignette, la chaîne et le titre.
struct LigneDiffusion: View {
    let bloc: BlocDiffusion
    let chaine: String
    let marque: MarqueListe?

    @State private var survolCloche = false

    var body: some View {
        HStack(spacing: 8) {
            lien
                #if targetEnvironment(macCatalyst)
                .allowsHitTesting(!survolCloche)
                #endif
            if bloc.debut > .now {
                ClocheDiffusion(bloc: bloc, chaine: chaine, surImage: false, survol: $survolCloche)
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var lien: some View {
        LienDiffusion(bloc: bloc) {
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    // « 23:50 » est plus large que « 00:10 » : jamais sur deux lignes.
                    Text(HeuresTele.heure(bloc.debut))
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(Theme.accentClair)
                    Text(HeuresTele.duree(bloc.dureeMinutes))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 64)
                ImageDistante(url: bloc.image, coins: 9)
                    .frame(width: 104, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        PastilleChaine(nom: chaine)
                        PastilleType(film: bloc.estFilm)
                    }
                    Text(bloc.premiere.titreGuide)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 7) {
                        if let episodes = bloc.libelleEpisodes {
                            Text(episodes)
                        } else if let annee = bloc.premiere.anneeGuide {
                            Text(String(annee))
                        }
                        if let marque {
                            PastilleMarque(marque: marque)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bloc.descriptionVocale(chaine: chaine, marque: marque))
        .accessibilityAddTraits(bloc.reference == nil ? [] : .isButton)
    }
}

/// Tout le programme à venir des chaînes cochées (EF-46 à EF-49) : un jour à la fois, la soirée en vedette.
struct ProgrammeTeleView: View {
    @Environment(EtatApp.self) private var etat
    @Query(sort: \Diffusion.debut) private var diffusions: [Diffusion]
    @Query private var chaines: [Chaine]
    @Query private var suivis: [Suivi]
    @State private var type: TypeTitre? = .film
    @State private var jourChoisi: DateTMDB?
    /// Les chaînes retenues ; vide : toutes.
    @State private var chainesChoisies: Set<String> = []

    /// Une semaine suffit : au-delà, le guide est incomplet et change encore.
    private static let joursAffiches = 7

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { horloge in
            contenu(maintenant: horloge.date)
        }
        .background(Theme.fond)
        .navigationTitle("Programme télé")
        .navigationBarTitleDisplayMode(.inline)
        .task { await etat.alertes.actualiserRappelsTele() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { menuChaines }
        }
    }

    private func contenu(maintenant: Date) -> some View {
        let parJour = blocsParJour(maintenant: maintenant)
        let jours = Array(parJour.keys.sorted().prefix(Self.joursAffiches))
        let jour = jourChoisi.flatMap { jours.contains($0) ? $0 : nil } ?? jours.first
        let marques = MarqueListe.marques(suivis)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SelecteurCases(selection: $type, cases: [.init(valeur: TypeTitre?.some(.film), nom: "Films"),
                                                         .init(valeur: TypeTitre?.some(.serie), nom: "Séries"), .init(valeur: TypeTitre?.none, nom: "Tout")])
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 20)

                if let jour {
                    choixDuJour(jours, choisi: jour, parJour: parJour, maintenant: maintenant)
                    let blocs = parJour[jour] ?? []
                    ForEach(MomentTele.allCases, id: \.self) { moment in
                        let duMoment = blocs.filter { GrilleTele.moment($0, maintenant: maintenant) == moment }
                        if !duMoment.isEmpty {
                            section(moment, blocs: duMoment, marques: marques, maintenant: maintenant)
                        }
                    }
                } else {
                    // Chaque impasse a sa sortie : les réglages des chaînes, ou le retour à toutes les chaînes.
                    ContentUnavailableView {
                        Label(type == .serie ? "Aucune série à venir" : "Rien à venir", systemImage: "tv")
                    } description: {
                        Text(chainesChoisies.isEmpty
                             ? "Aucun titre reconnu sur tes chaînes pour l'instant. Choisis tes chaînes, et Séance lira leur programme."
                             : "Rien sur les chaînes retenues pour ce jour.")
                    } actions: {
                        if chainesChoisies.isEmpty {
                            NavigationLink("Choisir mes chaînes", value: DestinationReglage.tele)
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Toutes les chaînes") { chainesChoisies = [] }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 40)
                }
            }
            .padding(.vertical, 12)
        }
    }

    /// Les passages pas encore finis, du type choisi, réunis en blocs et rangés par journée télé (de 6 h à 6 h).
    private func blocsParJour(maintenant: Date) -> [DateTMDB: [BlocDiffusion]] {
        let retenues = diffusions.filter {
            $0.fin > maintenant && (type == nil || $0.typeBrut == type?.rawValue) && (chainesChoisies.isEmpty || chainesChoisies.contains($0.chaine))
        }
        return Dictionary(grouping: GrilleTele.blocs(retenues)) { GrilleTele.jourAffiche($0, maintenant: maintenant) }
    }

    private func nomChaine(_ identifiant: String) -> String {
        NomChaine.lire(identifiant, parmi: chaines)
    }

    /// Les chaînes qui ont quelque chose au programme, par nom : n'en garder que quelques-unes, ou toutes.
    private var menuChaines: some View {
        let presentes = Set(diffusions.filter { $0.fin > .now }.map(\.chaine))
        let triees = presentes.sorted { nomChaine($0).localizedStandardCompare(nomChaine($1)) == .orderedAscending }
        return Menu {
            Button {
                chainesChoisies = []
            } label: {
                Label("Toutes les chaînes", systemImage: chainesChoisies.isEmpty ? "checkmark" : "tv")
            }
            Divider()
            ForEach(triees, id: \.self) { chaine in
                Button {
                    if chainesChoisies.contains(chaine) { chainesChoisies.remove(chaine) } else { chainesChoisies.insert(chaine) }
                } label: {
                    if chainesChoisies.contains(chaine) {
                        Label(nomChaine(chaine), systemImage: "checkmark")
                    } else {
                        Text(nomChaine(chaine))
                    }
                }
            }
        } label: {
            Label(chainesChoisies.isEmpty ? "Chaînes" : Format.pluriel(chainesChoisies.count, "chaîne"),
                  systemImage: chainesChoisies.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .menuActionDismissBehavior(.disabled)
        .accessibilityLabel(chainesChoisies.isEmpty ? "Filtrer par chaîne" : "Filtre : \(Format.pluriel(chainesChoisies.count, "chaîne"))")
    }

    // MARK: Les jours

    private func choixDuJour(_ jours: [DateTMDB], choisi: DateTMDB, parJour: [DateTMDB: [BlocDiffusion]], maintenant: Date) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(jours, id: \.self) { jour in
                    let actif = jour == choisi
                    let blocs = parJour[jour] ?? []
                    let films = blocs.filter(\.estFilm).count
                    // « 2 films », « 1 série », ou « 3 titres » quand la journée mêle les deux.
                    let detail = films == blocs.count ? Format.pluriel(films, "film")
                        : films == 0 ? Format.pluriel(blocs.count, "série") : Format.pluriel(blocs.count, "titre")
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { jourChoisi = jour }
                    } label: {
                        TuileJour(nom: nomCourt(jour, maintenant: maintenant), numero: jour.jour,
                                  detail: detail,
                                  actif: actif)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(nomLong(jour, maintenant: maintenant)), \(Format.pluriel(blocs.count, "programme"))")
                    .accessibilityAddTraits(actif ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func nomCourt(_ jour: DateTMDB, maintenant: Date) -> String {
        if jour == GrilleTele.jourTele(maintenant) { return "Auj." }
        if jour == GrilleTele.jourTele(maintenant.addingTimeInterval(86_400)) { return "Demain" }
        return jour.instant(heure: 12).formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_CH"))).capitalized
    }

    private func nomLong(_ jour: DateTMDB, maintenant: Date) -> String {
        if jour == GrilleTele.jourTele(maintenant) { return "Aujourd'hui" }
        if jour == GrilleTele.jourTele(maintenant.addingTimeInterval(86_400)) { return "Demain" }
        return jour.instant(heure: 12).formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH")))
    }

    // MARK: Les moments de la journée

    @ViewBuilder
    private func section(_ moment: MomentTele, blocs: [BlocDiffusion], marques: [ReferenceTitre: MarqueListe], maintenant: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbole(moment))
                    .foregroundStyle(moment == .enCours ? AnyShapeStyle(.red) : AnyShapeStyle(Theme.accentClair))
                Text(titre(moment)).font(.title3.weight(.bold))
                Text("\(blocs.count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Theme.surface, in: Capsule())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            switch moment {
            case .enCours, .soiree:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290, maximum: 520), spacing: 14)], spacing: 14) {
                    ForEach(blocs) { bloc in
                        CarteDiffusion(bloc: bloc, chaine: nomChaine(bloc.premiere.chaine), marque: bloc.reference.flatMap { marques[$0] },
                                       maintenant: maintenant)
                    }
                }
                .padding(.horizontal, 20)
            case .journee, .nuit:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330, maximum: 640), spacing: 10)], spacing: 10) {
                    ForEach(blocs) { bloc in
                        LigneDiffusion(bloc: bloc, chaine: nomChaine(bloc.premiere.chaine), marque: bloc.reference.flatMap { marques[$0] })
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func titre(_ moment: MomentTele) -> String {
        switch moment {
        case .enCours: "En ce moment"
        case .soiree: "En soirée"
        case .journee: "Dans la journée"
        case .nuit: "Tard le soir et la nuit"
        }
    }

    private func symbole(_ moment: MomentTele) -> String {
        switch moment {
        case .enCours: "dot.radiowaves.left.and.right"
        case .soiree: "moon.stars.fill"
        case .journee: "sun.max.fill"
        case .nuit: "moon.zzz.fill"
        }
    }
}
