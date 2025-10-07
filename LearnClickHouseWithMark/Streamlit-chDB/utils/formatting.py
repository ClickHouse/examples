from dateparser import parse
from functools import partial

def style_subheading(text):
    return f"<span style='color:#B3B6BD'>{text}</span>"


def format_date(table, start_date):
    end_date = table[table["startDate"] == start_date]["endDate"].values[0]
    start_formatted = parse(start_date).strftime('%b %Y')
    end_formatted = parse(end_date).strftime('%b %Y')
    return f"{start_formatted} - {end_formatted}"


def colour_diff(val):
    if round(val, 2) == 0.0:
        return "color: #B3B6BD"
    colour = '#FF7575' if val > 0 else '#99FFA1'
    return f'color: {colour}'


def format_difference(comparison_date, difference):
    if round(difference, 2) == 0.0:
        return "No difference"
    elif difference > 0:
        return f"£{difference:.2f} more than {comparison_date}"
    else:
        return f"£{difference:.2f} less than {comparison_date}"


def style_table(table, selected_date):
    return table.style.map(colour_diff, subset=['Difference']).format({
        "Difference": partial(format_difference, selected_date.strftime('%d %b %Y'))
    })
