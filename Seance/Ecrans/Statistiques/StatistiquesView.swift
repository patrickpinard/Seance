import Charts
import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Statistiques (EF-34 à EF-37) : heures regardées, mois par mois, acteurs et genres favoris.
struct StatistiquesView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    /// Lue pour que la page se recalcule quand un épisode est coché ailleurs.
    @Query private var visionnages: [Visionnage]
    @State private var annee: Int? = Calendar.current.component(.year, from: .now)
    @State private var bilanAnnee: Int?

    private static let anneeCourante = Calendar.current.component(.year, from: .now)

    var body: some View {
        let _ = visionnages.count
        let service = ServiceStatistiques(contexte: contexte)
        let bilan = (try? service.bilan(annee: annee)) ?? BilanStatistiques()
        let annees = Set(((try? service.annees()) ?? []) + [Self.anneeCourante]).sorted(by: >)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if bilan.minutesTotales == 0 {
                    MessageEtat(texte: annee == nil
                                ? "Rien de regardé pour l'instant. Marque un film comme vu ou coche des épisodes : tes heures, tes acteurs et tes genres favoris apparaîtront ici."
                                : "Rien de regardé en \(String(annee!)). Choisis une autre période en haut à droite.",
                                symbole: "chart.bar")
                        .padding(.horizontal, -20)
                } else {
                    CarteHeures(bilan: bilan, periode: libellePeriode)
                    if let annee {
                        boutonBilan(annee)
                    }
                    carte("Mois par mois", symbole: "chart.bar.fill") {
                        GraphiqueMois(bilan: bilan, annee: annee)
                    }
                    if !bilan.acteurs.isEmpty {
                        // EF-35 : les dix acteurs les plus regardés. Tous à un seul titre : rien à classer encore.
                        carte("Acteurs favoris", symbole: "person.2.fill") {
                            if bilan.acteurs.contains(where: { $0.nombreTitres >= 2 }) {
                                ClassementActeurs(classement: bilan.acteurs, periode: libellePeriode)
                            } else {
                                Text("Pas encore de favori : aucun acteur ne revient dans deux de tes titres \(libellePeriode).")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !bilan.genres.isEmpty {
                        carte("Genres favoris", symbole: "theatermasks.fill") {
                            ClassementGenres(classement: bilan.genres, noms: etat.nomsGenres)
                        }
                    }
                    if let record = bilan.recordEpisodes, record.nombreEpisodes > 1 {
                        carte("Ta plus grosse soirée", symbole: "flame.fill") {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(record.nombreEpisodes)").font(.system(size: 40, weight: .heavy, design: .rounded))
                                Text("épisodes").font(.title3.weight(.semibold))
                                Spacer()
                                Text(Format.jour(record.jour)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("Les heures comptent chaque visionnage : un film revu compte deux fois. Les acteurs et les genres comptent des titres différents : une série compte une fois.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            // Sur le Mac, une colonne lisible plutôt que des cartes étirées sur toute la fenêtre.
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.fond)
        .navigationTitle("Statistiques")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Période", selection: $annee) {
                        ForEach(annees, id: \.self) { valeur in
                            Text(String(valeur)).tag(Optional(valeur))
                        }
                        Text("Depuis le début").tag(Int?.none)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(libellePeriodeCourt).fixedSize()
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 4)
                }
                .accessibilityLabel("Période : \(libellePeriodeCourt)")
                .help("Choisir l'année affichée")
            }
        }
        .navigationDestination(for: TitresAvecActeur.self) { comptes in
            PersonneView(personne: comptes.personne, comptes: comptes)
        }
        .fullScreenCover(item: Binding(get: { bilanAnnee.map(AnneeBilan.init) }, set: { bilanAnnee = $0?.id })) { choix in
            BilanAnneeView(annee: choix.id)
        }
    }

    private var libellePeriode: String {
        guard let annee else { return "depuis le début" }
        return annee == Self.anneeCourante ? "cette année" : "en \(String(annee))"
    }

    private var libellePeriodeCourt: String {
        annee.map { String($0) } ?? "Tout"
    }

    /// Le bilan en cartes : ouvert en décembre, « jusqu'ici » avant, toujours ouvert pour une année passée.
    private func boutonBilan(_ annee: Int) -> some View {
        let enCours = annee == Self.anneeCourante && !ServiceStatistiques.bilanOuvert()
        return Button { bilanAnnee = annee } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(enCours ? "Ton année \(String(annee)) jusqu'ici" : "Ton bilan \(String(annee))")
                        .font(.headline)
                    Text("En cartes à faire défiler et à partager")
                        .font(.subheadline)
                        .opacity(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.headline)
            }
            .foregroundStyle(.black)
            .padding(16)
            .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ouvre le bilan en plein écran")
    }

    private func carte<Contenu: View>(_ titre: String, symbole: String, @ViewBuilder contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(titre, systemImage: symbole)
                .font(.headline)
                .labelStyle(EtiquetteSection())
            contenu()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AnneeBilan: Identifiable {
    let id: Int
}

/// Mise en forme partagée par les statistiques et le bilan.
enum Format {
    private static let locale = Locale(identifier: "fr_CH")

    /// « 42 h », « 3 h 20 » ou « 45 min ».
    static func duree(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let heures = minutes / 60
        let reste = minutes % 60
        return heures >= 10 || reste == 0 ? "\(Int((Double(minutes) / 60).rounded())) h" : "\(heures) h \(reste)"
    }

    static func heures(_ minutes: Int) -> Int {
        Int((Double(minutes) / 60).rounded())
    }

    /// « soit 1,8 jour », à partir de 24 heures.
    static func jours(_ minutes: Int) -> String? {
        guard minutes >= 24 * 60 else { return nil }
        let jours = Double(minutes) / (24 * 60)
        // Virgule décimale, comme dans un texte en français.
        let texte = jours.formatted(.number.precision(.fractionLength(jours < 10 ? 1 : 0)).locale(Locale(identifier: "fr_FR")))
        return "soit \(texte) jour\(jours >= 2 ? "s" : "")"
    }

    static func jour(_ date: DateTMDB) -> String {
        date.instant(fuseau: .suisse).formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    static func pluriel(_ nombre: Int, _ singulier: String, _ pluriel: String? = nil) -> String {
        "\(nombre) \(nombre > 1 ? (pluriel ?? singulier + "s") : singulier)"
    }
}

/// Le total d'heures, et sa part films / séries.
private struct CarteHeures: View {
    let bilan: BilanStatistiques
    let periode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Format.duree(bilan.minutesTotales))
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.degradeAccent)
                VStack(alignment: .leading, spacing: 0) {
                    Text("regardées \(periode)").font(.headline)
                    if let jours = Format.jours(bilan.minutesTotales) {
                        Text(jours).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            GeometryReader { geo in
                let part = bilan.minutesTotales == 0 ? 0 : CGFloat(bilan.minutesFilms) / CGFloat(bilan.minutesTotales)
                HStack(spacing: 3) {
                    if bilan.minutesFilms > 0 {
                        Capsule().fill(Theme.accent).frame(width: max(8, (geo.size.width - 3) * part))
                    }
                    if bilan.minutesSeries > 0 {
                        Capsule().fill(Color.teal)
                    }
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)

            HStack(alignment: .top) {
                repartition("Films", couleur: Theme.accent, minutes: bilan.minutesFilms, detail: Format.pluriel(bilan.nombreFilms, "film"))
                Spacer()
                repartition("Séries", couleur: .teal, minutes: bilan.minutesSeries, detail: Format.pluriel(bilan.nombreEpisodes, "épisode"))
            }
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func repartition(_ titre: String, couleur: Color, minutes: Int, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(titre, systemImage: "circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(PastilleCouleur(couleur: couleur))
            Text(Format.duree(minutes)).font(.title3.weight(.bold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PastilleCouleur: LabelStyle {
    let couleur: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            Circle().fill(couleur).frame(width: 8, height: 8)
            configuration.title
        }
    }
}

/// Heures par mois pour une année, par année depuis le début.
private struct GraphiqueMois: View {
    let bilan: BilanStatistiques
    let annee: Int?

    private struct Barre: Identifiable {
        let id: Int
        let libelle: String
        let heures: Double
    }

    private var barres: [Barre] {
        let formateur = DateFormatter()
        formateur.locale = Locale(identifier: "fr_CH")
        if let annee {
            return (1...12).map { mois in
                let minutes = bilan.parMois[Periode(annee: annee, numero: mois)] ?? 0
                let libelle = formateur.shortStandaloneMonthSymbols[mois - 1].replacingOccurrences(of: ".", with: "")
                return Barre(id: mois, libelle: String(libelle.prefix(4)), heures: Double(minutes) / 60)
            }
        }
        let parAnnee = Dictionary(grouping: bilan.parMois, by: { $0.key.annee }).mapValues { $0.reduce(0) { $0 + $1.value } }
        return parAnnee.keys.sorted().map { Barre(id: $0, libelle: String($0), heures: Double(parAnnee[$0] ?? 0) / 60) }
    }

    var body: some View {
        let barres = barres
        Chart(barres) { barre in
            BarMark(x: .value("Période", barre.libelle), y: .value("Heures", barre.heures))
                .foregroundStyle(Theme.degradeAccent)
                .cornerRadius(4)
                .accessibilityValue(Format.duree(Int(barre.heures * 60)))
        }
        .chartYAxis {
            AxisMarks(position: .leading) { valeur in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel { if let heures = valeur.as(Double.self) { Text("\(Int(heures)) h") } }
            }
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(.caption2) }
        }
        .frame(height: 180)
    }
}

/// Un acteur touché dans les statistiques : sa fiche montre en tête les titres comptés, les mêmes que le chiffre.
struct TitresAvecActeur: Hashable {
    let personne: ReferencePersonne
    /// « cette année », « en 2025 » ou « depuis le début ».
    let periode: String
    let titres: [ReferenceTitre]
}

private struct ClassementActeurs: View {
    let classement: [Classement<ActeurStat>]
    let periode: String

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(classement.enumerated()), id: \.element.cle) { rang, acteur in
                let contenu = HStack(spacing: 12) {
                    Text("\(rang + 1)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(rang == 0 ? Theme.accent : .secondary)
                        .frame(width: 30, alignment: .trailing)
                        .lineLimit(1)
                    Text(acteur.cle.nom).font(.body.weight(rang == 0 ? .semibold : .regular)).lineLimit(1)
                    Spacer()
                    Text(Format.pluriel(acteur.nombreTitres, "titre")).font(.subheadline).foregroundStyle(.secondary)
                    if acteur.cle.id != nil {
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
                // Sans identifiant (titre suivi avant la version 1.1), pas de fiche sûre à ouvrir.
                if let id = acteur.cle.id {
                    NavigationLink(value: TitresAvecActeur(personne: ReferencePersonne(id: id, nom: acteur.cle.nom),
                                                           periode: periode, titres: acteur.titres)) { contenu }
                        .buttonStyle(.plain)
                } else {
                    contenu
                }
            }
        }
    }
}

private struct ClassementGenres: View {
    let classement: [Classement<Int>]
    let noms: [Int: String]

    var body: some View {
        let maximum = max(1, classement.map(\.nombreTitres).max() ?? 1)
        VStack(spacing: 10) {
            ForEach(classement, id: \.cle) { genre in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(noms[genre.cle] ?? "Genre \(genre.cle)").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(Format.pluriel(genre.nombreTitres, "titre")).font(.caption).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        Capsule().fill(Theme.surface)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Theme.degradeAccent)
                                    .frame(width: geo.size.width * CGFloat(genre.nombreTitres) / CGFloat(maximum))
                            }
                    }
                    .frame(height: 8)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
