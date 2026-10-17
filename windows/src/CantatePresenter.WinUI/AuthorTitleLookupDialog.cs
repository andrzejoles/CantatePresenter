using CantatePresenter.Core.Models;
using CantatePresenter.Core.Online;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Wyszukiwarka tytułu i autora (AuthorTitleLookupSheet w macOS): dla zaznaczonej pieśni (lista propozycji z przyciskami)
/// albo dla wszystkich (propozycje z oceną zgodności, zaznaczanie i zastosowanie). Kandydaci z Wikiźródeł.
/// </summary>
public static class AuthorTitleLookupDialog
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };

    private static async Task<List<(LookupCandidate Candidate, string Lyrics)>> SearchAsync(string query, CancellationToken cancel)
    {
        var results = await Wikisource.SearchAsync(Http, query, Services.Library.Settings.OnlineSearchLanguage, Services.Version, cancel);
        return results.Select(r => (AuthorTitleLookup.FromWikisource(r, L("Wikiźródła")), r.Lyrics)).ToList();
    }

    public static async Task ShowAsync(MainWindow window, Song? initial)
    {
        var library = Services.Library;
        using var cancel = new CancellationTokenSource();
        var target = initial is not null && initial != library.TemporarySong ? initial : library.SelectedSong is Song s && s != library.TemporarySong ? s : library.Songs.FirstOrDefault();

        // MARK: Zakres
        var singleTab = new ToggleButton { Content = L("Dla zaznaczonej pieśni"), IsChecked = true, MinWidth = 170, CornerRadius = new CornerRadius(4, 0, 0, 4) };
        var batchTab = new ToggleButton { Content = L("Dla wszystkich pieśni"), MinWidth = 170, CornerRadius = new CornerRadius(0, 4, 4, 0) };
        var scopeRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        scopeRow.Children.Add(new TextBlock { Text = L("Zakres operacji:"), FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });
        var scopeButtons = new StackPanel { Orientation = Orientation.Horizontal };
        scopeButtons.Children.Add(singleTab);
        scopeButtons.Children.Add(batchTab);
        scopeRow.Children.Add(scopeButtons);

        // MARK: Jedna pieśń
        var songPicker = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var song in library.Songs)
        {
            songPicker.Items.Add(new ComboBoxItem { Content = song.Title + (song.Author.Trim().Length == 0 ? L(" (brak autora)") : $" — {song.Author}"), Tag = song.Id });
            if (song.Id == target?.Id) songPicker.SelectedIndex = songPicker.Items.Count - 1;
        }
        var query = new TextBox { PlaceholderText = L("Wpisz fragment tekstu lub tytuł..."), Text = target is null ? "" : AuthorTitleLookup.SuggestedQuery(target) };
        var searchButton = new Button { Content = L("Szukaj"), Style = (Style)Application.Current.Resources["AccentButtonStyle"], MinWidth = 70 };
        var message = new TextBlock { Foreground = Ui.Brush(Ui.Green), FontWeight = FontWeights.Medium, TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed };
        var pickerBlock = new StackPanel { Spacing = 4 };
        pickerBlock.Children.Add(new TextBlock { Text = L("Aktualna pieśń:"), FontSize = 12, FontWeight = FontWeights.Bold, Foreground = Ui.Secondary });
        pickerBlock.Children.Add(songPicker);
        var queryBlock = new StackPanel { Spacing = 4 };
        queryBlock.Children.Add(new TextBlock { Text = L("Fraza wyszukiwania (tytuł lub fragment tekstu):"), FontSize = 12, FontWeight = FontWeights.Bold, Foreground = Ui.Secondary });
        queryBlock.Children.Add(Ui.Columns(6, (query, -1), (Dictation.Button(query, DictationMode.Replace), 0), (searchButton, 0)));
        var singleTop = new StackPanel { Spacing = 10 };
        singleTop.Children.Add(Ui.Columns(16, (pickerBlock, 320), (queryBlock, -1)));
        singleTop.Children.Add(message);
        var results = new StackPanel { Spacing = 6 };
        var resultsScroll = new ScrollViewer { Content = results, Height = 340, Padding = new Thickness(0, 0, 12, 0) };
        var single = new StackPanel { Spacing = 12 };
        single.Children.Add(singleTop);
        single.Children.Add(Ui.Divider());
        single.Children.Add(resultsScroll);

        Song? Current() => (songPicker.SelectedItem as ComboBoxItem)?.Tag is string id ? library.SongById(id) : null;
        static StackPanel Centered(string glyph, string text, string? detail = null, bool busy = false)
        {
            var panel = new StackPanel { Spacing = 12, HorizontalAlignment = HorizontalAlignment.Center, Padding = new Thickness(0, 60, 0, 0) };
            panel.Children.Add(busy ? new ProgressRing { IsActive = true, Width = 28, Height = 28 } : new FontIcon { Glyph = glyph, FontFamily = Ui.SymbolFont, FontSize = 40, Foreground = Ui.Secondary, Opacity = 0.35 });
            panel.Children.Add(new TextBlock { Text = text, FontSize = 14, Foreground = Ui.Secondary, HorizontalAlignment = HorizontalAlignment.Center, TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap });
            if (detail is not null) panel.Children.Add(new TextBlock { Text = detail, FontSize = 12, Foreground = Ui.Secondary, Opacity = 0.85, HorizontalAlignment = HorizontalAlignment.Center, TextWrapping = TextWrapping.Wrap });
            return panel;
        }
        void ApplyCandidate(LookupCandidate candidate, bool updateTitle, bool unknownAuthor)
        {
            if (Current() is not Song song) return;
            if (updateTitle && candidate.Title.Length > 0) song.Title = candidate.Title;
            if (unknownAuthor) song.Author = L("Nieznany");
            else if (candidate.Artist.Length > 0) song.Author = candidate.Artist;
            library.UpdateSong(song);
            message.Text = "✓ " + L("Zaktualizowano dane utworu: {0} (Autor: {1})", song.Title, song.Author);
            message.Visibility = Visibility.Visible;
        }
        async Task RunSingle()
        {
            var text = query.Text.Trim();
            if (text.Length == 0 || Current() is null) return;
            message.Visibility = Visibility.Collapsed;
            searchButton.IsEnabled = false;
            results.Children.Clear();
            results.Children.Add(Centered("", L("Wyszukiwanie tytułu i autora w bazie hymnów i sieci..."), busy: true));
            List<(LookupCandidate Candidate, string Lyrics)> found;
            try
            {
                found = await SearchAsync(text, cancel.Token);
            }
            catch (Exception error) when (error is HttpRequestException or TaskCanceledException or OperationCanceledException)
            {
                results.Children.Clear();
                results.Children.Add(Centered(Glyphs.Warning, L("Błąd połączenia: {0}", error.Message)));
                searchButton.IsEnabled = true;
                return;
            }
            searchButton.IsEnabled = true;
            results.Children.Clear();
            if (found.Count == 0)
            {
                results.Children.Add(Centered(Glyphs.Search, L("Nie znaleziono propozycji dla podanej frazy."), L("Spróbuj wpisać inny fragment tekstu lub pierwsze słowa zwrotki.")));
                return;
            }
            foreach (var (candidate, _) in found)
            {
                var info = new StackPanel { Spacing = 4 };
                var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                titleRow.Children.Add(new TextBlock { Text = candidate.Title, FontWeight = FontWeights.Bold, FontSize = 14, TextWrapping = TextWrapping.Wrap });
                if (candidate.Source.Length > 0) titleRow.Children.Add(Ui.Badge(candidate.Source, Ui.Blue, 10));
                info.Children.Add(titleRow);
                var artistRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
                artistRow.Children.Add(new TextBlock { Text = L("Autor / Wykonawca:"), FontSize = 12, Foreground = Ui.Secondary });
                artistRow.Children.Add(new TextBlock { Text = candidate.Artist.Length == 0 ? L("(brak informacji)") : candidate.Artist, FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = candidate.Artist.Length == 0 ? Ui.Secondary : Ui.Resource("TextFillColorPrimaryBrush") });
                info.Children.Add(artistRow);
                if (candidate.Snippet.Length > 0) info.Children.Add(new TextBlock { Text = candidate.Snippet, FontSize = 11, Foreground = Ui.Secondary, MaxLines = 2, TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.Wrap });
                var actions = new StackPanel { Spacing = 4, HorizontalAlignment = HorizontalAlignment.Right };
                var applyBoth = Ui.Button(Glyphs.Checkmark, L("Zastosuj tytuł i autora"), (_, _) => ApplyCandidate(candidate, true, false), accent: true);
                applyBoth.HorizontalAlignment = HorizontalAlignment.Right;
                actions.Children.Add(applyBoth);
                var small = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
                Button Small(string text, Action action, string? tip = null)
                {
                    var b = new Button { Content = text, FontSize = 11, Padding = new Thickness(6, 2, 6, 3), MinHeight = 0 };
                    b.Click += (_, _) => action();
                    if (tip is not null) ToolTipService.SetToolTip(b, tip);
                    small.Children.Add(b);
                    return b;
                }
                Small(L("Tytuł + autor: 'Nieznany'"), () => ApplyCandidate(candidate, true, true), L("Zastosuj tytuł, a autora oznacz jako 'Nieznany' (np. gdy proponowany autor budzi wątpliwości)"));
                Small(L("Autor -> 'Nieznany'"), () => ApplyCandidate(candidate, false, true));
                if (candidate.Artist.Length > 0) Small(L("Tylko autora"), () => ApplyCandidate(candidate, false, false));
                actions.Children.Add(small);
                results.Children.Add(new Border
                {
                    Child = Ui.Columns(12, (info, -1), (actions, 0)),
                    Padding = new Thickness(10), CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(1),
                    BorderBrush = Ui.Resource("CardStrokeColorDefaultBrush"), Background = Ui.Resource("CardBackgroundFillColorDefaultBrush"),
                });
            }
        }
        searchButton.Click += async (_, _) => await RunSingle();
        query.KeyDown += async (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter) { e.Handled = true; await RunSingle(); } };
        songPicker.SelectionChanged += async (_, _) =>
        {
            if (Current() is not Song song) return;
            query.Text = AuthorTitleLookup.SuggestedQuery(song);
            await RunSingle();
        };

        // MARK: Wszystkie pieśni
        var onlyMissing = new CheckBox { Content = L("Tylko pieśni z brakującym autorem"), IsChecked = true };
        var onlyEmpty = new CheckBox { Content = L("Uzupełniaj tylko puste pola"), IsChecked = true };
        var updateTitles = new CheckBox { Content = L("Aktualizuj również tytuły"), IsChecked = false };
        var start = Ui.Button(Glyphs.Search, L("Rozpocznij przeszukiwanie"), (_, _) => { }, accent: true);
        var progress = new ProgressBar { Maximum = 1, Visibility = Visibility.Collapsed };
        var status = new TextBlock { FontSize = 11, Foreground = Ui.Secondary, TextWrapping = TextWrapping.Wrap };
        var batchMessage = new TextBlock { Foreground = Ui.Brush(Ui.Green), FontWeight = FontWeights.Medium, Visibility = Visibility.Collapsed, TextWrapping = TextWrapping.Wrap };
        var options = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 20 };
        options.Children.Add(onlyMissing);
        options.Children.Add(onlyEmpty);
        options.Children.Add(updateTitles);
        var batchTop = new StackPanel { Spacing = 8 };
        batchTop.Children.Add(Ui.Columns(12, (options, -1), (start, 0)));
        batchTop.Children.Add(progress);
        batchTop.Children.Add(status);
        batchTop.Children.Add(batchMessage);
        var proposalsList = new StackPanel { Spacing = 4 };
        List<LookupProposal> proposals = [];
        var applyButton = Ui.Button(Glyphs.Checkmark, "", (_, _) => { }, accent: true);
        void Count()
        {
            var selected = proposals.Count(p => p.IsSelected && !p.IsApplied);
            if (Ui.LabelText(applyButton) is TextBlock label) label.Text = L("Zastosuj do zaznaczonych ({0})", selected);
            applyButton.IsEnabled = selected > 0;
        }
        void RenderProposals()
        {
            proposalsList.Children.Clear();
            if (proposals.Count == 0)
            {
                proposalsList.Children.Add(Centered(Glyphs.Contact, L("Kliknij 'Rozpocznij przeszukiwanie', aby przeanalizować utwory w bibliotece."), L("System dopasuje pieśni na podstawie słów zwrotek oraz tytułów i zaproponuje autorów.")));
                return;
            }
            foreach (var proposal in proposals)
            {
                var select = new CheckBox { IsChecked = proposal.IsSelected, IsEnabled = !proposal.IsApplied, MinWidth = 0, VerticalAlignment = VerticalAlignment.Center };
                select.Click += (_, _) => { proposal.IsSelected = select.IsChecked == true; Count(); };
                var info = new StackPanel { Spacing = 3 };
                var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                titleRow.Children.Add(new TextBlock { Text = proposal.CurrentTitle, FontWeight = FontWeights.SemiBold, FontSize = 13 });
                if (updateTitles.IsChecked == true && proposal.ProposedTitle != proposal.CurrentTitle)
                {
                    titleRow.Children.Add(Ui.Icon(Glyphs.ArrowRight, 10));
                    titleRow.Children.Add(new TextBlock { Text = proposal.ProposedTitle, FontWeight = FontWeights.Bold, FontSize = 13, Foreground = Ui.Brush(Ui.Blue) });
                }
                info.Children.Add(Ui.Columns(8, (titleRow, -1), (Ui.Badge(L("{0}% zgodności", proposal.Confidence), proposal.Confidence > 70 ? Ui.Green : Ui.Orange, 10), 0)));
                var authorRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                authorRow.Children.Add(new TextBlock { Text = L("Autor:"), FontSize = 12, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center });
                authorRow.Children.Add(new TextBlock { Text = proposal.CurrentAuthor.Length == 0 ? L("(brak)") : proposal.CurrentAuthor, FontSize = 12, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center });
                authorRow.Children.Add(Ui.Icon(Glyphs.ArrowRight, 10));
                var accept = new CheckBox { IsChecked = proposal.AcceptAuthor, IsEnabled = !proposal.IsApplied };
                void AcceptLabel() => accept.Content = proposal.AcceptAuthor
                    ? (proposal.ProposedAuthor.Length == 0 ? L("(nie znaleziono)") : proposal.ProposedAuthor) + " " + L("(zastosuj)")
                    : L("Zapisz jako:") + " " + L("\"Nieznany\"");
                AcceptLabel();
                accept.Click += (_, _) => { proposal.AcceptAuthor = accept.IsChecked == true; AcceptLabel(); };
                authorRow.Children.Add(accept);
                info.Children.Add(authorRow);
                UIElement applied = proposal.IsApplied ? Ui.Icon(Glyphs.Checkmark, 16, Ui.Green) : new Border();
                proposalsList.Children.Add(new Border
                {
                    Child = Ui.Columns(10, (select, 0), (info, -1), (applied, 0)),
                    Padding = new Thickness(8, 6, 8, 6), CornerRadius = new CornerRadius(6), Background = Ui.Resource("CardBackgroundFillColorDefaultBrush"),
                    BorderBrush = Ui.Resource("CardStrokeColorDefaultBrush"), BorderThickness = new Thickness(1),
                });
            }
            Count();
        }
        var selectBar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        Button Bar(string text, Action action, string? tip = null)
        {
            var b = new Button { Content = text, FontSize = 11, Padding = new Thickness(6, 2, 6, 3), MinHeight = 0 };
            b.Click += (_, _) => { action(); RenderProposals(); };
            if (tip is not null) ToolTipService.SetToolTip(b, tip);
            selectBar.Children.Add(b);
            return b;
        }
        Bar(L("Zaznacz wszystkie"), () => proposals.ForEach(p => p.IsSelected = true));
        Bar(L("Odznacz wszystkie"), () => proposals.ForEach(p => p.IsSelected = false));
        selectBar.Children.Add(Ui.Divider(vertical: true, length: 16));
        Bar(L("Wszyscy autorzy"), () => proposals.ForEach(p => p.AcceptAuthor = true));
        Bar(L("Autorzy -> 'Nieznany'"), () => proposals.ForEach(p => p.AcceptAuthor = false), L("Oznacza proponowanych autorów jako 'Nieznany' (np. gdy nazwy budzą wątpliwości)"));
        var actionBar = new Border
        {
            Child = Ui.Columns(10, (selectBar, -1), (applyButton, 0)),
            Padding = new Thickness(10, 6, 10, 6), CornerRadius = new CornerRadius(6), Background = Ui.Resource("SubtleFillColorSecondaryBrush"), Visibility = Visibility.Collapsed,
        };
        applyButton.Click += (_, _) =>
        {
            var count = 0;
            foreach (var proposal in proposals.Where(p => p.IsSelected && !p.IsApplied))
            {
                if (library.SongById(proposal.SongId) is not Song song) continue;
                if (proposal.AcceptAuthor)
                {
                    if (proposal.ProposedAuthor.Length > 0 && (onlyEmpty.IsChecked != true || song.Author.Trim().Length == 0)) song.Author = proposal.ProposedAuthor;
                }
                else
                {
                    song.Author = L("Nieznany");
                }
                if (updateTitles.IsChecked == true && proposal.ProposedTitle.Length > 0) song.Title = proposal.ProposedTitle;
                library.UpdateSong(song);
                proposal.IsApplied = true;
                count++;
            }
            batchMessage.Text = "✓ " + L("Pomyślnie zaktualizowano dane dla {0} pieśni!", count);
            batchMessage.Visibility = Visibility.Visible;
            RenderProposals();
        };
        start.Click += async (_, _) =>
        {
            var candidates = library.Songs.Where(song => onlyMissing.IsChecked != true || song.Author.Trim().Length == 0).ToList();
            batchMessage.Visibility = Visibility.Collapsed;
            if (candidates.Count == 0)
            {
                batchMessage.Text = L("Brak pieśni spełniających wybrane kryteria (wszystkie mają już autora).");
                batchMessage.Visibility = Visibility.Visible;
                return;
            }
            start.IsEnabled = false;
            progress.Visibility = Visibility.Visible;
            proposals = [];
            RenderProposals();
            for (var i = 0; i < candidates.Count && !cancel.IsCancellationRequested; i++)
            {
                var song = candidates[i];
                progress.Value = (double)i / candidates.Count;
                status.Text = L("Przeszukiwanie {0} z {1}: {2}...", i + 1, candidates.Count, song.Title);
                var text = AuthorTitleLookup.SuggestedQuery(song);
                if (text.Length == 0) continue;
                try
                {
                    if (AuthorTitleLookup.Best(song, await SearchAsync(text, cancel.Token)) is LookupProposal best && (best.ProposedAuthor.Length > 0 || best.ProposedTitle.Length > 0))
                        proposals.Add(best);
                }
                catch (Exception error) when (error is HttpRequestException or TaskCanceledException or OperationCanceledException)
                {
                    if (cancel.IsCancellationRequested) return;
                }
            }
            progress.Value = 1;
            start.IsEnabled = true;
            status.Text = L("Ukończono! Znaleziono propozycje dla {0} z {1} pieśni.", proposals.Count, candidates.Count);
            actionBar.Visibility = proposals.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
            RenderProposals();
        };
        var batch = new StackPanel { Spacing = 10, Visibility = Visibility.Collapsed };
        batch.Children.Add(batchTop);
        batch.Children.Add(Ui.Divider());
        batch.Children.Add(actionBar);
        batch.Children.Add(new ScrollViewer { Content = proposalsList, Height = 320, Padding = new Thickness(0, 0, 12, 0) });
        RenderProposals();

        void ShowScope(bool all)
        {
            singleTab.IsChecked = !all;
            batchTab.IsChecked = all;
            single.Visibility = all ? Visibility.Collapsed : Visibility.Visible;
            batch.Visibility = all ? Visibility.Visible : Visibility.Collapsed;
        }
        singleTab.Click += (_, _) => ShowScope(false);
        batchTab.Click += (_, _) => ShowScope(true);

        var body = new StackPanel { Spacing = 12, Width = 820 };
        body.Children.Add(Ui.Note(L("Wyszukuje i automatycznie uzupełnia brakujące dane utworów w oparciu o bazę hymnów i sieć internetową")));
        body.Children.Add(new Border { Child = scopeRow, Padding = new Thickness(12, 8, 12, 8), CornerRadius = new CornerRadius(6), Background = Ui.Resource("SubtleFillColorSecondaryBrush") });
        body.Children.Add(single);
        body.Children.Add(batch);
        var title = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        title.Children.Add(Ui.Icon(Glyphs.Contact, 20, Ui.Blue));
        title.Children.Add(new TextBlock { Text = L("Wyszukiwarka tytułu i autora pieśni"), FontSize = 18, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center });
        var dialog = new ContentDialog { Title = title, Content = body, CloseButtonText = L("Zamknij") };
        dialog.Resources["ContentDialogMaxWidth"] = 900.0;
        dialog.Opened += async (_, _) => await RunSingle();
        await Dialogs.ShowAsync(window, dialog);
        cancel.Cancel();
    }
}
