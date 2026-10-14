using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Windows;
using CantatePresenter.Views;

namespace CantatePresenter.Services
{
    public class ScreenInfo
    {
        public int Index { get; set; }
        public string Name { get; set; } = "";
        public Rect Bounds { get; set; }
        public bool IsPrimary { get; set; }

        public override string ToString() => $"{Name} ({(int)Bounds.Width}x{(int)Bounds.Height}){(IsPrimary ? " [Główny]" : "")}";
    }

    public class ScreenManager : INotifyPropertyChanged
    {
        private static ScreenManager? _instance;
        public static ScreenManager Shared => _instance ??= new ScreenManager();

        public event PropertyChangedEventHandler? PropertyChanged;

        private PresentationWindow? _presentationWindow;
        private PresentationWindow? _testWindow;

        public bool IsPresentationActive => _presentationWindow != null && _presentationWindow.IsVisible;
        public bool IsWindowedPreviewActive => _testWindow != null && _testWindow.IsVisible;

        public List<ScreenInfo> GetConnectedScreens()
        {
            var list = new List<ScreenInfo>();
            int idx = 0;

            // In WPF, SystemParameters or Forms.Screen can be used.
            // Using Wpf screen detection:
            double primaryWidth = SystemParameters.PrimaryScreenWidth;
            double primaryHeight = SystemParameters.PrimaryScreenHeight;
            double virtualLeft = SystemParameters.VirtualScreenLeft;
            double virtualTop = SystemParameters.VirtualScreenTop;
            double virtualWidth = SystemParameters.VirtualScreenWidth;
            double virtualHeight = SystemParameters.VirtualScreenHeight;

            list.Add(new ScreenInfo
            {
                Index = 0,
                Name = "Ekran 1 (Główny komputer)",
                Bounds = new Rect(0, 0, primaryWidth, primaryHeight),
                IsPrimary = true
            });

            if (virtualWidth > primaryWidth || virtualHeight > primaryHeight)
            {
                list.Add(new ScreenInfo
                {
                    Index = 1,
                    Name = "Ekran 2 (Projektor / Zewnętrzny)",
                    Bounds = new Rect(primaryWidth, 0, virtualWidth - primaryWidth, virtualHeight),
                    IsPrimary = false
                });
            }

            return list;
        }

        public void StartPresentation()
        {
            if (_presentationWindow != null && _presentationWindow.IsVisible)
            {
                _presentationWindow.Activate();
                return;
            }

            var screens = GetConnectedScreens();
            var targetIdx = DataStore.Shared.Settings.SelectedScreenIndex;
            var targetScreen = screens.FirstOrDefault(s => s.Index == targetIdx) ?? screens.LastOrDefault() ?? screens[0];

            _presentationWindow = new PresentationWindow(isLiveProjector: true)
            {
                WindowStartupLocation = WindowStartupLocation.Manual,
                Left = targetScreen.Bounds.Left,
                Top = targetScreen.Bounds.Top,
                Width = targetScreen.Bounds.Width,
                Height = targetScreen.Bounds.Height,
                WindowStyle = WindowStyle.None,
                WindowState = WindowState.Maximized,
                Topmost = true
            };

            _presentationWindow.Closed += (s, e) =>
            {
                _presentationWindow = null;
                NotifyState();
            };

            _presentationWindow.Show();
            NotifyState();
        }

        public void StopPresentation()
        {
            if (_presentationWindow != null)
            {
                _presentationWindow.Close();
                _presentationWindow = null;
                NotifyState();
            }
        }

        public void TogglePresentation()
        {
            if (IsPresentationActive)
                StopPresentation();
            else
                StartPresentation();
        }

        public void ToggleWindowedPreview()
        {
            if (IsWindowedPreviewActive)
            {
                _testWindow?.Close();
                _testWindow = null;
                NotifyState();
            }
            else
            {
                _testWindow = new PresentationWindow(isLiveProjector: false)
                {
                    Title = "CantatePresenter — Podgląd Rzutnika",
                    Width = 800,
                    Height = 500,
                    WindowStartupLocation = WindowStartupLocation.CenterScreen
                };
                _testWindow.Closed += (s, e) =>
                {
                    _testWindow = null;
                    NotifyState();
                };
                _testWindow.Show();
                NotifyState();
            }
        }

        private void NotifyState()
        {
            OnPropertyChanged(nameof(IsPresentationActive));
            OnPropertyChanged(nameof(IsWindowedPreviewActive));
        }

        protected void OnPropertyChanged([CallerMemberName] string? name = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        }
    }
}
