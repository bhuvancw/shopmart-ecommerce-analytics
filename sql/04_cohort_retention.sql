-- Cohort analysis: group customers by first purchase month, track return rate

-- QUERY 13: Full cohort retention table
-- CTE 1 first_purchase: when did each customer first buy?
-- CTE 2 all_activity: all purchases tagged with cohort month
-- CTE 3 cohort_counts: how many active per cohort per month offset
-- CTE 4 cohort_sizes: size of each cohort at Month 0
-- FINAL: retention % = active / cohort_size * 100

with first_purchase as (
    SELECT
        c.customer_unique_id,
        strftime('%Y-%m', min(o.order_purchase_timestamp)) as cohort_month
    from customers c
    join orders o
    on c.customer_id = o.customer_id
    where o.order_status = 'delivered'
    and o.order_purchase_timestamp is not null
    group by c.customer_unique_id
),
all_activity as (
    SELECT
        c.customer_unique_id,
        fp.cohort_month,
        -- Month offset: how far after first purchase is this order
        (CAST(strftime('%Y', o.order_purchase_timestamp) AS INT)
       - CAST(strftime('%Y', fp.cohort_month || '-01')   AS INT)) * 12
      + (CAST(strftime('%m', o.order_purchase_timestamp) AS INT)
       - CAST(strftime('%m', fp.cohort_month || '-01')   AS INT))
                                                           AS months_since_first
    FROM customers c
    JOIN orders o         ON c.customer_id         = o.customer_id
    JOIN first_purchase fp ON c.customer_unique_id = fp.customer_unique_id
    WHERE o.order_status = 'delivered'
    AND o.order_purchase_timestamp IS NOT NULL
),
cohort_counts AS (
    SELECT
        cohort_month,
        months_since_first,
        COUNT(DISTINCT customer_unique_id) AS active_users
    FROM all_activity
    GROUP BY cohort_month, months_since_first
),
cohort_sizes AS (
    SELECT cohort_month, active_users AS cohort_size
    FROM cohort_counts
    WHERE months_since_first = 0
)
SELECT
    cc.cohort_month,
    cs.cohort_size,
    cc.months_since_first                                 AS month_number,
    cc.active_users,
    ROUND(cc.active_users * 100.0 / cs.cohort_size, 2)  AS retention_pct
FROM cohort_counts cc
JOIN cohort_sizes  cs ON cc.cohort_month = cs.cohort_month
WHERE cc.cohort_month >= '2017-01'
  AND cc.months_since_first <= 12
ORDER BY cc.cohort_month, cc.months_since_first;

-- QUERY 14: New customer acquisition trend per month
WITH first_buys as(
    SELECT
        c.customer_unique_id,
        min(strftime('%Y-%m', o.order_purchase_timestamp)) as first_month
    FROM customers c
    JOIN orders o
    ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    first_month,
    count(customer_unique_id) AS new_customers,
    -- Running total of entire customer base over time
    sum(count(customer_unique_id)) OVER(ORDER BY first_month) AS cumulative_customers,
    round(
        (count(customer_unique_id) - 
        lag(count(customer_unique_id)) OVER(ORDER BY first_month)) * 100.0 /
        nullif(lag(count(customer_unique_id)) OVER(ORDER BY first_month), 0), 1) as mom_growth_pct
from first_buys
GROUP BY first_month
ORDER BY first_month;

-- QUERY 15: Month-over-month retention: of last month's buyers, who returned?

WITH monthly_buyers AS (
    SELECT DISTINCT
        c.customer_unique_id,
        strftime('%Y-%m', o.order_purchase_timestamp)     AS month
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
)
SELECT
    curr.month,
    COUNT(DISTINCT curr.customer_unique_id)                AS buyers_this_month,
    COUNT(DISTINCT prev.customer_unique_id)                AS returned_from_prev,
    ROUND(COUNT(DISTINCT prev.customer_unique_id) * 100.0
          / COUNT(DISTINCT curr.customer_unique_id), 2)    AS retention_rate_pct,
    COUNT(DISTINCT curr.customer_unique_id)
    - COUNT(DISTINCT prev.customer_unique_id)              AS new_buyers
FROM monthly_buyers curr
LEFT JOIN monthly_buyers prev
    ON  curr.customer_unique_id = prev.customer_unique_id
    -- date() with '-1 month' modifier shifts back one month in SQLite
    AND prev.month = strftime('%Y-%m',
            date(curr.month || '-01', '-1 month'))
WHERE curr.month >= '2017-01'
GROUP BY curr.month
ORDER BY curr.month;

-- QUERY 16: Days between purchases for repeat buyers (re-engagement timing)
WITH purchase_seq AS (
    SELECT
        c.customer_unique_id,
        o.order_purchase_timestamp,
        -- Number each purchase per customer in chronological order
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        )                                                  AS purchase_rank
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
),
gaps AS (
    SELECT
        CAST(julianday(curr.order_purchase_timestamp)
           - julianday(prev.order_purchase_timestamp) AS INTEGER) AS gap_days
    FROM purchase_seq curr
    JOIN purchase_seq prev
        ON  curr.customer_unique_id = prev.customer_unique_id
        AND curr.purchase_rank      = prev.purchase_rank + 1
    WHERE julianday(curr.order_purchase_timestamp)
        - julianday(prev.order_purchase_timestamp) > 0
)
SELECT
    CASE
        WHEN gap_days <= 30  THEN '1-Within 1 month'
        WHEN gap_days <= 60  THEN '2-One to 2 months'
        WHEN gap_days <= 90  THEN '3-Two to 3 months'
        WHEN gap_days <= 180 THEN '4-Three to 6 months'
        ELSE                      '5-Over 6 months'
    END                                                    AS gap_bucket,
    COUNT(*)                                               AS occurrences,
    ROUND(AVG(gap_days), 1)                               AS avg_days,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)     AS pct
FROM gaps
GROUP BY 1
ORDER BY 1;



