using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using CantatePresenter.Models;
using CantatePresenter.Services;

namespace CantatePresenter.Views
{
    public partial class PresentationWindow : Window
    {
        private readonly bool _isLiveProjector;
        private bool _isInitialized = false;

        public PresentationWindow(bool isLiveProjector)
        {
            InitializeComponent();
            _isLiveProjector = isLiveProjector;

            Loaded += PresentationWindow_Loaded;
            DataStore.Shared.PresentationStateChanged += OnPresentationStateChanged;
            Closing += PresentationWindow_Closing;
        }

        private async void PresentationWindow_Loaded(object sender, RoutedEventArgs e)
        {
            try
            {
                await BrowserControl.EnsureCoreWebView2Async(null);
                BrowserControl.CoreWebView2.AcceleratorKeyPressed += CoreWebView2_AcceleratorKeyPressed;
                _isInitialized = true;
                UpdateContent();
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Błąd inicjalizacji silnika WebView2: {ex.Message}", "CantatePresenter", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void PresentationWindow_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
        {
            DataStore.Shared.PresentationStateChanged -= OnPresentationStateChanged;
            if (_isLiveProjector)
            {
                DataStore.Shared.IsLive = false;
            }
            if (Application.Current?.MainWindow != null)
            {
                Application.Current.MainWindow.Activate();
                Application.Current.MainWindow.Focus();
            }
        }

        private void OnPresentationStateChanged()
        {
            Dispatcher.Invoke(() =>
            {
                if (_isInitialized)
                    UpdateContent();
            });
        }

        public void UpdateContent()
        {
            if (!_isInitialized || BrowserControl.CoreWebView2 == null) return;

            var store = DataStore.Shared;

            // 1. Black Screen Mode
            if (store.IsBlackScreen)
            {
                BrowserControl.NavigateToString(@"
                <!DOCTYPE html><html><body style=""background:#000000;margin:0;padding:0;overflow:hidden;""></body></html>");
                return;
            }

            // 2. Standby Mode (Not Live or no current slide)
            if (!store.IsLive || store.CurrentSlide == null)
            {
                var logoPreset = LogoCatalog.GetById(store.Settings.ActiveLogoId);
                var dataDir = BackupService.GetDataDirectory();
                var standbyHtmlPath = Path.Combine(dataDir, "standby.html");

                if (File.Exists(standbyHtmlPath))
                {
                    var html = File.ReadAllText(standbyHtmlPath);
                    // Inject active logo SVG
                    html = html.Replace("<!-- LOGO_SLOT -->", logoPreset.SvgContent);
                    html = html.Replace("<div class=\"logo-container\" id=\"logo-slot\"></div>", $"<div class=\"logo-container\" id=\"logo-slot\">{logoPreset.SvgContent}</div>");
                    BrowserControl.NavigateToString(html);
                }
                else
                {
                    // Fallback minimal standby
                    var fallback = $@"
                    <!DOCTYPE html><html>
                    <body style=""background:#0a0e1a;color:#ffffff;display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;margin:0;font-family:'Segoe UI',sans-serif;"">
                        <div style=""width:160px;height:160px;margin-bottom:20px;"">{logoPreset.SvgContent}</div>
                        <h1 style=""font-size:44px;margin:0;font-weight:700;letter-spacing:1px;"">CantatePresenter</h1>
                        <p style=""color:#94a3b8;font-size:18px;margin-top:8px;"">Wersja 1.0.0</p>
                    </body></html>";
                    BrowserControl.NavigateToString(fallback);
                }
                return;
            }

            // 3. Clear Text Mode
            if (store.IsClearText)
            {
                var bg = store.Settings.BackgroundColorHex;
                BrowserControl.NavigateToString($@"
                <!DOCTYPE html><html><body style=""background:{bg};margin:0;padding:0;overflow:hidden;""></body></html>");
                return;
            }

            // 4. Live Slide Presentation Mode
            var slide = store.CurrentSlide;
            var settings = store.Settings;

            var lines = (slide.Text ?? "").Split('\n');
            var formattedLines = string.Join("<br/>", lines);

            var vAlign = settings.VerticalAlignment switch
            {
                "top" => "flex-start",
                "bottom" => "flex-end",
                _ => "center"
            };

            var textAlign = settings.TextAlignment.ToLowerInvariant();
            var shadow = settings.HasShadow ? "text-shadow: 2px 2px 8px rgba(0,0,0,0.85);" : "";
            var fontWeight = settings.IsBold ? "bold" : "normal";
            var margin = (int)(settings.MarginPercent * 100);

            var slideHtml = $@"
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset=""utf-8"">
                <style>
                    body, html {{
                        margin: 0;
                        padding: 0;
                        width: 100%;
                        height: 100%;
                        overflow: hidden;
                        background: {settings.BackgroundColorHex};
                        color: {settings.TextColorHex};
                        font-family: '{settings.FontFamily}', 'Segoe UI', sans-serif;
                        user-select: none;
                    }}
                    .container {{
                        display: flex;
                        flex-direction: column;
                        justify-content: {vAlign};
                        align-items: center;
                        box-sizing: border-box;
                        width: 100%;
                        height: 100%;
                        padding: {margin}vh {margin}vw;
                    }}
                    .text {{
                        font-size: 5.5vw;
                        font-weight: {fontWeight};
                        line-height: {settings.LineSpacingFactor};
                        text-align: {textAlign};
                        width: 100%;
                        white-space: pre-line;
                        word-wrap: break-word;
                        {shadow}
                    }}
                    .badge {{
                        position: absolute;
                        bottom: 16px;
                        right: 24px;
                        font-size: 14px;
                        font-weight: 600;
                        color: rgba(255,255,255,0.4);
                        background: rgba(0,0,0,0.3);
                        padding: 4px 10px;
                        border-radius: 4px;
                    }}
                </style>
            </head>
            <body>
                <div class=""container"">
                    <div class=""text"">{formattedLines}</div>
                </div>
                <div class=""badge"">{slide.Label}</div>
            </body>
            </html>";

            BrowserControl.NavigateToString(slideHtml);
        }

        private void CoreWebView2_AcceleratorKeyPressed(object? sender, Microsoft.Web.WebView2.Core.CoreWebView2AcceleratorKeyPressedEventArgs e)
        {
            if (e.KeyEventKind == Microsoft.Web.WebView2.Core.CoreWebView2KeyEventKind.KeyDown ||
                e.KeyEventKind == Microsoft.Web.WebView2.Core.CoreWebView2KeyEventKind.SystemKeyDown)
            {
                var store = DataStore.Shared;

                // Escape (27)
                if (e.VirtualKey == 27)
                {
                    Dispatcher.Invoke(() =>
                    {
                        Close();
                    });
                    e.Handled = true;
                    return;
                }

                // Space (32), Right (39), Down (40), Enter (13), PageDown (34)
                if (e.VirtualKey == 32 || e.VirtualKey == 39 || e.VirtualKey == 40 || e.VirtualKey == 13 || e.VirtualKey == 34)
                {
                    Dispatcher.Invoke(() => store.NextSlideAction());
                    e.Handled = true;
                    return;
                }

                // Left (37), Up (38), PageUp (33)
                if (e.VirtualKey == 37 || e.VirtualKey == 38 || e.VirtualKey == 33)
                {
                    Dispatcher.Invoke(() => store.PrevSlideAction());
                    e.Handled = true;
                    return;
                }

                // 'B' (66) -> Toggle Black Screen
                if (e.VirtualKey == 66)
                {
                    Dispatcher.Invoke(() => store.ToggleBlackScreen());
                    e.Handled = true;
                    return;
                }

                // 'C' (67) -> Toggle Clear Text
                if (e.VirtualKey == 67)
                {
                    Dispatcher.Invoke(() => store.ToggleClearText());
                    e.Handled = true;
                    return;
                }
            }
        }

        private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
        {
            HandleKeyInput(e);
        }

        private void Window_KeyDown(object sender, KeyEventArgs e)
        {
            HandleKeyInput(e);
        }

        private void HandleKeyInput(KeyEventArgs e)
        {
            var store = DataStore.Shared;

            if (e.Key == Key.Escape)
            {
                Close();
                e.Handled = true;
                return;
            }

            if (e.Key == Key.Space || e.Key == Key.Right || e.Key == Key.Down || e.Key == Key.PageDown || e.Key == Key.Enter)
            {
                store.NextSlideAction();
                e.Handled = true;
            }
            else if (e.Key == Key.Left || e.Key == Key.Up || e.Key == Key.PageUp)
            {
                store.PrevSlideAction();
                e.Handled = true;
            }
            else if (e.Key == Key.B)
            {
                store.ToggleBlackScreen();
                e.Handled = true;
            }
            else if (e.Key == Key.C)
            {
                store.ToggleClearText();
                e.Handled = true;
            }
        }

        private void ExitButton_Click(object sender, RoutedEventArgs e)
        {
            Close();
        }
    }
}
