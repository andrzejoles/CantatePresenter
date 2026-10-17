using System.Text;

namespace CantatePresenter.Core.Remote;

/// <summary>
/// Koder kodów QR (tryb bajtowy, poziom korekcji M, wersje 1–10) bez zależności, 1:1 z web/src/core/qr.js
/// (ISO/IEC 18004, układ jak w referencyjnej implementacji Nayuki). Wynik sprawdza shared/fixtures/qr.json.
/// </summary>
public static class QrCode
{
    /// <summary>[łączna liczba słów kodowych, słowa korekcji na blok, liczba bloków] dla poziomu M.</summary>
    private static readonly int[][] VersionsM = [[], [26, 10, 1], [44, 16, 1], [70, 26, 1], [100, 18, 2], [134, 24, 2], [172, 16, 4],
        [196, 18, 4], [242, 22, 4], [292, 22, 5], [346, 26, 5]];
    private static readonly int[][] Alignment = [[], [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]];
    /// <summary>Bity reszty na końcu danych.</summary>
    private static readonly int[] Remainder = [0, 0, 7, 7, 7, 7, 7, 0, 0, 0, 0];

    // MARK: - Reed–Solomon w GF(256), wielomian 0x11D

    private static int Multiply(int x, int y)
    {
        var z = 0;
        for (var i = 7; i >= 0; i--)
        {
            z = (z << 1) ^ ((z >> 7) * 0x11d);
            z ^= ((y >> i) & 1) * x;
        }
        return z & 0xff;
    }

    private static int[] Divisor(int degree)
    {
        var result = new int[degree];
        result[degree - 1] = 1;
        var root = 1;
        for (var i = 0; i < degree; i++)
        {
            for (var j = 0; j < result.Length; j++)
            {
                result[j] = Multiply(result[j], root);
                if (j + 1 < result.Length) result[j] ^= result[j + 1];
            }
            root = Multiply(root, 0x02);
        }
        return result;
    }

    private static List<int> RemainderOf(List<int> data, int[] divisor)
    {
        var result = new List<int>(new int[divisor.Length]);
        foreach (var b in data)
        {
            var factor = b ^ result[0];
            result.RemoveAt(0);
            result.Add(0);
            for (var i = 0; i < divisor.Length; i++) result[i] ^= Multiply(divisor[i], factor);
        }
        return result;
    }

    // MARK: - Kodowanie

    /// <summary>Macierz modułów [y, x] (true = ciemny) dla tekstu.</summary>
    public static bool[,] Encode(string text)
    {
        var bytes = Encoding.UTF8.GetBytes(text);
        var version = 1;
        for (; version <= 10; version++)
        {
            var (t, e, b) = (VersionsM[version][0], VersionsM[version][1], VersionsM[version][2]);
            if (4 + (version < 10 ? 8 : 16) + bytes.Length * 8 <= (t - e * b) * 8) break;
        }
        if (version > 10) throw new ArgumentException("text too long for QR", nameof(text));
        var (total, ecPerBlock, numBlocks) = (VersionsM[version][0], VersionsM[version][1], VersionsM[version][2]);
        var dataCapacity = total - ecPerBlock * numBlocks;

        // Bity: tryb bajtowy, długość, dane, terminator, dopełnienie.
        var bits = new List<int>();
        void Push(int value, int length)
        {
            for (var i = length - 1; i >= 0; i--) bits.Add((value >> i) & 1);
        }
        Push(0b0100, 4);
        Push(bytes.Length, version < 10 ? 8 : 16);
        foreach (var b in bytes) Push(b, 8);
        Push(0, Math.Min(4, dataCapacity * 8 - bits.Count));
        Push(0, (8 - bits.Count % 8) % 8);
        for (var pad = 0xec; bits.Count < dataCapacity * 8; pad ^= 0xec ^ 0x11) Push(pad, 8);
        var data = new List<int>();
        for (var i = 0; i < bits.Count; i += 8) data.Add(bits.Skip(i).Take(8).Aggregate(0, (a, bit) => (a << 1) | bit));

        // Bloki, korekcja błędów i przeplot.
        var shortBlocks = numBlocks - total % numBlocks;
        var shortLength = total / numBlocks;
        var divisor = Divisor(ecPerBlock);
        var blocks = new List<List<int>>();
        for (int i = 0, k = 0; i < numBlocks; i++)
        {
            var dataLength = shortLength - ecPerBlock + (i < shortBlocks ? 0 : 1);
            var block = data.GetRange(k, dataLength);
            k += dataLength;
            var ec = RemainderOf(block, divisor);
            if (i < shortBlocks) block.Add(0);
            block.AddRange(ec);
            blocks.Add(block);
        }
        var codewords = new List<int>();
        for (var i = 0; i < blocks[0].Count; i++)
        {
            for (var j = 0; j < blocks.Count; j++)
            {
                if (i != shortLength - ecPerBlock || j >= shortBlocks) codewords.Add(blocks[j][i]);
            }
        }

        // Wzory stałe.
        var size = version * 4 + 17;
        var modules = new bool[size, size];
        var isFixed = new bool[size, size];
        void Set(int x, int y, bool dark)
        {
            modules[y, x] = dark;
            isFixed[y, x] = true;
        }
        for (var i = 0; i < size; i++)
        {
            Set(6, i, i % 2 == 0);
            Set(i, 6, i % 2 == 0);
        }
        foreach (var (cx, cy) in new[] { (3, 3), (size - 4, 3), (3, size - 4) })
        {
            for (var dy = -4; dy <= 4; dy++)
            {
                for (var dx = -4; dx <= 4; dx++)
                {
                    var distance = Math.Max(Math.Abs(dx), Math.Abs(dy));
                    int x = cx + dx, y = cy + dy;
                    if (x >= 0 && x < size && y >= 0 && y < size) Set(x, y, distance != 2 && distance != 4);
                }
            }
        }
        var positions = Alignment[version];
        var last = positions.Length - 1;
        for (var i = 0; i < positions.Length; i++)
        {
            for (var j = 0; j < positions.Length; j++)
            {
                if ((i == 0 && j == 0) || (i == 0 && j == last) || (i == last && j == 0)) continue;
                for (var dy = -2; dy <= 2; dy++)
                {
                    for (var dx = -2; dx <= 2; dx++) Set(positions[j] + dx, positions[i] + dy, Math.Max(Math.Abs(dx), Math.Abs(dy)) != 1);
                }
            }
        }
        void DrawFormat(int mask)
        {
            var value = (0b00 << 3) | mask; // poziom M = 00
            var rem = value;
            for (var i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >> 9) * 0x537);
            var formatBits = ((value << 10) | rem) ^ 0x5412;
            bool Bit(int i) => ((formatBits >> i) & 1) == 1;
            for (var i = 0; i <= 5; i++) Set(8, i, Bit(i));
            Set(8, 7, Bit(6));
            Set(8, 8, Bit(7));
            Set(7, 8, Bit(8));
            for (var i = 9; i < 15; i++) Set(14 - i, 8, Bit(i));
            for (var i = 0; i < 8; i++) Set(size - 1 - i, 8, Bit(i));
            for (var i = 8; i < 15; i++) Set(8, size - 15 + i, Bit(i));
            Set(8, size - 8, true);
        }
        DrawFormat(0);
        if (version >= 7)
        {
            var rem = version;
            for (var i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >> 11) * 0x1f25);
            var versionBits = (version << 12) | rem;
            for (var i = 0; i < 18; i++)
            {
                var dark = ((versionBits >> i) & 1) == 1;
                int a = size - 11 + i % 3, b = i / 3;
                Set(a, b, dark);
                Set(b, a, dark);
            }
        }

        // Dane zygzakiem od prawego dolnego rogu.
        var totalBits = codewords.Count * 8 + Remainder[version];
        var index = 0;
        for (var right = size - 1; right >= 1; right -= 2)
        {
            if (right == 6) right = 5;
            for (var vertical = 0; vertical < size; vertical++)
            {
                for (var j = 0; j < 2; j++)
                {
                    var x = right - j;
                    var upward = ((right + 1) & 2) == 0;
                    var y = upward ? size - 1 - vertical : vertical;
                    if (!isFixed[y, x] && index < totalBits)
                    {
                        modules[y, x] = index < codewords.Count * 8 && ((codewords[index >> 3] >> (7 - (index & 7))) & 1) == 1;
                        index++;
                    }
                }
            }
        }

        // Maska z najniższą karą.
        Func<int, int, bool>[] maskFunctions =
        [
            (x, y) => (x + y) % 2 == 0, (_, y) => y % 2 == 0, (x, _) => x % 3 == 0,
            (x, y) => (x + y) % 3 == 0, (x, y) => (x / 3 + y / 2) % 2 == 0,
            (x, y) => x * y % 2 + x * y % 3 == 0, (x, y) => (x * y % 2 + x * y % 3) % 2 == 0,
            (x, y) => ((x + y) % 2 + x * y % 3) % 2 == 0,
        ];
        void ApplyMask(int mask)
        {
            for (var y = 0; y < size; y++)
            {
                for (var x = 0; x < size; x++)
                {
                    if (!isFixed[y, x] && maskFunctions[mask](x, y)) modules[y, x] = !modules[y, x];
                }
            }
        }
        int bestMask = 0, bestPenalty = int.MaxValue;
        for (var mask = 0; mask < 8; mask++)
        {
            ApplyMask(mask);
            DrawFormat(mask);
            var value = Penalty(modules);
            if (value < bestPenalty)
            {
                bestPenalty = value;
                bestMask = mask;
            }
            ApplyMask(mask);
        }
        ApplyMask(bestMask);
        DrawFormat(bestMask);
        return modules;
    }

    /// <summary>Kara za trudne do odczytania układy (reguły N1–N4).</summary>
    private static int Penalty(bool[,] m)
    {
        var size = m.GetLength(0);
        var result = 0;
        var lines = new List<bool[]>();
        for (var y = 0; y < size; y++) lines.Add(Enumerable.Range(0, size).Select(x => m[y, x]).ToArray());
        for (var x = 0; x < size; x++) lines.Add(Enumerable.Range(0, size).Select(y => m[y, x]).ToArray());
        foreach (var line in lines)
        {
            var run = 1;
            for (var i = 1; i <= size; i++)
            {
                if (i < size && line[i] == line[i - 1])
                {
                    run++;
                }
                else
                {
                    if (run >= 5) result += 3 + run - 5;
                    run = 1;
                }
            }
            var text = new string(line.Select(d => d ? '1' : '0').ToArray());
            foreach (var pattern in new[] { "10111010000", "00001011101" })
            {
                for (var at = text.IndexOf(pattern, StringComparison.Ordinal); at >= 0; at = text.IndexOf(pattern, at + 1, StringComparison.Ordinal)) result += 40;
            }
        }
        for (var y = 0; y < size - 1; y++)
        {
            for (var x = 0; x < size - 1; x++)
            {
                var c = m[y, x];
                if (c == m[y, x + 1] && c == m[y + 1, x] && c == m[y + 1, x + 1]) result += 3;
            }
        }
        var dark = 0;
        foreach (var module in m) if (module) dark++;
        result += (int)Math.Floor(Math.Abs(dark * 20.0 / (size * size) - 10)) * 10;
        return result;
    }

    /// <summary>Wiersze macierzy jako „0”/„1” (format shared/fixtures/qr.json).</summary>
    public static string[] Rows(bool[,] modules) =>
        Enumerable.Range(0, modules.GetLength(0)).Select(y => new string(Enumerable.Range(0, modules.GetLength(1)).Select(x => modules[y, x] ? '1' : '0').ToArray())).ToArray();
}
