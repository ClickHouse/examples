SELECT
    county,
    toStartOfQuarter(date) AS qtr,
    countDistinct(street) AS distinct_streets_with_sales
FROM uk_price_paid
GROUP BY county, qtr
ORDER BY qtr, county;