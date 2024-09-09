-- Create a database
CREATE DATABASE IF NOT EXISTS web_analytics;

-- Switch to the database
USE web_analytics;

-- Create a table for storing website logs
CREATE TABLE IF NOT EXISTS website_logs (
    event_time DateTime DEFAULT now(),   -- Timestamp of the event
    user_id UInt32,                      -- User identifier
    session_id UUID,                     -- Session identifier
    page_url String,                     -- Visited page URL
    referrer_url String,                 -- Referrer URL
    device_type Enum8('desktop' = 1, 'mobile' = 2, 'tablet' = 3),  -- Device type
    browser String,                      -- Browser used by the visitor
    os String,                           -- Operating system used by the visitor
    country String,                      -- Country from where the user accessed the site
    duration UInt32,                     -- Time spent on page in seconds
    click_count UInt16                   -- Number of clicks on the page
)
ENGINE = MergeTree() 
PARTITION BY toYYYYMM(event_time)  -- Partition data by month
ORDER BY (event_time, user_id)      -- Order data by event time and user
TTL event_time + INTERVAL 1 YEAR    -- Set time to live for 1 year, to automatically delete old data
SETTINGS index_granularity = 8192;  -- Index granularity setting
