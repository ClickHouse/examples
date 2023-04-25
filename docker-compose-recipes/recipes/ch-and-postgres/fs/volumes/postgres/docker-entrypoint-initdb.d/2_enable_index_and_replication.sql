CREATE unique INDEX hacker_news_table_index on hacker_news(type, id);
ALTER TABLE hacker_news REPLICA IDENTITY USING INDEX hacker_news_table_index;
