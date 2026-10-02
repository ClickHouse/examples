using System.Reflection;
using CapacityBoard.Components;
using CapacityBoard.Data;
using Microsoft.AspNetCore.Http.Connections;
using Npgsql;

var preflight = args.Contains("--preflight");
if (args.Contains("migrate"))
{
    await using var migration = Database.Create("capacity_migration");
    await using var connection = await migration.OpenConnectionAsync();
    using var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("CapacityBoard.sql.migrate.sql")
        ?? throw new InvalidOperationException("Migration resource missing");
    var sql = await new StreamReader(resource).ReadToEndAsync();
    await using var command = new NpgsqlCommand(sql, connection) { CommandTimeout = 15 };
    await command.ExecuteNonQueryAsync();
    Console.WriteLine("Reviewed migration applied.");
    return;
}
if (args.Contains("--check-db"))
{
    await using var check = Database.Create("capacity_app");
    await using var connection = await check.OpenConnectionAsync();
    Console.WriteLine("Actual Npgsql factory connection succeeded.");
    return;
}
var originText = Environment.GetEnvironmentVariable("APP_ORIGIN") ?? "http://127.0.0.1:5000";
if (!Uri.TryCreate(originText, UriKind.Absolute, out var origin) || origin.Scheme != "http" ||
    origin.Host != "127.0.0.1" || origin.Port < 1024 || origin.AbsolutePath != "/" ||
    !string.IsNullOrEmpty(origin.Query) || !string.IsNullOrEmpty(origin.Fragment) ||
    !string.IsNullOrEmpty(origin.UserInfo))
    throw new InvalidOperationException("APP_ORIGIN must be an http://127.0.0.1 local origin");
var expectedOrigin = origin.GetLeftPart(UriPartial.Authority);
var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    Args = args,
    ContentRootPath = AppContext.BaseDirectory
});
builder.WebHost.UseUrls(expectedOrigin);
builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxRequestBodySize = 16 * 1024;
    options.Limits.MaxConcurrentConnections = 32;
    options.Limits.MaxConcurrentUpgradedConnections = 32;
    options.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(5);
    options.Limits.KeepAliveTimeout = TimeSpan.FromSeconds(30);
});
builder.Services.Configure<HostOptions>(options => options.ShutdownTimeout = TimeSpan.FromSeconds(12));
if (!preflight)
{
    builder.Services.AddSingleton(_ => Database.Create("capacity_app"));
    builder.Services.AddSingleton<BoardRepository>();
    builder.Services.AddRazorComponents().AddInteractiveServerComponents(options =>
    {
        options.DetailedErrors = false;
        options.DisconnectedCircuitMaxRetained = 10;
        options.DisconnectedCircuitRetentionPeriod = TimeSpan.FromSeconds(30);
        options.JSInteropDefaultCallTimeout = TimeSpan.FromSeconds(5);
    }).AddHubOptions(options =>
    {
        options.MaximumReceiveMessageSize = 16 * 1024;
        options.MaximumParallelInvocationsPerClient = 1;
        options.ClientTimeoutInterval = TimeSpan.FromSeconds(30);
        options.KeepAliveInterval = TimeSpan.FromSeconds(10);
    });
}
var app = builder.Build();
app.UseWebSockets();
app.Use(async (context, next) =>
{
    var sentOrigin = context.Request.Headers.Origin.ToString();
    var signalMutation = context.Request.Path.StartsWithSegments("/_blazor") &&
        (context.Request.Method != "GET" || context.WebSockets.IsWebSocketRequest);
    if (context.Request.Host.Value != origin.Authority ||
        (sentOrigin.Length > 0 && sentOrigin != expectedOrigin) ||
        (signalMutation && sentOrigin != expectedOrigin))
    {
        context.Response.StatusCode = 403;
        return;
    }
    context.Response.Headers.CacheControl = "no-store";
    context.Response.Headers.ContentSecurityPolicy = "frame-ancestors 'none'";
    context.Response.Headers.XContentTypeOptions = "nosniff";
    await next();
});
app.MapGet("/health", () => Results.Ok(new { ready = true }));
if (!preflight)
{
    // Verify startup connectivity; dispose it before serving any circuit.
    await using (var startup = await app.Services.GetRequiredService<NpgsqlDataSource>().OpenConnectionAsync()) { }
    app.UseStaticFiles();
    app.UseAntiforgery();
    app.MapRazorComponents<App>().AddInteractiveServerRenderMode(options =>
    {
        options.DisableWebSocketCompression = true;
    }).Add(endpoint =>
    {
        // ASP.NET Core 10 exposes dispatcher options through endpoint metadata.
        var dispatcher = endpoint.Metadata.OfType<HttpConnectionDispatcherOptions>().FirstOrDefault();
        if (dispatcher is not null)
        {
            dispatcher.Transports = HttpTransportType.WebSockets | HttpTransportType.LongPolling;
            dispatcher.ApplicationMaxBufferSize = 16 * 1024;
            dispatcher.TransportMaxBufferSize = 16 * 1024;
        }
    });
}
await app.RunAsync();
