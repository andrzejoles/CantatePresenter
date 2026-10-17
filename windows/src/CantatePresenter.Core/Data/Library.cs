using System.Globalization;
using System.Text.Json.Nodes;
using CantatePresenter.Core.Models;
using CantatePresenter.Core.Text;

namespace CantatePresenter.Core.Data;

public enum PersistenceIssueKind { Unreadable, SaveFailed, NewerSchema }

/// <summary>Problem z plikiem danych do pokazania użytkownikowi (jak PersistenceIssue w macOS).</summary>
public sealed record PersistenceIssue(PersistenceIssueKind Kind, string FileName, string? QuarantinedCopy, string Detail);

/// <summary>
/// Stan aplikacji: odpowiednik DataStore z macOS (biblioteka, plany, ustawienia, projekcja na żywo) bez UI.
/// Zapis po każdej zmianie przez <see cref="JsonFileStore"/>; nieczytelny plik nie jest nadpisywany,
/// a dane z nowszej wersji formatu są tylko do odczytu.
/// </summary>
public sealed class Library
{
    private readonly AppPaths paths;
    private readonly JsonFileStore store = new();
    private readonly HashSet<string> locked = [];

    public List<Song> Songs { get; private set; } = [];
    public List<ServicePlan> Plans { get; private set; } = [];
    public AppSettings Settings { get; private set; } = AppSettings.Default();
    public List<CcliUsageEntry> CcliUsage { get; private set; } = [];
    public List<PersistenceIssue> Issues { get; } = [];
    public bool IsReadOnlyNewerSchema { get; private set; }

    public string? ActivePlanId { get; set; }
    public string? SelectedSongId { get; private set; }
    public Song? ActiveSong { get; private set; }
    public int ActiveSlideIndex { get; private set; }
    public bool IsLive { get; private set; }
    public bool IsBlackScreen { get; private set; }
    public bool IsClearText { get; private set; }
    /// <summary>Pieśń z szybkiego tekstu: na ekranie, ale nie w bibliotece.</summary>
    public Song? TemporarySong { get; private set; }
    /// <summary>Ostatnia pieśń z planu; po szybkim tekście plan idzie dalej od niej (N11).</summary>
    private string? lastPlanSongId;

    /// <summary>Powód zmiany: „songs”, „plans”, „settings”, „live”, „selection”, „all”.</summary>
    public event Action<string>? Changed;

    /// <summary>Tłumaczenie tekstów (klucz = polski tekst, wartości {0}, {1}).</summary>
    public Func<string, object[], string> Translate { get; set; } = (key, args) => Format(key, args);

    public static string Format(string template, object[] args)
    {
        var result = template;
        for (var i = 0; i < args.Length; i++) result = result.Replace("{" + i + "}", Convert.ToString(args[i], CultureInfo.CurrentCulture));
        return result;
    }

    public Library(AppPaths paths)
    {
        this.paths = paths;
        Directory.CreateDirectory(paths.DataDirectory);
        LoadAll();
    }

    public string DataDirectory => paths.DataDirectory;

    // MARK: - Persistence

    public void LoadAll()
    {
        LoadSettings();
        LoadSongs();
        LoadPlans();
        LoadCcliUsage();
        Changed?.Invoke("all");
    }

    private JsonNode? Load(string path, out bool missing)
    {
        var name = Path.GetFileName(path);
        var result = store.Load(path);
        missing = result.Status == LoadStatus.Missing;
        Issues.RemoveAll(i => i.Kind == PersistenceIssueKind.Unreadable && i.FileName == name);
        if (result.Status == LoadStatus.Unreadable)
        {
            locked.Add(name);
            Issues.Add(new PersistenceIssue(PersistenceIssueKind.Unreadable, name, result.QuarantinedCopy, result.Error ?? ""));
            return null;
        }
        locked.Remove(name);
        return result.Value;
    }

    private void LoadSettings()
    {
        var node = Load(paths.SettingsFile, out var missing);
        Settings = AppSettings.FromJson(node);
        Issues.RemoveAll(i => i.Kind == PersistenceIssueKind.NewerSchema);
        IsReadOnlyNewerSchema = Settings.OriginalSchemaVersion > AppSettings.SchemaVersionCurrent;
        if (IsReadOnlyNewerSchema)
        {
            Issues.Add(new PersistenceIssue(PersistenceIssueKind.NewerSchema, Settings.OriginalSchemaVersion.ToString(CultureInfo.InvariantCulture), null, ""));
        }
        else if (missing || Settings.OriginalSchemaVersion < AppSettings.SchemaVersionCurrent)
        {
            SaveSettings();
        }
    }

    private void LoadSongs()
    {
        var node = Load(paths.SongsFile, out var missing);
        if (missing)
        {
            Songs = SampleSongs.Create();
            SaveSongs();
        }
        else
        {
            Songs = node is JsonArray array ? array.Select(Song.FromJson).ToList() : [];
            Songs = AssignUniqueIdentifiers(Songs, []);
        }
        SelectedSongId ??= Songs.FirstOrDefault()?.Id;
    }

    private void LoadPlans()
    {
        var node = Load(paths.PlansFile, out var missing);
        if (missing)
        {
            var plan = ServicePlan.Create(Translate("Niedziela - Zestaw pieśni", []));
            plan.Items = Songs.Take(4).Select(s => new PlanItem(Json.NewId(), s.Id, "")).ToList();
            Plans = [plan];
            SavePlans();
        }
        else
        {
            Plans = node is JsonArray array ? array.Select(ServicePlan.FromJson).OfType<ServicePlan>().ToList() : [];
        }
        if (ActivePlanId is null || Plans.All(p => p.Id != ActivePlanId)) ActivePlanId = Plans.FirstOrDefault()?.Id;
    }

    private void LoadCcliUsage()
    {
        var node = Load(paths.CcliUsageFile, out _);
        CcliUsage = node is JsonArray array ? array.Select(CcliUsageEntry.FromJson).ToList() : [];
    }

    private void Persist(JsonNode value, string path)
    {
        var name = Path.GetFileName(path);
        if (IsReadOnlyNewerSchema || locked.Contains(name)) return;
        try
        {
            store.Save(value, path);
            Issues.RemoveAll(i => i.Kind == PersistenceIssueKind.SaveFailed && i.FileName == name);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            if (!Issues.Any(i => i.Kind == PersistenceIssueKind.SaveFailed && i.FileName == name))
            {
                Issues.Add(new PersistenceIssue(PersistenceIssueKind.SaveFailed, name, null, error.Message));
            }
        }
    }

    public void SaveSongs()
    {
        Persist(new JsonArray(Songs.Select(s => (JsonNode?)s.ToJson()).ToArray()), paths.SongsFile);
        Changed?.Invoke("songs");
    }

    public void SavePlans()
    {
        Persist(new JsonArray(Plans.Select(p => (JsonNode?)p.ToJson()).ToArray()), paths.PlansFile);
        Changed?.Invoke("plans");
    }

    public void SaveSettings()
    {
        Persist(Settings.ToJson(), paths.SettingsFile);
        Changed?.Invoke("settings");
    }

    private void SaveCcliUsage() => Persist(new JsonArray(CcliUsage.Select(e => (JsonNode?)e.ToJson()).ToArray()), paths.CcliUsageFile);

    /// <summary>Zajęte identyfikatory (w bibliotece albo dwa razy w imporcie) dostają nowe (W8).</summary>
    public static List<Song> AssignUniqueIdentifiers(IEnumerable<Song> songs, IEnumerable<string> existing)
    {
        var used = existing.ToHashSet();
        var result = new List<Song>();
        foreach (var song in songs)
        {
            if (used.Contains(song.Id))
            {
                song.Id = Json.NewId();
                song.Slides = song.Slides.Select(s => s with { Id = Json.NewId() }).ToList();
            }
            used.Add(song.Id);
            result.Add(song);
        }
        return result;
    }

    // MARK: - Library

    public ServicePlan? ActivePlan => Plans.FirstOrDefault(p => p.Id == ActivePlanId) ?? Plans.FirstOrDefault();

    public Song? SelectedSong =>
        Songs.FirstOrDefault(s => s.Id == SelectedSongId) ?? (TemporarySong?.Id == SelectedSongId ? TemporarySong : null);

    public Song? SongById(string id) => Songs.FirstOrDefault(s => s.Id == id);

    public void SelectSong(string? id)
    {
        SelectedSongId = id;
        Changed?.Invoke("selection");
    }

    public Song AddSong(Song song)
    {
        song = AssignUniqueIdentifiers([song], Songs.Select(s => s.Id))[0];
        Songs.Insert(0, song);
        SelectedSongId = song.Id;
        SaveSongs();
        return song;
    }

    public void AddSongs(IEnumerable<Song> songs)
    {
        var added = AssignUniqueIdentifiers(songs, Songs.Select(s => s.Id));
        Songs.AddRange(added);
        SelectedSongId ??= added.FirstOrDefault()?.Id;
        SaveSongs();
    }

    public void UpdateSong(Song song)
    {
        var index = Songs.FindIndex(s => s.Id == song.Id);
        if (index < 0) return;
        song.Slides = Song.SlidesFromLyrics(song.RawLyrics);
        song.UpdatedAt = Json.IsoDate();
        Songs[index] = song;
        if (ActiveSong?.Id == song.Id)
        {
            ActiveSong = song;
            ActiveSlideIndex = Math.Min(ActiveSlideIndex, Math.Max(0, song.Slides.Count - 1));
        }
        SaveSongs();
    }

    public void DeleteSong(string id)
    {
        Songs.RemoveAll(s => s.Id == id);
        if (SelectedSongId == id) SelectedSongId = Songs.FirstOrDefault()?.Id;
        if (ActiveSong?.Id == id) StopLive();
        foreach (var plan in Plans) plan.Items.RemoveAll(i => i.SongId == id);
        SaveSongs();
        SavePlans();
    }

    private static readonly CompareInfo Polish = CultureInfo.GetCultureInfo("pl-PL").CompareInfo;

    /// <summary>Biblioteka po wyszukiwaniu, posortowana po tytule (polskie zasady sortowania).</summary>
    public List<Song> FilteredSongs(string query, SearchScope scope = SearchScope.All)
    {
        var list = TextFold.SearchFold(query).Length > 0
            ? Songs.Where(s => SongSearch.Matches(s.Title, s.Author, s.Tags, s.RawLyrics, query, scope)).ToList()
            : Songs.ToList();
        list.Sort((a, b) => Polish.Compare(a.Title, b.Title, CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace));
        return list;
    }

    // MARK: - Plans

    public ServicePlan CreatePlan(string name)
    {
        var plan = ServicePlan.Create(name);
        Plans.Add(plan);
        ActivePlanId = plan.Id;
        SavePlans();
        return plan;
    }

    public void DeletePlan(string id)
    {
        Plans.RemoveAll(p => p.Id == id);
        if (ActivePlanId == id) ActivePlanId = Plans.FirstOrDefault()?.Id;
        SavePlans();
    }

    public void RenamePlan(string id, string name)
    {
        var plan = Plans.FirstOrDefault(p => p.Id == id);
        if (plan is null || name.Trim().Length == 0) return;
        plan.Name = name.Trim();
        plan.UpdatedAt = Json.IsoDate();
        SavePlans();
    }

    public void SetActivePlan(string? id)
    {
        ActivePlanId = id;
        Changed?.Invoke("plans");
    }

    public void AddSongToPlan(string songId)
    {
        if (ActivePlan is not ServicePlan plan) return;
        plan.Items.Add(new PlanItem(Json.NewId(), songId, ""));
        plan.UpdatedAt = Json.IsoDate();
        SavePlans();
    }

    public void RemovePlanItem(string itemId)
    {
        if (ActivePlan is not ServicePlan plan) return;
        plan.Items.RemoveAll(i => i.Id == itemId);
        plan.UpdatedAt = Json.IsoDate();
        SavePlans();
    }

    public void MovePlanItem(int from, int to)
    {
        if (ActivePlan is not ServicePlan plan || from == to || from < 0 || from >= plan.Items.Count) return;
        var item = plan.Items[from];
        plan.Items.RemoveAt(from);
        plan.Items.Insert(Math.Clamp(to, 0, plan.Items.Count), item);
        plan.UpdatedAt = Json.IsoDate();
        SavePlans();
    }

    // MARK: - Presentation

    public SongSlide? CurrentLiveSlide =>
        ActiveSong is Song song && ActiveSlideIndex >= 0 && ActiveSlideIndex < song.Slides.Count ? song.Slides[ActiveSlideIndex] : null;

    public string? CurrentCopyrightNotice => ActiveSong is Song song ? Ccli.Notice(song, ActiveSlideIndex, Settings, Translate) : null;

    public void Present(Song song, int slideIndex = 0)
    {
        if (ActivePlan?.Items.Any(i => i.SongId == song.Id) == true) lastPlanSongId = song.Id;
        ActiveSong = song;
        ActiveSlideIndex = Math.Clamp(slideIndex, 0, Math.Max(0, song.Slides.Count - 1));
        IsLive = true;
        IsBlackScreen = false;
        IsClearText = false;
        RecordCcliUsage(song, DateTimeOffset.Now);
        Changed?.Invoke("live");
    }

    public void RecordCcliUsage(Song song, DateTimeOffset date)
    {
        if (Ccli.UsageEntry(song, date, CcliUsage) is not CcliUsageEntry entry) return;
        CcliUsage.Add(entry);
        SaveCcliUsage();
    }

    /// <summary>Tekst na ekran bez zapisywania w bibliotece.</summary>
    public void PresentQuickText(string text, string? title)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0) return;
        var name = string.IsNullOrWhiteSpace(title) ? Translate("Szybki tekst", []) : title.Trim();
        TemporarySong = Song.Create(name, "Tymczasowy", tags: [Translate("Szybki tekst", [])], rawLyrics: trimmed);
        SelectedSongId = TemporarySong.Id;
        Present(TemporarySong);
    }

    public void NextSlide()
    {
        if (ActiveSong is not Song song) return;
        if (ActiveSlideIndex < song.Slides.Count - 1)
        {
            ActiveSlideIndex++;
            IsClearText = IsBlackScreen = false;
            Changed?.Invoke("live");
        }
        else
        {
            NextSongInPlan();
        }
    }

    public void PrevSlide()
    {
        if (ActiveSong is null || ActiveSlideIndex == 0) return;
        ActiveSlideIndex--;
        IsClearText = IsBlackScreen = false;
        Changed?.Invoke("live");
    }

    public void JumpToSlide(int index)
    {
        if (ActiveSong is not Song song || index < 0 || index >= song.Slides.Count) return;
        ActiveSlideIndex = index;
        IsClearText = IsBlackScreen = false;
        Changed?.Invoke("live");
    }

    /// <summary>Po numerze zwrotki, nie po etykiecie (S10).</summary>
    public void JumpToVerse(int number)
    {
        if (ActiveSong is not Song song) return;
        var index = song.Slides.FindIndex(s => s.Type == SlideTypes.Verse && s.Number == number);
        if (index >= 0) JumpToSlide(index);
        else if (number - 1 < song.Slides.Count) JumpToSlide(number - 1);
    }

    public void JumpToChorus()
    {
        var index = ActiveSong?.Slides.FindIndex(s => s.Type == SlideTypes.Chorus) ?? -1;
        if (index >= 0) JumpToSlide(index);
    }

    public void ToggleBlackScreen() { IsBlackScreen = !IsBlackScreen; Changed?.Invoke("live"); }
    public void ToggleClearText() { IsClearText = !IsClearText; Changed?.Invoke("live"); }

    public void StopLive()
    {
        IsLive = IsBlackScreen = IsClearText = false;
        Changed?.Invoke("live");
    }

    /// <summary>Start albo wznowienie po zatrzymaniu (jak pilot w macOS): ta sama pieśń i slajd, inaczej zaznaczona albo pierwsza z planu.</summary>
    public void StartOrResume()
    {
        if (IsLive || StartCandidate is not Song song) return;
        Present(song, song.Id == ActiveSong?.Id ? ActiveSlideIndex : 0);
    }

    /// <summary>Pieśń, którą uruchomi „Start”: ostatnio wyświetlana, zaznaczona albo pierwsza z planu.</summary>
    public Song? StartCandidate =>
        ActiveSong ?? SelectedSong ?? ActivePlan?.Items.Select(i => SongById(i.SongId)).FirstOrDefault(s => s is not null);

    /// <summary>Pozycja w planie: bieżącej pieśni albo (po szybkim tekście) ostatniej pieśni z planu.</summary>
    public int? CurrentPlanIndex(ServicePlan plan)
    {
        var anchor = ActiveSong is Song song && plan.Items.Any(i => i.SongId == song.Id) ? song.Id : lastPlanSongId;
        var index = anchor is null ? -1 : plan.Items.FindIndex(i => i.SongId == anchor);
        return index >= 0 ? index : null;
    }

    public void NextSongInPlan()
    {
        if (ActivePlan is not ServicePlan plan || plan.Items.Count == 0) return;
        var nextIndex = CurrentPlanIndex(plan) is int current ? current + 1 : 0;
        if (nextIndex < plan.Items.Count && SongById(plan.Items[nextIndex].SongId) is Song next)
        {
            Present(next);
            SelectedSongId = next.Id;
        }
    }

    public void PrevSongInPlan()
    {
        if (ActivePlan is not ServicePlan plan || plan.Items.Count == 0) return;
        if (CurrentPlanIndex(plan) is not int current || current == 0) return;
        if (SongById(plan.Items[current - 1].SongId) is Song previous)
        {
            Present(previous);
            SelectedSongId = previous.Id;
        }
    }

    /// <summary>Pieśń, która zabrzmi po bieżącej według planu (podgląd dla muzyków), bez zmiany projekcji.</summary>
    public Song? UpcomingSongInPlan
    {
        get
        {
            if (ActivePlan is not ServicePlan plan || plan.Items.Count == 0) return null;
            var nextIndex = CurrentPlanIndex(plan) is int current ? current + 1 : 0;
            return nextIndex < plan.Items.Count ? SongById(plan.Items[nextIndex].SongId) : null;
        }
    }

    /// <summary>Następny slajd do podglądu: kolejny w pieśni albo pierwszy następnej pieśni z planu.</summary>
    public SongSlide? NextSlidePreview
    {
        get
        {
            if (ActiveSong is not Song song) return null;
            if (ActiveSlideIndex + 1 < song.Slides.Count) return song.Slides[ActiveSlideIndex + 1];
            if (ActivePlan is not ServicePlan plan || CurrentPlanIndex(plan) is not int current || current + 1 >= plan.Items.Count) return null;
            return SongById(plan.Items[current + 1].SongId)?.Slides.FirstOrDefault();
        }
    }

    // MARK: - Settings

    public void UpdateSettings(Action<AppSettings> change)
    {
        change(Settings);
        SaveSettings();
    }

    /// <summary>Podmienia wszystkie dane (przywrócenie kopii zapasowej), po wczytaniu z dysku.</summary>
    public void Reload()
    {
        StopLive();
        ActiveSong = null;
        TemporarySong = null;
        SelectedSongId = null;
        LoadAll();
    }
}
