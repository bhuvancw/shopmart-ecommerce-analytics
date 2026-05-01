-- RFM: Recency, Frequency, Monetary — segments customers by value and behavior

-- QUERY 17: Full RFM segmentation with labeled segments
-- PERCENT_RANK() used instead of NTILE() which SQLite doesn't support

WITH ref AS (
    SELECT
        max(date(order_purchase_timestamp)) AS ref_date
    FROM orders 
),
rfm_raw AS (
    SELECT
        c.customer_unique_id,
        CAST(julianday((SELECT ref_date FROM ref))
         - julianday(max(date(o.order_purchase_timestamp)))
         AS integer) AS recency_days,
        count(DISTINCT o.order_id) AS frequency,
        round(sum(p.payment_value), 2) AS monetary
    FROM customers c
    JOIN orders o
    ON c.customer_id = o.customer_id
    JOIN payments p ON o.order_id    = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_scored AS (
    SELECT *,
        -- Recency score 5 = most recent (reversed because lower days = better)
        6 - MAX(1, MIN(5, CAST(
                PERCENT_RANK() OVER (ORDER BY recency_days DESC) * 5
            AS INTEGER) + 1))                              AS r_score,
        -- Frequency score 5 = bought most often
        MAX(1, MIN(5, CAST(
                PERCENT_RANK() OVER (ORDER BY frequency ASC) * 5
            AS INTEGER) + 1))                              AS f_score,
        -- Monetary score 5 = spent the most
        MAX(1, MIN(5, CAST(
                PERCENT_RANK() OVER (ORDER BY monetary ASC) * 5
            AS INTEGER) + 1))                              AS m_score
    FROM rfm_raw
),
rfm_labeled AS (
    SELECT *,
        CASE
            WHEN r_score>=4 AND f_score>=4 AND m_score>=4 THEN 'Champion'
            WHEN r_score>=3 AND f_score>=3 AND m_score>=3 THEN 'Loyal Customer'
            WHEN r_score>=4 AND f_score<=2               THEN 'Promising New'
            WHEN r_score=3  AND f_score>=2               THEN 'Needs Attention'
            WHEN r_score<=2 AND f_score>=3 AND m_score>=3 THEN 'At Risk'
            WHEN r_score<=2 AND f_score>=4               THEN 'Cannot Lose Them'
            WHEN r_score<=2 AND f_score<=2 AND m_score<=2 THEN 'Lost Customer'
            ELSE                                              'Low Value'
        END                                                AS segment
    FROM rfm_scored
)

SELECT
    segment,
    COUNT(customer_unique_id)                              AS customers,
    ROUND(COUNT(customer_unique_id) * 100.0
          / SUM(COUNT(customer_unique_id)) OVER(), 2)     AS pct_of_customers,
    ROUND(AVG(recency_days), 0)                           AS avg_recency_days,
    ROUND(AVG(frequency), 2)                              AS avg_orders,
    ROUND(AVG(monetary), 2)                               AS avg_revenue,
    ROUND(SUM(monetary), 2)                               AS total_revenue,
    ROUND(SUM(monetary) * 100.0
          / SUM(SUM(monetary)) OVER(), 2)                  AS revenue_share_pct
FROM rfm_labeled
GROUP BY segment
ORDER BY total_revenue DESC;

-- QUERY 18: Customer LTV distribution to understand spending tiers

WITH ltv AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id)      AS total_orders,
        ROUND(SUM(p.payment_value), 2)  AS lifetime_value
    FROM customers c
    JOIN orders   o ON c.customer_id = o.customer_id
    JOIN payments p ON o.order_id    = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    CASE
        WHEN lifetime_value >= 1000 THEN '1-Premium (R$1000+)'
        WHEN lifetime_value >= 500  THEN '2-High (R$500-999)'
        WHEN lifetime_value >= 200  THEN '3-Mid (R$200-499)'
        WHEN lifetime_value >= 100  THEN '4-Low-Mid (R$100-199)'
        ELSE                             '5-Low (under R$100)'
    END                                                    AS ltv_segment,
    COUNT(*)                                               AS customers,
    ROUND(AVG(lifetime_value), 2)                         AS avg_ltv,
    ROUND(SUM(lifetime_value), 2)                         AS total_revenue
FROM ltv
GROUP BY 1
ORDER BY 1;

-- QUERY 19: New vs returning customer revenue split
-- Healthy = 30% or more revenue from returning customers

WITH ranked AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        p.payment_value,
        -- ROW_NUMBER ranks each purchase per customer by date
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        )                                                  AS purchase_num
    FROM customers c
    JOIN orders   o ON c.customer_id = o.customer_id
    JOIN payments p ON o.order_id    = p.order_id
    WHERE o.order_status = 'delivered'
)
SELECT
    CASE WHEN purchase_num=1 THEN 'New Customer'
         ELSE 'Returning Customer' END                     AS customer_type,
    COUNT(DISTINCT customer_unique_id)                     AS customers,
    COUNT(DISTINCT order_id)                               AS orders,
    ROUND(SUM(payment_value), 2)                          AS revenue,
    ROUND(AVG(payment_value), 2)                          AS avg_order_value,
    ROUND(SUM(payment_value) * 100.0
          / SUM(SUM(payment_value)) OVER(), 2)             AS revenue_share_pct
FROM ranked
GROUP BY 1;