import Foundation

public enum ENDLogoAsset {
    /// Oficjalne logo Equipes Notre-Dame (end.org.pl) jako base64 do osadzenia w SVG/HTML.
    /// Plik PNG leży w zasobach pakietu (N9), a nie jako 50 KB tekstu w kodzie.
    public static let base64PNG: String = {
        guard let url = Localization.resourceBundle?.url(forResource: "end_logo", withExtension: "png"),
              let data = try? Data(contentsOf: url) else {
            return ""
        }
        return data.base64EncodedString()
    }()
}
