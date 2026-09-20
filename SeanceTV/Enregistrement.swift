import OSLog
import SwiftData

extension ModelContext {
    /// Le pendant, sur la TV, du `sauver()` de l'app iPhone : un enregistrement qui échoue ne passe pas sous silence
    /// (EF-138). La TV n'a pas d'écran « Journal » : l'échec part dans le journal système, lisible depuis le Mac.
    func sauver() {
        do {
            try save()
        } catch {
            Logger(subsystem: "ch.patrick.seance.tv", category: "donnees").error("Enregistrement impossible : \(error.localizedDescription, privacy: .public)")
        }
    }
}
