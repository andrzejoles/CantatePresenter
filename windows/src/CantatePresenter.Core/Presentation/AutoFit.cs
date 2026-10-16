namespace CantatePresenter.Core.Presentation;

/// <summary>Pomiar szerokości tekstu daną czcionką (w Windows: DirectWrite/Win2D; w testach: przybliżenie).</summary>
public interface ITextMeasurer
{
    double Width(string text, string fontFamily, double size, bool bold);
}

/// <summary>
/// Auto-Fit: największa czcionka, przy której tekst slajdu mieści się na ekranie (jak AutoFitEngine w macOS i autofit.js):
/// wyszukiwanie binarne, 12 kroków, każde słowo musi się zmieścić w szerokości, a cały tekst w wysokości.
/// </summary>
public static class AutoFit
{
    private static double WrappedHeight(string text, ITextMeasurer m, string font, double size, bool bold, double width, double lineSpacing)
    {
        var lines = 0;
        foreach (var paragraph in text.Split('\n'))
        {
            var words = paragraph.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            lines++;
            var current = "";
            foreach (var word in words)
            {
                var candidate = current.Length > 0 ? current + " " + word : word;
                if (current.Length > 0 && m.Width(candidate, font, size, bold) > width) { lines++; current = word; }
                else current = candidate;
            }
        }
        return lines * size * 1.2 + Math.Max(0, lines - 1) * size * (lineSpacing - 1);
    }

    public static double OptimalFontSize(string text, double width, double height, ITextMeasurer measurer, string fontFamily = "Helvetica Neue",
        bool isBold = true, double lineSpacingFactor = 1.15, double marginPercent = 0.07, double minFontSize = 14, double maxFontSize = 260)
    {
        if (text.Trim().Length == 0) return 48;
        if (width <= 50 || height <= 50) return 24;
        var usableWidth = Math.Max(40, width * (1 - 2 * marginPercent)) * 0.99;
        var usableHeight = Math.Max(40, height * (1 - 2 * marginPercent)) * 0.99;
        var words = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        double low = minFontSize, high = maxFontSize, best = minFontSize;
        for (var step = 0; step < 12; step++)
        {
            var mid = (low + high) / 2;
            if (mid < minFontSize) break;
            if (words.Any(w => measurer.Width(w, fontFamily, mid, isBold) > usableWidth)) { high = mid; continue; }
            if (WrappedHeight(text, measurer, fontFamily, mid, isBold, usableWidth, lineSpacingFactor) <= usableHeight) { best = mid; low = mid; }
            else high = mid;
        }
        return Math.Max(minFontSize, Math.Floor(best));
    }
}
