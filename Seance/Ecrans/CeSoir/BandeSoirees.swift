import SeanceDonnees
import SwiftUI

/// La tuile d'un jour, la même dans le programme télé et dans Ce soir : « Auj. », le numéro en grand, et ce qu'il y a ce jour-là.
struct TuileJour: View {
    let nom: String
    let numero: Int
    let detail: String
    let actif: Bool
    /// Un jour où quelque chose est prévu ressort, même sans être choisi.
    var marque = false

    var body: some View {
        VStack(spacing: 2) {
            Text(nom)
                .font(.caption.weight(.bold))
            Text("\(numero)")
                .font(.system(.title2, design: .rounded).weight(.heavy))
            Text(detail)
                .font(.caption2)
                .opacity(0.75)
                .lineLimit(1)
        }
        .frame(minWidth: 66)
        .padding(.vertical, 9).padding(.horizontal, 6)
        .foregroundStyle(actif ? Color.black : marque ? Theme.accentClair : Color.primary)
        .background(actif ? AnyShapeStyle(Theme.degradeAccent) : marque ? AnyShapeStyle(Theme.accent.opacity(0.16)) : AnyShapeStyle(Theme.surface),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .texteContenu()
    }
}

/// Les soirées en rangée de jours, comme le programme télé : ce soir et les six jours suivants, puis les soirées plus
/// lointaines où quelque chose est prévu. La dernière tuile ouvre un calendrier pour aller à une autre date.
struct BandeSoirees: View {
    /// Le jour choisi, à minuit.
    @Binding var jour: Date
    /// Le jour de la soirée en cours (une soirée va de 6 h à 6 h), à minuit.
    let aujourdhui: Date
    /// Nombre de titres prévus par soirée, sous la clé de `ServiceSoiree.soiree(jour:)`.
    let prevus: [String: Int]

    @State private var autreDate = false

    private static let locale = Locale(identifier: "fr_CH")

    /// Une semaine suffit ; plus loin, seulement les soirées où quelque chose est prévu, et le jour choisi.
    private var jours: [Date] {
        let calendrier = Calendar.current
        let semaine = (0..<7).compactMap { calendrier.date(byAdding: .day, value: $0, to: aujourdhui) }
        let fin = semaine.last ?? aujourdhui
        let lointains = Set(prevus.keys.compactMap { ServiceSoiree.jour($0) }.map { calendrier.startOfDay(for: $0) } + [jour]).filter { $0 > fin }
        return semaine + lointains.sorted()
    }

    var body: some View {
        ScrollViewReader { defilement in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(jours, id: \.self) { date in
                        let nombre = prevus[Self.cle(date)] ?? 0
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { jour = date }
                        } label: {
                            TuileJour(nom: nomCourt(date), numero: Calendar.current.component(.day, from: date),
                                      detail: nombre > 0 ? Format.pluriel(nombre, "titre") : moisCourt(date),
                                      actif: date == jour, marque: nombre > 0)
                        }
                        .buttonStyle(.plain)
                        .id(date)
                        .accessibilityLabel(libelleVocal(date, nombre: nombre))
                        .accessibilityAddTraits(date == jour ? .isSelected : [])
                    }
                    Button { autreDate = true } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "calendar").font(.title3.weight(.semibold))
                            Text("Autre date").font(.caption2.weight(.semibold))
                        }
                        .frame(minWidth: 66)
                        .padding(.vertical, 14).padding(.horizontal, 6)
                        .foregroundStyle(Theme.accentClair)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choisir une autre date")
                }
                .padding(.horizontal, 20)
            }
            // Un jour choisi loin dans la rangée (autre date, titre déplacé) : elle défile jusqu'à lui.
            .onChange(of: jour) { _, nouveau in
                withAnimation(.snappy) { defilement.scrollTo(nouveau, anchor: .center) }
            }
        }
        .sheet(isPresented: $autreDate) {
            ChoixJourSoiree(depart: jour, aujourdhui: aujourdhui) { jour = $0 }
        }
    }

    private static func cle(_ date: Date) -> String {
        ServiceSoiree.soiree(jour: date.addingTimeInterval(12 * 3600))
    }

    private func nomCourt(_ date: Date) -> String {
        let calendrier = Calendar.current
        if date == aujourdhui { return "Ce soir" }
        if let demain = calendrier.date(byAdding: .day, value: 1, to: aujourdhui), date == demain { return "Demain" }
        return date.formatted(.dateTime.weekday(.abbreviated).locale(Self.locale)).capitalized
    }

    private func moisCourt(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).locale(Self.locale))
    }

    private func libelleVocal(_ date: Date, nombre: Int) -> String {
        let nom = date == aujourdhui ? "Ce soir" : date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Self.locale))
        return nombre > 0 ? "\(nom), \(Format.pluriel(nombre, "titre")) prévu\(nombre > 1 ? "s" : "")" : "\(nom), rien de prévu"
    }
}

/// Aller à la soirée d'une date lointaine : le calendrier du mois, à partir de ce soir.
private struct ChoixJourSoiree: View {
    let aujourdhui: Date
    let choisir: (Date) -> Void

    @Environment(\.dismiss) private var fermer
    @State private var jour: Date

    init(depart: Date, aujourdhui: Date, choisir: @escaping (Date) -> Void) {
        self.aujourdhui = aujourdhui
        self.choisir = choisir
        _jour = State(initialValue: max(depart, aujourdhui))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker("Soirée", selection: $jour, in: aujourdhui..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.accent)
                    .environment(\.locale, Locale(identifier: "fr_CH"))
                Button {
                    choisir(Calendar.current.startOfDay(for: jour))
                    fermer()
                } label: {
                    Text("Voir la soirée du \(LibelleSoiree.jour(jour).lowercased())")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Theme.fond)
            .titreDeFeuille("Autre date")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { fermer() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.fond)
    }
}
