import Foundation

/// « Qui est-ce ? » (8.9) : à la pause d'un film ou d'un épisode, les visages de ce qu'on regarde, et pour chacun où on
/// l'a déjà vu — la question qu'on se pose devant l'écran, sans sortir de la lecture.
public enum QuiEstCe {
    /// Les visages à montrer, dans l'ordre du générique : les premiers rôles du film ou de la série, puis, pour un
    /// épisode, ses invités — souvent ceux qu'on ne remet pas. Une personne n'y paraît qu'une fois ; les réalisateurs
    /// n'y sont pas (on ne les voit pas à l'image), les visages sans portrait passent après les autres.
    public static func visages(casting: Casting?, invites: [PersonneCasting] = [], nombre: Int = 12) -> [PersonneCasting] {
        var vus = Set<Int>()
        let tous = (casting?.principaux(8) ?? []) + invites.sorted { ($0.ordre ?? .max) < ($1.ordre ?? .max) }
        let uniques = tous.filter { vus.insert($0.id).inserted }
        let avecPortrait = uniques.filter { $0.cheminPortrait != nil }
        let sansPortrait = uniques.filter { $0.cheminPortrait == nil }
        return Array((avecPortrait + sansPortrait).prefix(nombre))
    }

    /// Où tu l'as déjà vu : ses films et séries que tu as vus, sauf celui qu'on regarde, les plus connus d'abord.
    public static func dejaVu(dans filmographie: Filmographie, vus: Set<ReferenceTitre>, sauf actuel: ReferenceTitre?) -> [CreditPersonne] {
        var dejaLa = Set<ReferenceTitre>()
        return (filmographie.roles + filmographie.realisations)
            .filter { vus.contains($0.reference) && $0.reference != actuel && dejaLa.insert($0.reference).inserted }
            .sorted { ($0.nombreVotes ?? 0) > ($1.nombreVotes ?? 0) }
    }

    /// Ce qu'il joue ici, « Lieutenant Ripley », ou son rôle d'invité ; rien quand TMDB ne le dit pas.
    public static func role(_ personne: PersonneCasting) -> String? {
        guard let personnage = personne.personnage?.trimmingCharacters(in: .whitespacesAndNewlines), !personnage.isEmpty else { return nil }
        return personnage
    }
}
