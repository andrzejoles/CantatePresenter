using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using CantatePresenter.Models;
using CantatePresenter.Services;

namespace CantatePresenter.Views
{
    public partial class SettingsDialog : Window
    {
        public SettingsDialog()
        {
            InitializeComponent();
            LoadSettings();
        }

        private void LoadSettings()
        {
            var store = DataStore.Shared;
            var settings = store.Settings;

            // Screens
            var screens = ScreenManager.Shared.GetConnectedScreens();
            ScreenComboBox.ItemsSource = screens;
            ScreenComboBox.SelectedIndex = Math.Min(settings.SelectedScreenIndex, Math.Max(0, screens.Count - 1));

            // Fonts
            var fontNames = Fonts.SystemFontFamilies.Select(f => f.Source).OrderBy(n => n).ToList();
            FontComboBox.ItemsSource = fontNames;
            FontComboBox.SelectedItem = fontNames.FirstOrDefault(f => f.Equals(settings.FontFamily, StringComparison.OrdinalIgnoreCase)) ?? "Segoe UI";

            BoldCheckBox.IsChecked = settings.IsBold;
            ShadowCheckBox.IsChecked = settings.HasShadow;
            MarginSlider.Value = Math.Round(settings.MarginPercent * 100);

            // Logos
            LogoListBox.ItemsSource = LogoCatalog.All;
            var currentLogo = LogoCatalog.GetById(settings.ActiveLogoId);
            LogoListBox.SelectedItem = currentLogo;

            // Google Drive
            GoogleDriveAutoBackupCheckBox.IsChecked = settings.GoogleDrive.AutoBackupOnExit;
        }

        private void LogoListBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (LogoListBox.SelectedItem is LogoPreset logo)
            {
                DataStore.Shared.Settings.ActiveLogoId = logo.Id;
                DataStore.Shared.SaveSettings();
            }
        }

        private void ExportBackup_Click(object sender, RoutedEventArgs e)
        {
            var sfd = new SaveFileDialog
            {
                Title = "Zapisz pełną kopię zapasową bazy",
                Filter = "Kopia CantatePresenter (*.cantatebackup)|*.cantatebackup|Archiwum ZIP (*.zip)|*.zip",
                FileName = $"CantatePresenter_Backup_{DateTime.Now:yyyy-MM-dd_HH-mm-ss}.cantatebackup"
            };

            if (sfd.ShowDialog() == true)
            {
                try
                {
                    var (archivePath, manifest) = BackupService.CreateBackupArchive(Path.GetDirectoryName(sfd.FileName));
                    if (File.Exists(sfd.FileName)) File.Delete(sfd.FileName);
                    File.Move(archivePath, sfd.FileName);
                    MessageBox.Show($"Kopia zapasowa została pomyślnie utworzona!\n\nPieśni: {manifest.SongsCount}\nPlany: {manifest.PlansCount}", "CantatePresenter", MessageBoxButton.OK, MessageBoxImage.Information);
                }
                catch (Exception ex)
                {
                    MessageBox.Show($"Błąd podczas tworzenia kopii: {ex.Message}", "CantatePresenter", MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }

        private void RestoreBackup_Click(object sender, RoutedEventArgs e)
        {
            var ofd = new OpenFileDialog
            {
                Title = "Wskaż plik kopii zapasowej do przywrócenia",
                Filter = "Kopie CantatePresenter (*.cantatebackup;*.holyricsbackup;*.zip)|*.cantatebackup;*.holyricsbackup;*.zip"
            };

            if (ofd.ShowDialog() == true)
            {
                var confirm = MessageBox.Show("Czy na pewno chcesz przywrócić dane z wybranego archiwum? Aktualny stan zostanie nadpisany.", "Potwierdzenie przywrócenia", MessageBoxButton.YesNo, MessageBoxImage.Question);
                if (confirm == MessageBoxResult.Yes)
                {
                    bool ok = BackupService.RestoreBackupArchive(ofd.FileName);
                    if (ok)
                    {
                        DataStore.Shared.LoadAll();
                        LoadSettings();
                        MessageBox.Show("Baza danych i ustawienia zostały pomyślnie przywrócone!", "CantatePresenter", MessageBoxButton.OK, MessageBoxImage.Information);
                    }
                    else
                    {
                        MessageBox.Show("Nie udało się przywrócić bazy z tego pliku.", "CantatePresenter", MessageBoxButton.OK, MessageBoxImage.Error);
                    }
                }
            }
        }

        private void Close_Click(object sender, RoutedEventArgs e)
        {
            var settings = DataStore.Shared.Settings;
            if (ScreenComboBox.SelectedItem is ScreenInfo si)
                settings.SelectedScreenIndex = si.Index;

            if (FontComboBox.SelectedItem is string font)
                settings.FontFamily = font;

            settings.IsBold = BoldCheckBox.IsChecked ?? true;
            settings.HasShadow = ShadowCheckBox.IsChecked ?? true;
            settings.MarginPercent = MarginSlider.Value / 100.0;
            settings.GoogleDrive.AutoBackupOnExit = GoogleDriveAutoBackupCheckBox.IsChecked ?? false;

            DataStore.Shared.SaveSettings();
            Close();
        }
    }
}
