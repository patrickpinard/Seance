import SwiftUI

/// Les briques des pages de réglage de la TV. Le `Form` de tvOS posait deux problèmes : sa page est transparente — le
/// texte de la page précédente se lisait au travers — et ses lignes passent au blanc quand elles ont le focus, sans
/// changer la couleur d'un texte secondaire, qui devenait blanc sur blanc. Ici, chaque état de couleur est explicite.

/// La coquille d'une page de réglage : fond opaque, titre, et une colonne centrée, lisible à trois mètres.
struct PageTV<Contenu: View>: View {
    let titre: String
    var sousTitre: String?
    @ViewBuilder let contenu: Contenu

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(titre).font(.system(size: 58, weight: .heavy))
                    if let sousTitre {
                        Text(sousTitre).font(.system(size: 26)).foregroundStyle(.secondary).frame(maxWidth: 1200, alignment: .leading)
                    }
                }
                contenu
            }
            .frame(maxWidth: 1500, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, MargesTV.bord)
            .padding(.top, 60)
            .padding(.bottom, 80)
        }
        // Opaque : sans cela, la page précédente se lit au travers.
        .background(Theme.fond.ignoresSafeArea())
    }
}

/// Un groupe de lignes : un intitulé, une carte, et une explication dessous.
struct SectionTV<Contenu: View>: View {
    var titre: String?
    var explication: String?
    @ViewBuilder let contenu: Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let titre {
                Text(titre.uppercased()).font(.system(size: 22, weight: .bold)).foregroundStyle(.secondary).padding(.leading, 8)
            }
            VStack(spacing: 4) {
                contenu
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            if let explication {
                Text(explication).font(.system(size: 23)).foregroundStyle(.secondary).frame(maxWidth: 1300, alignment: .leading).padding(.leading, 8)
            }
        }
        .focusSection()
    }
}

/// Une ligne qui s'ouvre ou qui agit. Blanche à texte noir quand elle a le focus, y compris son texte secondaire.
struct LigneTVReglage<Accessoire: View>: View {
    let titre: String
    var detail: String?
    var symbole: String?
    /// Vert ou orange à gauche : l'état d'un réglage.
    var enOrdre: Bool?
    /// Grisée et sans effet : une action en cours, ou une condition non remplie.
    var desactive = false
    var action: (() -> Void)?
    @ViewBuilder var accessoire: Accessoire


    var body: some View {
        if let action {
            Button(action: action) { corps }
                .buttonStyle(LigneTV())
                .disabled(desactive)
                .opacity(desactive ? 0.5 : 1)
        } else {
            corps.padding(.horizontal, 24).frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        }
    }

    private var corps: some View {
        Corps(titre: titre, detail: detail, symbole: symbole, enOrdre: enOrdre, accessoire: accessoire)
    }

    private struct Corps<A: View>: View {
        let titre: String
        let detail: String?
        let symbole: String?
        let enOrdre: Bool?
        let accessoire: A
        @Environment(\.isFocused) private var aLeFocus

        var body: some View {
            HStack(spacing: 20) {
                if let enOrdre {
                    Image(systemName: enOrdre ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(enOrdre ? Color.green : Color.orange)
                } else if let symbole {
                    Image(systemName: symbole).font(.system(size: 30)).foregroundStyle(aLeFocus ? AnyShapeStyle(Color.black) : AnyShapeStyle(Theme.accentClair))
                        .frame(width: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre).font(.system(size: 30, weight: .semibold))
                    if let detail {
                        // Sur fond blanc, un gris clair disparaît : le texte secondaire devient gris foncé.
                        Text(detail).font(.system(size: 23)).foregroundStyle(aLeFocus ? Color.black.opacity(0.65) : Color.white.opacity(0.65))
                    }
                }
                Spacer(minLength: 12)
                accessoire
            }
            .foregroundStyle(aLeFocus ? .black : .white)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        }
    }
}

extension LigneTVReglage where Accessoire == EmptyView {
    init(titre: String, detail: String? = nil, symbole: String? = nil, enOrdre: Bool? = nil, desactive: Bool = false, action: (() -> Void)? = nil) {
        self.init(titre: titre, detail: detail, symbole: symbole, enOrdre: enOrdre, desactive: desactive, action: action) { EmptyView() }
    }
}

/// Un chevron, une valeur, une coche : ce qui se met au bout d'une ligne, et suit sa couleur.
struct BoutTV: View {
    enum Forme { case chevron, coche(Bool), valeur(String), alerte(String) }
    let forme: Forme

    @Environment(\.isFocused) private var aLeFocus

    var body: some View {
        switch forme {
        case .chevron:
            Image(systemName: "chevron.right").font(.system(size: 26, weight: .bold)).opacity(0.45)
        case .coche(let coche):
            Image(systemName: coche ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 34))
                .foregroundStyle(coche ? (aLeFocus ? AnyShapeStyle(Color.black) : AnyShapeStyle(Theme.accentClair)) : AnyShapeStyle(.tertiary))
        case .valeur(let texte):
            Text(texte).font(.system(size: 26, weight: .medium)).opacity(0.7)
        case .alerte(let texte):
            Text(texte).font(.system(size: 24, weight: .bold)).foregroundStyle(Color.orange)
        }
    }
}

/// Une saisie : le champ s'ouvre en plein écran sur tvOS, la ligne montre ce qui est écrit.
struct ChampTV: View {
    let titre: String
    var invite: String = ""
    var secret = false
    @Binding var texte: String

    var body: some View {
        // Le libellé au-dessus du champ (6.3) : une fois rempli, un champ ne montre que sa valeur — « 192.168.1.220 »,
        // « admin » — et on ne sait plus ce qu'il demande. Au-dessus, le libellé reste lisible même quand le champ
        // prend le focus et passe au blanc.
        VStack(alignment: .leading, spacing: 0) {
            Text(titre).font(.system(size: 21, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            champ
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var champ: some View {
        if secret {
            SecureField(titre, text: $texte, prompt: Text(invite.isEmpty ? titre : invite))
                .textFieldStyle(.plain)
                .font(.system(size: 30))
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        } else {
            TextField(titre, text: $texte, prompt: Text(invite.isEmpty ? titre : invite))
                .textFieldStyle(.plain)
                .font(.system(size: 30))
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        }
    }
}

/// Une case à cocher, en ligne.
struct BasculeTV: View {
    let titre: String
    var detail: String?
    @Binding var actif: Bool

    var body: some View {
        LigneTVReglage(titre: titre, detail: detail, action: { actif.toggle() }) {
            BoutTV(forme: .coche(actif))
        }
    }
}

/// Une question posée en plein écran, avec les boutons de la charte (6.3). Les fenêtres du système (`alert`,
/// `confirmationDialog`) écrivaient parfois en blanc sur blanc sur la TV : ici, chaque couleur est explicite, et la
/// touche Retour referme.
struct DialogueTV: View {
    struct Choix: Identifiable {
        let libelle: String
        var principal = false
        let action: () -> Void

        var id: String { libelle }
    }

    let titre: String
    var message: String?
    let choix: [Choix]

    @Environment(\.dismiss) private var fermer

    var body: some View {
        ZStack {
            Theme.fond.ignoresSafeArea()
            VStack(spacing: 26) {
                Text(titre)
                    .font(.system(size: 50, weight: .heavy))
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 24) {
                    ForEach(choix) { un in
                        Button {
                            fermer()
                            un.action()
                        } label: {
                            Text(un.libelle)
                        }
                        .buttonStyle(BoutonTV(principal: un.principal))
                    }
                }
                .padding(.top, 10)
                Button("Annuler") { fermer() }
                    .buttonStyle(BoutonTV())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 1300)
            .padding(60)
        }
        .onExitCommand { fermer() }
    }
}
