-- QUERY 8: Full order funnel — Created > Approved > Shipped > Delivered

SELECT
    count(distinct order_id) as stage1_created,
    count(distinct CASE
        when order_status != 'canceled'
        and order_approved_at is not null
        then order_id end) as stage2_approved,
    count(distinct CASE
        when order_status in ('shipped', 'delivered')
        then order_id end) as stage3_shipped,
    count(distinct CASE
        when order_status = 'delivered'
        then order_id end) as stage4_delivered,
    count(distinct CASE
        when order_status = 'canceled'
        then order_id end) as canceled,
    round(
        count(DISTINCT case when order_status = 'delivered'
            then order_id end) * 100.0
        / count(distinct order_id), 2) as overall_conversion_pct
from orders;

-- QUERY 9: Monthly funnel to track if conversion is improving or declining

SELECT
    strftime('%Y-%m', order_purchase_timestamp)            AS month,
    COUNT(DISTINCT order_id)                               AS created,
    COUNT(DISTINCT CASE WHEN order_status='delivered'
          THEN order_id END)                               AS delivered,
    COUNT(DISTINCT CASE WHEN order_status='canceled'
          THEN order_id END)                               AS canceled,
    ROUND(COUNT(DISTINCT CASE WHEN order_status='delivered'
          THEN order_id END) * 100.0
          / COUNT(DISTINCT order_id), 2)                   AS delivery_rate_pct,
    ROUND(COUNT(DISTINCT CASE WHEN order_status='canceled'
          THEN order_id END) * 100.0
          / COUNT(DISTINCT order_id), 2)                   AS cancel_rate_pct
FROM orders
WHERE order_purchase_timestamp IS NOT NULL
GROUP BY strftime('%Y-%m', order_purchase_timestamp)
ORDER BY month;

-- QUERY 10: Delivery speed vs review score — faster = happier customers

SELECT
    CASE
        WHEN CAST(julianday(order_delivered_customer_date)
                - julianday(order_purchase_timestamp) AS INTEGER) <= 3
            THEN '1-Express (<=3 days)'
        WHEN CAST(julianday(order_delivered_customer_date)
                - julianday(order_purchase_timestamp) AS INTEGER) <= 7
            THEN '2-Fast (4-7 days)'
        WHEN CAST(julianday(order_delivered_customer_date)
                - julianday(order_purchase_timestamp) AS INTEGER) <= 14
            THEN '3-Standard (8-14 days)'
        WHEN CAST(julianday(order_delivered_customer_date)
                - julianday(order_purchase_timestamp) AS INTEGER) <= 30
            THEN '4-Slow (15-30 days)'
        ELSE '5-Very Slow (30+ days)'
    END                                                    AS delivery_bucket,
    COUNT(DISTINCT o.order_id)                             AS orders,
    ROUND(AVG(r.review_score), 2)                         AS avg_review_score,
    ROUND(COUNT(DISTINCT o.order_id) * 100.0
          / SUM(COUNT(DISTINCT o.order_id)) OVER(), 2)     AS pct_of_orders
FROM orders o
LEFT JOIN reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_purchase_timestamp IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- QUERY 11: Late vs on-time delivery and the impact on satisfaction

SELECT
    CASE
        when o.order_delivered_customer_date <= o.order_estimated_delivery_date
        then "On Time"
        else 'Late'
    end as delivery_status,
    count(distinct o.order_id) as orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    ROUND(AVG(p.payment_value), 2) AS avg_order_value,
    round(avg(julianday(o.order_delivered_customer_date) 
        - julianday(o.order_purchase_timestamp)), 1) as avg_delivery_days
from orders o
join reviews r
on o.order_id = r.order_id
join payments p
on o.order_id = p.order_id
where o.order_status = 'delivered'
and o.order_estimated_delivery_date is not null
and o.order_delivered_customer_date is not null
group by 1;

-- QUERY 12: Cancellation rate by category to spot quality problems

WITH order_cats as (
    SELECT DISTINCT
        o.order_id,
        o.order_status,
        coalesce(t.category_english, p.product_category_name) as category
    from orders o
    join order_items oi on o.order_id = oi.order_id
    join products p on p.product_id = oi.product_id
    left join category_translation t on p.product_category_name = t.category_english
    where p.product_category_name is not null
)
SELECT
    category,
    count(order_id) as total_orders,
    sum(case when order_status = 'canceled' then 1 else 0 end) as canceled,
    round(sum(case when order_status = 'canceled' then 1 else 0 end) *100
            / count(order_id), 2) as cancel_rate_pct
from order_cats
where category is not null
group by category
order by cancel_rate_pct DESC
limit 15;



