import streamlit as st
import plotly.express as px
import clickhouse_connect
import queries

st.set_page_config(layout="wide")

client = clickhouse_connect.get_client(
  host='sql-clickhouse.clickhouse.com', 
  username='demo',
  secure=True
)

st.title("Python BlueSky dashboard with ClickHouse and Streamlit")

st.markdown("## How much are people using it?")
st.markdown("How many messages have been generated so far?")

all_messages = client.query_df(queries.all_messages)
last_24_hours_messages = client.query_df(queries.last_24_hours)  

left, right = st.columns(2)
with left:
  st.metric(label="Total events", value=f"{all_messages['messages'][0]:,}")

with right:
  st.metric(
    label="Events in the last 24 hours", 
    value=f"{last_24_hours_messages['last24Hours'][0]:,}",
    delta=f"{int(last_24_hours_messages['last24Hours'][0])-int(last_24_hours_messages['previous24Hours'][0]):,}"
  )  

st.markdown("## When do people use BlueSky?")
st.markdown("What's the most popular time for people to like, post, and re-post?")

left, right = st.columns(2)

with left:
  df = client.query_df(queries.time_of_day)
  fig = px.bar(df, 
    x="hour_of_day", y="count", color="event", 
    labels={"hour_of_day": "Hour of Day", "count": "Event Count", "event": "Event Type"},
    color_discrete_map={"like": "light blue", "post": "red", "repost": "green"}
  )
  fig.update_layout(
      legend=dict(
          orientation="h",
          yanchor="bottom",
          y=1.1,
          xanchor="center",
          x=0.5
      )
  )
  st.plotly_chart(fig)

with right:
  df = client.query_df(queries.events_by_day)
  st.plotly_chart(px.bar(df, 
    x="day", y="count", 
    labels={"day": "Day", "count": "Event Count"},
  ))

st.markdown("## Post types")
st.markdown("BlueSky has lots of different post types. These are the most popular ones:")

left, middle, right = st.columns(3)
df = client.query_df(queries.top_post_types)
df['short_collection'] = df['collection'].apply(lambda x: x[:30] + "..." if len(x) > 30 else x)

df_posts_sorted = df.sort_values(by='posts', ascending=True)
df_users_sorted = df.sort_values(by='users', ascending=True)

with left:
  st.dataframe(df.drop(["short_collection"], axis=1), hide_index=True)  

with middle:
  fig1 = px.bar(df_posts_sorted, 
    x="posts", 
    y="short_collection", 
    orientation="h", 
    title = "By posts",
    labels={"posts": "Number of Posts", "short_collection": "Post Type"},
    log_x=True
  )
  st.plotly_chart(fig1)

with right:
  fig2 = px.bar(df_users_sorted, 
    x="users", 
    y="short_collection", 
    orientation="h", 
    title = "By users",
    labels={"users": "Number of Users", "short_collection": "Post Type"},
    log_x=True
  )

  st.plotly_chart(fig2)

left, right = st.columns(2)
with left:
  st.markdown("""
## Most liked/reposted
""")
  
  col1, col2 = st.columns(2)
  with col1:
    st.write("Who has the most liked posts?")
    df = client.query_df(queries.most_liked)
    st.dataframe(df, hide_index=True)

  with col2:
    st.write("Who has the most re-posts?")
    df = client.query_df(queries.most_reposted)
    st.dataframe(df, hide_index=True)

with right:
  st.markdown("""
  ## Posts per language
  What language do people use?
  """)

  df = client.query_df(queries.posts_per_language)
  fig = px.pie(names=df["name"], values=df["value"], 
              color=df["name"], color_discrete_sequence=px.colors.qualitative.Set3)
  st.plotly_chart(fig)