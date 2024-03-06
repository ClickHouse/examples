import datetime
import streamlit as st
import utils.queries as queries

from utils.charts import line_chart
from utils.formatting import colour_diff, format_date, style_subheading, style_table
from utils.data import EnergyUsage, AlternateUsage

from chdb.session import Session

st.title("How much would it cost me then?")
st.markdown(
    style_subheading("Compare today's cost for gas and electricity with past dates"),
    unsafe_allow_html=True
)

db = Session(path="energy.chdb")
with st.spinner("Loading data..."):
    table = db.query(queries.tariffs_query, "DataFrame")

left, _ = st.columns([2,3])
with left:
    comparison_date = st.selectbox(
        "Compare today's cost with the rates from",
        options = table["startDate"],
        format_func=lambda value: format_date(table, value),
        index=table.shape[0]-1
    )
    alternate = table[table["startDate"] == comparison_date]
    friendly_comparison = format_date(table, comparison_date)

    selected_date = st.date_input(
        label='For the amount of gas and electricity used on', 
        value=datetime.date(2024, 1, 1),
        format="DD/MM/YYYY"
    )


usage = db.query(queries.energy_usage_for_day_query(selected_date), "DataFrame")

gas = EnergyUsage(usage[usage['energyType'] == 'gas'])
alternate_gas = AlternateUsage(
    standing_charge = alternate["gasStandingCharge"].values[0] / 100,
    unit_rate = alternate["gasUnitRate"].values[0] / 100
)

elec = EnergyUsage(usage[usage['energyType'] == 'electricity'])
alternate_elec = AlternateUsage(
    standing_charge = alternate["elecStandingCharge"].values[0] / 100,
    unit_rate = alternate["elecUnitRate"].values[0] / 100
)

all_energy = db.query(queries.energy_usage_query, "DataFrame")

st.markdown(f"#### Usage on {selected_date.strftime('%d %b %Y')}")
left, right = st.columns(2)

with left:
    st.metric(value=gas.usage(), label="Gas (kWh)")

with right:
    st.metric(value=elec.usage(), label="Electricity (kWh)")

st.markdown("#### Gas cost consumption")
st.markdown(
    style_subheading(f"""See how much **{gas.usage()} kWh** would cost 
    with the rate from **{friendly_comparison}**"""),
    unsafe_allow_html=True
)

gas_table = gas.table(selected_date, friendly_comparison, alternate_gas)
st.dataframe(style_table(gas_table, selected_date), hide_index=True)

fig = line_chart(all_energy[all_energy["energyType"] == "gas"], 
    selected_date, 'Gas Cost (£)'
)
st.plotly_chart(fig)


st.markdown("#### Electricity cost consumption")
st.markdown(
    style_subheading(f"""See how much **{elec.usage()} kWh** would cost 
    with the rate from **{friendly_comparison}**"""),
    unsafe_allow_html=True
)

elec_table = elec.table(selected_date, friendly_comparison, alternate_elec)
st.dataframe(style_table(elec_table, selected_date), hide_index=True)

fig = line_chart(all_energy[all_energy["energyType"] == "electricity"], 
    selected_date, 'Electricity Cost (£)'
)
st.plotly_chart(fig)

