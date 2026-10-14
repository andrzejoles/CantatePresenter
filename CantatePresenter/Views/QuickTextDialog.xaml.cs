using System.Windows;
using System.Windows.Input;

namespace CantatePresenter.Views
{
    public partial class QuickTextDialog : Window
    {
        public string ResultTitle { get; private set; } = "Szybki tekst";
        public string ResultText { get; private set; } = string.Empty;

        public QuickTextDialog()
        {
            InitializeComponent();
            Loaded += (s, e) => LyricsBox.Focus();
        }

        private void LyricsBox_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter && (Keyboard.Modifiers & ModifierKeys.Control) == ModifierKeys.Control)
            {
                e.Handled = true;
                Submit();
            }
        }

        private void PresentNow_Click(object sender, RoutedEventArgs e)
        {
            Submit();
        }

        private void Submit()
        {
            var text = LyricsBox.Text.Trim();
            if (string.IsNullOrWhiteSpace(text))
            {
                MessageBox.Show("Wpisz treść do wyświetlenia przed zatwierdzeniem.", "Brak tekstu", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            ResultTitle = string.IsNullOrWhiteSpace(TitleBox.Text) ? "Szybki tekst" : TitleBox.Text.Trim();
            ResultText = text;
            DialogResult = true;
            Close();
        }
    }
}
