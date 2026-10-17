using System.Runtime.InteropServices;
using System.Text;
using CantatePresenter.Core.GoogleDrive;

namespace CantatePresenter.WinUI;

/// <summary>
/// Tokeny Google w Menedżerze poświadczeń Windows (poświadczenie ogólne użytkownika), odpowiednik Pęku kluczy
/// w macOS (W4): nigdy w settings.json ani w kopiach zapasowych.
/// </summary>
public sealed class WindowsCredentialStore(string target) : ICredentialStore
{
    public static readonly WindowsCredentialStore GoogleDrive = new("com.cantate.presenter.gdrive");

    private const int CredTypeGeneric = 1;
    private const int CredPersistLocalMachine = 2;
    private const int ErrorNotFound = 1168;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public int Flags;
        public int Type;
        public string TargetName;
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public int CredentialBlobSize;
        public nint CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public nint Attributes;
        public string? TargetAlias;
        public string? UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, int type, int flags, out nint credential);

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite(ref Credential credential, int flags);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, int type, int flags);

    [DllImport("advapi32.dll")]
    private static extern void CredFree(nint buffer);

    public string? Load()
    {
        if (!CredRead(target, CredTypeGeneric, 0, out var pointer)) return null;
        try
        {
            var credential = Marshal.PtrToStructure<Credential>(pointer);
            if (credential.CredentialBlob == 0 || credential.CredentialBlobSize == 0) return null;
            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            return Encoding.UTF8.GetString(bytes);
        }
        finally
        {
            CredFree(pointer);
        }
    }

    public void Save(string value)
    {
        var bytes = Encoding.UTF8.GetBytes(value);
        var blob = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new Credential
            {
                Type = CredTypeGeneric,
                TargetName = target,
                Comment = "CantatePresenter: Dysk Google",
                CredentialBlobSize = bytes.Length,
                CredentialBlob = blob,
                Persist = CredPersistLocalMachine,
                UserName = "CantatePresenter",
            };
            if (!CredWrite(ref credential, 0))
                throw new IOException(Services.L("Nie można zapisać danych logowania w Menedżerze poświadczeń Windows (kod {0}).", Marshal.GetLastWin32Error()));
        }
        finally
        {
            Marshal.FreeHGlobal(blob);
        }
    }

    public void Clear()
    {
        if (!CredDelete(target, CredTypeGeneric, 0) && Marshal.GetLastWin32Error() != ErrorNotFound)
            Services.Trace($"Menedżer poświadczeń: usuwanie nie powiodło się ({Marshal.GetLastWin32Error()})");
    }
}
