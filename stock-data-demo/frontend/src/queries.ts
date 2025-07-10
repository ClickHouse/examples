export const liveTableQuery = `
    with 
{syms: Array(String)} as symbols,
toDate(now('America/New_York')) as curr_day,
trades_info as (
    select
        sym,
        argMax(p, t) as last_price,
        round(((last_price - (argMinIf(p, t, fromUnixTimestamp64Milli(t, 'America/New_York') >= curr_day))) / (argMinIf(p, t, fromUnixTimestamp64Milli(t, 'America/New_York') >= curr_day))) * 100, 2) as change_pct,
        sum(s) as total_volume,
        max(t) as latest_t
    from
        trades
    where
        toDate(fromUnixTimestamp64Milli(t, 'America/New_York')) = curr_day
        and sym in symbols
    group by
        sym
    order by
        sym asc
),
quotes_info as (
    select
        sym,
        argMax(bp, t) as bid,
        argMax(ap, t) as ask,
        max(t) as latest_t
    from
        quotes
    where
        toDate(fromUnixTimestamp64Milli(t, 'America/New_York')) = curr_day
        and sym in symbols
    group by
        sym
    order by
        sym asc
)
select
    t.sym as ticker,
    t.last_price as last,
    q.bid as bid,
    q.ask as ask,
    t.change_pct as change,
    t.total_volume as volume,
    toUnixTimestamp64Milli(now64()) - greatest(t.latest_t, q.latest_t) as latency
from
    trades_info as t
    left join quotes_info as q on t.sym = q.sym
`;

export const tickerListQuery = `
with 
toDate(now('America/New_York')) as curr_day
    select
        sym,
        argMax(p, t) as last_price,
        round(((last_price - (argMinIf(p, t, fromUnixTimestamp64Milli(t, 'America/New_York') >= curr_day))) / (argMinIf(p, t, fromUnixTimestamp64Milli(t, 'America/New_York') >= curr_day))) * 100, 2) as change_pct
    from
        trades
    where
        toDate(fromUnixTimestamp64Milli(t, 'America/New_York')) = curr_day
    group by
        sym
    order by
        sym asc

`;

export const tickerPriceTimerSeriesQuery = `
select
    toUnixTimestamp64Milli(
        toDateTime64(toStartOfInterval(
            fromUnixTimestamp64Milli(t), interval 15 second
        ),3)
    ) as x,
    argMin(p, t) as o,
    max(p) as h,
    min(p) as l,
    argMax(p, t) as c,
    sum(s) as v
from
    trades
where
    x < toUnixTimestamp64Milli(toDateTime64(toStartOfInterval(now(), interval 1 second),3))
    and x > toUnixTimestamp64Milli(now64() - interval 5 minute)
    and (toInt64({last: String}) = 0 or x > toInt64({last: String}))
    and sym = {sym: String}
group by
    x
order by
    x asc
`;

export const minutePriceHistoricQuery = `
select
toUnixTimestamp64Milli(toDateTime64(toStartOfInterval(fromUnixTimestamp64Milli(t), interval 1 minute), 3)) as x,
argMin(p, t) as o,
max(p) as h,
min(p) as l,
argMax(p, t) as c,
sum(s) as v
from trades
where x > toUnixTimestamp64Milli(now64() - interval 30 minute)
and sym = {sym: String}
group by x order by x asc
`;

export const hourPriceHistoricQuery = `
select
toUnixTimestamp64Milli(toDateTime64(toStartOfInterval(fromUnixTimestamp64Milli(t), interval 2 minute), 3)) as x,
argMin(p, t) as o,
max(p) as h,
min(p) as l,
argMax(p, t) as c,
sum(s) as v
from trades
where x > toUnixTimestamp64Milli(now64() - interval 1 hour)
and sym = {sym: String}
group by x order by x asc
`;

export const dayPriceHistoricQuery = `
select
toUnixTimestamp64Milli(toDateTime64(toStartOfInterval(fromUnixTimestamp64Milli(t), interval 1 hour), 3)) as x,
argMin(p, t) as o,
max(p) as h,
min(p) as l,
argMax(p, t) as c,
sum(s) as v
from trades
where x > toUnixTimestamp64Milli(now64() - interval 1 day)
and sym = {sym: String}
group by x order by x asc
`;

export const popularStocksQuery = `
select sym from trades 
where t > toUnixTimestamp64Milli(now64() - interval 5 minute) 
group by 1 
order by count() desc 
limit 10
`;
