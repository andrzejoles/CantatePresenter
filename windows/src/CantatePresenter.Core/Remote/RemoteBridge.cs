using System.Reflection;
using CantatePresenter.Core.Data;
using CantatePresenter.Core.Models;
using CantatePresenter.Core.Presentation;
using CantatePresenter.Core.Text;

namespace CantatePresenter.Core.Remote;

/// <summary>
/// Połączenie pilota z biblioteką (jak RemoteControlBridge w macOS): stan do wysłania, wykonanie poleceń, wyszukiwanie,
/// strony dla telefonu i tabletu. Wywoływać w wątku interfejsu, bo Library nie jest bezpieczna wątkowo.
/// </summary>
public static class RemoteBridge
{
    public static RemoteRouter Router(Library library, string token, string stageToken, Func<SongSlide, string> slideLabel) =>
        new(token, stageToken)
        {
            Page = () => Page("remote_page", library.Settings.AppLanguage),
            State = () => State(library, slideLabel),
            Perform = command => Perform(command, library),
            StagePage = () => Page("stage_page", library.Settings.AppLanguage),
            StageState = semitones => RemoteRouter.Encode(new StagePayload(MusicianStage.Make(library, semitones, slideLabel), StageLabels(library.Translate))),
            Search = query => RemoteRouter.Encode(Search(query, library)),
            Forbidden = () => library.Translate("Brak dostępu. Zeskanuj ponownie kod QR w aplikacji CantatePresenter.", []),
        };

    public sealed record StagePayload(MusicianStage Stage, IReadOnlyDictionary<string, string> Labels);

    // MARK: - Pages

    /// <summary>
    /// Strona z zasobów (te same pliki co w macOS: Sources/CantatePresenterCore/Resources/*.html).
    /// Język wstawiany tylko z liter i myślników.
    /// </summary>
    public static string Page(string name, string language)
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name + ".html");
        var template = stream is null ? $"<!doctype html><html lang=\"{{{{LANG}}}}\"><meta charset=\"utf-8\"><title>CantatePresenter</title><p>CantatePresenter: {name}.html</p></html>" : new StreamReader(stream).ReadToEnd();
        return template.Replace("{{LANG}}", new string(language.Where(c => char.IsLetter(c) || c == '-').ToArray()));
    }

    // MARK: - State

    public static RemoteState State(Library library, Func<SongSlide, string> slideLabel)
    {
        var song = library.ActiveSong;
        var plan = library.ActivePlan;
        var candidate = library.StartCandidate;
        return new RemoteState(
            library.IsLive,
            library.IsBlackScreen,
            library.IsClearText,
            song?.Title ?? "",
            library.ActiveSlideIndex,
            library.CurrentLiveSlide?.Text ?? "",
            (song?.Slides ?? []).Select(s => new RemoteSlideInfo(slideLabel(s), FirstLine(s.Text))).ToList(),
            plan?.Name ?? "",
            (plan?.Items ?? []).Select(i => new RemotePlanEntry(library.SongById(i.SongId)?.Title ?? "?", i.SongId == song?.Id)).ToList(),
            Labels(library.Translate),
            !library.IsLive && candidate is not null,
            library.IsLive ? "" : candidate?.Title ?? "");
    }

    private static string FirstLine(string text) => text.Split('\n')[0];

    // MARK: - Commands

    public static void Perform(RemoteCommand command, Library library)
    {
        switch (command)
        {
            case RemoteCommand.Next: library.NextSlide(); break;
            case RemoteCommand.Previous: library.PrevSlide(); break;
            case RemoteCommand.NextSong: library.NextSongInPlan(); break;
            case RemoteCommand.PreviousSong: library.PrevSongInPlan(); break;
            case RemoteCommand.Black: library.ToggleBlackScreen(); break;
            case RemoteCommand.ClearText: library.ToggleClearText(); break;
            case RemoteCommand.Stop: library.StopLive(); break;
            case RemoteCommand.Start: library.StartOrResume(); break;
            case RemoteCommand.Slide(var index):
                if (!library.IsLive && library.ActiveSong is Song active && index < active.Slides.Count) library.Present(active, index);
                else library.JumpToSlide(index);
                break;
            case RemoteCommand.Song(var id):
                if (library.Songs.FirstOrDefault(s => string.Equals(s.Id, id, StringComparison.OrdinalIgnoreCase)) is Song found)
                {
                    library.Present(found);
                    library.SelectSong(found.Id);
                }
                break;
            case RemoteCommand.PlanItem(var index):
                if (library.ActivePlan?.Items is { } items && index < items.Count && library.SongById(items[index].SongId) is Song planned)
                {
                    library.Present(planned);
                    library.SelectSong(planned.Id);
                }
                break;
        }
    }

    // MARK: - Search

    /// <summary>Pieśni pasujące do zapytania (jak lista w aplikacji): najpierw trafienia w tytule lub autorze.</summary>
    public static List<RemoteSearchResult> Search(string query, Library library, int limit = 40)
    {
        if (TextFold.SearchFold(query).Length == 0) return [];
        var all = library.FilteredSongs(query, SearchScope.All);
        var titled = all.Where(s => SongSearch.Matches(s.Title, s.Author, s.Tags, s.RawLyrics, query, SearchScope.TitleAndAuthor)).ToHashSet();
        return all.Where(titled.Contains).Concat(all.Where(s => !titled.Contains(s))).Take(limit)
            .Select(s => new RemoteSearchResult(s.Id, s.Title, s.Author, FirstLine(s.Slides.FirstOrDefault()?.Text ?? ""))).ToList();
    }

    // MARK: - Labels

    /// <summary>Teksty strony telefonu w języku interfejsu aplikacji.</summary>
    public static Dictionary<string, string> Labels(Func<string, object[], string> t) => new()
    {
        ["next"] = t("Dalej", []),
        ["previous"] = t("Wstecz", []),
        ["nextSong"] = t("Następna pieśń", []),
        ["previousSong"] = t("Poprzednia pieśń", []),
        ["black"] = t("Czarny ekran", []),
        ["clearText"] = t("Ukryj tekst", []),
        ["stop"] = t("Zakończ projekcję", []),
        ["slides"] = t("Slajdy", []),
        ["plan"] = t("Plan", []),
        ["notLive"] = t("Projekcja nie jest uruchomiona. Wybierz pieśń z planu lub wyszukaj ją.", []),
        ["start"] = t("Rozpocznij projekcję", []),
        ["resume"] = t("Wznów projekcję", []),
        ["search"] = t("Szukaj pieśni", []),
        ["searchPlaceholder"] = t("Tytuł, autor lub fragment tekstu", []),
        ["noResults"] = t("Nie znaleziono pieśni", []),
        ["offline"] = t("Brak połączenia z komputerem. Sprawdź, czy telefon jest w tej samej sieci Wi-Fi.", []),
        ["title"] = t("Pilot CantatePresenter", []),
    };

    /// <summary>Teksty strony dla muzyków; „{0}” wstawia strona.</summary>
    public static Dictionary<string, string> StageLabels(Func<string, object[], string> t) => new()
    {
        ["title"] = t("Ekran dla muzyków", []),
        ["key"] = t("Tonacja: {0}", []),
        ["next"] = t("Następny slajd", []),
        ["nextSong"] = t("Następnie: {0}", []),
        ["borrowed"] = t("Chwyty jak w: {0}", []),
        ["noChords"] = t("Brak chwytów dla tej pieśni", []),
        ["notLive"] = t("Brak aktywnej prezentacji", []),
        ["black"] = t("CZARNY EKRAN", []),
        ["clear"] = t("TEKST UKRYTY", []),
        ["transpose"] = t("Transpozycja", []),
        ["font"] = t("Czcionka", []),
        ["offline"] = t("Brak połączenia z komputerem. Sprawdź, czy telefon jest w tej samej sieci Wi-Fi.", []),
    };
}
