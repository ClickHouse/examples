using HabitApi;
using Xunit;
namespace HabitTests;

public sealed class ContractTests
{
    [Fact]
    public void ExplicitCalendarDatesIncludeLeapDay()
    {
        Assert.Equal(new DateOnly(2024, 2, 29), CalendarContract.Date("2024-02-29"));
        foreach (var invalid in new[] { "2026-02-29", "2026-2-03", "2026-10-01T00:00:00Z", "1999-12-31", "2101-01-01" })
            Assert.Throws<ApiProblem>(() => CalendarContract.Date(invalid));
    }
    [Fact]
    public void MonthlyRangeIsHalfOpenAndCrossesYearBoundary()
    {
        var (start, end) = CalendarContract.Month("2026-12");
        Assert.Equal(new DateOnly(2026, 12, 1), start);
        Assert.Equal(new DateOnly(2027, 1, 1), end);
        Assert.Throws<ApiProblem>(() => CalendarContract.Month("2026-2"));
    }
    [Fact]
    public void TokensBindUsersAndRejectAmbiguousMappings()
    {
        var a = new string('a', 48);
        var b = new string('b', 48);
        var tokens = new Tokens($"user-a:{a},user-b:{b}");
        Assert.Equal("user-a", tokens.Resolve("Bearer " + a));
        Assert.Equal("user-b", tokens.Resolve("Bearer " + b));
        Assert.Null(tokens.Resolve("Bearer " + new string('c', 48)));
        Assert.Throws<InvalidOperationException>(() => new Tokens($"user-a:{a},user-b:{a}"));
    }
}
