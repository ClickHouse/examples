SELECT
    formatReadableQuantity(sum(price)) AS total_revenue,
    formatReadableQuantity(avg(price)) AS avg_price
FROM uk_price_paid