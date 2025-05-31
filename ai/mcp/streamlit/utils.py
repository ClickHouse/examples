import streamlit as st
from agno.run.response import RunEvent, RunResponse

async def as_stream(response):
  async for chunk in response:
    if isinstance(chunk, RunResponse) and isinstance(chunk.content, str):
      if chunk.event == RunEvent.run_response:
        yield chunk.content

def apply_styles():
  st.markdown("""
  <style>
  hr.divider {
  background-color: white;
  margin: 0;
  }
  </style>
  <hr class='divider' />""", unsafe_allow_html=True)