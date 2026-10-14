using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text.Encodings.Web;
using System.Text.Json;
using CantatePresenter.Models;

namespace CantatePresenter.Services
{
    public class DataStore : INotifyPropertyChanged
    {
        private static DataStore? _instance;
        public static DataStore Shared => _instance ??= new DataStore();

        public event PropertyChangedEventHandler? PropertyChanged;
        public event Action? PresentationStateChanged;

        public ObservableCollection<Song> Songs { get; } = new();
        public ObservableCollection<ServicePlan> Plans { get; } = new();

        private AppSettings _settings = new();
        public AppSettings Settings
        {
            get => _settings;
            set { _settings = value; OnPropertyChanged(); }
        }

        private Song? _currentSong;
        public Song? CurrentSong
        {
            get => _currentSong;
            set
            {
                if (_currentSong != value)
                {
                    _currentSong = value;
                    OnPropertyChanged();
                    CurrentSlideIndex = 0;
                    PresentationStateChanged?.Invoke();
                }
            }
        }

        private int _currentSlideIndex = 0;
        public int CurrentSlideIndex
        {
            get => _currentSlideIndex;
            set
            {
                if (_currentSlideIndex != value)
                {
                    _currentSlideIndex = value;
                    OnPropertyChanged();
                    OnPropertyChanged(nameof(CurrentSlide));
                    PresentationStateChanged?.Invoke();
                }
            }
        }

        public SongSlide? CurrentSlide
        {
            get
            {
                if (_currentSong == null || _currentSong.Slides.Count == 0) return null;
                if (_currentSlideIndex < 0 || _currentSlideIndex >= _currentSong.Slides.Count) return null;
                return _currentSong.Slides[_currentSlideIndex];
            }
        }

        public SongSlide? NextSlide
        {
            get
            {
                if (_currentSong == null || _currentSong.Slides.Count == 0) return null;
                int nextIdx = _currentSlideIndex + 1;
                if (nextIdx < _currentSong.Slides.Count)
                    return _currentSong.Slides[nextIdx];
                return null;
            }
        }

        private bool _isLive = false;
        public bool IsLive
        {
            get => _isLive;
            set { _isLive = value; OnPropertyChanged(); PresentationStateChanged?.Invoke(); }
        }

        private bool _isBlackScreen = false;
        public bool IsBlackScreen
        {
            get => _isBlackScreen;
            set { _isBlackScreen = value; OnPropertyChanged(); PresentationStateChanged?.Invoke(); }
        }

        private bool _isClearText = false;
        public bool IsClearText
        {
            get => _isClearText;
            set { _isClearText = value; OnPropertyChanged(); PresentationStateChanged?.Invoke(); }
        }

        private DataStore()
        {
            LoadAll();
        }

        public void LoadAll()
        {
            var dataDir = BackupService.GetDataDirectory();

            // Load Settings
            var settingsPath = Path.Combine(dataDir, "settings.json");
            if (File.Exists(settingsPath))
            {
                try
                {
                    var s = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(settingsPath));
                    if (s != null) _settings = s;
                }
                catch { }
            }

            // Load Songs
            var songsPath = Path.Combine(dataDir, "songs.json");
            Songs.Clear();
            if (File.Exists(songsPath))
            {
                try
                {
                    var list = JsonSerializer.Deserialize<List<Song>>(File.ReadAllText(songsPath));
                    if (list != null)
                    {
                        foreach (var song in list)
                            Songs.Add(song);
                    }
                }
                catch { }
            }

            // Load Plans
            var plansPath = Path.Combine(dataDir, "plans.json");
            Plans.Clear();
            if (File.Exists(plansPath))
            {
                try
                {
                    var list = JsonSerializer.Deserialize<List<ServicePlan>>(File.ReadAllText(plansPath));
                    if (list != null)
                    {
                        foreach (var p in list)
                            Plans.Add(p);
                    }
                }
                catch { }
            }

            if (Songs.Count > 0)
                CurrentSong = Songs[0];
        }

        public void SaveSettings()
        {
            var dataDir = BackupService.GetDataDirectory();
            var options = new JsonSerializerOptions { WriteIndented = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
            File.WriteAllText(Path.Combine(dataDir, "settings.json"), JsonSerializer.Serialize(Settings, options));
        }

        public void SaveSongs()
        {
            var dataDir = BackupService.GetDataDirectory();
            var options = new JsonSerializerOptions { WriteIndented = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
            File.WriteAllText(Path.Combine(dataDir, "songs.json"), JsonSerializer.Serialize(Songs.ToList(), options));
        }

        public void SavePlans()
        {
            var dataDir = BackupService.GetDataDirectory();
            var options = new JsonSerializerOptions { WriteIndented = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
            File.WriteAllText(Path.Combine(dataDir, "plans.json"), JsonSerializer.Serialize(Plans.ToList(), options));
        }

        public void AddSong(Song song)
        {
            Songs.Insert(0, song);
            CurrentSong = song;
            SaveSongs();
        }

        public void UpdateSong(Song song)
        {
            var idx = Songs.ToList().FindIndex(s => s.Id == song.Id);
            if (idx >= 0)
            {
                Songs[idx] = song;
                if (CurrentSong?.Id == song.Id)
                {
                    CurrentSong = song;
                }
                SaveSongs();
            }
        }

        public void DeleteSong(Song song)
        {
            Songs.Remove(song);
            if (CurrentSong?.Id == song.Id)
            {
                CurrentSong = Songs.FirstOrDefault();
            }
            SaveSongs();
        }

        public void NextSlideAction()
        {
            if (_currentSong == null || _currentSong.Slides.Count == 0) return;
            if (_currentSlideIndex < _currentSong.Slides.Count - 1)
            {
                CurrentSlideIndex++;
            }
            else
            {
                NextSongAction();
            }
        }

        public void PrevSlideAction()
        {
            if (_currentSong == null || _currentSong.Slides.Count == 0) return;
            if (_currentSlideIndex > 0)
            {
                CurrentSlideIndex--;
            }
            else
            {
                PrevSongAction(toLastSlide: true);
            }
        }

        public void NextSongAction()
        {
            if (_currentSong == null) return;
            var idx = Songs.IndexOf(_currentSong);
            if (idx >= 0 && idx < Songs.Count - 1)
            {
                CurrentSong = Songs[idx + 1];
                CurrentSlideIndex = 0;
            }
        }

        public void PrevSongAction(bool toLastSlide = false)
        {
            if (_currentSong == null) return;
            var idx = Songs.IndexOf(_currentSong);
            if (idx > 0)
            {
                CurrentSong = Songs[idx - 1];
                CurrentSlideIndex = toLastSlide && CurrentSong.Slides.Count > 0 ? CurrentSong.Slides.Count - 1 : 0;
            }
        }

        public void PresentQuickText(string text, string? title = null)
        {
            var trimmed = text?.Trim() ?? string.Empty;
            if (string.IsNullOrWhiteSpace(trimmed)) return;

            var songTitle = string.IsNullOrWhiteSpace(title) ? "Szybki tekst" : title.Trim();
            var quickSong = new Song
            {
                Id = Guid.NewGuid(),
                Title = songTitle,
                Author = "Tymczasowy",
                RawLyrics = trimmed,
                Slides = Song.ParseLyrics(trimmed)
            };

            CurrentSong = quickSong;
            CurrentSlideIndex = 0;
            IsLive = true;
            IsBlackScreen = false;
            IsClearText = false;
        }

        public void ToggleBlackScreen()
        {
            IsBlackScreen = !IsBlackScreen;
        }

        public void ToggleClearText()
        {
            IsClearText = !IsClearText;
        }

        public void ZoomIn()
        {
            Settings.UiScale = Math.Min(1.6, Settings.UiScale + 0.1);
            SaveSettings();
            OnPropertyChanged(nameof(Settings));
        }

        public void ZoomOut()
        {
            Settings.UiScale = Math.Max(0.85, Settings.UiScale - 0.1);
            SaveSettings();
            OnPropertyChanged(nameof(Settings));
        }

        public void ResetZoom()
        {
            Settings.UiScale = 1.0;
            SaveSettings();
            OnPropertyChanged(nameof(Settings));
        }

        protected void OnPropertyChanged([CallerMemberName] string? name = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        }
    }
}
