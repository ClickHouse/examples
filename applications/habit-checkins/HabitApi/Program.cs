using System.Text.Json.Serialization;
using HabitApi;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = 4096);
builder.WebHost.UseUrls(Environment.GetEnvironmentVariable("APP_URL") ?? "http://127.0.0.1:8080");
builder.Services.AddProblemDetails();
builder.Services.ConfigureHttpJsonOptions(options => options.SerializerOptions.UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow);
builder.Services.AddSingleton(new Tokens(PgConfig.Required("APP_TOKENS")));
builder.Services.AddDbContext<HabitDb>(options => options.UseNpgsql(PgConfig.ConnectionString(),
    pg => pg.MigrationsHistoryTable("__EFMigrationsHistory", "habits")));
builder.Services.AddScoped<HabitService>();
var app = builder.Build();
app.UseExceptionHandler();
app.Use(async (context, next) =>
{
    if (context.Request.Path == "/health" && context.Request.Method == "GET")
    {
        await next(context);
        return;
    }
    var user = context.RequestServices.GetRequiredService<Tokens>().Resolve(context.Request.Headers.Authorization);
    if (user is null)
    {
        context.Response.StatusCode = 401;
        context.Response.Headers.WWWAuthenticate = "Bearer";
        await context.Response.WriteAsJsonAsync(new { error = "authentication_required" });
        return;
    }
    context.Items["owner"] = user;
    try
    {
        await next(context);
    }
    catch (ApiProblem e)
    {
        context.Response.StatusCode = e.Status;
        await context.Response.WriteAsJsonAsync(new { error = e.Message });
    }
});

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapPost("/habits", async (CreateHabit body, HttpContext ctx, HabitService service) =>
    Results.Json(await service.Create(Owner(ctx), body.Name), statusCode: 201));
app.MapGet("/habits", async (HttpContext ctx, HabitService service) => Results.Ok(await service.List(Owner(ctx))));
app.MapPut("/habits/{id:guid}/check-ins/{date}", async (Guid id, string date, HttpContext ctx, HabitService service) =>
    Results.Ok(await service.Complete(Owner(ctx), id, CalendarContract.Date(date))));
app.MapDelete("/habits/{id:guid}/check-ins/{date}", async (Guid id, string date, HttpContext ctx, HabitService service) =>
{
    await service.Undo(Owner(ctx), id, CalendarContract.Date(date));
    return Results.NoContent();
});
app.MapPost("/habits/{id:guid}/archive", async (Guid id, HttpContext ctx, HabitService service) =>
    Results.Ok(await service.Archive(Owner(ctx), id)));
app.MapGet("/habits/{id:guid}/history", async (Guid id, string month, HttpContext ctx, HabitService service) =>
    Results.Ok(await service.History(Owner(ctx), id, month)));
app.Run();

static string Owner(HttpContext context) => (string)context.Items["owner"]!;
public sealed record CreateHabit(string? Name);
