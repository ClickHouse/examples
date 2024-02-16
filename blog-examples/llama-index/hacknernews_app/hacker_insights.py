"""
# My first app
Here's our first attempt at using data to create a table:
"""
import logging
import sys

import streamlit as st
from clickhouse_connect import common
from llama_index.core.settings import Settings
from llama_index.embeddings.fastembed import FastEmbedEmbedding
from llama_index.llms.openai import OpenAI

from llama_index.core import VectorStoreIndex, PromptTemplate
from llama_index.core.indices.struct_store import NLSQLTableQueryEngine
from llama_index.core.indices.vector_store import VectorIndexAutoRetriever
from llama_index.core.indices.vector_store.retrievers.auto_retriever.prompts import PREFIX, EXAMPLES
from llama_index.core.prompts import PromptType
from llama_index.core.query_engine import RetrieverQueryEngine, SQLAutoVectorQueryEngine
from llama_index.core.tools import QueryEngineTool
from llama_index.core.vector_stores.types import VectorStoreInfo, MetadataInfo
from llama_index.vector_stores.clickhouse import ClickHouseVectorStore
import clickhouse_connect
import openai
from sqlalchemy import (
    create_engine,
)
from llama_index.core import SQLDatabase

logging.basicConfig(stream=sys.stdout, level=logging.INFO)
logging.getLogger().addHandler(logging.StreamHandler(stream=sys.stdout))

host = st.secrets.clickhouse.host
password = st.secrets.clickhouse.password
username = st.secrets.clickhouse.username
secure = st.secrets.clickhouse.secure
http_port = st.secrets.clickhouse.http_port
native_port = st.secrets.clickhouse.native_port
open_ai_model = "gpt-4"

database = st.secrets.clickhouse.database
hackernews_table = st.secrets.clickhouse.hackernews_table
stackoverflow_table = st.secrets.clickhouse.stackoverflow_table
database = st.secrets.clickhouse.database

st.set_page_config(
    page_title="Get summaries of Hacker News posts enriched with Stackoverflow survey results, powered by LlamaIndex and CLickHouse",
    page_icon="🦙🚀", layout="centered", initial_sidebar_state="auto", menu_items=None)
st.title("💬HackBot powered by LlamaIndex 🦙 and ClickHouse 🚀")
st.info(
    "Check out the full [blog post](https://blog.streamlit.io/build-a-chatbot-with-custom-data-sources-powered-by-llamaindex/) for this app",
    icon="📃")
st.caption("A streamlit chatbot for Hacker News powered by 💬🦙 and ClickHouse 🚀")


@st.cache_resource
def load_embedding():
    return FastEmbedEmbedding(
        model_name="sentence-transformers/all-MiniLM-L6-v2",
        max_length=384,
    )


Settings.embed_model = load_embedding()

CLICKHOUSE_TEXT_TO_SQL_TMPL = (
    "Given an input question, first create a syntactically correct ClickHouse SQL "
    "query to run, then look at the results of the query and return the answer. "
    "You can order the results by a relevant column to return the most "
    "interesting examples in the database.\n\n"
    "Never query for all the columns from a specific table, only ask for a "
    "few relevant columns given the question.\n\n"
    "Pay attention to use only the column names that you can see in the schema "
    "description. "
    "Be careful to not query for columns that do not exist. "
    "Pay attention to which column is in which table. "
    "Also, qualify column names with the table name when needed. \n"
    "If needing to group on Array Columns use the ClickHouse function arrayJoin e.g. arrayJoin(columnName) \n"
    "For example, the following query identifies the most popular database:\n"
    "SELECT d, count(*) AS count FROM so_surveys GROUP BY "
    "arrayJoin(database_want_to_work_with) AS d ORDER BY count DESC LIMIT 1\n"
    "You are required to use the following format, each taking one line:\n\n"
    "Question: Question here\n"
    "SQLQuery: SQL Query to run\n"
    "SQLResult: Result of the SQLQuery\n"
    "Answer: Final answer here\n\n"
    "Only use tables listed below.\n"
    "{schema}\n\n"
    "Question: {query_str}\n"
    "SQLQuery: "
)

CLICKHOUSE_TEXT_TO_SQL_PROMPT = PromptTemplate(
    CLICKHOUSE_TEXT_TO_SQL_TMPL,
    prompt_type=PromptType.TEXT_TO_SQL,
)
CLICKHOUSE_CUSTOM_SUFFIX = """

The following is the datasource schema to work with. 
IMPORTANT: Make sure that filters are only used as needed and only suggest filters for fields in the data source.

Data Source:
```json
{info_str}
```

User Query:
{query_str}

Structured Request:
"""

CLICKHOUSE_VECTOR_STORE_QUERY_PROMPT_TMPL = PREFIX + EXAMPLES + CLICKHOUSE_CUSTOM_SUFFIX


@st.cache_resource
def clickhouse():
    common.set_setting('autogenerate_session_id', False)
    return clickhouse_connect.get_client(
        host=host, port=http_port, username=username, password=password,
        secure=secure, settings={"max_parallel_replicas": "3", "use_hedged_requests": "0",
                                 "allow_experimental_parallel_reading_from_replicas": "1"}
    )


def sql_auto_vector_query_engine():
    with st.spinner(text="Preparing indexes. This should take a few seconds. No time to make 🫖"):
        engine = create_engine(
            f'clickhouse+native://{username}:{password}@{host}:' +
            f'{native_port}/{database}?compression=lz4&secure={secure}'
        )
        sql_database = SQLDatabase(engine, include_tables=[stackoverflow_table], view_support=True)
        vector_store = ClickHouseVectorStore(clickhouse_client=clickhouse(), table=hackernews_table)
        vector_index = VectorStoreIndex.from_vector_store(vector_store)
        return sql_database, vector_index


def get_engine(min_length, score, min_date):
    sql_database, vector_index = sql_auto_vector_query_engine()

    nl_sql_engine = NLSQLTableQueryEngine(
        sql_database=sql_database,
        tables=[stackoverflow_table],
        text_to_sql_prompt=CLICKHOUSE_TEXT_TO_SQL_PROMPT,
        llm=OpenAI(model=open_ai_model)
    )
    vector_store_info = VectorStoreInfo(
        content_info="Social news posts and comments from users",
        metadata_info=[
            MetadataInfo(
                name="post_score", type="int", description="Score of the comment or post",
            ),
            MetadataInfo(
                name="by", type="str", description="the author or person who posted the comment",
            ),
            MetadataInfo(
                name="time", type="date", description="the time at which the post or comment was made",
            ),
        ]
    )

    vector_auto_retriever = VectorIndexAutoRetriever(
        vector_index, vector_store_info=vector_store_info, similarity_top_k=10,
        prompt_template_str=CLICKHOUSE_VECTOR_STORE_QUERY_PROMPT_TMPL, llm=OpenAI(model=open_ai_model),
        vector_store_kwargs={"where": f"length >= {min_length} AND post_score >= {score} AND time >= '{min_date}'"}
    )

    retriever_query_engine = RetrieverQueryEngine.from_args(vector_auto_retriever, llm=OpenAI(model=open_ai_model))

    sql_tool = QueryEngineTool.from_defaults(
        query_engine=nl_sql_engine,
        description=(
            "Useful for translating a natural language query into a SQL query over"
            f" a table: {stackoverflow_table}, containing the survey responses on"
            f" different types of technology users currently use and want to use"
        ),
    )
    vector_tool = QueryEngineTool.from_defaults(
        query_engine=retriever_query_engine,
        description=(
            f"Useful for answering semantic questions abouts users comments and posts"
        ),
    )

    return SQLAutoVectorQueryEngine(
        sql_tool, vector_tool, llm=OpenAI(model=open_ai_model)
    )


if "max_score" not in st.session_state.keys():
    client = clickhouse()
    st.session_state.max_score = int(
        client.query("SELECT max(post_score) FROM default.hackernews_llama").first_row[0])
    st.session_state.max_length = int(
        client.query("SELECT max(length) FROM default.hackernews_llama").first_row[0])
    st.session_state.min_date, st.session_state.max_date = client.query(
        "SELECT min(toDate(time)), max(toDate(time)) FROM default.hackernews_llama WHERE time != '1970-01-01 00:00:00'").first_row

if "messages" not in st.session_state:
    st.session_state.messages = [
        {"role": "assistant", "content": "Ask me a question about opinions on Hacker News and Stackoverflow!"}]

with st.sidebar:
    score = st.slider('Min Score', 0, st.session_state.max_score, value=0)
    min_length = st.slider('Min comment Length (tokens)', 0, st.session_state.max_length, value=20)
    min_date = st.date_input('Min comment date', value=st.session_state.min_date, min_value=st.session_state.min_date,
                             max_value=st.session_state.max_date)
    openai_api_key = st.text_input("Open API Key", key="chatbot_api_key", type="password")
    openai.api_key = openai_api_key
    "[Get an OpenAI API key](https://platform.openai.com/account/api-keys)"
    "[View the source code](https://github.com/clickhouse/examples/blob/main/Chatbot.py)"
    "[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/ClickHouse/examples?quickstart=1)"

if not openai_api_key:
    st.info("Please add your OpenAI API key to continue.")
    st.stop()

if prompt := st.chat_input(placeholder="Your question about Hacker News"):
    st.session_state.messages.append({"role": "user", "content": prompt})

for message in st.session_state.messages:  # Display the prior chat messages
    with st.chat_message(message["role"]):
        st.write(message["content"])

# If last message is not from assistant, generate a new response
if st.session_state.messages[-1]["role"] != "assistant":
    with st.chat_message("assistant"):
        with st.spinner("Thinking..."):
            response = str(get_engine(min_length, score, min_date).query(prompt))
            st.write(response)
            st.session_state.messages.append({"role": "assistant", "content": response})
