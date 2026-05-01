-- QUERY 1: Overall KPIs across the entire business

SELECT
    count(distinct o.order_id) as total_orders,
    count(distinct c.customer_unique_id) as unique_customers,
    round(sum(p.payment_value), 2) as total_revenue_blr,
    rOUND(AVG(p.payment_value), 2)         AS avg_order_value,
    ROUND(MIN(p.payment_value), 2)         AS min_order_value,
    ROUND(MAX(p.payment_value), 2)         AS max_order_value
from orders o
join customers c
on o.customer_id = c.customer_id
join payments p
on o.order_id = p.order_id
where o.order_status = 'delivered';

-- QUERY 2: Monthly revenue with MoM growth using LAG window function

with monthly as 
(
    SELECT
        strftime('%Y-%m', o.order_purchase_timestamp) as month,
        count(distinct o.order_id) as orders,
        COUNT(DISTINCT c.customer_unique_id)              AS customers,
        ROUND(SUM(p.payment_value), 2)                   AS revenue,
        ROUND(AVG(p.payment_value), 2)                   AS avg_order_value
    from orders o
    join customers c
    on o.customer_id = c.customer_id
    join payments p
    on o.order_id = p.order_id
    where o.order_status = 'delivered'
    and o.order_purchase_timestamp is not NULL
    group by strftime('%Y-%m', o.order_purchase_timestamp)
)

SELECT
    month,
    orders,
    customers,
    revenue,
    avg_order_value,
    lag(revenue) over(order by month) as prev_month_revenue,
    round((revenue - lag(revenue) over(order by month)) * 100.0
        / nullif(lag(revenue) over(order by month), 0), 1) as mom_growth_pct,
    round(sum(revenue) over(order by month), 2) as cumulative_revenue
from monthly
order by month;

-- QUERY 3: Top 10 categories by revenue with share percentage
WITH category_revenue AS (
    SELECT
        coalesce(t.category_english, p.product_category_name, 'Unknown') as category,
        sum(oi.price) as total_revenue
    FROM products p
    LEFT JOIN category_translation t
        ON t.category_portuguese = p.product_category_name
    JOIN order_items oi
        ON p.product_id = oi.product_id
    JOIN orders o 
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY category
)

SELECT
    category,
    total_revenue,
    round(
        total_revenue * 100.0 /
        sum(total_revenue) over (),
        2
    ) as revenue_share_pct
FROM category_revenue
ORDER BY total_revenue DESC
LIMIT 10;

-- QUERY 4: Customer repeat purchase rate — the most critical retention metric
-- Industry benchmark = 20-40%; below 5% = serious problem

with customer_orders as 
(
    SELECT
        c.customer_unique_id,
        count(distinct o.order_id) as total_orders
    from customers c
    join orders o
    on c.customer_id = o.customer_id
    group by c.customer_unique_id
)
SELECT
    total_orders as purchases,
    count(customer_unique_id) as customers,
    round(count(customer_unique_id) * 100.0
        / sum(count(customer_unique_id)) over(), 2) as pct_of_purchases,
    ROUND(SUM(COUNT(customer_unique_id)) OVER (ORDER BY total_orders) * 100.0
        / SUM(COUNT(customer_unique_id)) OVER(), 2) AS cumulative_pct
from customer_orders
GROUP BY total_orders
order by total_orders;

-- QUERY 5: Revenue by state to identify top geographic markets
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id)              AS orders,
    COUNT(DISTINCT c.customer_unique_id)     AS customers,
    ROUND(SUM(p.payment_value), 2)          AS revenue,
    ROUND(AVG(p.payment_value), 2)          AS avg_order_value,
    RANK() OVER (ORDER BY SUM(p.payment_value) DESC) AS rank
FROM customers c
JOIN orders   o ON c.customer_id = o.customer_id
JOIN payments p ON o.order_id    = p.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY revenue DESC;

-- QUERY 6: Payment method breakdown — which methods drive most revenue
SELECT
    p.payment_type,
    COUNT(DISTINCT p.order_id)                             AS orders,
    ROUND(SUM(p.payment_value), 2)                        AS revenue,
    ROUND(AVG(p.payment_value), 2)                        AS avg_order_value,
    ROUND(AVG(CAST(p.payment_installments AS REAL)), 1)   AS avg_installments,
    ROUND(COUNT(DISTINCT p.order_id) * 100.0
          / SUM(COUNT(DISTINCT p.order_id)) OVER(), 2)    AS order_share_pct
FROM payments p
JOIN orders o ON p.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY p.payment_type
ORDER BY orders DESC;

-- QUERY 7: Orders by day of week to find best campaign timing
SELECT
    case cast(strftime('%w', order_purchase_timestamp) as integer)
        when 0 then '7-Sunday'
        when 1 then '1-Monday'
        when 2 then '2-Tuesday'
        when 3 then '3-Wednesday'
        when 4 then '4-Thursday'
        when 5 then '5-Friday'
        when 6 then '6-Saturday'
    end as day_of_week,
    COUNT(DISTINCT order_id)                               AS total_orders,
    ROUND(COUNT(DISTINCT order_id) * 100.0
          / SUM(COUNT(DISTINCT order_id)) OVER(), 2)       AS pct_of_orders
FROM orders
WHERE order_status = 'delivered'
  AND order_purchase_timestamp IS NOT NULL
GROUP BY strftime('%w', order_purchase_timestamp)
ORDER BY day_of_week;













































