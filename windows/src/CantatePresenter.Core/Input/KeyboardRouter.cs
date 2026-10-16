namespace CantatePresenter.Core.Input;

/// <summary>Skróty z ustawień: kody klawiszy macOS (ten sam settings.json we wszystkich wersjach).</summary>
public sealed record ShortcutSettings(
    int NextSlideKey = 49, int PrevSlideKey = 123, int PrevSongKey = 33, int NextSongKey = 30,
    int StartPresentationKey = 36, int StopPresentationKey = 53, int BlackScreenKey = 11, int ClearTextKey = 8);

public enum KeyFocus { Text, MultilineText, List, Other }

/// <summary>Kontekst klawisza: okno główne z danym fokusem albo okno projekcji. Inne okna (arkusze) nie są obsługiwane.</summary>
public sealed record KeyContext(bool IsPresentation, KeyFocus Focus = KeyFocus.Other)
{
    public static KeyContext Main(KeyFocus focus) => new(false, focus);
    public static readonly KeyContext Presentation = new(true);
}

public sealed record KeyboardAction(string Type, int? Number = null);

/// <summary>
/// Skróty klawiszowe: odpowiednik KeyboardRouter z wersji macOS (wzorzec). Zgodność pilnują shared/fixtures/keyboard.json.
/// Kolejność jak w macOS: skróty z Ctrl, skróty z ustawień, potem stałe klawisze.
/// </summary>
public static class KeyboardRouter
{
    private const int Escape = 53, Return = 36, Left = 123, Right = 124, Down = 125, Up = 126, PageDown = 121, PageUp = 116, R = 15;
    private static readonly HashSet<int> Digits = [18, 19, 20, 21, 23, 22, 26, 28, 25];
    private static readonly HashSet<int> NonTyping = [116, 121, 115, 119, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111];

    public static KeyboardAction? Action(int? macCode, string characters, bool command, ShortcutSettings shortcuts, KeyContext? context)
    {
        if (context is null || macCode is not int code) return null;
        var isMain = !context.IsPresentation;
        if (isMain && context.Focus == KeyFocus.MultilineText) return null;
        if (isMain && context.Focus == KeyFocus.Text)
        {
            if (code == Escape && !command) return new("endTextEditing");
            if (command || !NonTyping.Contains(code)) return null;
        }
        if (command)
        {
            if (!isMain) return null;
            return characters switch
            {
                "t" => new("quickText"),
                "=" or "+" => new("zoomIn"),
                "-" => new("zoomOut"),
                "0" => new("zoomReset"),
                _ => null,
            };
        }
        if (isMain && context.Focus == KeyFocus.List && (code == Up || code == Down)) return null;

        (int? Code, string Type)[] configured =
        [
            (shortcuts.NextSlideKey, "nextSlide"),
            (shortcuts.PrevSlideKey, "prevSlide"),
            (shortcuts.NextSongKey, "nextSong"),
            (shortcuts.PrevSongKey, "prevSong"),
            (shortcuts.StopPresentationKey, "stopPresentation"),
            (shortcuts.BlackScreenKey, "blackScreen"),
            (shortcuts.ClearTextKey, "clearText"),
            (context.IsPresentation ? null : shortcuts.StartPresentationKey, "startPresentation"),
        ];
        foreach (var (configuredCode, type) in configured)
        {
            if (configuredCode == code) return new(type);
        }

        if (code is Right or Down or PageDown) return new("nextSlide");
        if (code == Return && context.IsPresentation) return new("nextSlide");
        if (code is Left or Up or PageUp) return new("prevSlide");
        if (code == Escape) return new("stopPresentation");
        if (code == R) return new("chorus");
        if (Digits.Contains(code))
        {
            return int.TryParse(characters, out var number) && number is >= 1 and <= 9 ? new("verse", number) : null;
        }
        return null;
    }

    /// <summary>Klawisz Windows (Virtual-Key) → kod klawisza macOS, żeby skróty z settings.json działały tak samo.</summary>
    public static int? MacCode(int virtualKey) => virtualKey switch
    {
        >= 0x41 and <= 0x5A => LetterCodes[virtualKey - 0x41],
        >= 0x30 and <= 0x39 => DigitCodes[virtualKey - 0x30],
        0x20 => 49, 0x0D => 36, 0x1B => 53, 0x09 => 48, 0x08 => 51, 0x2E => 117,
        0x25 => 123, 0x27 => 124, 0x28 => 125, 0x26 => 126, 0x21 => 116, 0x22 => 121, 0x24 => 115, 0x23 => 119,
        0xDB => 33, 0xDD => 30, 0xBB => 24, 0xBD => 27, 0xBA => 41, 0xDE => 39, 0xDC => 42, 0xBC => 43, 0xBE => 47, 0xBF => 44, 0xC0 => 50,
        0x70 => 122, 0x71 => 120, 0x72 => 99, 0x73 => 118, 0x74 => 96, 0x75 => 97, 0x76 => 98, 0x77 => 100, 0x78 => 101, 0x79 => 109, 0x7A => 103, 0x7B => 111,
        _ => null,
    };

    // A..Z (kVK_ANSI_*): kolejność liter alfabetu.
    private static readonly int[] LetterCodes = [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6];
    // 0..9
    private static readonly int[] DigitCodes = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25];

    /// <summary>Nazwa klawisza do wyświetlenia (kod macOS).</summary>
    public static string KeyName(int macCode)
    {
        var letter = Array.IndexOf(LetterCodes, macCode);
        if (letter >= 0) return ((char)('A' + letter)).ToString();
        var digit = Array.IndexOf(DigitCodes, macCode);
        if (digit >= 0) return digit.ToString();
        return macCode switch
        {
            49 => "Spacja", 36 => "Enter", 53 => "Esc", 123 => "←", 124 => "→", 125 => "↓", 126 => "↑",
            33 => "[", 30 => "]", 116 => "Page Up", 121 => "Page Down", 48 => "Tab",
            _ => $"#{macCode}",
        };
    }
}
