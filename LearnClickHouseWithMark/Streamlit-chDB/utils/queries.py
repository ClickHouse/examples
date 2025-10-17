tariffs_query = """
    SELECT
        startDate AS rawStartDate,
        toString(startDate) AS startDate,
        endDate AS rawEndDate,
        toString(endDate) AS endDate,
        sumIf(standingCharge, energyType = 'gas') AS gasStandingCharge,
        sumIf(unitRate, energyType = 'gas') AS gasUnitRate,
        sumIf(standingCharge, energyType = 'electricity') AS elecStandingCharge,
        sumIf(unitRate, energyType = 'electricity') AS elecUnitRate
    FROM `data/tariffs.csv`
    GROUP BY ALL
    ORDER BY startDate ASC
    """

def energy_usage_for_day_query(day):
    return f"""
FROM (
    SELECT energyType,
           toDate(epochTimestamp) AS day,
           sum(toDecimal32(kWh, 6)) AS totalUsage
    FROM energy.usage
    GROUP BY ALL
) as u
JOIN energy.tariffs AS t
ON t.energyType = u.energyType AND t.day = u.day
SELECT energyType, standingCharge, unitRate, totalUsage, 
       sum(toDecimal32((standingCharge + (unitRate * totalUsage)), 5)) AS rawCost,
       rawCost/100 AS cost
WHERE day = '{day.strftime("%Y-%m-%d")}'
GROUP BY ALL
"""

energy_usage_query = """
FROM (
    SELECT energyType,
           toDate(epochTimestamp) AS day,
           sum(toDecimal32(kWh, 6)) AS totalUsage
    FROM energy.usage
    GROUP BY ALL
) as u
JOIN energy.tariffs AS t
ON t.energyType = u.energyType AND t.day = u.day
SELECT toString(day) AS day, energyType, totalUsage, standingCharge, unitRate,
    toDecimal32((standingCharge + (unitRate * totalUsage)), 2) / 100 AS cost
ORDER BY day DESC, energyType
"""
