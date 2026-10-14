using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Microsoft.Win32;
using CantatePresenter.Models;
using CantatePresenter.Services;

namespace CantatePresenter.Views
{
    public partial class MainWindow : Window
    {
        private readonly DataStore _store = DataStore.Shared;
        private readonly ScreenManager _screenManager = ScreenManager.Shared;
        private List<Song> _filteredSongs = new();

        public MainWindow()
        {
            InitializeComponent();

            _store.PresentationStateChanged += OnPresentationStateChanged;
            _screenManager.PropertyChanged += (s, e) => UpdateScreenStatusBadge();

            Loaded += MainWindow_Loaded;
        }

        private void MainWindow_Loaded(object sender, RoutedEventArgs e)
        {
            ApplyUiScale();
            RefreshSongsList();
            UpdateLiveMonitor();
            UpdateScreenStatusBadge();
        }

        private void RefreshSongsList()
        {
            var q = SongSearchBox.Text.Trim();
            _filteredSongs = _store.Songs.Where(s => s.Matches(q)).ToList();
            SongsListBox.ItemsSource = _filteredSongs;

            if (_store.CurrentSong != null && _filteredSongs.Contains(_store.CurrentSong))
            {
                SongsListBox.SelectedItem = _store.CurrentSong;
            }
            else if (_filteredSongs.Count > 0)
            {
                SongsListBox.SelectedIndex = 0;
            }
        }

        private void SongSearchBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            RefreshSongsList();
        }

        private void SongsListBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (SongsListBox.SelectedItem is Song song)
            {
                _store.CurrentSong = song;
                UpdateCurrentSongView();
            }
        }

        private void UpdateCurrentSongView()
        {
            var song = _store.CurrentSong;
            if (song == null)
            {
                CurrentSongTitleText.Text = "Wybierz pieśń z biblioteki";
                CurrentSongAuthorText.Text = "";
                CurrentSongKeyText.Text = "";
                SlideCardsContainer.Children.Clear();
                ChordsContainer.Visibility = Visibility.Collapsed;
                return;
            }

            CurrentSongTitleText.Text = song.Title;
            CurrentSongAuthorText.Text = string.IsNullOrEmpty(song.Author) ? "Autor: Nieznany" : $"Autor: {song.Author}";
            CurrentSongKeyText.Text = string.IsNullOrEmpty(song.Key) ? "" : $"Tonacja: {song.Key}";

            if (!string.IsNullOrEmpty(song.Chords))
            {
                ChordsPreviewText.Text = song.Chords;
                ChordsContainer.Visibility = Visibility.Visible;
            }
            else
            {
                ChordsContainer.Visibility = Visibility.Collapsed;
            }

            // Render slide cards
            SlideCardsContainer.Children.Clear();
            for (int i = 0; i < song.Slides.Count; i++)
            {
                var slide = song.Slides[i];
                int slideIdx = i;
                bool isSelected = (_store.CurrentSlideIndex == slideIdx);

                var card = new Border
                {
                    Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(isSelected ? "#1e3a8a" : (slide.Type == SlideType.Chorus ? "#1e293b" : "#334155"))),
                    BorderBrush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(isSelected ? "#38bdf8" : (slide.Type == SlideType.Chorus ? "#0284c7" : "#475569"))),
                    BorderThickness = new Thickness(isSelected ? 2 : 1),
                    CornerRadius = new CornerRadius(8),
                    Padding = new Thickness(14),
                    Margin = new Thickness(0, 0, 0, 10),
                    Cursor = Cursors.Hand
                };

                var sp = new StackPanel();
                var header = new TextBlock
                {
                    Text = $"{slideIdx + 1}. {slide.Label}",
                    FontWeight = FontWeights.Bold,
                    FontSize = 12,
                    Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString(isSelected ? "#38bdf8" : "#94a3b8")),
                    Margin = new Thickness(0, 0, 0, 6)
                };
                var body = new TextBlock
                {
                    Text = slide.Text,
                    FontSize = 14,
                    Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#ffffff")),
                    TextWrapping = TextWrapping.Wrap
                };

                sp.Children.Add(header);
                sp.Children.Add(body);
                card.Child = sp;

                card.MouseLeftButtonDown += (s, e) =>
                {
                    _store.CurrentSlideIndex = slideIdx;
                    _store.IsLive = true;
                    UpdateCurrentSongView();
                };

                SlideCardsContainer.Children.Add(card);
            }
        }

        private void OnPresentationStateChanged()
        {
            Dispatcher.Invoke(() =>
            {
                UpdateLiveMonitor();
                UpdateCurrentSongView();
            });
        }

        private void UpdateLiveMonitor()
        {
            if (_store.IsBlackScreen)
            {
                LiveMonitorCard.Background = Brushes.Black;
                StandbyMonitorPanel.Visibility = Visibility.Collapsed;
                LiveSlideText.Visibility = Visibility.Collapsed;
                OverlayStatusText.Text = "CZARNY EKRAN (B)";
                OverlayStatusText.Visibility = Visibility.Visible;
                return;
            }

            if (_store.IsClearText)
            {
                LiveMonitorCard.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(_store.Settings.BackgroundColorHex));
                StandbyMonitorPanel.Visibility = Visibility.Collapsed;
                LiveSlideText.Visibility = Visibility.Collapsed;
                OverlayStatusText.Text = "TEKST UKRYTY (C)";
                OverlayStatusText.Visibility = Visibility.Visible;
                return;
            }

            OverlayStatusText.Visibility = Visibility.Collapsed;

            if (!_store.IsLive || _store.CurrentSlide == null)
            {
                LiveMonitorCard.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#0b0f19"));
                StandbyMonitorPanel.Visibility = Visibility.Visible;
                LiveSlideText.Visibility = Visibility.Collapsed;
            }
            else
            {
                LiveMonitorCard.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(_store.Settings.BackgroundColorHex));
                StandbyMonitorPanel.Visibility = Visibility.Collapsed;
                LiveSlideText.Text = _store.CurrentSlide.Text;
                LiveSlideText.Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString(_store.Settings.TextColorHex));
                LiveSlideText.Visibility = Visibility.Visible;
            }

            // Next Slide
            if (_store.NextSlide != null)
            {
                NextSlideText.Text = $"{_store.NextSlide.Label}:\n{_store.NextSlide.Text}";
            }
            else
            {
                NextSlideText.Text = "— Koniec pieśni —";
            }
        }

        private void UpdateScreenStatusBadge()
        {
            if (_screenManager.IsPresentationActive)
            {
                StatusBadge.Visibility = Visibility.Visible;
                StatusBadgeText.Text = "RZUTNIK AKTYWNY";
                StartPresentationBtn.Content = "■ Zamknij pełny ekran";
            }
            else if (_screenManager.IsWindowedPreviewActive)
            {
                StatusBadge.Visibility = Visibility.Visible;
                StatusBadgeText.Text = "OKNO TESTOWE";
                StartPresentationBtn.Content = "▶ Prezentuj na pełnym ekranie (F5)";
            }
            else
            {
                StatusBadge.Visibility = Visibility.Collapsed;
                StartPresentationBtn.Content = "▶ Prezentuj na pełnym ekranie (F5)";
            }
        }

        private void ApplyUiScale()
        {
            double scale = _store.Settings.UiScale;
            UiScaleTransform.ScaleX = scale;
            UiScaleTransform.ScaleY = scale;
            ZoomText.Text = $"{(int)(scale * 100)}%";
        }

        private void ZoomIn_Click(object sender, RoutedEventArgs e)
        {
            _store.ZoomIn();
            ApplyUiScale();
        }

        private void ZoomOut_Click(object sender, RoutedEventArgs e)
        {
            _store.ZoomOut();
            ApplyUiScale();
        }

        private void ZoomReset_Click(object sender, RoutedEventArgs e)
        {
            _store.ResetZoom();
            ApplyUiScale();
        }

        private void NewSong_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new SongEditorDialog { Owner = this };
            if (dlg.ShowDialog() == true && dlg.ResultSong != null)
            {
                _store.AddSong(dlg.ResultSong);
                RefreshSongsList();
                SongsListBox.SelectedItem = dlg.ResultSong;
            }
        }

        private void EditCurrentSong_Click(object sender, RoutedEventArgs e)
        {
            if (_store.CurrentSong == null) return;
            var dlg = new SongEditorDialog(_store.CurrentSong) { Owner = this };
            if (dlg.ShowDialog() == true && dlg.ResultSong != null)
            {
                _store.UpdateSong(dlg.ResultSong);
                RefreshSongsList();
                UpdateCurrentSongView();
            }
        }

        private void Import_Click(object sender, RoutedEventArgs e)
        {
            var ofd = new OpenFileDialog
            {
                Title = "Wybierz pliki do zaimportowania",
                Filter = "Obsługiwane pliki (*.txt;*.json;*.mufl;*.muf;*.hly)|*.txt;*.json;*.mufl;*.muf;*.hly|Wszystkie pliki (*.*)|*.*",
                Multiselect = true
            };

            if (ofd.ShowDialog() == true)
            {
                var imported = new List<Song>();
                Mouse.OverrideCursor = Cursors.Wait;
                try
                {
                    foreach (var file in ofd.FileNames)
                    {
                        try
                        {
                            var songs = TextImporter.ImportFromFile(file);
                            imported.AddRange(songs);
                        }
                        catch { }
                    }
                }
                finally
                {
                    Mouse.OverrideCursor = null;
                }

                if (imported.Count > 0)
                {
                    var reviewDlg = new ImportReviewDialog(imported) { Owner = this };
                    if (reviewDlg.ShowDialog() == true && reviewDlg.ApprovedSongs.Count > 0)
                    {
                        foreach (var s in reviewDlg.ApprovedSongs)
                        {
                            _store.AddSong(s);
                        }
                        RefreshSongsList();
                        MessageBox.Show($"Zaimportowano pomyślnie {reviewDlg.ApprovedSongs.Count} pieśni!", "CantatePresenter", MessageBoxButton.OK, MessageBoxImage.Information);
                    }
                }
            }
        }

        private void Export_Click(object sender, RoutedEventArgs e)
        {
            var sfd = new SaveFileDialog
            {
                Title = "Eksportuj całą bazę pieśni do JSON",
                Filter = "Plik JSON (*.json)|*.json",
                FileName = $"CantatePresenter_Baza_{DateTime.Now:yyyy-MM-dd}.json"
            };

            if (sfd.ShowDialog() == true)
            {
                SongExporter.ExportToFile(_store.Songs.ToList(), sfd.FileName);
                MessageBox.Show("Baza pieśni została pomyślnie wyeksportowana!", "CantatePresenter", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }

        private void Chords_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new ChordsSearchDialog(_store.CurrentSong) { Owner = this };
            if (dlg.ShowDialog() == true)
            {
                UpdateCurrentSongView();
            }
        }

        private void Settings_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new SettingsDialog { Owner = this };
            dlg.ShowDialog();
            UpdateLiveMonitor();
        }

        private void Help_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new UserManualDialog { Owner = this };
            dlg.ShowDialog();
        }

        private void StartPresentation_Click(object sender, RoutedEventArgs e)
        {
            _screenManager.TogglePresentation();
        }

        private void TestWindow_Click(object sender, RoutedEventArgs e)
        {
            _screenManager.ToggleWindowedPreview();
        }

        private void BlackScreen_Click(object sender, RoutedEventArgs e)
        {
            _store.ToggleBlackScreen();
        }

        private void ClearText_Click(object sender, RoutedEventArgs e)
        {
            _store.ToggleClearText();
        }

        private void StopPresentation_Click(object sender, RoutedEventArgs e)
        {
            _screenManager.StopPresentation();
            _store.IsLive = false;
        }

        private void Window_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.OriginalSource is TextBox) return;

            if (e.Key == Key.Space || e.Key == Key.Right || e.Key == Key.Down)
            {
                _store.NextSlideAction();
                e.Handled = true;
            }
            else if (e.Key == Key.Left || e.Key == Key.Up)
            {
                _store.PrevSlideAction();
                e.Handled = true;
            }
            else if (e.Key == Key.B)
            {
                _store.ToggleBlackScreen();
                e.Handled = true;
            }
            else if (e.Key == Key.C)
            {
                _store.ToggleClearText();
                e.Handled = true;
            }
            else if (e.Key == Key.F5 || (e.Key == Key.Enter && Keyboard.Modifiers == ModifierKeys.None))
            {
                _screenManager.StartPresentation();
                e.Handled = true;
            }
            else if (e.Key == Key.Escape)
            {
                _screenManager.StopPresentation();
                _store.IsLive = false;
                e.Handled = true;
            }
        }
    }
}
