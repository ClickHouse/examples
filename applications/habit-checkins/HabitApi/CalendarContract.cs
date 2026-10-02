using System.Globalization;
namespace HabitApi;

public static class CalendarContract
{
    public static readonly DateOnly FirstDate = new(2000, 1, 1);
    public static readonly DateOnly LastDate = new(2100, 12, 31);

    public static DateOnly Date(string input)
    {
        if (!DateOnly.TryParseExact(input, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date)
            || date < FirstDate || date > LastDate)
            throw new ApiProblem(400, "date_must_be_yyyy_mm_dd_between_2000_and_2100");
        return date;
    }

    public static (DateOnly Start, DateOnly End) Month(string input)
    {
        if (input.Length != 7) throw new ApiProblem(400, "month_must_be_yyyy_mm");
        var start = Date(input + "-01");
        return (start, start.AddMonths(1));
    }
}

public sealed class ApiProblem(int status, string code) : Exception(code)
{
    public int Status
    {
        get;
    } = status;
}
