using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Windows.Media.SpeechRecognition;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>Jak pole wypełnia się dyktowanym tekstem (DictationTargetMode w macOS).</summary>
public enum DictationMode
{
    Replace,
    Append,
    AppendNewline,
}

/// <summary>
/// Dyktowanie głosem jak DictationButtonView w macOS, przez rozpoznawanie mowy systemu Windows
/// (Windows.Media.SpeechRecognition, temat „dictation”). Język i „tylko na urządzeniu” z ustawień wspólnych z macOS.
/// Windows rozpoznaje dyktowany tekst w usłudze online Microsoft, więc opcja „tylko na tym urządzeniu” wyłącza dyktowanie.
/// </summary>
public static class Dictation
{
    /// <summary>Języki dyktowania jak LanguagePresets.dictationLanguages w macOS.</summary>
    public static readonly (string Code, string Name, string Flag)[] Languages =
    [
        ("pl-PL", "Polski (Polska)", "🇵🇱"), ("en-US", "English (United States)", "🇺🇸"), ("en-GB", "English (United Kingdom)", "🇬🇧"),
        ("de-DE", "Deutsch (Deutschland)", "🇩🇪"), ("es-ES", "Español (España)", "🇪🇸"), ("uk-UA", "Українська (Україна)", "🇺🇦"),
        ("it-IT", "Italiano (Italia)", "🇮🇹"), ("fr-FR", "Français (France)", "🇫🇷"),
    ];

    // Kody błędów rozpoznawania mowy (HRESULT).
    private const int PrivacyPolicyNotAccepted = unchecked((int)0x80045509);
    private const int AccessDenied = unchecked((int)0x80070005);

    /// <summary>Trwające dyktowanie (tylko jedno naraz, jak w macOS).</summary>
    private static Session? active;

    private static string LanguageName(string code) => Languages.FirstOrDefault(l => l.Code == code).Name ?? code;

    /// <summary>Pole z przyciskiem mikrofonu obok (u góry przy polach wielowierszowych).</summary>
    public static FrameworkElement WithMic(TextBox field, DictationMode mode, string? prompt = null)
    {
        var grid = new Grid { ColumnSpacing = 6 };
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var button = Button(field, mode, prompt);
        button.VerticalAlignment = field.AcceptsReturn ? VerticalAlignment.Top : VerticalAlignment.Stretch;
        Grid.SetColumn(button, 1);
        grid.Children.Add(field);
        grid.Children.Add(button);
        return grid;
    }

    public static Button Button(TextBox field, DictationMode mode, string? prompt = null)
    {
        var button = new Button { Padding = new Thickness(8, 4, 8, 4) };
        Session? session = null;
        void Show(bool recording)
        {
            button.Content = recording ? "● " + L("Dyktuję...") : "🎤";
            ToolTipService.SetToolTip(button, recording ? L("Kliknij, aby zakończyć dyktowanie") : prompt ?? L("Dyktuj głosowo ({0})", LanguageName(Library.Settings.DictationLanguage)));
            if (recording) button.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.IndianRed);
            else button.ClearValue(Control.ForegroundProperty);
        }
        Show(false);
        button.Click += async (_, _) =>
        {
            if (session is not null)
            {
                await session.StopAsync();
                return;
            }
            if (active is not null) await active.StopAsync();
            var settings = Library.Settings;
            if (settings.DictationOnDeviceOnly)
            {
                ShowError(button, L("Windows rozpoznaje dyktowany tekst tylko w usłudze online firmy Microsoft. Aby dyktować, wyłącz w Ustawieniach opcję „Rozpoznawaj mowę tylko na tym urządzeniu”."));
                return;
            }
            var started = new Session(field, mode, () => { session = null; Show(false); }, message => ShowError(button, message));
            session = started;
            active = started;
            Show(true);
            if (!await started.StartAsync(settings.DictationLanguage))
            {
                session = null;
                if (active == started) active = null;
                Show(false);
            }
        };
        // Zamknięcie okna z polem kończy dyktowanie.
        field.Unloaded += async (_, _) => { if (session is not null) await session.StopAsync(); };
        return button;
    }

    private static void ShowError(FrameworkElement anchor, string message)
    {
        // Flyout zamiast okna dialogowego: działa także wewnątrz otwartego okna (np. edytora pieśni).
        var flyout = new Flyout { Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, MaxWidth = 340 } };
        flyout.ShowAt(anchor, new FlyoutShowOptions { Placement = FlyoutPlacementMode.Bottom });
    }

    /// <summary>Komunikat dla użytkownika przy błędzie rozpoznawania mowy.</summary>
    public static string ErrorMessage(Exception error, string language) => error.HResult switch
    {
        PrivacyPolicyNotAccepted => L("Rozpoznawanie mowy online jest wyłączone w systemie Windows. Włącz je w Ustawieniach systemu Windows → Prywatność i zabezpieczenia → Mowa."),
        AccessDenied => L("Odmówiono dostępu do mikrofonu. Zezwól aplikacjom klasycznym na dostęp do mikrofonu w Ustawieniach systemu Windows → Prywatność i zabezpieczenia → Mikrofon."),
        _ when error is UnauthorizedAccessException => L("Odmówiono dostępu do mikrofonu. Zezwól aplikacjom klasycznym na dostęp do mikrofonu w Ustawieniach systemu Windows → Prywatność i zabezpieczenia → Mikrofon."),
        _ => $"{L("Problem z dyktowaniem")}: {error.Message}",
    };

    /// <summary>Czy Windows ma rozpoznawanie dyktowanego tekstu w tym języku (języki mowy zainstalowane w systemie).</summary>
    public static bool SupportsLanguage(string code)
    {
        try
        {
            return SpeechRecognizer.SupportedTopicLanguages.Any(l => string.Equals(l.LanguageTag, code, StringComparison.OrdinalIgnoreCase));
        }
        catch (Exception)
        {
            return false;
        }
    }

    /// <summary>Języki mowy dostępne w systemie (do raportu próby w CI).</summary>
    public static IReadOnlyList<string> SystemLanguages()
    {
        try
        {
            return SpeechRecognizer.SupportedTopicLanguages.Select(l => l.LanguageTag).ToList();
        }
        catch (Exception error)
        {
            return ["błąd: " + error.Message];
        }
    }

    private sealed class Session(TextBox field, DictationMode mode, Action ended, Action<string> error)
    {
        private SpeechRecognizer? recognizer;
        private readonly string baseText = field.Text;
        private readonly List<string> finished = [];
        private bool stopped;

        public async Task<bool> StartAsync(string language)
        {
            if (!SupportsLanguage(language))
            {
                error(L("System Windows nie rozpoznaje mowy w wybranym języku ({0}). Dodaj ten język w Ustawieniach systemu Windows → Czas i język → Mowa.", LanguageName(language)));
                return false;
            }
            try
            {
                recognizer = new SpeechRecognizer(new Windows.Globalization.Language(language));
                recognizer.Constraints.Add(new SpeechRecognitionTopicConstraint(SpeechRecognitionScenario.Dictation, "dictation"));
                var compiled = await recognizer.CompileConstraintsAsync();
                if (compiled.Status != SpeechRecognitionResultStatus.Success)
                {
                    error($"{L("Problem z dyktowaniem")}: {compiled.Status}");
                    Dispose();
                    return false;
                }
                // Zdarzenia przychodzą spoza wątku interfejsu.
                recognizer.HypothesisGenerated += (_, e) => Enqueue(() => Apply(e.Hypothesis.Text));
                recognizer.ContinuousRecognitionSession.ResultGenerated += (_, e) => Enqueue(() =>
                {
                    if (e.Result.Status == SpeechRecognitionResultStatus.Success && e.Result.Text.Length > 0) finished.Add(e.Result.Text);
                    Apply("");
                });
                recognizer.ContinuousRecognitionSession.Completed += (_, e) => Enqueue(() =>
                {
                    if (!stopped && e.Status is not (SpeechRecognitionResultStatus.Success or SpeechRecognitionResultStatus.UserCanceled or SpeechRecognitionResultStatus.TimeoutExceeded))
                    {
                        error(e.Status == SpeechRecognitionResultStatus.NetworkFailure
                            ? L("Brak połączenia z usługą rozpoznawania mowy.")
                            : $"{L("Problem z dyktowaniem")}: {e.Status}");
                    }
                    Finish();
                });
                await recognizer.ContinuousRecognitionSession.StartAsync();
                return true;
            }
            catch (Exception failure)
            {
                Trace("dyktowanie: " + failure);
                error(ErrorMessage(failure, language));
                Dispose();
                return false;
            }
        }

        public async Task StopAsync()
        {
            if (stopped) return;
            stopped = true;
            try
            {
                if (recognizer is not null) await recognizer.ContinuousRecognitionSession.StopAsync();
            }
            catch (Exception failure)
            {
                Trace("dyktowanie (stop): " + failure.Message);
            }
            Finish();
        }

        private void Enqueue(Action action) => field.DispatcherQueue.TryEnqueue(() => action());

        private void Apply(string hypothesis)
        {
            var recognized = string.Join(" ", finished.Append(hypothesis).Where(t => t.Trim().Length > 0));
            var clean = System.Text.RegularExpressions.Regex.Replace(recognized, @"\s+", " ").Trim();
            if (clean.Length == 0) return;
            field.Text = mode == DictationMode.Replace || baseText.Trim().Length == 0
                ? clean
                : baseText + (mode == DictationMode.AppendNewline ? "\r\r" : " ") + clean;
            field.SelectionStart = field.Text.Length;
        }

        private void Finish()
        {
            stopped = true;
            Dispose();
            if (active == this) active = null;
            ended();
        }

        private void Dispose()
        {
            recognizer?.Dispose();
            recognizer = null;
        }
    }
}
