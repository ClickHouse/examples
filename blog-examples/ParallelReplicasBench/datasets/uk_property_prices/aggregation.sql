SELECT
    county,
    town,
    district,
    count()    AS properties_sold,
    sum(price) AS total_sales_value,
    avg(price) AS average_sale_price
FROM uk_price_paid
GROUP BY
    county,
    town,
    district
ORDER BY sum(price) DESC
LIMIT 10