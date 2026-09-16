SELECT count() AS stored_rows, uniqExact(event_id) AS distinct_events
FROM link_shortener.click_events;
