using System;
using System.Collections.Generic;
using System.Linq;

namespace CantatePresenter.Models
{
    public class LogoPreset
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public string Subtitle { get; set; } = "";
        public string Category { get; set; } = "";
        public string SvgContent { get; set; } = "";

        public LogoPreset(string id, string name, string subtitle, string category, string svgContent)
        {
            Id = id;
            Name = name;
            Subtitle = subtitle;
            Category = category;
            SvgContent = svgContent;
        }
    }

    public static class LogoCatalog
    {
        public static readonly List<LogoPreset> All = new()
        {
            new LogoPreset(
                "light_of_glory",
                "1. Promień Chwały",
                "Świetlisty krzyż z wiązkami projekcyjnymi",
                "Światło i Projektor",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""g1"" x1=""0"" y1=""0"" x2=""200"" y2=""200"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#00F0FF""/>
                        <stop offset=""100%"" stop-color=""#7000FF""/>
                    </linearGradient>
                    <linearGradient id=""beam"" x1=""100"" y1=""0"" x2=""100"" y2=""200"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#FFFFFF"" stop-opacity=""0.9""/>
                        <stop offset=""50%"" stop-color=""#38BDF8"" stop-opacity=""0.6""/>
                        <stop offset=""100%"" stop-color=""#000000"" stop-opacity=""0""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#0D111D"" stroke=""url(#g1)"" stroke-width=""2.5""/>
                <polygon points=""100,20 160,180 40,180"" fill=""url(#beam)"" opacity=""0.35""/>
                <rect x=""94"" y=""38"" width=""12"" height=""100"" rx=""6"" fill=""#FFFFFF""/>
                <rect x=""62"" y=""62"" width=""76"" height=""12"" rx=""6"" fill=""#FFFFFF""/>
                <circle cx=""100"" cy=""68"" r=""14"" fill=""#00F0FF"" opacity=""0.8"" filter=""blur(4px)""/>
                <circle cx=""100"" cy=""68"" r=""5"" fill=""#FFFFFF""/>
                <path d=""M 60 145 Q 100 125 140 145"" stroke=""#00F0FF"" stroke-width=""3"" stroke-linecap=""round"" fill=""none""/>
                <path d=""M 75 158 Q 100 144 125 158"" stroke=""#A855F7"" stroke-width=""2.5"" stroke-linecap=""round"" fill=""none""/>
            </svg>"
            ),
            new LogoPreset(
                "spirit_flame",
                "2. Płomień Ducha i Harfa",
                "Unoszący się ogień uwielbienia ze strunami muzycznymi",
                "Muzyka i Duch",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""fire"" x1=""100"" y1=""180"" x2=""100"" y2=""20"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#EF4444""/>
                        <stop offset=""45%"" stop-color=""#F59E0B""/>
                        <stop offset=""90%"" stop-color=""#FDE047""/>
                        <stop offset=""100%"" stop-color=""#FFFFFF""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#0B0F19"" stroke=""#F59E0B"" stroke-width=""2"" stroke-opacity=""0.4""/>
                <path d=""M 100 25 C 130 65, 155 105, 140 145 C 128 175, 72 175, 60 145 C 45 105, 70 65, 100 25 Z"" fill=""url(#fire)"" opacity=""0.9""/>
                <path d=""M 100 65 C 115 90, 130 115, 120 140 C 112 160, 88 160, 80 140 C 70 115, 85 90, 100 65 Z"" fill=""#0B0F19""/>
                <line x1=""90"" y1=""95"" x2=""90"" y2=""145"" stroke=""#FDE047"" stroke-width=""2"" stroke-linecap=""round""/>
                <line x1=""100"" y1=""85"" x2=""100"" y2=""148"" stroke=""#FFFFFF"" stroke-width=""2.5"" stroke-linecap=""round""/>
                <line x1=""110"" y1=""95"" x2=""110"" y2=""145"" stroke=""#FDE047"" stroke-width=""2"" stroke-linecap=""round""/>
                <circle cx=""100"" cy=""40"" r=""3"" fill=""#FFFFFF""/>
            </svg>"
            ),
            new LogoPreset(
                "multiscreen_cross",
                "3. Podwójny Ekran Prezentera",
                "Dwa nakładające się ekrany z krzyżem w przestrzeni negatywowej",
                "Ekrany i Technologia",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""sc1"" x1=""30"" y1=""40"" x2=""130"" y2=""140"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#3B82F6""/>
                        <stop offset=""100%"" stop-color=""#1D4ED8""/>
                    </linearGradient>
                    <linearGradient id=""sc2"" x1=""70"" y1=""60"" x2=""170"" y2=""160"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#06B6D4""/>
                        <stop offset=""100%"" stop-color=""#0E7490""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#090D16"" stroke=""#1E293B"" stroke-width=""2""/>
                <rect x=""35"" y=""45"" width=""90"" height=""60"" rx=""10"" fill=""url(#sc1)"" fill-opacity=""0.75"" stroke=""#60A5FA"" stroke-width=""2""/>
                <rect x=""75"" y=""75"" width=""90"" height=""60"" rx=""10"" fill=""url(#sc2)"" fill-opacity=""0.85"" stroke=""#67E8F9"" stroke-width=""2""/>
                <!-- Glowing central cross on front screen -->
                <rect x=""115"" y=""85"" width=""10"" height=""40"" rx=""5"" fill=""#FFFFFF""/>
                <rect x=""100"" y=""97"" width=""40"" height=""10"" rx=""5"" fill=""#FFFFFF""/>
                <circle cx=""50"" cy=""58"" r=""3"" fill=""#93C5FD""/>
                <circle cx=""58"" cy=""58"" r=""3"" fill=""#93C5FD""/>
            </svg>"
            ),
            new LogoPreset(
                "ascending_song",
                "4. Wznosząca się Pieśń",
                "Otwarty śpiewnik z ulatującymi świetlistymi nutami",
                "Śpiewnik i Nuty",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""bookGrad"" x1=""30"" y1=""120"" x2=""170"" y2=""170"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#6366F1""/>
                        <stop offset=""100%"" stop-color=""#EC4899""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#0F172A"" stroke=""#334155"" stroke-width=""2""/>
                <!-- Open Book Pages -->
                <path d=""M 35 140 C 65 125, 95 128, 100 148 C 105 128, 135 125, 165 140 L 165 160 C 135 145, 105 148, 100 168 C 95 148, 65 145, 35 160 Z"" fill=""url(#bookGrad)""/>
                <!-- Floating Notes & Cross -->
                <path d=""M 100 35 L 100 115"" stroke=""#F43F5E"" stroke-width=""4"" stroke-linecap=""round""/>
                <path d=""M 80 55 L 120 55"" stroke=""#F43F5E"" stroke-width=""4"" stroke-linecap=""round""/>
                <ellipse cx=""65"" cy=""85"" rx=""6"" ry=""5"" fill=""#F472B6""/>
                <path d=""M 70 85 L 70 65 L 85 68"" stroke=""#F472B6"" stroke-width=""2"" stroke-linecap=""round""/>
                <ellipse cx=""135"" cy=""78"" rx=""6"" ry=""5"" fill=""#A78BFA""/>
                <path d=""M 140 78 L 140 58 L 155 60"" stroke=""#A78BFA"" stroke-width=""2"" stroke-linecap=""round""/>
            </svg>"
            ),
            new LogoPreset(
                "monogram_h",
                "5. Geometryczny Monogram H",
                "Minimalistyczna litera H ze zintegrowanym krzyżem chwały",
                "Monogram i Typografia",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""hGrad"" x1=""40"" y1=""30"" x2=""160"" y2=""170"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#38BDF8""/>
                        <stop offset=""50%"" stop-color=""#818CF8""/>
                        <stop offset=""100%"" stop-color=""#C084FC""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#0A0E17"" stroke=""url(#hGrad)"" stroke-width=""3""/>
                <!-- Left pillar -->
                <rect x=""52"" y=""42"" width=""22"" height=""116"" rx=""8"" fill=""url(#hGrad)""/>
                <!-- Right pillar -->
                <rect x=""126"" y=""42"" width=""22"" height=""116"" rx=""8"" fill=""url(#hGrad)""/>
                <!-- Cross centerpiece -->
                <rect x=""68"" y=""90"" width=""64"" height=""20"" rx=""6"" fill=""#FFFFFF""/>
                <rect x=""90"" y=""65"" width=""20"" height=""70"" rx=""6"" fill=""#FFFFFF""/>
                <circle cx=""100"" cy=""100"" r=""4"" fill=""#38BDF8""/>
            </svg>"
            ),
            new LogoPreset(
                "dawn_mountain",
                "6. Świt Nadziei (Góra Chwały)",
                "Wschód słońca nad szczytami uwielbienia ze świetlistą aureolą",
                "Natura i Nadzieja",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""sun"" x1=""100"" y1=""40"" x2=""100"" y2=""120"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#FBBF24""/>
                        <stop offset=""100%"" stop-color=""#F97316""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#0C1322"" stroke=""#F59E0B"" stroke-width=""2"" stroke-opacity=""0.5""/>
                <!-- Sun & rays -->
                <circle cx=""100"" cy=""85"" r=""32"" fill=""url(#sun)""/>
                <rect x=""97"" y=""32"" width=""6"" height=""106"" rx=""3"" fill=""#FFFFFF"" opacity=""0.95""/>
                <rect x=""70"" y=""58"" width=""60"" height=""6"" rx=""3"" fill=""#FFFFFF"" opacity=""0.95""/>
                <!-- Mountains in foreground -->
                <polygon points=""25,165 75,105 130,165"" fill=""#1E293B""/>
                <polygon points=""90,165 145,115 175,165"" fill=""#334155""/>
                <polygon points=""60,165 110,120 160,165"" fill=""#0F172A"" opacity=""0.8""/>
            </svg>"
            ),
            new LogoPreset(
                "worship_dove",
                "7. Gołębica Pokoju i Dźwięku",
                "Lecąca gołębica uformowana z płynnych fal dźwiękowych",
                "Pokój i Wolność",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""doveGrad"" x1=""30"" y1=""30"" x2=""170"" y2=""170"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#38BDF8""/>
                        <stop offset=""100%"" stop-color=""#818CF8""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#080E1A"" stroke=""#0284C7"" stroke-width=""2""/>
                <path d=""M 45 115 C 65 70, 115 65, 145 50 C 135 75, 120 95, 135 120 C 115 110, 95 125, 75 145 C 75 130, 60 120, 45 115 Z"" fill=""url(#doveGrad)""/>
                <!-- Olive leaf / light beacon -->
                <ellipse cx=""152"" cy=""48"" rx=""6"" ry=""3"" transform=""rotate(-30 152 48)"" fill=""#34D399""/>
                <!-- Subtle sound ripples -->
                <path d=""M 50 140 Q 80 125 110 145"" stroke=""#38BDF8"" stroke-width=""2"" fill=""none"" opacity=""0.7""/>
                <path d=""M 65 152 Q 95 138 125 155"" stroke=""#818CF8"" stroke-width=""2"" fill=""none"" opacity=""0.5""/>
            </svg>"
            ),
            new LogoPreset(
                "king_crown",
                "8. Korona Króla Chwały",
                "Geometryczna korona majestatu z centralnym krzyżem",
                "Majestat i Królestwo",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""gold"" x1=""30"" y1=""50"" x2=""170"" y2=""160"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#FDE047""/>
                        <stop offset=""50%"" stop-color=""#EAB308""/>
                        <stop offset=""100%"" stop-color=""#CA8A04""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#111827"" stroke=""url(#gold)"" stroke-width=""2.5""/>
                <!-- Crown Base -->
                <polygon points=""40,140 160,140 150,90 120,115 100,75 80,115 50,90"" fill=""url(#gold)""/>
                <!-- Bottom band -->
                <rect x=""40"" y=""142"" width=""120"" height=""12"" rx=""4"" fill=""#A16207""/>
                <!-- Cross on top of center peak -->
                <rect x=""97"" y=""42"" width=""6"" height=""30"" rx=""3"" fill=""#FFFFFF""/>
                <rect x=""87"" y=""50"" width=""26"" height=""6"" rx=""3"" fill=""#FFFFFF""/>
                <!-- Jewels -->
                <circle cx=""65"" cy=""148"" r=""3"" fill=""#EF4444""/>
                <circle cx=""100"" cy=""148"" r=""4"" fill=""#3B82F6""/>
                <circle cx=""135"" cy=""148"" r=""3"" fill=""#EF4444""/>
            </svg>"
            ),
            new LogoPreset(
                "projector_lens",
                "9. Obiektyw Projektora i Pryzmat",
                "Precyzyjna soczewka projektora rozszczepiająca boskie światło",
                "Projekcja i Optyka",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""lensGrad"" x1=""40"" y1=""40"" x2=""160"" y2=""160"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#06B6D4""/>
                        <stop offset=""50%"" stop-color=""#3B82F6""/>
                        <stop offset=""100%"" stop-color=""#8B5CF6""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#0B0F19"" stroke=""url(#lensGrad)"" stroke-width=""2""/>
                <circle cx=""100"" cy=""100"" r=""55"" stroke=""url(#lensGrad)"" stroke-width=""3"" fill=""none""/>
                <circle cx=""100"" cy=""100"" r=""38"" stroke=""#38BDF8"" stroke-width=""2"" stroke-dasharray=""8 6"" fill=""none""/>
                <!-- Center cross aperture -->
                <rect x=""96"" y=""65"" width=""8"" height=""70"" rx=""4"" fill=""#FFFFFF""/>
                <rect x=""75"" y=""86"" width=""50"" height=""8"" rx=""4"" fill=""#FFFFFF""/>
                <circle cx=""100"" cy=""100"" r=""10"" fill=""#38BDF8"" opacity=""0.6""/>
            </svg>"
            ),
            new LogoPreset(
                "halo_clef",
                "10. Aureola i Klucz Wiolinowy",
                "Złota glorietta połączona z dynamicznym symbolem pieśni",
                "Muzyka i Klasyka",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""halo"" x1=""40"" y1=""40"" x2=""160"" y2=""160"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#FCD34D""/>
                        <stop offset=""100%"" stop-color=""#F59E0B""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#13111C"" stroke=""url(#halo)"" stroke-width=""2""/>
                <!-- Glowing Halo Ring -->
                <ellipse cx=""100"" cy=""65"" rx=""55"" ry=""18"" stroke=""url(#halo)"" stroke-width=""4"" fill=""none""/>
                <!-- Treble Clef Stylized Cross -->
                <path d=""M 100 40 L 100 155 C 100 168, 82 168, 82 155 C 82 145, 94 140, 100 148"" stroke=""#FFFFFF"" stroke-width=""4.5"" stroke-linecap=""round"" fill=""none""/>
                <path d=""M 75 85 L 125 85"" stroke=""#FFFFFF"" stroke-width=""4.5"" stroke-linecap=""round""/>
                <circle cx=""100"" cy=""105"" r=""14"" stroke=""#FBBF24"" stroke-width=""3"" fill=""none""/>
            </svg>"
            ),
            new LogoPreset(
                "living_waters",
                "11. Strumienie Żywej Wody",
                "Harmonijne fale łaski i dźwięku w odcieniach lazuru",
                "Natura i Spokój",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""water"" x1=""20"" y1=""60"" x2=""180"" y2=""180"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#38BDF8""/>
                        <stop offset=""50%"" stop-color=""#0284C7""/>
                        <stop offset=""100%"" stop-color=""#0369A1""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#081426"" stroke=""#0EA5E9"" stroke-width=""2""/>
                <path d=""M 35 105 C 65 85, 95 125, 125 105 C 145 90, 155 95, 165 105"" stroke=""#38BDF8"" stroke-width=""4"" stroke-linecap=""round"" fill=""none""/>
                <path d=""M 35 125 C 65 105, 95 145, 125 125 C 145 110, 155 115, 165 125"" stroke=""#0284C7"" stroke-width=""4"" stroke-linecap=""round"" fill=""none""/>
                <path d=""M 35 145 C 65 125, 95 165, 125 145 C 145 130, 155 135, 165 145"" stroke=""#0369A1"" stroke-width=""4"" stroke-linecap=""round"" fill=""none""/>
                <!-- Water drop cross on top -->
                <path d=""M 100 45 C 115 65, 120 75, 120 85 C 120 96, 111 105, 100 105 C 89 105, 80 96, 80 85 C 80 75, 85 65, 100 45 Z"" fill=""#E0F2FE""/>
                <rect x=""98"" y=""65"" width=""4"" height=""28"" rx=""2"" fill=""#0284C7""/>
                <rect x=""88"" y=""75"" width=""24"" height=""4"" rx=""2"" fill=""#0284C7""/>
            </svg>"
            ),
            new LogoPreset(
                "stage_neon",
                "12. Neon Sceniczny (Stage HUD)",
                "Kontrastowa nowoczesna estetyka estradowa w stylu cyber-worship",
                "Nowoczesne i Scena",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#05050A"" stroke=""#22D3EE"" stroke-width=""2.5""/>
                <!-- Hexagon / diamond frame -->
                <polygon points=""100,38 155,70 155,130 100,162 45,130 45,70"" stroke=""#F43F5E"" stroke-width=""2"" fill=""none"" opacity=""0.6""/>
                <!-- Bright Neon Cross -->
                <rect x=""94"" y=""55"" width=""12"" height=""90"" rx=""6"" fill=""#22D3EE"" filter=""drop-shadow(0 0 10px #22D3EE)""/>
                <rect x=""65"" y=""80"" width=""70"" height=""12"" rx=""6"" fill=""#22D3EE"" filter=""drop-shadow(0 0 10px #22D3EE)""/>
                <circle cx=""100"" cy=""86"" r=""6"" fill=""#FFFFFF""/>
            </svg>"
            ),
            new LogoPreset(
                "wings_of_faith",
                "13. Skrzydła Wiary i Chwały",
                "Anielskie skrzydła unoszące modlitwę i pieśń ku niebiosom",
                "Skrzydła i Aniołowie",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""wing"" x1=""20"" y1=""40"" x2=""180"" y2=""160"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#A78BFA""/>
                        <stop offset=""100%"" stop-color=""#4F46E5""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#0C0E1A"" stroke=""#6366F1"" stroke-width=""2""/>
                <!-- Left Wing -->
                <path d=""M 95 145 C 55 130, 35 90, 42 55 C 58 75, 75 90, 95 105 Z"" fill=""url(#wing)"" opacity=""0.9""/>
                <!-- Right Wing -->
                <path d=""M 105 145 C 145 130, 165 90, 158 55 C 142 75, 125 90, 105 105 Z"" fill=""url(#wing)"" opacity=""0.9""/>
                <!-- Center Slim Cross -->
                <rect x=""97"" y=""45"" width=""6"" height=""105"" rx=""3"" fill=""#FFFFFF""/>
                <rect x=""80"" y=""70"" width=""40"" height=""6"" rx=""3"" fill=""#FFFFFF""/>
                <circle cx=""100"" cy=""73"" r=""10"" fill=""#818CF8"" opacity=""0.5""/>
            </svg>"
            ),
            new LogoPreset(
                "praise_heart",
                "14. Serce Pełne Chwały",
                "Czysta wstęga origami tworząca serce z krzyżem w centrum",
                "Miłość i Oddanie",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""heart"" x1=""40"" y1=""40"" x2=""160"" y2=""160"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#FB7185""/>
                        <stop offset=""100%"" stop-color=""#E11D48""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#140D14"" stroke=""#FB7185"" stroke-width=""2""/>
                <path d=""M 100 160 C 60 125, 35 100, 35 70 C 35 48, 52 35, 75 35 C 88 35, 96 42, 100 50 C 104 42, 112 35, 125 35 C 148 35, 165 48, 165 70 C 165 100, 140 125, 100 160 Z"" stroke=""url(#heart)"" stroke-width=""4"" fill=""none""/>
                <!-- Cross inside heart -->
                <rect x=""96"" y=""55"" width=""8"" height=""75"" rx=""4"" fill=""#FFFFFF""/>
                <rect x=""75"" y=""75"" width=""50"" height=""8"" rx=""4"" fill=""#FFFFFF""/>
                <circle cx=""100"" cy=""79"" r=""4"" fill=""#FB7185""/>
            </svg>"
            ),
            new LogoPreset(
                "crystal_prism",
                "15. Kryształowa Arka Przymierza",
                "Wielościenny klejnot odbijający całą paletę niebiańskich barw",
                "Kryształ i Geometria",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#0A0F1D"" stroke=""#38BDF8"" stroke-width=""2""/>
                <polygon points=""100,35 155,75 135,155 65,155 45,75"" stroke=""#60A5FA"" stroke-width=""2.5"" fill=""#1E293B"" fill-opacity=""0.5""/>
                <!-- Inner facets -->
                <line x1=""100"" y1=""35"" x2=""100"" y2=""155"" stroke=""#93C5FD"" stroke-width=""2""/>
                <line x1=""45"" y1=""75"" x2=""155"" y2=""75"" stroke=""#93C5FD"" stroke-width=""2""/>
                <line x1=""45"" y1=""75"" x2=""100"" y2=""110"" stroke=""#38BDF8"" stroke-width=""1.5""/>
                <line x1=""155"" y1=""75"" x2=""100"" y2=""110"" stroke=""#38BDF8"" stroke-width=""1.5""/>
                <circle cx=""100"" cy=""75"" r=""7"" fill=""#FFFFFF""/>
            </svg>"
            ),
            new LogoPreset(
                "apple_native_screen",
                "16. Minimalistyczny Ekran Apple Mac",
                "Stylowy, surowy design ikony macOS z ekranem Retina i nutą",
                "Apple Minimalizm",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""macBody"" x1=""0"" y1=""0"" x2=""200"" y2=""200"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#334155""/>
                        <stop offset=""100%"" stop-color=""#0F172A""/>
                    </linearGradient>
                    <linearGradient id=""screenGrad"" x1=""40"" y1=""40"" x2=""160"" y2=""130"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#2563EB""/>
                        <stop offset=""100%"" stop-color=""#7C3AED""/>
                    </linearGradient>
                </defs>
                <!-- Squircle icon body -->
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""url(#macBody)"" stroke=""#475569"" stroke-width=""2""/>
                <!-- Inner Display Frame -->
                <rect x=""34"" y=""38"" width=""132"" height=""92"" rx=""12"" fill=""url(#screenGrad)""/>
                <!-- Stand base -->
                <rect x=""92"" y=""130"" width=""16"" height=""22"" fill=""#64748B""/>
                <rect x=""75"" y=""150"" width=""50"" height=""6"" rx=""3"" fill=""#94A3B8""/>
                <!-- Cross on display -->
                <rect x=""96"" y=""52"" width=""8"" height=""64"" rx=""4"" fill=""#FFFFFF""/>
                <rect x=""76"" y=""68"" width=""48"" height=""8"" rx=""4"" fill=""#FFFFFF""/>
                <circle cx=""100"" cy=""72"" r=""5"" fill=""#38BDF8""/>
            </svg>"
            ),
            new LogoPreset(
                "acoustic_guitar",
                "17. Złota Gitara Akustyczna",
                "Ciepłe drewno akustyczne, rozeta, struny i promieniujące fale dźwiękowe",
                "Muzyka & Instrumenty",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""gWood"" x1=""50"" y1=""50"" x2=""150"" y2=""180"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#F59E0B""/>
                        <stop offset=""50%"" stop-color=""#D97706""/>
                        <stop offset=""100%"" stop-color=""#78350F""/>
                    </linearGradient>
                    <linearGradient id=""gNeck"" x1=""100"" y1=""20"" x2=""100"" y2=""80"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#92400E""/>
                        <stop offset=""100%"" stop-color=""#451A03""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#0C101C"" stroke=""#F59E0B"" stroke-width=""2"" stroke-opacity=""0.5""/>
                <circle cx=""100"" cy=""122"" r=""38"" stroke=""#38BDF8"" stroke-width=""1.5"" stroke-dasharray=""4 4"" opacity=""0.35""/>
                <circle cx=""100"" cy=""122"" r=""50"" stroke=""#F59E0B"" stroke-width=""1.5"" stroke-dasharray=""5 5"" opacity=""0.3""/>
                <circle cx=""100"" cy=""122"" r=""62"" stroke=""#38BDF8"" stroke-width=""1.5"" stroke-dasharray=""6 6"" opacity=""0.2""/>
                <path d=""M 85 78 C 65 80, 60 98, 72 110 C 60 120, 56 142, 68 158 C 80 172, 120 172, 132 158 C 144 142, 140 120, 128 110 C 140 98, 135 80, 115 78 Z"" fill=""url(#gWood)"" stroke=""#FEF08A"" stroke-width=""2""/>
                <path d=""M 88 83 C 72 85, 68 100, 77 111 C 67 121, 64 140, 74 153 C 83 165, 117 165, 126 153 C 136 140, 133 121, 123 111 C 132 100, 128 85, 112 83 Z"" fill=""#0F172A"" opacity=""0.25""/>
                <circle cx=""100"" cy=""114"" r=""14"" fill=""#0C101C"" stroke=""#FEF08A"" stroke-width=""2.5""/>
                <circle cx=""100"" cy=""114"" r=""17"" stroke=""#F59E0B"" stroke-width=""1"" stroke-dasharray=""2 2""/>
                <rect x=""86"" y=""146"" width=""28"" height=""6"" rx=""2"" fill=""#451A03"" stroke=""#FEF08A"" stroke-width=""1""/>
                <rect x=""94"" y=""32"" width=""12"" height=""48"" fill=""url(#gNeck)"" stroke=""#B45309"" stroke-width=""1""/>
                <line x1=""94"" y1=""42"" x2=""106"" y2=""42"" stroke=""#E2E8F0"" stroke-width=""1.2""/>
                <line x1=""94"" y1=""52"" x2=""106"" y2=""52"" stroke=""#E2E8F0"" stroke-width=""1.2""/>
                <line x1=""94"" y1=""62"" x2=""106"" y2=""62"" stroke=""#E2E8F0"" stroke-width=""1.2""/>
                <line x1=""94"" y1=""72"" x2=""106"" y2=""72"" stroke=""#E2E8F0"" stroke-width=""1.2""/>
                <path d=""M 92 32 L 91 18 L 109 18 L 108 32 Z"" fill=""#78350F"" stroke=""#FEF08A"" stroke-width=""1""/>
                <circle cx=""88"" cy=""22"" r=""2.5"" fill=""#FEF08A""/>
                <circle cx=""88"" cy=""27"" r=""2.5"" fill=""#FEF08A""/>
                <circle cx=""112"" cy=""22"" r=""2.5"" fill=""#FEF08A""/>
                <circle cx=""112"" cy=""27"" r=""2.5"" fill=""#FEF08A""/>
                <line x1=""96"" y1=""20"" x2=""96"" y2=""146"" stroke=""#FFFFFF"" stroke-width=""0.8"" opacity=""0.9""/>
                <line x1=""98"" y1=""20"" x2=""98"" y2=""146"" stroke=""#FEF08A"" stroke-width=""0.8"" opacity=""0.9""/>
                <line x1=""100"" y1=""20"" x2=""100"" y2=""146"" stroke=""#FFFFFF"" stroke-width=""0.8"" opacity=""0.9""/>
                <line x1=""102"" y1=""20"" x2=""102"" y2=""146"" stroke=""#FEF08A"" stroke-width=""0.8"" opacity=""0.9""/>
                <line x1=""104"" y1=""20"" x2=""104"" y2=""146"" stroke=""#FFFFFF"" stroke-width=""0.8"" opacity=""0.9""/>
            </svg>"
            ),
            new LogoPreset(
                "clef_spectrum",
                "18. Klucz Wiolinowy & Korektor Audio",
                "Elegancki klucz wiolinowy zespolony z dynamicznym pasmem korektora fal dźwiękowych",
                "Muzyka & Dźwięk",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""clefGrad"" x1=""60"" y1=""30"" x2=""140"" y2=""170"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#38BDF8""/>
                        <stop offset=""50%"" stop-color=""#818CF8""/>
                        <stop offset=""100%"" stop-color=""#C084FC""/>
                    </linearGradient>
                    <linearGradient id=""barGrad"" x1=""0"" y1=""180"" x2=""0"" y2=""40"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#06B6D4"" stop-opacity=""0.3""/>
                        <stop offset=""50%"" stop-color=""#A855F7"" stop-opacity=""0.8""/>
                        <stop offset=""100%"" stop-color=""#F43F5E""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#0A0D18"" stroke=""#38BDF8"" stroke-width=""2"" stroke-opacity=""0.4""/>
                <rect x=""36"" y=""125"" width=""6"" height=""35"" rx=""3"" fill=""url(#barGrad)""/>
                <rect x=""46"" y=""105"" width=""6"" height=""55"" rx=""3"" fill=""url(#barGrad)""/>
                <rect x=""56"" y=""85"" width=""6"" height=""75"" rx=""3"" fill=""url(#barGrad)""/>
                <rect x=""66"" y=""70"" width=""6"" height=""90"" rx=""3"" fill=""url(#barGrad)""/>
                <rect x=""76"" y=""90"" width=""6"" height=""70"" rx=""3"" fill=""url(#barGrad)""/>
                <rect x=""86"" y=""60"" width=""6"" height=""100"" rx=""3"" fill=""url(#barGrad)""/>
                <rect x=""96"" y=""45"" width=""6"" height=""115"" rx=""3"" fill=""url(#barGrad)""/>
                <rect x=""106"" y=""65"" width=""6"" height=""95"" rx=""3"" fill=""url(#barGrad)""/>
                <rect x=""116"" y=""80"" width=""6"" height=""80"" rx=""3"" fill=""url(#barGrad)""/>
                <rect x=""126"" y=""60"" width=""6"" height=""100"" rx=""3"" fill=""url(#barGrad)""/>
                <rect x=""136"" y=""95"" width=""6"" height=""65"" rx=""3"" fill=""url(#barGrad)""/>
                <rect x=""146"" y=""115"" width=""6"" height=""45"" rx=""3"" fill=""url(#barGrad)""/>
                <rect x=""156"" y=""130"" width=""6"" height=""30"" rx=""3"" fill=""url(#barGrad)""/>
                <line x1=""30"" y1=""80"" x2=""170"" y2=""80"" stroke=""#FFFFFF"" stroke-opacity=""0.15"" stroke-width=""1""/>
                <line x1=""30"" y1=""95"" x2=""170"" y2=""95"" stroke=""#FFFFFF"" stroke-opacity=""0.15"" stroke-width=""1""/>
                <line x1=""30"" y1=""110"" x2=""170"" y2=""110"" stroke=""#FFFFFF"" stroke-opacity=""0.15"" stroke-width=""1""/>
                <line x1=""30"" y1=""125"" x2=""170"" y2=""125"" stroke=""#FFFFFF"" stroke-opacity=""0.15"" stroke-width=""1""/>
                <line x1=""30"" y1=""140"" x2=""170"" y2=""140"" stroke=""#FFFFFF"" stroke-opacity=""0.15"" stroke-width=""1""/>
                <path d=""M 104 165 C 96 165 92 158 95 152 C 98 146 106 148 106 154 C 106 158 102 161 98 161 C 99 140 100 80 100 42 C 100 30 112 28 112 38 C 112 55 86 85 86 112 C 86 132 118 135 118 116 C 118 98 100 98 100 110 C 100 120 110 120 110 114"" stroke=""#FFFFFF"" stroke-width=""5"" stroke-linecap=""round"" stroke-linejoin=""round"" fill=""none""/>
                <path d=""M 104 165 C 96 165 92 158 95 152 C 98 146 106 148 106 154 C 106 158 102 161 98 161 C 99 140 100 80 100 42 C 100 30 112 28 112 38 C 112 55 86 85 86 112 C 86 132 118 135 118 116 C 118 98 100 98 100 110 C 100 120 110 120 110 114"" stroke=""url(#clefGrad)"" stroke-width=""3"" stroke-linecap=""round"" stroke-linejoin=""round"" fill=""none""/>
                <circle cx=""95"" cy=""155"" r=""4"" fill=""#FFFFFF""/>
            </svg>"
            ),
            new LogoPreset(
                "symphony_staff",
                "19. Symfonia & Pięciolinia",
                "Falująca pięciolinia w przestrzeni 3D z rozświetlonymi ósemkami i nutami pieśni",
                "Muzyka & Kompozycja",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""noteGrad"" x1=""60"" y1=""60"" x2=""140"" y2=""140"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#FDE047""/>
                        <stop offset=""100%"" stop-color=""#EA580C""/>
                    </linearGradient>
                    <linearGradient id=""staveGrad"" x1=""20"" y1=""100"" x2=""180"" y2=""100"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#38BDF8"" stop-opacity=""0.2""/>
                        <stop offset=""50%"" stop-color=""#60A5FA"" stop-opacity=""0.9""/>
                        <stop offset=""100%"" stop-color=""#A855F7"" stop-opacity=""0.2""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#081026"" stroke=""#60A5FA"" stroke-width=""2"" stroke-opacity=""0.4""/>
                <path d=""M 25 125 C 60 90, 100 150, 140 115 C 155 102, 168 105, 175 110"" stroke=""url(#staveGrad)"" stroke-width=""2.5"" fill=""none"" stroke-linecap=""round""/>
                <path d=""M 25 115 C 60 80, 100 140, 140 105 C 155 92, 168 95, 175 100"" stroke=""url(#staveGrad)"" stroke-width=""2.5"" fill=""none"" stroke-linecap=""round""/>
                <path d=""M 25 105 C 60 70, 100 130, 140 95 C 155 82, 168 85, 175 90"" stroke=""url(#staveGrad)"" stroke-width=""2.5"" fill=""none"" stroke-linecap=""round""/>
                <path d=""M 25 95 C 60 60, 100 120, 140 85 C 155 72, 168 75, 175 80"" stroke=""url(#staveGrad)"" stroke-width=""2.5"" fill=""none"" stroke-linecap=""round""/>
                <path d=""M 25 85 C 60 50, 100 110, 140 75 C 155 62, 168 65, 175 70"" stroke=""url(#staveGrad)"" stroke-width=""2.5"" fill=""none"" stroke-linecap=""round""/>
                <ellipse cx=""80"" cy=""120"" rx=""12"" ry=""8"" transform=""rotate(-25 80 120)"" fill=""url(#noteGrad)""/>
                <ellipse cx=""130"" cy=""98"" rx=""12"" ry=""8"" transform=""rotate(-25 130 98)"" fill=""url(#noteGrad)""/>
                <line x1=""89"" y1=""116"" x2=""89"" y2=""52"" stroke=""#FFFFFF"" stroke-width=""3.5"" stroke-linecap=""round""/>
                <line x1=""139"" y1=""94"" x2=""139"" y2=""30"" stroke=""#FFFFFF"" stroke-width=""3.5"" stroke-linecap=""round""/>
                <polygon points=""87,55 141,33 141,41 87,63"" fill=""#FFFFFF""/>
                <circle cx=""82"" cy=""118"" r=""3"" fill=""#FFFFFF""/>
                <circle cx=""132"" cy=""96"" r=""3"" fill=""#FFFFFF""/>
                <ellipse cx=""50"" cy=""80"" rx=""8"" ry=""5.5"" transform=""rotate(-25 50 80)"" fill=""#38BDF8"" opacity=""0.75""/>
                <line x1=""56"" y1=""78"" x2=""56"" y2=""44"" stroke=""#38BDF8"" stroke-width=""2"" opacity=""0.75""/>
            </svg>"
            ),
            new LogoPreset(
                "davids_lyre",
                "20. Lira Dawidowa & Fale Akustyczne",
                "Klasyczna złota harfa/lira z 7 strunami i rozchodzącymi się falami rezonansu",
                "Muzyka Dawna & Harfa",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""goldLyre"" x1=""50"" y1=""30"" x2=""150"" y2=""170"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#FDE047""/>
                        <stop offset=""40%"" stop-color=""#F59E0B""/>
                        <stop offset=""80%"" stop-color=""#B45309""/>
                        <stop offset=""100%"" stop-color=""#78350F""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#0E1424"" stroke=""#F59E0B"" stroke-width=""2"" stroke-opacity=""0.4""/>
                <circle cx=""100"" cy=""140"" r=""45"" stroke=""#F59E0B"" stroke-width=""1"" stroke-dasharray=""3 3"" opacity=""0.25""/>
                <circle cx=""100"" cy=""140"" r=""60"" stroke=""#38BDF8"" stroke-width=""1"" stroke-dasharray=""4 4"" opacity=""0.2""/>
                <circle cx=""100"" cy=""140"" r=""75"" stroke=""#F59E0B"" stroke-width=""1"" stroke-dasharray=""5 5"" opacity=""0.15""/>
                <path d=""M 68 135 C 68 165, 132 165, 132 135 Z"" fill=""url(#goldLyre)"" stroke=""#FEF08A"" stroke-width=""2""/>
                <path d=""M 72 140 C 50 115, 45 65, 62 38 C 66 32, 74 36, 72 44 C 60 70, 64 110, 80 135 Z"" fill=""url(#goldLyre)"" stroke=""#FEF08A"" stroke-width=""1.5""/>
                <path d=""M 128 140 C 150 115, 155 65, 138 38 C 134 32, 126 36, 128 44 C 140 70, 136 110, 120 135 Z"" fill=""url(#goldLyre)"" stroke=""#FEF08A"" stroke-width=""1.5""/>
                <path d=""M 58 46 C 58 42, 142 42, 142 46 C 142 50, 58 50, 58 46 Z"" fill=""url(#goldLyre)"" stroke=""#FEF08A"" stroke-width=""1.5""/>
                <line x1=""79"" y1=""48"" x2=""79"" y2=""138"" stroke=""#FFFFFF"" stroke-width=""1"" opacity=""0.85""/>
                <line x1=""86"" y1=""48"" x2=""86"" y2=""142"" stroke=""#FEF08A"" stroke-width=""1.2"" opacity=""0.95""/>
                <line x1=""93"" y1=""48"" x2=""93"" y2=""145"" stroke=""#FFFFFF"" stroke-width=""1.2"" opacity=""0.95""/>
                <line x1=""100"" y1=""48"" x2=""100"" y2=""147"" stroke=""#FEF08A"" stroke-width=""1.5"" opacity=""1""/>
                <line x1=""107"" y1=""48"" x2=""107"" y2=""145"" stroke=""#FFFFFF"" stroke-width=""1.2"" opacity=""0.95""/>
                <line x1=""114"" y1=""48"" x2=""114"" y2=""142"" stroke=""#FEF08A"" stroke-width=""1.2"" opacity=""0.95""/>
                <line x1=""121"" y1=""48"" x2=""121"" y2=""138"" stroke=""#FFFFFF"" stroke-width=""1"" opacity=""0.85""/>
                <circle cx=""100"" cy=""146"" r=""6"" fill=""#0E1424"" stroke=""#FEF08A"" stroke-width=""1.5""/>
                <circle cx=""100"" cy=""146"" r=""2"" fill=""#FEF08A""/>
            </svg>"
            ),
            new LogoPreset(
                "vocal_harmony",
                "21. Wokal & Fale Harmoniczne",
                "Fale głosu ludzkiego, wielogłosowość i chór uwielbienia unoszący się ku niebu",
                "Muzyka & Wokal",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <defs>
                    <linearGradient id=""wave1"" x1=""20"" y1=""0"" x2=""180"" y2=""0"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#EC4899""/>
                        <stop offset=""100%"" stop-color=""#F59E0B""/>
                    </linearGradient>
                    <linearGradient id=""wave2"" x1=""20"" y1=""0"" x2=""180"" y2=""0"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#06B6D4""/>
                        <stop offset=""100%"" stop-color=""#3B82F6""/>
                    </linearGradient>
                    <linearGradient id=""wave3"" x1=""20"" y1=""0"" x2=""180"" y2=""0"" gradientUnits=""userSpaceOnUse"">
                        <stop offset=""0%"" stop-color=""#8B5CF6""/>
                        <stop offset=""100%"" stop-color=""#10B981""/>
                    </linearGradient>
                </defs>
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#0B0F20"" stroke=""#8B5CF6"" stroke-width=""2"" stroke-opacity=""0.4""/>
                <path d=""M 28 85 C 55 45, 80 135, 100 85 C 120 35, 145 125, 172 85"" stroke=""url(#wave1)"" stroke-width=""4.5"" stroke-linecap=""round"" fill=""none""/>
                <path d=""M 28 100 C 55 140, 80 60, 100 100 C 120 140, 145 60, 172 100"" stroke=""url(#wave2)"" stroke-width=""4.5"" stroke-linecap=""round"" fill=""none""/>
                <path d=""M 28 115 C 55 80, 80 150, 100 115 C 120 80, 145 150, 172 115"" stroke=""url(#wave3)"" stroke-width=""3"" stroke-linecap=""round"" fill=""none"" opacity=""0.75""/>
                <rect x=""91"" y=""42"" width=""18"" height=""34"" rx=""9"" fill=""#1E293B"" stroke=""#FFFFFF"" stroke-width=""2""/>
                <line x1=""91"" y1=""52"" x2=""109"" y2=""52"" stroke=""#94A3B8"" stroke-width=""1""/>
                <line x1=""91"" y1=""60"" x2=""109"" y2=""60"" stroke=""#94A3B8"" stroke-width=""1""/>
                <path d=""M 85 58 C 85 78, 115 78, 115 58"" stroke=""#FFFFFF"" stroke-width=""2.5"" fill=""none""/>
                <line x1=""100"" y1=""78"" x2=""100"" y2=""92"" stroke=""#FFFFFF"" stroke-width=""2.5""/>
                <circle cx=""100"" cy=""58"" r=""32"" stroke=""#FDE047"" stroke-width=""1.5"" stroke-dasharray=""3 3"" opacity=""0.6""/>
                <circle cx=""48"" cy=""55"" r=""4"" fill=""#F43F5E""/>
                <line x1=""52"" y1=""55"" x2=""52"" y2=""40"" stroke=""#F43F5E"" stroke-width=""1.5""/>
                <circle cx=""154"" cy=""50"" r=""4"" fill=""#38BDF8""/>
                <line x1=""158"" y1=""50"" x2=""158"" y2=""35"" stroke=""#38BDF8"" stroke-width=""1.5""/>
            </svg>"
            ),
            new LogoPreset(
                "equipes_notre_dame",
                "22. Oficjalne Logo Equipes Notre-Dame",
                "Oryginalny oficjalny znak ruchu END (pobrany z end.org.pl): Ryba i obrączki przymierza",
                "Ruchy & Wspólnoty",
                @"<svg viewBox=""0 0 200 200"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"" xmlns:xlink=""http://www.w3.org/1999/xlink"">
                <rect x=""15"" y=""15"" width=""170"" height=""170"" rx=""44"" fill=""#0D111D"" stroke=""#3B82F6"" stroke-width=""2"" stroke-opacity=""0.4""/>
                <image href=""data:image/png;base64,\(ENDLogoAsset.base64PNG)"" x=""24"" y=""45"" width=""152"" height=""110"" preserveAspectRatio=""xMidYMid meet""/>
            </svg>"
            ),
            new LogoPreset(
                "equipes_notre_dame_transparent",
                "23. Oficjalne Logo Equipes Notre-Dame (Transparentne)",
                "Czysty pobrany oficjalny znak END z przezroczystym tłem na rzutnik lub standby",
                "Ruchy & Wspólnoty",
                @"<svg viewBox=""0 0 864 508"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"" xmlns:xlink=""http://www.w3.org/1999/xlink"">
                <image href=""data:image/png;base64,\(ENDLogoAsset.base64PNG)"" x=""0"" y=""0"" width=""864"" height=""508""/>
            </svg>"
            ),
        };

        public static LogoPreset GetById(string id)
        {
            return All.FirstOrDefault(l => l.Id == id) ?? All[0];
        }
    }
}
