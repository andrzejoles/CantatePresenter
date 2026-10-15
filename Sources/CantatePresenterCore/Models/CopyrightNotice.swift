import Foundation

// MARK: - Copyright Notice

/// Informacja o prawach autorskich na slajdzie dla pieśni z numerem CCLI. Licencja CCLI wymaga, żeby przy wyświetlaniu
/// tekstu pokazać tytuł, autorów, linię ©, numer pieśni i numer licencji (na pierwszym lub ostatnim slajdzie).
public enum CopyrightNotice {
    public static func text(for song: Song, slideIndex: Int, settings: AppSettings) -> String? {
        guard let ccliNumber = song.ccliNumber?.trimmingCharacters(in: .whitespaces), !ccliNumber.isEmpty else { return nil }
        
        let isShown: Bool
        switch settings.copyrightNoticePlacement {
        case .none: isShown = false
        case .firstSlide: isShown = slideIndex == 0
        case .lastSlide: isShown = slideIndex == song.slides.count - 1
        case .allSlides: isShown = true
        }
        guard isShown else { return nil }
        
        var parts = [song.title]
        let author = song.author.trimmingCharacters(in: .whitespaces)
        if !author.isEmpty { parts.append(author) }
        if let copyright = song.copyright?.trimmingCharacters(in: .whitespaces), !copyright.isEmpty { parts.append(copyright) }
        parts.append(Lnow("Pieśń CCLI nr {0}", ccliNumber))
        let license = settings.ccliLicenseNumber.trimmingCharacters(in: .whitespaces)
        if !license.isEmpty { parts.append(Lnow("Licencja CCLI nr {0}", license)) }
        return parts.joined(separator: " · ")
    }
}
