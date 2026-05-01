-- Advanced revenue: sellers, basket analysis, AOV, review impact

-- QUERY 20: Top 20 sellers by GMV with performance tier labels

SELECT
    s.seller_id,
    s.seller_state,
    count(DISTINCT o.order_id) AS orders_fulfilled,
    round(sum(oi.price), 2) AS gross_merchandise_value,
    round(avg(r.review_score), 2) AS avg_rating,
    round(avg(julianday(o.order_delivered_customer_date)
        - julianday(o.order_purchase_timestamp)), 2) AS avg_delivery_days,
    CASE
        WHEN avg(r.review_score) >= 4.5 THEN 'Gold Seller'
        WHEN avg(r.review_score) >= 4 THEN 'Silver Seller'
        WHEN avg(r.review_score) >= 3 THEN 'Standard'
        ELSE 'Needs Improvement'
    END AS seller_tier
FROM sellers s
JOIN order_items oi
ON s.seller_id = oi.seller_id
JOIN orders o
on oi.order_id = o.order_id
LEFT JOIN reviews r
ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_id, s.seller_state
HAVING count(DISTINCT oi.order_id) >= 50
ORDER BY gross_merchandise_value DESC
LIMIT 20;

-- QUERY 21: AOV percentile distribution for designing discount thresholds
WITH order_vals AS (
    SELECT o.order_id, SUM(p.payment_value) AS val
    FROM orders o
    JOIN payments p ON o.order_id = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id
)
SELECT
    ROUND(MIN(val), 2)                                     AS min_value,
    ROUND(AVG(val), 2)                                     AS mean_value,
    ROUND(MAX(val), 2)                                     AS max_value,
    COUNT(*)                                               AS total_orders,
    SUM(CASE WHEN val < 50   THEN 1 ELSE 0 END)           AS orders_under_50,
    SUM(CASE WHEN val < 100  THEN 1 ELSE 0 END)           AS orders_under_100,
    SUM(CASE WHEN val >= 500 THEN 1 ELSE 0 END)           AS orders_over_500
FROM order_vals;

-- QUERY 22: Category pairs bought together to power recommendations
-- a.category < b.category prevents (A,B) and (B,A) duplicate pairs

WITH order_cats AS (
    SELECT DISTINCT
        oi.order_id,
        COALESCE(t.category_english,
                 p.product_category_name) AS category
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN category_translation t
           ON p.product_category_name = t.category_portuguese   
    WHERE p.product_category_name IS NOT NULL
)
SELECT
    a.category                                             AS category_1,
    b.category                                             AS category_2,
    COUNT(*)                                               AS times_bought_together
FROM order_cats a
JOIN order_cats b
    ON  a.order_id = b.order_id
    AND a.category < b.category
GROUP BY a.category, b.category
HAVING COUNT(*) >= 20
ORDER BY times_bought_together DESC
LIMIT 15;

-- QUERY 23: Review score vs revenue — do happier customers spend more?
SELECT
    r.review_score,
    COUNT(DISTINCT o.order_id)                             AS orders,
    ROUND(SUM(p.payment_value), 2)                        AS revenue,
    ROUND(AVG(p.payment_value), 2)                        AS avg_order_value,
    ROUND(AVG(julianday(o.order_delivered_customer_date)
            - julianday(o.order_purchase_timestamp)), 1)   AS avg_delivery_days
FROM reviews r
JOIN orders   o ON r.order_id = o.order_id
JOIN payments p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
  AND r.review_score IS NOT NULL
GROUP BY r.review_score
ORDER BY r.review_score;

SELECT
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    p.payment_type,
    p.payment_installments,
    p.payment_value                                        AS revenue,
    oi.price                                               AS item_price,
    oi.freight_value,
    COALESCE(t.category_english,
             pr.product_category_name, 'Unknown')          AS category,
    r.review_score,
    CAST(julianday(o.order_delivered_customer_date)
       - julianday(o.order_purchase_timestamp) AS INTEGER) AS delivery_days,
    CASE WHEN o.order_delivered_customer_date
              > o.order_estimated_delivery_date
         THEN 1 ELSE 0 END                                 AS was_late,
    strftime('%Y-%m', o.order_purchase_timestamp)          AS order_month,
    CAST(strftime('%Y', o.order_purchase_timestamp) AS INT) AS order_year,
    CAST(strftime('%m', o.order_purchase_timestamp) AS INT) AS month_num,
    CAST(strftime('%H', o.order_purchase_timestamp) AS INT) AS order_hour,
    CASE CAST(strftime('%w', o.order_purchase_timestamp) AS INT)
        WHEN 0 THEN 'Sunday'    WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'   WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'  WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END                                                    AS day_of_week
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
LEFT JOIN payments p
    ON o.order_id = p.order_id AND p.payment_sequential = 1
LEFT JOIN order_items oi
    ON o.order_id = oi.order_id AND oi.order_item_id = 1
LEFT JOIN products pr    ON oi.product_id = pr.product_id
LEFT JOIN category_translation t
    ON pr.product_category_name = t.category_portuguese
LEFT JOIN reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
ORDER BY o.order_purchase_timestamp;