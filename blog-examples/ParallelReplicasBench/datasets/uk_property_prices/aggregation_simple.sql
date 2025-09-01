SELECT
    town,
    sum(price) AS total_revenue
FROM uk_price_paid
GROUP BY town
ORDER BY total_revenue DESC
LIMIT 3