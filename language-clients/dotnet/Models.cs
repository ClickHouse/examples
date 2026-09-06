using ClickHouse.Driver;

namespace ClientTour;

/// <summary>One sensor reading; the shape of <c>client_tour.readings_dotnet</c>.</summary>
/// <remarks>
/// The driver matches properties to columns by name. ClickHouse columns are snake_case
/// and C# properties are PascalCase, so every property carries an explicit column name.
/// </remarks>
internal sealed class Reading
{
    [ClickHouseColumn(Name = "reading_id")]
    public Guid ReadingId { get; init; }

    // DateTime64(3, 'UTC'): the driver writes the ticks as-is, so Kind must be Utc.
    [ClickHouseColumn(Name = "recorded_at")]
    public DateTime RecordedAt { get; init; }

    [ClickHouseColumn(Name = "device_id")]
    public string DeviceId { get; init; } = "";

    [ClickHouseColumn(Name = "site")]
    public string Site { get; init; } = "";

    [ClickHouseColumn(Name = "temp_c")]
    public double TempC { get; init; }

    [ClickHouseColumn(Name = "humidity_pct")]
    public double? HumidityPct { get; init; }

    [ClickHouseColumn(Name = "battery_pct")]
    public byte BatteryPct { get; init; }

    [ClickHouseColumn(Name = "tags")]
    public string[] Tags { get; init; } = [];

    [ClickHouseColumn(Name = "attributes")]
    public Dictionary<string, string> Attributes { get; init; } = [];
}

/// <summary>One row of the step 6 aggregate, mapped by <c>QueryAsync&lt;T&gt;</c>.</summary>
/// <remarks>Read mapping assigns through setters, so these cannot be init-only.</remarks>
internal sealed class SiteSummary
{
    [ClickHouseColumn(Name = "site")]
    public string Site { get; set; } = "";

    // count() is UInt64.
    [ClickHouseColumn(Name = "readings")]
    public ulong Readings { get; set; }

    [ClickHouseColumn(Name = "avg_temp_c")]
    public double AvgTempC { get; set; }

    [ClickHouseColumn(Name = "max_temp_c")]
    public double MaxTempC { get; set; }
}
