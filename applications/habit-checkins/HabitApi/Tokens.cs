using System.Security.Cryptography;
using System.Text;
namespace HabitApi;

public sealed class Tokens
{
    private readonly List<(byte[] Digest, string User)> entries = [];

    public Tokens(string configuration)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in configuration.Split(','))
        {
            var fields = entry.Split(':');
            if (fields.Length != 2 || fields[0].Length is < 1 or > 64
                || fields[0].Any(c => !char.IsAsciiLetterOrDigit(c) && c != '-' && c != '_')
                || fields[1].Length is < 32 or > 256 || !seen.Add(fields[1]))
                throw new InvalidOperationException("Invalid APP_TOKENS mapping");
            entries.Add((SHA256.HashData(Encoding.UTF8.GetBytes(fields[1])), fields[0]));
        }
    }

    public string? Resolve(string? authorization)
    {
        if (authorization is null || !authorization.StartsWith("Bearer ", StringComparison.Ordinal)
            || authorization.Length > 263) return null;
        var digest = SHA256.HashData(Encoding.UTF8.GetBytes(authorization[7..]));
        string? user = null;
        foreach (var entry in entries)
            if (CryptographicOperations.FixedTimeEquals(entry.Digest, digest)) user = entry.User;
        return user;
    }
}
