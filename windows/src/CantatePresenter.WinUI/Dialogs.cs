using CantatePresenter.Core.Models;
using CantatePresenter.Core.Online;
using CantatePresenter.Core.Text;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

public static class Labels
{
    /// <summary>Etykieta slajdu w języku interfejsu: domyślne („Zwrotka 2”) tłumaczone, własne bez zmian.</summary>
    public static string Slide(SongSlide slide)
    {
        var baseName = SlideTypes.PolishName.GetValueOrDefault(slide.Type, slide.Label);
        if (slide.Label == baseName) return L(baseName);
        if (slide.Number is int number && slide.Label == $"{baseName} {number}") return $"{L(baseName)} {number}";
        return slide.Label;
    }
}

/// <summary>Okna dialogowe (ContentDialog). Gdy któreś jest otwarte, skróty prezentacji nie działają (jak arkusze w macOS).</summary>
public static class Dialogs
{
    public static async Task<ContentDialogResult> ShowAsync(MainWindow window, ContentDialog dialog)
    {
        dialog.XamlRoot = window.Content.XamlRoot;
        dialog.RequestedTheme = ((FrameworkElement)window.Content).ActualTheme;
        window.DialogOpen = true;
        try
        {
            return await dialog.ShowAsync();
        }
        finally
        {
            window.DialogOpen = false;
        }
    }

    private static TextBox Field(string text, string placeholder = "", bool multiline = false, double height = 0)
    {
        var box = new TextBox { Text = text, PlaceholderText = placeholder, AcceptsReturn = multiline, TextWrapping = multiline ? TextWrapping.Wrap : TextWrapping.NoWrap };
        if (height > 0) box.Height = height;
        if (multiline) ScrollViewer.SetVerticalScrollBarVisibility(box, ScrollBarVisibility.Auto);
        return box;
    }

    private static StackPanel Labeled(string label, UIElement control)
    {
        var panel = new StackPanel { Spacing = 4 };
        panel.Children.Add(new TextBlock { Text = label, FontWeight = FontWeights.SemiBold, FontSize = 12 });
        panel.Children.Add(control);
        return panel;
    }

    public static async Task<string?> PromptAsync(MainWindow window, string title, string value, string placeholder = "", string? primary = null)
    {
        var box = Field(value, placeholder);
        box.MinWidth = 320;
        box.Loaded += (_, _) => { box.Focus(FocusState.Programmatic); box.SelectAll(); };
        var dialog = new ContentDialog { Title = title, Content = box, PrimaryButtonText = primary ?? L("OK"), CloseButtonText = L("Anuluj"), DefaultButton = ContentDialogButton.Primary };
        return await ShowAsync(window, dialog) == ContentDialogResult.Primary ? box.Text : null;
    }

    public static async Task<bool> ConfirmAsync(MainWindow window, string message)
    {
        var dialog = new ContentDialog { Title = message, PrimaryButtonText = L("OK"), CloseButtonText = L("Anuluj"), DefaultButton = ContentDialogButton.Close };
        return await ShowAsync(window, dialog) == ContentDialogResult.Primary;
    }

    public static async Task InfoAsync(MainWindow window, string title, string message)
    {
        var dialog = new ContentDialog { Title = title, Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap }, CloseButtonText = L("Zamknij") };
        await ShowAsync(window, dialog);
    }

    /// <summary>Szybki tekst na żywo (QuickTextSheet w macOS): bez zapisywania w bibliotece, Ctrl+Enter wyświetla.</summary>
    public static async Task<(string Text, string Title)?> QuickTextAsync(MainWindow window)
    {
        var title = Field("", L("np. Ogłoszenie, Intencja, Słowo na dziś..."));
        var text = Field("", L("Wpisz lub wklej treść do wyświetlenia...\n\nPuste linie dzielą tekst na kolejne slajdy."), multiline: true, height: 220);
        var count = Ui.Badge("", Ui.Blue, 11);
        count.Visibility = Visibility.Collapsed;
        text.TextChanged += (_, _) =>
        {
            var trimmed = text.Text.Trim();
            var slides = trimmed.Length == 0 ? 0 : Song.SlidesFromLyrics(trimmed.Replace("\r\n", "\n").Replace("\r", "\n")).Count;
            ((TextBlock)count.Child).Text = L("Slajdy: {0}", slides);
            count.Visibility = slides > 0 ? Visibility.Visible : Visibility.Collapsed;
        };
        var head = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        head.Children.Add(Ui.Icon(Glyphs.Bolt, 22, Ui.Orange));
        var headText = new StackPanel { Spacing = 2 };
        headText.Children.Add(new TextBlock { Text = L("Szybki tekst na żywo"), FontSize = 18, FontWeight = FontWeights.Bold });
        headText.Children.Add(Ui.Note(L("Wpisz tekst lub ogłoszenie — zostanie wyświetlone na projektorze bez zapisywania w bazie.")));
        head.Children.Add(headText);
        var panel = new StackPanel { Spacing = 12, MinWidth = 500 };
        panel.Children.Add(Labeled(L("Tytuł (opcjonalny):"), title));
        var contentLabel = Ui.Columns(8, (new TextBlock { Text = L("Treść do wyświetlenia:"), FontWeight = FontWeights.SemiBold, FontSize = 12, VerticalAlignment = VerticalAlignment.Center }, -1),
            (Dictation.Button(text, DictationMode.AppendNewline), 0), (count, 0));
        var contentField = new StackPanel { Spacing = 4 };
        contentField.Children.Add(contentLabel);
        contentField.Children.Add(text);
        panel.Children.Add(contentField);
        var tip = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        tip.Children.Add(Ui.Icon(Glyphs.Info, 12));
        tip.Children.Add(Ui.Note(Lw("Wskazówka: Naciśnij ⌘+Return lub przycisk poniżej, aby natychmiast wysłać na ekran.")));
        panel.Children.Add(tip);
        var dialog = new ContentDialog
        {
            Title = head, Content = panel, PrimaryButtonText = "⚡ " + L("Wyświetl teraz"), CloseButtonText = L("Anuluj"),
            DefaultButton = ContentDialogButton.Primary, IsPrimaryButtonEnabled = false,
        };
        text.TextChanged += (_, _) => dialog.IsPrimaryButtonEnabled = text.Text.Trim().Length > 0;
        var submitted = false;
        text.PreviewKeyDown += (_, e) =>
        {
            var control = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(Windows.System.VirtualKey.Control).HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
            if (control && e.Key == Windows.System.VirtualKey.Enter && text.Text.Trim().Length > 0)
            {
                e.Handled = true;
                submitted = true;
                dialog.Hide();
            }
        };
        text.Loaded += (_, _) => text.Focus(FocusState.Programmatic);
        var result = await ShowAsync(window, dialog);
        return (result == ContentDialogResult.Primary || submitted) && text.Text.Trim().Length > 0 ? (text.Text.Replace("\r\n", "\n").Replace("\r", "\n"), title.Text) : null;
    }

    public static async Task AboutAsync(MainWindow window)
    {
        var panel = new StackPanel { Spacing = 8 };
        panel.Children.Add(new TextBlock { Text = "♫ CantatePresenter", FontSize = 22, FontWeight = FontWeights.Bold });
        panel.Children.Add(new TextBlock { Text = L("Wersja {0}", Services.Version) + " · Windows" });
        panel.Children.Add(new TextBlock { Text = L("Autor: Andrzej Oles\nOpracowano we współpracy z Claude (Anthropic)"), TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(new TextBlock { Text = Services.Library.DataDirectory, Opacity = 0.6, FontSize = 12, IsTextSelectionEnabled = true, TextWrapping = TextWrapping.Wrap });
        var dialog = new ContentDialog { Title = L("O programie"), Content = panel, CloseButtonText = L("Zamknij"), SecondaryButtonText = L("Sprawdź uaktualnienia...") };
        if (await ShowAsync(window, dialog) == ContentDialogResult.Secondary) await Updater.CheckAsync(window, manual: true);
    }
}
