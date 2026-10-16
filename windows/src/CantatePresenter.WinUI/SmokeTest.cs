using System.Text.Json.Nodes;
using CantatePresenter.Core.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Storage.Streams;

namespace CantatePresenter.WinUI;

/// <summary>
/// Próba w CI (runner Windows): aplikacja sama przechodzi przez planszę, projekcję, chwyty i czarny ekran, zapisuje zrzuty
/// okien i raport, potem się zamyka. Uruchomienie: CantatePresenter.exe --smoke-test KATALOG (z CANTATE_DATA_DIR na kopii).
/// </summary>
public static class SmokeTest
{
    public static async Task RunAsync(MainWindow window, string outputDirectory)
    {
        var report = new JsonObject();
        var failures = new JsonArray();
        void Check(string name, bool ok)
        {
            Services.Trace($"próba: {name} = {ok}");
            report[name] = ok;
            if (!ok) failures.Add(name);
        }
        try
        {
            Directory.CreateDirectory(outputDirectory);
            var library = Services.Library;
            await Task.Delay(1500);
            await Capture(window.Content as FrameworkElement, Path.Combine(outputDirectory, "1-main.png"));

            var song = Song.Create("Próba z CI", "Autor Testowy", "D", rawLyrics: "[Zwrotka 1]\nIdziemy razem przez pola,\nsłońce nad nami świeci.\n\n[Refren]\nŚpiewaj radośnie,\nniech się niesie.",
                chords: "Zwrotka 1:\nD            G\nIdziemy razem przez pola,\nA            D\nsłońce nad nami świeci.\n\nRefren:\nG        A\nŚpiewaj radośnie,\nD        h\nniech się niesie.");
            song.CcliNumber = "1234567";
            Services.Trace("próba: library.AddSong(song);");
            library.AddSong(song);
            Check("songAdded", library.Songs.Any(s => s.Title == "Próba z CI"));
            Check("slides", song.Slides.Count == 2);

            Services.Trace("próba: window.Presentation.ShowOn(null);");
            window.Presentation.ShowOn(null);
            await Task.Delay(1200);
            await Capture(window.Presentation.ContentElement, Path.Combine(outputDirectory, "2-standby.png"));

            Services.Trace("próba: library.Present(song);");
            library.Present(song);
            Check("live", library.IsLive && library.CurrentLiveSlide?.Text.StartsWith("Idziemy") == true);
            var size = Core.Presentation.AutoFit.OptimalFontSize(song.Slides[0].Text, 1280, 720, TextMeasurer.Shared);
            report["autoFitSize"] = size;
            Check("autoFit", size > 30 && size < 260);
            Check("copyrightNotice", library.CurrentCopyrightNotice?.Contains("1234567") == true);
            await Task.Delay(800);
            await Capture(window.Presentation.ContentElement, Path.Combine(outputDirectory, "3-live.png"));
            await Capture(window.Content as FrameworkElement, Path.Combine(outputDirectory, "4-main-live.png"));

            window.HandleKey(Windows.System.VirtualKey.Right, Core.Input.KeyContext.Presentation);
            Check("keyNext", library.ActiveSlideIndex == 1);
            window.HandleKey(Windows.System.VirtualKey.Number1, Core.Input.KeyContext.Presentation);
            Check("keyVerse", library.ActiveSlideIndex == 0);

            Services.Trace("próba: window.OpenMusicians();");
            window.OpenMusicians();
            await Task.Delay(1000);
            if (window.Musicians is MusiciansWindow musicians) await Capture(musicians.ContentElement, Path.Combine(outputDirectory, "5-musicians.png"));
            var stage = Core.Presentation.MusicianStage.Make(library, 2, s => s.Label);
            Check("musicianChords", stage.Current?.Lines.FirstOrDefault()?.Chords?.Trim() == "E            A");

            window.HandleKey(Windows.System.VirtualKey.B, Core.Input.KeyContext.Presentation);
            Check("blackScreen", library.IsBlackScreen);
            library.StopLive();
            library.StartOrResume();
            Check("resume", library.IsLive);
            Check("noIssues", library.Issues.Count == 0);
            report["version"] = Services.Version;
            report["screens"] = Screens.All().Count;
        }
        catch (Exception error)
        {
            report["exception"] = error.ToString();
            failures.Add("exception");
        }
        report["failures"] = failures;
        await File.WriteAllTextAsync(Path.Combine(outputDirectory, "report.json"), report.ToJsonString(Json.Pretty));
        Application.Current.Exit();
    }

    private static async Task Capture(FrameworkElement? element, string path)
    {
        Services.Trace($"zrzut: {Path.GetFileName(path)} {element?.ActualWidth}x{element?.ActualHeight}");
        if (element is null || element.ActualWidth < 1) return;
        var bitmap = new RenderTargetBitmap();
        await bitmap.RenderAsync(element);
        var pixels = await bitmap.GetPixelsAsync();
        using var stream = new InMemoryRandomAccessStream();
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, (uint)bitmap.PixelWidth, (uint)bitmap.PixelHeight, 96, 96, pixels.ToArray());
        await encoder.FlushAsync();
        Services.Trace("zrzut: zakodowany");
        stream.Seek(0);
        var bytes = new byte[stream.Size];
        using var reader = new DataReader(stream);
        await reader.LoadAsync((uint)stream.Size);
        reader.ReadBytes(bytes);
        await File.WriteAllBytesAsync(path, bytes);
    }
}
