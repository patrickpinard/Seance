import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// L'onglet « Listes » de Mes listes (EF-63) : créer une liste, l'ouvrir, la supprimer.
struct SectionListesNommees: View {
    let recherche: String

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \ListePerso.creeeLe) private var listes: [ListePerso]
    @State private var nom = ""

    private var affichees: [ListePerso] {
        guard !recherche.isEmpty else { return listes }
        return listes.filter { liste in
            liste.nom.localizedCaseInsensitiveContains(recherche) || liste.apercus.contains { $0.titre.localizedCaseInsensitiveContains(recherche) }
        }
    }

    var body: some View {
        Section {
            HStack(spacing: 10) {
                TextField("Nouvelle liste, par exemple « Soirées Statham »", text: $nom)
                    .onSubmit(creer)
                Button("Créer", action: creer)
                    .disabled(nom.trimmingCharacters(in: .whitespaces).isEmpty)
                    .tint(Theme.accent)
            }
        }
        if listes.isEmpty {
            Text("Aucune liste pour l'instant. Crée-en une, puis range-y des titres depuis leur fiche (« Plus ») ou par un clic droit sur une affiche.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        } else if affichees.isEmpty {
            Text("Aucune liste ne correspond à « \(recherche) ».")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
        ForEach(affichees) { liste in
            NavigationLink(value: liste.persistentModelID) {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(liste.nom).font(.headline).lineLimit(1)
                        Text(liste.titres.isEmpty ? "Vide" : Format.pluriel(liste.titres.count, "titre"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .swipeActions { Button("Supprimer", role: .destructive) { supprimer(liste) } }
            .contextMenu {
                Button(role: .destructive) { supprimer(liste) } label: { Label("Supprimer la liste", systemImage: "trash") }
            }
        }
    }

    private func creer() {
        guard (try? ServiceListes(contexte: contexte).creer(nom)) != nil else { return }
        nom = ""
    }

    /// La liste disparaît ; « Annuler » la recrée avec ses titres.
    private func supprimer(_ liste: ListePerso) {
        let (nom, date, titres, apercus) = (liste.nom, liste.creeeLe, liste.titres, liste.apercus)
        try? ServiceListes(contexte: contexte).supprimer(liste)
        etat.confirmer("Liste « \(nom) » supprimée", symbole: "trash") { [contexte] in
            let recreee = ListePerso(nom: nom)
            recreee.creeeLe = date
            recreee.titres = titres
            recreee.apercus = apercus
            contexte.insert(recreee)
            try? contexte.save()
        }
    }
}

/// Une liste nommée : ses titres dans l'ordre d'ajout, à ouvrir, prévoir pour une soirée ou retirer.
struct ListePersoView: View {
    let id: PersistentIdentifier

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var fermer
    @Query private var listes: [ListePerso]
    @State private var renommage = false
    @State private var nouveauNom = ""
    @State private var suppression = false

    private var liste: ListePerso? {
        listes.first { $0.persistentModelID == id }
    }

    var body: some View {
        List {
            if let liste {
                let titres = (try? ServiceListes(contexte: contexte).titres(liste)) ?? []
                if titres.isEmpty {
                    Text("Cette liste est vide. Range-y des titres depuis leur fiche (« Plus » › Ajouter à une liste) ou par un clic droit sur une affiche.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(titres, id: \.reference) { apercu in
                    NavigationLink(value: apercu.reference) {
                        HStack(spacing: 12) {
                            ImageDistante(url: ImageTMDB.url(apercu.cheminAffiche, .affiche), coins: 8)
                                .frame(width: 50, height: 75)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(apercu.titre.isEmpty ? "\(apercu.reference.type == .film ? "Film" : "Série") \(apercu.reference.tmdbID)" : apercu.titre)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(apercu.reference.type == .film ? "Film" : "Série").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions { Button("Retirer", role: .destructive) { retirer(apercu, de: liste) } }
                    .contextMenu {
                        Button {
                            etat.titreADater = TitreChoisi(reference: apercu.reference, titre: apercu.titre, cheminAffiche: apercu.cheminAffiche)
                        } label: { Label("Prévoir pour une soirée…", systemImage: "calendar") }
                        Divider()
                        Button(role: .destructive) { retirer(apercu, de: liste) } label: { Label("Retirer de la liste", systemImage: "minus.circle") }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.fond)
        .navigationTitle(liste?.nom ?? "Liste")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        nouveauNom = liste?.nom ?? ""
                        renommage = true
                    } label: { Label("Renommer…", systemImage: "pencil") }
                    Button(role: .destructive) { suppression = true } label: { Label("Supprimer la liste", systemImage: "trash") }
                } label: {
                    Label("Plus", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("Renommer la liste", isPresented: $renommage) {
            TextField("Nom", text: $nouveauNom)
            Button("Renommer") { if let liste { try? ServiceListes(contexte: contexte).renommer(liste, en: nouveauNom) } }
            Button("Annuler", role: .cancel) {}
        }
        .confirmationDialog("Supprimer la liste « \(liste?.nom ?? "") » ?", isPresented: $suppression, titleVisibility: .visible) {
            Button("Supprimer la liste", role: .destructive) {
                if let liste { try? ServiceListes(contexte: contexte).supprimer(liste) }
                fermer()
            }
        } message: {
            Text("Les titres restent dans tes autres listes et dans ton historique.")
        }
    }

    private func retirer(_ apercu: ApercuTitre, de liste: ListePerso) {
        try? ServiceListes(contexte: contexte).retirer(apercu.reference, de: liste)
        etat.confirmer("« \(apercu.titre) » retiré de « \(liste.nom) »", symbole: "minus.circle") { [contexte] in
            try? ServiceListes(contexte: contexte).ajouter(apercu.reference, titre: apercu.titre, cheminAffiche: apercu.cheminAffiche, a: liste)
        }
    }
}

/// « Ajouter à une liste… » : cocher les listes où ranger le titre, ou en créer une.
struct AjoutAListeView: View {
    let titre: TitreChoisi

    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var fermer
    @Query(sort: \ListePerso.creeeLe) private var listes: [ListePerso]
    @State private var nom = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if listes.isEmpty {
                        Text("Aucune liste pour l'instant : crée la première ci-dessous.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(listes) { liste in
                        let dedans = liste.titres.contains(titre.reference)
                        Button { basculer(liste, dedans: dedans) } label: {
                            HStack {
                                Text(liste.nom)
                                Spacer()
                                Text(Format.pluriel(liste.titres.count, "titre")).font(.caption).foregroundStyle(.secondary)
                                Image(systemName: dedans ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(dedans ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(dedans ? .isSelected : [])
                    }
                } header: {
                    Text("Ranger « \(titre.titre) » dans")
                }
                Section("Nouvelle liste") {
                    HStack(spacing: 10) {
                        TextField("Nom de la liste", text: $nom).onSubmit(creer)
                        Button("Créer et ajouter", action: creer)
                            .disabled(nom.trimmingCharacters(in: .whitespaces).isEmpty)
                            .tint(Theme.accent)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.fond)
            .titreDeFeuille("Ajouter à une liste")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { fermer() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.fond)
    }

    private func basculer(_ liste: ListePerso, dedans: Bool) {
        let service = ServiceListes(contexte: contexte)
        if dedans {
            try? service.retirer(titre.reference, de: liste)
        } else {
            try? service.ajouter(titre.reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche, a: liste)
        }
    }

    private func creer() {
        let service = ServiceListes(contexte: contexte)
        guard let liste = try? service.creer(nom) else { return }
        try? service.ajouter(titre.reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche, a: liste)
        nom = ""
    }
}
