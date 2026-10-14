import Foundation

public struct SampleSongs {
    public static func loadDefaults() -> [Song] {
        return [
            Song(
                title: "Barka",
                author: "Cesáreo Gabaráin (tłum. ks. Stanisław Szmidt)",
                key: "D",
                tags: ["Oazowe", "Powołaniowe", "Tradycyjne"],
                rawLyrics: """
                [Zwrotka 1]
                Pan kiedyś stanął nad brzegiem,
                Szukał ludzi gotowych pójść za Nim,
                By łowić serca słów Bożych prawdą.

                [Refren]
                O Panie, to Ty na mnie spojrzałeś,
                Twoje usta dziś wyrzekły me imię.
                Swoją barkę pozostawiam na brzegu,
                Razem z Tobą nowy zacznę dziś łów.

                [Zwrotka 2]
                Jestem ubogim człowiekiem,
                Moim skarbem są ręce gotowe
                Do pracy z Tobą i czyste serce.

                [Refren]
                O Panie, to Ty na mnie spojrzałeś,
                Twoje usta dziś wyrzekły me imię.
                Swoją barkę pozostawiam na brzegu,
                Razem z Tobą nowy zacznę dziś łów.

                [Zwrotka 3]
                Ty potrzebujesz mych dłoni,
                Mego serca młodego zapałem,
                Mych kropli potu i samotności.

                [Refren]
                O Panie, to Ty na mnie spojrzałeś,
                Twoje usta dziś wyrzekły me imię.
                Swoją barkę pozostawiam na brzegu,
                Razem z Tobą nowy zacznę dziś łów.

                [Zwrotka 4]
                Dziś wypływamy już razem
                Łowić serca na morzach dusz ludzkich,
                Twej prawdy siecią i słowem życia.

                [Refren]
                O Panie, to Ty na mnie spojrzałeś,
                Twoje usta dziś wyrzekły me imię.
                Swoją barkę pozostawiam na brzegu,
                Razem z Tobą nowy zacznę dziś łów.
                """
            ),
            Song(
                title: "Oceany (Duchu prowadź)",
                author: "Hillsong United (tłum. polskie)",
                key: "D",
                tags: ["Uwielbienie", "Współczesne"],
                rawLyrics: """
                [Zwrotka 1]
                Na głębię wzywasz dzisiaj wiarę mą,
                Gdzie tylko Twoja łaska sięga.
                Tam znajdę Cię pośród szalejących fal,
                Gdy grunt pod stopami znika mi.

                [Refren]
                Więc imię Twoje wołać chcę,
                Ponad falami wzrok mój trzymać.
                Gdy wzburzy się ocean burz,
                W ramionach Twych odpocznę ja,
                Bo należę do Ciebie, a Ty do mnie.

                [Zwrotka 2]
                Twe łaski skarb w otchłani wielkich wód,
                Twa dłoń potężna mnie ochrania.
                I chociaż lęk próbuje znowu zgnębić mnie,
                Nie zachwieję się, bo Ty nie zawiedziesz.

                [Bridge]
                Duchu, prowadź mnie tam, gdzie wiara nie ma granic,
                Pozwól chodzić po wodach,
                Dokądkolwiek mnie wezwiesz.
                Głębiej zabierz mnie niż stopy mogą stanąć,
                By ma wiara wzrosła w obecności Zbawcy.
                """
            ),
            Song(
                title: "Dzięki Jezu",
                author: "Tradycyjna",
                key: "G",
                tags: ["Dziękczynienie", "Uwielbienie"],
                rawLyrics: """
                [Zwrotka 1]
                Dzięki Jezu, dzięki Jezu,
                Dzięki Ci, że kochasz mnie!
                Dzięki Jezu, dzięki Jezu,
                Dzięki Ci, że kochasz mnie!

                [Refren]
                Na Golgocie umarłeś,
                Nowe życie mi dałeś!
                Dzięki Jezu, dzięki Jezu,
                Dzięki Ci, że kochasz mnie!

                [Zwrotka 2]
                Twoja krew mnie obmyła,
                Twoja łaska zbawiła!
                Dzięki Jezu, dzięki Jezu,
                Dzięki Ci, że kochasz mnie!
                """
            ),
            Song(
                title: "Schowaj mnie",
                author: "Reuben Morgan",
                key: "C",
                tags: ["Uwielbienie", "Spokojne"],
                rawLyrics: """
                [Zwrotka 1]
                Schowaj mnie pod skrzydła Twe,
                Ukryj mnie w silnej dłoni Twej.

                [Refren]
                Gdy fale mórz chcą porwać mnie,
                Z Tobą wzniosę się ponad deszcz.
                Królem jesteś nad wodami burz,
                I ufam Ci, bo jesteś Bóg!

                [Zwrotka 2]
                Odpocznij duszo w Nim,
                Jego moc w ciszy ukoi cię.

                [Refren]
                Gdy fale mórz chcą porwać mnie,
                Z Tobą wzniosę się ponad deszcz.
                Królem jesteś nad wodami burz,
                I ufam Ci, bo jesteś Bóg!
                """
            ),
            Song(
                title: "10 000 Powodów (Błogosław duszo moja Pana)",
                author: "Matt Redman (tłum. polskie)",
                key: "G",
                tags: ["Uwielbienie", "Chwała"],
                rawLyrics: """
                [Refren]
                Błogosław, duszo moja, Pana,
                O, duszo ma, Jego święte Imię czcij!
                Śpiewaj Mu, jak nigdy dotąd dotąd,
                O, duszo ma, czcij święte Imię Twe!

                [Zwrotka 1]
                Wschodzi słońce, nowy dzień nastaje,
                Czas, by śpiewać Twoją pieśń na nowo.
                Cokolwiek minęło i co przede mną leży,
                Niech śpiewam znów, gdy nadejdzie zmierzch.

                [Zwrotka 2]
                Bogaty w miłość, nieskory do gniewu,
                Twe Imię wielkie, Twe serce dobre.
                Dla całej Twej dobroci będę śpiewał,
                Mam dziesięć tysięcy powodów, by czcić.

                [Zwrotka 3]
                I w owym dniu, gdy sił mi już zabraknie,
                Mój koniec zbliży się i czas mój minie,
                Wciąż moja dusza śpiewać będzie chwałę,
                Przez dziesięć tysięcy lat i na zawsze!
                """
            ),
            Song(
                title: "Jezus Siłą Mą",
                author: "Współczesna",
                key: "E",
                tags: ["Uwielbienie", "Radosne"],
                rawLyrics: """
                [Zwrotka 1]
                Jezus siłą mą, Jezus siłą mą,
                Jezus siłą mą i zbawieniem!
                Jezus siłą mą, Jezus siłą mą,
                Jezus siłą mą i zbawieniem!

                [Refren]
                On moim Panem jest,
                I moim Królem jest!
                Nie zlęknę się, bo ze mną Pan!
                On moim Panem jest,
                I moim Królem jest!
                Nie zlęknę się, bo ze mną Pan!
                """
            ),
            Song(
                title: "Abba Ojcze",
                author: "O. Jan Góra OP",
                key: "D",
                tags: ["Hymn ŚDM", "Tradycyjne"],
                rawLyrics: """
                [Zwrotka 1]
                Ty wyzwoliłeś nas Panie
                Z kajdanów i z niemocy,
                Światło Twe rozproszyło
                Mroki naszej nocy.

                [Refren]
                Abba, Ojcze! Abba, Ojcze!
                Abba, Ojcze!

                [Zwrotka 2]
                Kościół jak drzewo życia
                W wieczności zapuszcza korzenie,
                Przenika naszą codzienność
                I przynosi ocalenie.

                [Zwrotka 3]
                Bóg stał się naszym Ojcem,
                A my Jego dziećmi,
                Braćmi dla siebie wzajemnie
                W Chrystusie na zawsze.
                """
            ),
            Song(
                title: "Amazing Grace (Cudowna Boża Łaska)",
                author: "John Newton",
                key: "G",
                tags: ["Hymn", "Klasyczne"],
                rawLyrics: """
                [Zwrotka 1]
                Amazing grace! How sweet the sound
                That saved a wretch like me!
                I once was lost, but now am found;
                Was blind, but now I see.

                [Zwrotka 2]
                'Twas grace that taught my heart to fear,
                And grace my fears relieved;
                How precious did that grace appear
                The hour I first believed!

                [Zwrotka 3]
                Through many dangers, toils and snares,
                I have already come;
                'Tis grace hath brought me safe thus far,
                And grace will lead me home.

                [Zwrotka 4]
                When we've been there ten thousand years,
                Bright shining as the sun,
                We've no less days to sing God's praise
                Than when we'd first begun.
                """
            )
        ]
    }
}
