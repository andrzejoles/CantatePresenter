namespace CantatePresenter.Core.Models;

/// <summary>Pieśni na pierwsze uruchomienie: wyłącznie teksty w domenie publicznej (te same co w wersji webowej).</summary>
public static class SampleSongs
{
    private static Song Make(string title, string author, string[] tags, string copyright, string lyrics)
    {
        var song = Song.Create(title, author, tags: tags, rawLyrics: lyrics);
        song.Copyright = copyright;
        return song;
    }

    public static List<Song> Create() =>
    [
        Make("Kiedy ranne wstają zorze", "Franciszek Karpiński (1792)", ["Poranne", "Domena publiczna"], "Domena publiczna",
            "[Zwrotka 1]\nKiedy ranne wstają zorze,\nTobie ziemia, Tobie morze,\nTobie śpiewa żywioł wszelki,\nBądź pochwalon, Boże wielki!\n\n[Zwrotka 2]\nA człowiek, który bez miary\nObsypany Twymi dary,\nCoś go stworzył i ocalił,\nA czemuż by Cię nie chwalił?\n\n[Zwrotka 3]\nLedwie oczy przetrzeć zdołam,\nWnet do mego Pana wołam,\nDo mego Boga na niebie\nI szukam Go koło siebie."),
        Make("Boże, coś Polskę", "Alojzy Feliński (1816)", ["Patriotyczne", "Domena publiczna"], "Domena publiczna",
            "[Zwrotka 1]\nBoże, coś Polskę przez tak liczne wieki\nOtaczał blaskiem potęgi i chwały,\nCoś ją osłaniał tarczą swej opieki\nOd nieszczęść, które przygnębić ją miały.\n\n[Refren]\nPrzed Twe ołtarze zanosim błaganie:\nOjczyznę wolną pobłogosław, Panie!"),
    ];
}
