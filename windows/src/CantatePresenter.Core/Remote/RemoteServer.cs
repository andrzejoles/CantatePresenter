using System.Collections.Concurrent;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace CantatePresenter.Core.Remote;

/// <summary>
/// Serwer pilota w sieci lokalnej (jak RemoteControlServer w macOS): strona dla telefonu i proste API po HTTP,
/// bez zależności zewnętrznych. Dostęp tylko z tokenem z kodu QR; nowy token rozłącza wszystkie telefony.
/// </summary>
public sealed class RemoteServer : IDisposable
{
    public const int PreferredPort = 8765;
    /// <summary>Telefon liczy się jako połączony, jeśli pytał o stan w tym czasie (strona pyta co sekundę).</summary>
    public static readonly TimeSpan ConnectedWindow = TimeSpan.FromSeconds(5);
    /// <summary>Połączenie, które nie przyśle całego żądania w tym czasie, jest zamykane.</summary>
    public static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(10);

    /// <summary>Obsługa żądania z bieżącymi tokenami (sterowanie, muzycy); aplikacja przekazuje ją do wątku interfejsu.</summary>
    private readonly Func<RemoteHttpRequest, string, string, Task<RemoteHttpResponse>> route;
    private readonly ConcurrentDictionary<string, DateTime> lastSeen = new();
    private TcpListener? listener;
    private CancellationTokenSource? cancellation;

    public RemoteServer(Func<RemoteHttpRequest, string, string, Task<RemoteHttpResponse>> route) => this.route = route;

    public bool IsRunning => listener is not null;
    public int? Port { get; private set; }
    public string Token { get; private set; } = RemoteRouter.MakeToken();
    /// <summary>Token dla muzyków: tylko podgląd slajdu z chwytami.</summary>
    public string StageToken { get; private set; } = RemoteRouter.MakeToken();
    public string? ErrorMessage { get; private set; }

    // MARK: - Lifecycle

    /// <summary>Start na porcie 8765, a gdy jest zajęty, na dowolnym wolnym (adres w kodzie QR i tak go zawiera).</summary>
    public void Start(int port = PreferredPort)
    {
        if (listener is not null) return;
        ErrorMessage = null;
        foreach (var candidate in port == 0 ? [0] : new[] { port, 0 })
        {
            try
            {
                var started = new TcpListener(IPAddress.Any, candidate);
                started.Start();
                listener = started;
                Port = ((IPEndPoint)started.LocalEndpoint).Port;
                cancellation = new CancellationTokenSource();
                _ = AcceptLoop(started, cancellation.Token);
                return;
            }
            catch (SocketException error)
            {
                ErrorMessage = error.Message;
            }
        }
    }

    public void Stop()
    {
        cancellation?.Cancel();
        listener?.Stop();
        listener = null;
        cancellation = null;
        Port = null;
        lastSeen.Clear();
    }

    public void Dispose() => Stop();

    /// <summary>Nowe tokeny: dotychczasowe telefony i tablety tracą dostęp i muszą zeskanować nowy kod.</summary>
    public void RegenerateTokens()
    {
        Token = RemoteRouter.MakeToken();
        StageToken = RemoteRouter.MakeToken();
        lastSeen.Clear();
    }

    // MARK: - Status

    public int ConnectedDevices(DateTime? now = null)
    {
        var moment = now ?? DateTime.UtcNow;
        return lastSeen.Values.Count(seen => moment - seen < ConnectedWindow);
    }

    /// <summary>Adres do kodu QR: adres komputera w sieci lokalnej, port i token.</summary>
    public string? Address => IsRunning && LocalIPv4Address() is string host ? $"http://{host}:{Port}/?t={Token}" : null;

    /// <summary>Adres podglądu dla muzyków (tylko odczyt).</summary>
    public string? StageAddress => IsRunning && LocalIPv4Address() is string host ? $"http://{host}:{Port}/stage?t={StageToken}" : null;

    // MARK: - Connections

    private async Task AcceptLoop(TcpListener server, CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            TcpClient client;
            try
            {
                client = await server.AcceptTcpClientAsync(token);
            }
            catch (Exception error) when (error is OperationCanceledException or ObjectDisposedException or SocketException)
            {
                return;
            }
            _ = Handle(client, token);
        }
    }

    private async Task Handle(TcpClient client, CancellationToken serverToken)
    {
        using (client)
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(serverToken);
            timeout.CancelAfter(RequestTimeout);
            try
            {
                var stream = client.GetStream();
                var buffer = new MemoryStream();
                var chunk = new byte[16 * 1024];
                RemoteHttpResponse response;
                while (true)
                {
                    var read = await stream.ReadAsync(chunk, timeout.Token);
                    if (read > 0) buffer.Write(chunk, 0, read);
                    var (status, request) = RemoteHttpRequest.Parse(buffer.GetBuffer().AsSpan(0, (int)buffer.Length));
                    if (status == RemoteHttpRequest.Status.Complete && request is not null)
                    {
                        response = await route(request, Token, StageToken);
                        if (response.Status == 200 && client.Client.RemoteEndPoint is IPEndPoint remote) lastSeen[remote.Address.ToString()] = DateTime.UtcNow;
                        break;
                    }
                    if (status == RemoteHttpRequest.Status.Invalid || read == 0)
                    {
                        response = RemoteHttpResponse.Text("Bad request", 400);
                        break;
                    }
                }
                await stream.WriteAsync(response.Serialized(), timeout.Token);
            }
            catch (Exception error) when (error is IOException or OperationCanceledException or SocketException or ObjectDisposedException)
            {
                // Telefon się rozłączył albo nie dokończył żądania w czasie.
            }
        }
    }

    // MARK: - Network Address

    /// <summary>
    /// Adres IPv4 komputera w sieci lokalnej (Wi-Fi albo Ethernet): bez pętli zwrotnej i adresów 169.254.x.x;
    /// najpierw karty z bramą domyślną (sieć, w której jest telefon), potem pozostałe (np. karty maszyn wirtualnych).
    /// </summary>
    public static string? LocalIPv4Address()
    {
        var candidates = new List<(int Rank, string Name, string Address)>();
        NetworkInterface[] interfaces;
        try
        {
            interfaces = NetworkInterface.GetAllNetworkInterfaces();
        }
        catch (NetworkInformationException)
        {
            return null;
        }
        foreach (var networkInterface in interfaces)
        {
            if (networkInterface.OperationalStatus != OperationalStatus.Up
                || networkInterface.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel) continue;
            IPInterfaceProperties properties;
            try
            {
                properties = networkInterface.GetIPProperties();
            }
            catch (NetworkInformationException)
            {
                continue;
            }
            var hasGateway = properties.GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(IPAddress.Any));
            var physical = networkInterface.NetworkInterfaceType is NetworkInterfaceType.Wireless80211 or NetworkInterfaceType.Ethernet;
            foreach (var unicast in properties.UnicastAddresses)
            {
                if (unicast.Address.AddressFamily != AddressFamily.InterNetwork || IPAddress.IsLoopback(unicast.Address)) continue;
                var text = unicast.Address.ToString();
                if (text.StartsWith("169.254.", StringComparison.Ordinal)) continue;
                candidates.Add(((hasGateway ? 0 : 2) + (physical ? 0 : 1), networkInterface.Name, text));
            }
        }
        return candidates.OrderBy(c => c.Rank).ThenBy(c => c.Name, StringComparer.Ordinal).Select(c => c.Address).FirstOrDefault();
    }
}
