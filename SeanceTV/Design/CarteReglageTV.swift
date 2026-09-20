import SeanceKit
import SwiftUI

/// Une grande carte de réglage sur la TV, dans le dessin des cartes de « Ce soir » : une affiche de tes titres floutée en
/// fond, le symbole de l'app en orange, le nom en gros, l'état en pastille et sa valeur dessous. `enOrdre == nil` : une
/// action ou une page sans état (« Tes goûts », « À propos »).
struct CarteReglageTV: View {
    let titre: String
    let symbole: String
    let detail: String
    let enOrdre: Bool?
    var cheminAffiche: String?

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                if let enOrdre {
                    Label(enOrdre ? "En ordre" : "À régler", systemImage: enOrdre ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(enOrdre ? Color.green : Color.orange)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                Text(titre).font(.system(size: 34, weight: .heavy)).lineLimit(2).minimumScaleFactor(0.75)
                Text(detail).font(.system(size: 22)).foregroundStyle(.white.opacity(0.8)).lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: symbole).font(.system(size: 58, weight: .semibold)).foregroundStyle(Theme.degradeAccent).frame(width: 80)
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 210, maxHeight: 210, alignment: .leading)
        .background {
            ZStack {
                Theme.surface
                if let cheminAffiche {
                    ImageTV(url: ImageTMDB.url(cheminAffiche, .afficheGrande), symboleVide: "").blur(radius: 10)
                }
                LinearGradient(colors: [.black.opacity(0.92), .black.opacity(0.6), .black.opacity(0.25)], startPoint: .leading, endPoint: .trailing)
            }
        }
        .clipped()
    }
}
