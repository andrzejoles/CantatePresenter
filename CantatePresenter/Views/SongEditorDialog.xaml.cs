using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using CantatePresenter.Models;
using CantatePresenter.Services;

namespace CantatePresenter.Views
{
    public partial class SongEditorDialog : Window
    {
        private readonly Song? _existingSong;
        public Song? ResultSong { get; private set; }

        public SongEditorDialog(Song? existingSong = null)
        {
            InitializeComponent();
            _existingSong = existingSong;

            if (_existingSong != null)
            {
                Title = $"Edycja: {_existingSong.Title} — CantatePresenter";
                TitleBox.Text = _existingSong.Title;
                AuthorBox.Text = _existingSong.Author;
                KeyBox.Text = _existingSong.Key;
                LyricsBox.Text = _existingSong.RawLyrics;
            }
            else
            {
                Title = "Nowa Pieśń — CantatePresenter";
                TitleBox.Text = "";
                LyricsBox.Text = "[Zwrotka 1]\n\n\n[Refren]\n\n";
            }

            UpdateSlidePreview();
        }

        private void LyricsBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            UpdateSlidePreview();
        }

        private void InsertTag_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string tag)
            {
                var caret = LyricsBox.CaretIndex;
                var insertText = $"\n\n{tag}\n";
                LyricsBox.Text = LyricsBox.Text.Insert(caret, insertText);
                LyricsBox.CaretIndex = caret + insertText.Length;
                LyricsBox.Focus();
            }
        }

        private void UpdateSlidePreview()
        {
            if (PreviewStack == null) return;
            PreviewStack.Children.Clear();

            var text = LyricsBox.Text;
            var slides = Song.ParseLyrics(text);

            for (int i = 0; i < slides.Count; i++)
            {
                var slide = slides[i];
                var card = new Border
                {
                    Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(slide.Type == SlideType.Chorus ? "#1e293b" : "#18181b")),
                    BorderBrush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(slide.Type == SlideType.Chorus ? "#38bdf8" : "#3f3f46")),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(6),
                    Padding = new Thickness(10),
                    Margin = new Thickness(0, 0, 0, 8)
                };

                var sp = new StackPanel();
                var header = new TextBlock
                {
                    Text = $"{i + 1}. {slide.Label}",
                    FontWeight = FontWeights.Bold,
                    FontSize = 11,
                    Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString(slide.Type == SlideType.Chorus ? "#38bdf8" : "#a1a1aa")),
                    Margin = new Thickness(0, 0, 0, 4)
                };
                var body = new TextBlock
                {
                    Text = slide.Text,
                    FontSize = 12,
                    Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#ffffff")),
                    TextWrapping = TextWrapping.Wrap
                };

                sp.Children.Add(header);
                sp.Children.Add(body);
                card.Child = sp;

                PreviewStack.Children.Add(card);
            }
        }

        private void Save_Click(object sender, RoutedEventArgs e)
        {
            var title = TitleBox.Text.Trim();
            if (string.IsNullOrEmpty(title))
            {
                MessageBox.Show("Podaj tytuł pieśni.", "CantatePresenter", MessageBoxButton.OK, MessageBoxImage.Warning);
                TitleBox.Focus();
                return;
            }

            var author = AuthorBox.Text.Trim();
            var key = KeyBox.Text.Trim();
            var lyrics = LyricsBox.Text.Trim();

            // Check and contextually fix Polish diacritics
            var (fixedTitle, _) = PolishEncodingService.RestoreTitleDiacritics(title, lyrics);

            if (_existingSong != null)
            {
                _existingSong.Title = fixedTitle;
                _existingSong.Author = author;
                _existingSong.Key = key;
                _existingSong.RawLyrics = lyrics;
                _existingSong.Slides = Song.ParseLyrics(lyrics);
                _existingSong.UpdatedAt = DateTime.UtcNow;
                ResultSong = _existingSong;
            }
            else
            {
                ResultSong = new Song(fixedTitle, author, key, lyrics);
            }

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
