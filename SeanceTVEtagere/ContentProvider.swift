import TVServices

/// L'étagère du haut : ta soirée et les nouveautés de ton NAS, en affiches, sur l'écran d'accueil de l'Apple TV.
final class ContentProvider: TVTopShelfContentProvider {
    // La variante à rappel : l'asynchrone rend un type que la concurrence stricte de Swift 6 refuse de laisser passer.
    override func loadTopShelfContent(completionHandler: @escaping ((any TVTopShelfContent)?) -> Void) {
        completionHandler(contenu())
    }

    private func contenu() -> (any TVTopShelfContent)? {
        guard let etagere = EtagereDuHaut.lire() else { return nil }
        let collections = etagere.sections.filter { !$0.titres.isEmpty }.map { section in
            let elements = section.titres.map { titre in
                let element = TVTopShelfSectionedItem(identifier: titre.lien)
                element.title = titre.titre
                element.imageShape = .poster
                if let adresse = titre.affiche, let url = URL(string: adresse) {
                    element.setImageURL(url, for: .screenScale1x)
                    element.setImageURL(url, for: .screenScale2x)
                }
                if let lien = URL(string: titre.lien) {
                    element.displayAction = TVTopShelfAction(url: lien)
                    element.playAction = TVTopShelfAction(url: lien)
                }
                return element
            }
            let collection = TVTopShelfItemCollection(items: elements)
            collection.title = section.titre
            return collection
        }
        return collections.isEmpty ? nil : TVTopShelfSectionedContent(sections: collections)
    }
}
