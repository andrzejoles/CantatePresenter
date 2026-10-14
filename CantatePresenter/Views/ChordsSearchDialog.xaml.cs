using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using CantatePresenter.Models;
using CantatePresenter.Services;

namespace CantatePresenter.Views
{
    public partial class ChordsSearchDialog : Window
    {
        private readonly GuitarChordsService _chordsService = new();
        private readonly Song? _targetSong;
        private string _baseChords = "";
        private int _currentSemitones = 0;

        public string? ResultChords { get; private set; }

        public ChordsSearchDialog(Song? song = null)
        {
            InitializeComponent();
            _targetSong = song;

            if (_targetSong != null)
            {
                SearchBox.Text = _targetSong.Title;
                if (!string.IsNullOrEmpty(_targetSong.Chords))
                {
                    _baseChords = _targetSong.Chords;
                    ChordsPreviewBox.Text = _baseChords;
                }
            }

            DoSearch();
        }

        private async void DoSearch()
        {
            var q = SearchBox.Text.Trim();
            if (string.IsNullOrEmpty(q)) return;

            var results = await _chordsService.SearchChordsAsync(q, _targetSong?.Author);
            ResultsListBox.ItemsSource = results;

            if (results.Count > 0 && string.IsNullOrEmpty(_baseChords))
            {
                ResultsListBox.SelectedIndex = 0;
            }
        }

        private void Search_Click(object sender, RoutedEventArgs e)
        {
            DoSearch();
        }

        private void SearchBox_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter)
            {
                DoSearch();
            }
        }

        private void ResultsListBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (ResultsListBox.SelectedItem is GuitarChordResult res)
            {
                _baseChords = res.ChordsSheet;
                _currentSemitones = 0;
                UpdateTransposedView();
            }
        }

        private void TransposeUp_Click(object sender, RoutedEventArgs e)
        {
            _currentSemitones++;
            UpdateTransposedView();
        }

        private void TransposeDown_Click(object sender, RoutedEventArgs e)
        {
            _currentSemitones--;
            UpdateTransposedView();
        }

        private void TransposeReset_Click(object sender, RoutedEventArgs e)
        {
            _currentSemitones = 0;
            UpdateTransposedView();
        }

        private void UpdateTransposedView()
        {
            TransposeLabel.Text = $"Przesunięcie: {(_currentSemitones > 0 ? "+" : "")}{_currentSemitones} półtonów";
            ChordsPreviewBox.Text = _chordsService.Transpose(_baseChords, _currentSemitones);
        }

        private void Apply_Click(object sender, RoutedEventArgs e)
        {
            ResultChords = ChordsPreviewBox.Text.Trim();
            if (_targetSong != null)
            {
                _targetSong.Chords = ResultChords;
                DataStore.Shared.UpdateSong(_targetSong);
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
