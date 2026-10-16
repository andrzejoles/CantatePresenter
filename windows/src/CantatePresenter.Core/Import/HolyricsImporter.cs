using System.IO.Compression;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Xml;
using CantatePresenter.Core.Models;

namespace CantatePresenter.Core.Import;

public sealed class HolyricsException(string message) : Exception(message);

/// <summary>Rekord Music z eksportu Holyrics (pola jak w HolyricsJavaDeserializer.RawMusicRecord).</summary>
public sealed class RawMusicRecord
{
    public string Title = "", Author = "", Artist = "", Lyrics = "", Key = "", Note = "", Formatting = "", Language = "";
}

/// <summary>
/// Strumień Java ObjectStream (.mufl / .muf, AC ED 00 05): odpowiednik HolyricsJavaDeserializer z macOS.
/// Każdy odczyt sprawdza granice, a zagnieżdżenie jest ograniczone (W6), więc uszkodzony plik daje błąd, nie awarię.
/// </summary>
public sealed class HolyricsJavaDeserializer
{
    private const byte TcNull = 0x70, TcReference = 0x71, TcClassDesc = 0x72, TcObject = 0x73, TcString = 0x74, TcArray = 0x75,
        TcBlockData = 0x77, TcEndBlockData = 0x78, TcReset = 0x79, TcBlockDataLong = 0x7A, TcLongString = 0x7C;
    private const uint BaseWireHandle = 0x7E0000;
    private const int MaxDepth = 32;

    private sealed record ClassDescriptor(string Name, byte Flags, List<(string Name, char Type)> Fields, object? SuperClass);

    private readonly byte[] bytes;
    private int pos;
    private int depth;
    private List<object?> handles = [];
    private static readonly UTF8Encoding Utf8 = new(false, false);

    private HolyricsJavaDeserializer(byte[] bytes) => this.bytes = bytes;

    public static bool IsJavaSerializedStream(byte[] bytes) =>
        bytes.Length >= 4 && bytes[0] == 0xAC && bytes[1] == 0xED && bytes[2] == 0x00 && bytes[3] == 0x05;

    private int Remaining => bytes.Length - pos;

    private void Require(long count)
    {
        if (count < 0 || count > Remaining) throw new HolyricsException($"Przedwczesny koniec danych na pozycji {pos}");
    }

    private byte U8() { Require(1); return bytes[pos++]; }
    private int U16() { Require(2); var v = (bytes[pos] << 8) | bytes[pos + 1]; pos += 2; return v; }
    private uint U32() { Require(4); var v = (uint)(bytes[pos] << 24 | bytes[pos + 1] << 16 | bytes[pos + 2] << 8 | bytes[pos + 3]); pos += 4; return v; }
    private long I64() { Require(8); long v = 0; for (var i = 0; i < 8; i++) v = (v << 8) | bytes[pos + i]; pos += 8; return v; }
    private void Skip(long count) { Require(count); pos += (int)count; }
    private string Text(int length) { Require(length); var s = Utf8.GetString(bytes, pos, length); pos += length; return s; }
    private string Utf() => Text(U16());

    private string LongUtf()
    {
        var length = I64();
        if (length < 0 || length > Remaining) throw new HolyricsException($"Nieprawidłowa długość {length} na pozycji {pos}");
        return Text((int)length);
    }

    private int Assign(object? value) { handles.Add(value); return handles.Count - 1; }
    private void Set(int index, object? value) { if (index < handles.Count) handles[index] = value; }

    private List<object> BlockContents(bool collect)
    {
        var elements = new List<object>();
        while (true)
        {
            Require(1);
            switch (bytes[pos])
            {
                case TcEndBlockData: pos++; return elements;
                case TcBlockData: pos++; Skip(U8()); break;
                case TcBlockDataLong: pos++; Skip(U32()); break;
                default:
                    var element = Content();
                    if (collect && element is not null) elements.Add(element);
                    break;
            }
        }
    }

    private object? Content()
    {
        if (depth >= MaxDepth) throw new HolyricsException($"Zbyt głębokie zagnieżdżenie danych na pozycji {pos}");
        depth++;
        try { return ReadTagged(); }
        finally { depth--; }
    }

    private object? ReadTagged()
    {
        var tc = U8();
        switch (tc)
        {
            case TcNull: return null;
            case TcReference:
            {
                var reference = U32();
                if (reference < BaseWireHandle || reference - BaseWireHandle >= handles.Count) throw new HolyricsException($"Nieprawidłowy uchwyt referencji {reference}");
                return handles[(int)(reference - BaseWireHandle)];
            }
            case TcString: { var h = Assign(null); var s = Utf(); Set(h, s); return s; }
            case TcLongString: { var h = Assign(null); var s = LongUtf(); Set(h, s); return s; }
            case TcClassDesc:
            {
                var h = Assign(null);
                var name = Utf();
                I64();
                var flags = U8();
                var count = U16();
                if (count * 3 > Remaining) throw new HolyricsException($"Nieprawidłowa długość {count} na pozycji {pos}");
                var fields = new List<(string, char)>();
                for (var i = 0; i < count; i++)
                {
                    var type = (char)U8();
                    var fieldName = Utf();
                    if (type is '[' or 'L') Content();
                    fields.Add((fieldName, type));
                }
                while (true)
                {
                    Require(1);
                    if (bytes[pos] == TcEndBlockData) { pos++; break; }
                    if (bytes[pos] == TcBlockData) { pos++; Skip(U8()); } else pos++;
                }
                var descriptor = new ClassDescriptor(name, flags, fields, Content());
                Set(h, descriptor);
                return descriptor;
            }
            case TcObject: return ReadObject(tc);
            case TcArray:
            {
                Content();
                var h = Assign(null);
                var length = U32();
                if (length > Remaining) throw new HolyricsException($"Nieprawidłowa długość {length} na pozycji {pos}");
                var array = new List<object?>();
                Set(h, array);
                for (var i = 0; i < length; i++) array.Add(Content());
                return array;
            }
            case TcBlockData: Skip(U8()); return null;
            case TcBlockDataLong: Skip(U32()); return null;
            case TcEndBlockData: return null;
            case TcReset: handles = []; return null;
            default: throw new HolyricsException($"Nieoczekiwany znacznik 0x{tc:X2} na pozycji {pos - 1}");
        }
    }

    private object ReadObject(byte tc)
    {
        if (Content() is not ClassDescriptor descriptor) throw new HolyricsException($"Nieoczekiwany znacznik 0x{tc:X2} na pozycji {pos}");
        var h = Assign(null);
        var obj = new Dictionary<string, object?> { ["_class"] = descriptor.Name };
        Set(h, obj);
        var hierarchy = new List<ClassDescriptor>();
        object? current = descriptor;
        while (current is ClassDescriptor c && hierarchy.Count < MaxDepth) { hierarchy.Add(c); current = c.SuperClass; }
        hierarchy.Reverse();
        var record = descriptor.Name.Contains("Music") ? new RawMusicRecord() : null;

        foreach (var cls in hierarchy)
        {
            foreach (var (name, type) in cls.Fields)
            {
                switch (type)
                {
                    case 'Z': obj[name] = U8() != 0; break;
                    case 'B': obj[name] = U8(); break;
                    case 'C': obj[name] = U16(); break;
                    case 'S': obj[name] = (short)U16(); break;
                    case 'I': obj[name] = (int)U32(); break;
                    case 'J': obj[name] = I64(); break;
                    case 'F': Skip(4); break;
                    case 'D': Skip(8); break;
                }
            }
            foreach (var (name, type) in cls.Fields)
            {
                if (type is not ('[' or 'L')) continue;
                var value = Content();
                if (value is string text)
                {
                    obj[name] = text;
                    if (record is not null)
                    {
                        switch (name)
                        {
                            case "title": record.Title = text; break;
                            case "author": record.Author = text; break;
                            case "artist": record.Artist = text; break;
                            case "lyrics": record.Lyrics = text; break;
                            case "formatting": record.Formatting = text; break;
                            case "note": record.Note = text; break;
                            case "language": record.Language = text; break;
                            // Tonacja, jeśli eksport ją zawiera (N5).
                            case "key" or "tone" or "tom": record.Key = text; break;
                        }
                    }
                }
                else if (value is not null)
                {
                    obj[name] = value;
                }
            }
            if ((cls.Flags & 0x01) != 0)
            {
                if (cls.Name == "java.util.ArrayList")
                {
                    var elements = BlockContents(collect: true);
                    obj["_elements"] = elements;
                    Set(h, obj);
                    return elements;
                }
                BlockContents(collect: false);
            }
        }
        if (record is not null) { Set(h, record); return record; }
        Set(h, obj);
        return obj;
    }

    /// <summary>Rekordy Music ze strumienia Java; uszkodzony plik daje <see cref="HolyricsException"/>.</summary>
    public static List<RawMusicRecord> DeserializeMusicRecords(byte[] bytes)
    {
        if (bytes.Length < 4) throw new HolyricsException("Błąd nagłówka: Plik jest za krótki");
        if (!IsJavaSerializedStream(bytes)) throw new HolyricsException("Błąd nagłówka: Nieprawidłowy nagłówek Java ObjectStream (oczekiwano AC ED 00 05)");
        var stream = new HolyricsJavaDeserializer(bytes) { pos = 4 };
        var records = new List<RawMusicRecord>();
        while (stream.pos < bytes.Length)
        {
            switch (stream.Content())
            {
                case null: break;
                case List<object> list when list.All(e => e is RawMusicRecord): records.AddRange(list.Cast<RawMusicRecord>()); break;
                case List<object?> array when array.All(e => e is RawMusicRecord): records.AddRange(array.Cast<RawMusicRecord>()); break;
                case RawMusicRecord record: records.Add(record); break;
                case Dictionary<string, object?> dict:
                    if (dict.GetValueOrDefault("_elements") is List<object> elements && elements.All(e => e is RawMusicRecord)) records.AddRange(elements.Cast<RawMusicRecord>());
                    else if (dict.GetValueOrDefault("title") is string title)
                    {
                        string S(string key) => dict.GetValueOrDefault(key) as string ?? "";
                        records.Add(new RawMusicRecord { Title = title, Author = S("author"), Artist = S("artist"), Lyrics = S("lyrics"), Formatting = S("formatting"), Note = S("note"), Language = S("language") });
                    }
                    break;
            }
        }
        return records;
    }
}

/// <summary>Import bibliotek Holyrics: odpowiednik HolyricsImporter z macOS (JSON, XML, tekst ze znacznikami, archiwa).</summary>
public static partial class HolyricsImporter
{
    public static readonly IReadOnlySet<string> Extensions = new HashSet<string> { "muf", "mufl", "hly", "holyrics", "zip" };

    private static readonly (Regex Pattern, string Replacement)[] Markers =
    [
        (new Regex(@"##\(Verse\s*(\d+)\)", RegexOptions.IgnoreCase), "[Zwrotka $1]"),
        (new Regex(@"##\(Verse\)", RegexOptions.IgnoreCase), "[Zwrotka]"),
        (new Regex(@"##\(Chorus\s*(\d*)\)", RegexOptions.IgnoreCase), "[Refren]"),
        (new Regex(@"##\(Bridge\s*(\d*)\)", RegexOptions.IgnoreCase), "[Bridge]"),
        (new Regex(@"##\(Coda\s*(\d*)\)", RegexOptions.IgnoreCase), "[Coda]"),
        (new Regex(@"##\(Intro\s*(\d*)\)", RegexOptions.IgnoreCase), "[Wstęp]"),
        (new Regex(@"##\((Outro|Ending)\s*(\d*)\)", RegexOptions.IgnoreCase), "[Zakończenie]"),
        (new Regex(@"##\(Pre-Chorus\s*(\d*)\)", RegexOptions.IgnoreCase), "[Przed-refren]"),
        (new Regex(@"##\((Tag|Interlude)\s*(\d*)\)", RegexOptions.IgnoreCase), "[Przejście]"),
        (new Regex(@"##\(([^)]+)\)", RegexOptions.IgnoreCase), "[$1]"),
    ];

    public static string TranslateVerseMarkers(string text)
    {
        var result = text.Replace("\r\n", "\n").Replace("\r", "\n");
        foreach (var (pattern, replacement) in Markers) result = pattern.Replace(result, replacement);
        return result;
    }

    private static string TrimAll(string s) => s.Trim();
    private static string TrimSpaces(string s) => Text.LyricsParser.TrimSpaces(s);

    public static ImportedSong FromRecord(RawMusicRecord record)
    {
        var title = TrimAll(record.Title);
        var author = TrimAll(record.Author);
        var tags = new List<string> { "Import Holyrics" };
        if (record.Note.Length > 0) tags.Add(TrimAll(record.Note));
        return new ImportedSong(title.Length > 0 ? title : "Pieśń Holyrics", author.Length > 0 ? author : TrimAll(record.Artist), record.Key, tags, TranslateVerseMarkers(record.Lyrics));
    }

    private static string ValueAfterColon(string line) => line.Contains(':') ? TrimAll(line[(line.IndexOf(':') + 1)..]) : "";

    public static ImportedSong ParseSingleSong(string text, string fallbackTitle)
    {
        var lines = text.Replace("\r\n", "\n").Replace("\r", "\n").Split(['\n', '\u000B', '\u000C', '\u0085', '\u2028', '\u2029']);
        string title = "", author = "", key = "";
        var tags = new List<string> { "Import Holyrics" };
        var lyrics = new List<string>();
        var inLyrics = false;
        static bool Starts(string lower, params string[] prefixes) => prefixes.Any(lower.StartsWith);
        foreach (var rawLine in lines)
        {
            var line = TrimSpaces(rawLine);
            if (line.Length == 0) { if (inLyrics) lyrics.Add(""); continue; }
            var lower = line.ToLowerInvariant();
            if (Starts(lower, "@title:", "@nome:", "@titulo:", "title:", "título:", "nome:")) title = ValueAfterColon(line);
            else if (Starts(lower, "@author:", "@autor:", "@artist:", "@artista:", "author:", "autor:", "artist:")) author = ValueAfterColon(line);
            else if (Starts(lower, "@key:", "@tom:", "key:", "tom:")) key = ValueAfterColon(line);
            else if (Starts(lower, "@tags:", "@tag:", "tags:")) tags.AddRange(ValueAfterColon(line).Split(',').Select(TrimSpaces).Where(t => t.Length > 0));
            else if (Starts(lower, "@ccli:", "@copyright:", "@order:", "@ordem:")) continue;
            else { inLyrics = true; lyrics.Add(rawLine); }
        }
        return new ImportedSong(title.Length > 0 ? title : fallbackTitle, author, key, tags, TranslateVerseMarkers(TrimAll(string.Join("\n", lyrics))));
    }

    private static List<string> SplitMultiSong(string text)
    {
        foreach (var delimiter in new[] { "\n===\n", "\n===\r\n", "\n---song---\n", "\n[SONG]\n", "\n[MUSIC]\n", "\n{SONG}\n" })
        {
            if (text.Contains(delimiter)) return text.Split(delimiter).Select(TrimAll).Where(b => b.Length > 0).ToList();
        }
        return [text];
    }

    private static List<ImportedSong>? ParseJson(string text)
    {
        JsonNode? data;
        try { data = JsonNode.Parse(text); } catch (System.Text.Json.JsonException) { return null; }
        static bool IsDicts(JsonNode? v) => v is JsonArray a && a.All(x => x is JsonObject);
        List<JsonObject> dicts = [];
        if (IsDicts(data)) dicts = ((JsonArray)data!).Cast<JsonObject>().ToList();
        else if (data is JsonObject obj)
        {
            var list = IsDicts(obj["songs"]) ? obj["songs"] : IsDicts(obj["musics"]) ? obj["musics"] : IsDicts(obj["items"]) ? obj["items"] : null;
            dicts = list is JsonArray array ? array.Cast<JsonObject>().ToList() : [obj];
        }
        if (dicts.Count == 0) return null;
        static string Str(params JsonNode?[] values) => values.Select(Json.OptStr).FirstOrDefault(v => v is not null) ?? "";
        var songs = new List<ImportedSong>();
        foreach (var d in dicts)
        {
            var title = Str(d["title"], d["name"], d["nome"], d["titulo"]);
            var lyrics = Str(d["lyrics"], d["letra"], d["text"]);
            if (lyrics.Length == 0 && d["slides"] is JsonArray slides && slides.All(s => Json.OptStr(s) is not null)) lyrics = string.Join("\n\n", slides.Select(s => Json.OptStr(s)));
            else if (lyrics.Length == 0 && IsDicts(d["paragraphs"])) lyrics = string.Join("\n\n", ((JsonArray)d["paragraphs"]!).Select(p => Json.OptStr(p?["text"])).OfType<string>());
            if (title.Length > 0 || lyrics.Length > 0)
            {
                songs.Add(new ImportedSong(title.Length > 0 ? title : "Bez tytułu", Str(d["author"], d["artist"], d["artista"], d["autor"]), Str(d["key"], d["tone"], d["tom"]),
                    ["Import Holyrics JSON"], TranslateVerseMarkers(lyrics)));
            }
        }
        return songs.Count > 0 ? songs : null;
    }

    private static readonly HashSet<string> SongElements = ["song", "music", "musica"];
    private static readonly Dictionary<string, string> FieldAliases = new()
    {
        ["title"] = "title", ["nome"] = "title", ["titulo"] = "title", ["author"] = "author", ["artist"] = "author", ["autor"] = "author",
        ["artista"] = "author", ["key"] = "key", ["tom"] = "key", ["tone"] = "key", ["lyrics"] = "lyrics", ["letra"] = "lyrics",
    };

    /// <summary>XML Holyrics / OpenSong (jak HolyricsXMLReader: pierwsze niepuste pole wygrywa), bez DTD.</summary>
    private static List<ImportedSong> ParseXml(string xml, string fallbackTitle)
    {
        var document = new XmlDocument { XmlResolver = null };
        try
        {
            using var reader = XmlReader.Create(new StringReader(xml), new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null });
            document.Load(reader);
        }
        catch (XmlException)
        {
            return [];
        }
        var records = new List<Dictionary<string, string>>();
        var documentFields = new Dictionary<string, string>();
        void Walk(XmlElement element, Dictionary<string, string>? current)
        {
            var name = element.LocalName.ToLowerInvariant();
            if (SongElements.Contains(name))
            {
                var record = new Dictionary<string, string>();
                foreach (var child in element.ChildNodes.OfType<XmlElement>()) Walk(child, record);
                records.Add(record);
                return;
            }
            if (FieldAliases.TryGetValue(name, out var alias))
            {
                var target = current ?? documentFields;
                if (string.IsNullOrEmpty(target.GetValueOrDefault(alias))) target[alias] = TrimAll(element.InnerText);
            }
            foreach (var child in element.ChildNodes.OfType<XmlElement>()) Walk(child, current);
        }
        if (document.DocumentElement is XmlElement root) Walk(root, null);
        var list = records.Count > 0 ? records : documentFields.Count > 0 ? [documentFields] : [];
        return list.Where(f => f.GetValueOrDefault("title", "").Length > 0 || f.GetValueOrDefault("lyrics", "").Length > 0).Select(f =>
        {
            var title = f.GetValueOrDefault("title", "");
            return new ImportedSong(title.Length > 0 ? title : fallbackTitle, f.GetValueOrDefault("author", ""), f.GetValueOrDefault("key", ""),
                ["Import Holyrics XML"], TranslateVerseMarkers(f.GetValueOrDefault("lyrics", "")));
        }).ToList();
    }

    /// <summary>Tekst eksportu Holyrics: JSON, XML, kilka pieśni z separatorami albo jedna.</summary>
    public static List<ImportedSong> ParseText(string raw, string fallbackTitle = "Pieśń Holyrics")
    {
        var text = TrimAll(raw);
        if (text.Length == 0) return [];
        if ((text.StartsWith('{') || text.StartsWith('[')) && ParseJson(text) is { } json) return json;
        if (text.StartsWith('<') && ParseXml(text, fallbackTitle) is { Count: > 0 } xml) return xml;
        var blocks = SplitMultiSong(text);
        if (blocks.Count > 1)
        {
            var songs = blocks.Select(b => ParseSingleSong(b, fallbackTitle)).Where(s => s.Title.Length > 0 && s.RawLyrics.Length > 0).ToList();
            if (songs.Count > 0) return songs;
        }
        return [ParseSingleSong(text, fallbackTitle)];
    }

    /// <summary>Pieśni z pliku Holyrics (bez deduplikacji): archiwum, strumień Java albo tekst.</summary>
    public static List<ImportedSong> ReadFile(byte[] bytes, string fileName)
    {
        var extension = Path.GetExtension(fileName).TrimStart('.').ToLowerInvariant();
        if (extension is "zip" or "hly" or "holyrics")
        {
            try
            {
                using var zip = new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read);
                var songs = new List<ImportedSong>();
                foreach (var entry in zip.Entries)
                {
                    var inner = Path.GetExtension(entry.Name).TrimStart('.').ToLowerInvariant();
                    if (inner is not ("muf" or "mufl" or "txt" or "json" or "xml")) continue;
                    using var stream = entry.Open();
                    using var copy = new MemoryStream();
                    stream.CopyTo(copy);
                    songs.AddRange(ReadFile(copy.ToArray(), entry.Name));
                }
                if (songs.Count > 0) return songs;
            }
            catch (InvalidDataException)
            {
                // Nie ZIP: dalej jak zwykły plik.
            }
        }
        if (HolyricsJavaDeserializer.IsJavaSerializedStream(bytes))
        {
            try
            {
                var records = HolyricsJavaDeserializer.DeserializeMusicRecords(bytes);
                if (records.Count > 0) return records.Select(FromRecord).ToList();
            }
            catch (HolyricsException)
            {
                // Uszkodzony strumień: tak jak w macOS próba odczytu jako tekst.
            }
        }
        return ParseText(TextImport.Decode(bytes), Path.GetFileNameWithoutExtension(fileName));
    }
}
