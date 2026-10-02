using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CapacityBoard.Domain;

public sealed record WorkItem(Guid Id, string Name, int Points);
public sealed record BoardSnapshot(Guid Id, string Title, int Capacity, int Revision, WorkItem[] Items)
{
    public int Total => Items.Sum(item => item.Points);
    public int Remaining => Capacity - Total;
}
public sealed record SaveRequest(Guid OperationId, int ExpectedRevision, WorkItem[] Items);
public sealed record CanonicalSave(Guid OperationId, int ExpectedRevision, WorkItem[] Items, string Fingerprint);

public sealed class BoardError(string code) : Exception(code)
{
    public string Code { get; } = code;
}

public static class Allocation
{
    public static readonly Guid BoardId = Guid.Parse("11111111-1111-4111-8111-111111111111");
    public const int MaxSaves = 25;

    public static CanonicalSave Validate(SaveRequest request)
    {
        if (request.OperationId == Guid.Empty || request.ExpectedRevision is < 1 or > MaxSaves + 1 ||
            request.Items is null || request.Items.Length > 20)
            throw new BoardError("invalid_allocation");
        var seen = new HashSet<Guid>();
        var items = new WorkItem[request.Items.Length];
        for (var index = 0; index < request.Items.Length; index++)
        {
            var item = request.Items[index];
            if (item is null || item.Id == Guid.Empty || !seen.Add(item.Id) || item.Points is < 0 or > 30)
                throw new BoardError("invalid_allocation");
            items[index] = item with { Name = Name(item.Name) };
        }
        // Row order is retained: a retry must describe the same complete ordered set.
        var payload = JsonSerializer.Serialize(new { request.ExpectedRevision, Items = items });
        var fingerprint = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(payload)));
        return new CanonicalSave(request.OperationId, request.ExpectedRevision, items, fingerprint);
    }

    public static int Points(string? input)
    {
        if (input is null || input.Length is < 1 or > 2 ||
            !int.TryParse(input, System.Globalization.NumberStyles.None,
                System.Globalization.CultureInfo.InvariantCulture, out var value) || value > 30)
            throw new BoardError("invalid_points");
        return value;
    }

    public static string Name(string? input)
    {
        if (input is null || input.Length > 160)
            throw new BoardError("invalid_name");
        // Reject invalid UTF-16 before encoding or sending text to PostgreSQL.
        for (var index = 0; index < input.Length; index++)
        {
            var ch = input[index];
            if (char.IsControl(ch)) throw new BoardError("invalid_name");
            if (char.IsHighSurrogate(ch))
            {
                if (++index >= input.Length || !char.IsLowSurrogate(input[index]))
                    throw new BoardError("invalid_name");
            }
            else if (char.IsLowSurrogate(ch)) throw new BoardError("invalid_name");
        }
        var name = input.Trim();
        if (name.Length is < 1 or > 80) throw new BoardError("invalid_name");
        return name;
    }
}
