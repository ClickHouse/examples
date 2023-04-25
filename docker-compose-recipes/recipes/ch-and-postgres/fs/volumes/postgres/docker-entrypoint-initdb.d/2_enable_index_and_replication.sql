CREATE unique INDEX hacker_news_table_index on hacker_news(id, type);
ALTER TABLE hacker_news REPLICA IDENTITY USING INDEX hacker_news_table_index;
