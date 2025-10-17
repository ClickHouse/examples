import plotly.express as px

def line_chart(df, selected_date, title, x="day", y="cost"):
    fig = px.line(df, x, y, title=title, color_discrete_sequence=["#FAFF69"])
    fig.add_vline(x=selected_date, line_dash="dash", line_color="#FC74FF")
    fig.update_layout(margin=dict(t=20))
    return fig
