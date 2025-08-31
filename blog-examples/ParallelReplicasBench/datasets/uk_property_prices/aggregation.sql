SELECT
    county,
    town,
    district,
    formatReadableQuantity(count())    AS properties_sold,
    formatReadableQuantity(sum(price)) AS total_sales_value,
    formatReadableQuantity(avg(price)) AS average_sale_price
FROM uk_price_paid
GROUP BY
    county,
    town,
    district
ORDER BY sum(price) DESC
LIMIT 10