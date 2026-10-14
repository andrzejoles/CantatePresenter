using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Windows;
using CantatePresenter.Models;
using CantatePresenter.Services;

namespace CantatePresenter.Views
{
    public class ImportCandidateItem : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler? PropertyChanged;

        private bool _shouldImport = true;
        public bool ShouldImport
        {
            get => _shouldImport;
            set { _shouldImport = value; OnPropertyChanged(); }
        }

        private string _title = "";
        public string Title
        {
            get => _title;
            set { _title = value; OnPropertyChanged(); }
        }

        private bool _includeAuthor = true;
        public bool IncludeAuthor
        {
            get => _includeAuthor;
            set { _includeAuthor = value; OnPropertyChanged(); }
        }

        private string _author = "";
        public string Author
        {
            get => _author;
            set { _author = value; OnPropertyChanged(); }
        }

        public string Key { get; set; } = "";
        public string RawLyrics { get; set; } = "";
        public List<string> Tags { get; set; } = new();
        public int SlidesCount { get; set; }

        public Song ToSong()
        {
            var finalAuthor = IncludeAuthor && !string.IsNullOrWhiteSpace(Author) ? Author.Trim() : "Nieznany";
            var (fixedTitle, _) = PolishEncodingService.RestoreTitleDiacritics(Title, RawLyrics);
            return new Song(fixedTitle, finalAuthor, Key, RawLyrics) { Tags = Tags };
        }

        protected void OnPropertyChanged([CallerMemberName] string? name = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        }
    }

    public partial class ImportReviewDialog : Window
    {
        public ObservableCollection<ImportCandidateItem> Candidates { get; } = new();
        public List<Song> ApprovedSongs { get; private set; } = new();

        public ImportReviewDialog(List<Song> songs)
        {
            InitializeComponent();

            foreach (var s in songs)
            {
                // Auto-detect suspect authors (e.g. contains "Góra", "Nieznany", "Zespół", etc.)
                bool suspect = string.IsNullOrWhiteSpace(s.Author) || s.Author.Contains("Łysa Góra", System.StringComparison.OrdinalIgnoreCase);

                Candidates.Add(new ImportCandidateItem
                {
                    ShouldImport = true,
                    Title = s.Title,
                    IncludeAuthor = !suspect,
                    Author = s.Author,
                    Key = s.Key,
                    RawLyrics = s.RawLyrics,
                    Tags = s.Tags,
                    SlidesCount = s.Slides.Count
                });
            }

            ImportDataGrid.ItemsSource = Candidates;
        }

        private void SelectAll_Click(object sender, RoutedEventArgs e)
        {
            foreach (var item in Candidates) item.ShouldImport = true;
        }

        private void DeselectAllAuthors_Click(object sender, RoutedEventArgs e)
        {
            foreach (var item in Candidates) item.IncludeAuthor = false;
        }

        private void Import_Click(object sender, RoutedEventArgs e)
        {
            ApprovedSongs = Candidates.Where(c => c.ShouldImport).Select(c => c.ToSong()).ToList();
            DialogResult = true;
            Close();
        }

        private void Cancel_Click(object sender, RoutedEventArgs e)
        {
            DialogResult = false;
            Close();
        }
    }
}
