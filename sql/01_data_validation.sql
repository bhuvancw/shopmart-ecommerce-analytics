-- CHECK 1: Row counts in all tables

select 'customers' as tbl, count(*) as rows from customers union ALL
select 'order items', count(*) from order_items union ALL
select 'orders', count(*) from orders union ALL
select 'category_translation', count(*) from category_translation union ALL
select 'payments', count(*) from payments union ALL
select 'products', count(*) from products union ALL
select 'reviews', count(*) from reviews union ALL
select 'sellers', count(*) from sellers;

-- CHECK 2: Order status distribution to understand data split

SELECT
    order_status,
    count(*) as order_count,
    round(count(*) * 100.0 / sum(count(*)) over(), 2) as pct_of_total
from orders
group by order_status
order by order_count desc;

-- CHECK 3: Date range so we know our analysis time window

SELECT
    min(date(order_purchase_timestamp)) as earliest_order,
    max(date(order_purchase_timestamp)) as latest_order,
    count(distinct strftime('%Y-%m', order_purchase_timestamp)) as active_months
from orders
where order_purchase_timestamp is not null;

-- CHECK 4: Duplicate order IDs (must be zero for clean revenue)

SELECT
    count(order_id) as total_orders,
    count(distinct order_id) as unique_orders,
    count(order_id) - count(distinct order_id) as duplicates
from orders;

-- CHECK 5: Orders with no matching customer (orphan records)

SELECT
    count(*) as orders_missing_customers
from orders o
left join customers c
on o.customer_id = c.customer_id
where c.customer_id is null;

-- CHECK 6: Payment sanity — no negatives or zeros in revenue

SELECT
    count(*) as total_rows,
    sum(case when payment_value <= 0 then 1 else 0 end) as zero_or_negative,
    min(payment_value) as min_payment,
    max(payment_value) as max_payment,
    round(avg(payment_value),2) as avg_payment,
    round(sum(payment_value),2) as total_revenue
from payments;

-- CHECK 7: Review scores must only be 1, 2, 3, 4, or 5

SELECT
    review_score,
    count(*) as count
from reviews
where review_score is not null
group by review_score;

-- CHECK 8: Delivery time sanity (negative = data error)
-- julianday() in SQLite = DATEDIFF() in MS SQL

SELECT
    round(min(julianday(order_delivered_customer_date)
            - julianday(order_purchase_timestamp)), 1) as min_days,
    round(max(julianday(order_delivered_customer_date)
            - julianday(order_purchase_timestamp)), 1) as max_days,
    round(avg(julianday(order_delivered_customer_date)
            - julianday(order_purchase_timestamp)), 1) as avg_days,
    sum(case when julianday(order_delivered_customer_date)
            - julianday(order_purchase_timestamp) < 0 then 1 else 0 end) as negative_days
from orders
where order_status = 'delivered'
    and order_purchase_timestamp is not NULL
    and order_delivered_customer_date is not NULL;