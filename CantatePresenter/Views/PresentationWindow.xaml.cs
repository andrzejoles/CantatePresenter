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

        private void Window_KeyDown(object sender, KeyEventArgs e)
        {
            var store = DataStore.Shared;

            if (e.Key == Key.Escape)
            {
                Close();
                e.Handled = true;
                return;
            }

            if (e.Key == Key.Space || e.Key == Key.Right || e.Key == Key.Down)
            {
                store.NextSlideAction();
                e.Handled = true;
            }
            else if (e.Key == Key.Left || e.Key == Key.Up)
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
    }
}
