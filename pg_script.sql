-- 1. Вывести распределение (количество) клиентов по сферам деятельности,
--    отсортировав результат по убыванию количества.

select
	c.job_industry_category,
	count(c.customer_id) as customers_count
from customer c 
where c.job_industry_category is not null
group by c.job_industry_category
order by customers_count desc;


-- 2. Найти общую сумму дохода (list_price*quantity) по всем подтвержденным заказам за каждый месяц
--    по сферам деятельности клиентов. Отсортировать результат по году, месяцу и сфере деятельности.

select
	date_trunc('year', o.order_date) as year_order,
	date_trunc('month', o.order_date) as month_order, 
	c.job_industry_category,
	sum(oi.item_list_price_at_sale * oi.quantity) as total
from customer c 
join orders o on o.customer_id = c.customer_id
join order_items oi on oi.order_id = o.order_id 
where o.order_status = 'Approved'
group by
	year_order,
	month_order,
	c.job_industry_category
order by
	year_order,
	month_order,
	c.job_industry_category;


-- 3. Вывести количество уникальных онлайн-заказов для всех брендов в рамках подтвержденных заказов клиентов из сферы IT.
--    Включить бренды, у которых нет онлайн-заказов от IT-клиентов, — для них должно быть указано количество 0.

select
    p.brand,
    count(distinct 
        case
	        when o.order_status = 'Approved' 
        		and o.online_order is true 
        		and c.job_industry_category = 'IT'
        	then o.order_id
        end
    ) as unique_online_orders
from product p
left join order_items oi on p.product_id = oi.product_id
left join orders o on oi.order_id = o.order_id
left join customer c on o.customer_id = c.customer_id
group by p.brand
order by p.brand;


-- 4. Найти по всем клиентам: сумму всех заказов (общего дохода), максимум, минимум и количество заказов,
--    а также среднюю сумму заказа по каждому клиенту. Отсортировать результат по убыванию суммы всех заказов и количества заказов.
--    Выполнить двумя способами: используя только GROUP BY и используя только оконные функции. Сравнить результат.

-- 4.1 Используя только GROUP BY
with order_totals as (
	select 
		o.customer_id,
		o.order_id,
		sum(oi.quantity * oi.item_list_price_at_sale) as total
	from orders o 
	join order_items oi on o.order_id = oi.order_id 
	group by o.customer_id, o.order_id
)
select
	distinct ot.customer_id,
    sum(ot.total) as total_income,
    max(ot.total) as max_order_price,
    min (ot.total) as min_order_price,
    count(ot.order_id) as orders_count,
    avg(ot.total) as avg_order_price
from order_totals ot
group by ot.customer_id
order by total_income desc, orders_count desc;

-- 4.2 Используя только оконные функции

with items_total as (
	select 
		o.customer_id,
		o.order_id,
		oi.quantity * oi.item_list_price_at_sale as total
	from orders o 
	join order_items oi on o.order_id = oi.order_id 
),
orders_total as (
	select 
		it.customer_id,
		it.order_id,
		sum(it.total) over (partition by it.order_id) as order_total
	from items_total it
)
select 
    distinct ot.customer_id,
    sum(ot.order_total) over (partition by ot.customer_id) as total_income,
    max(ot.order_total) over (partition by ot.customer_id) as max_order_price,
    min(ot.order_total) over (partition by ot.customer_id) as min_order_price,
    count(ot.order_id) over (partition by ot.customer_id) as orders_count,
    avg(ot.order_total) over (partition by ot.customer_id) as avg_order_price
from orders_total ot
order by total_income desc, orders_count desc;


-- 5. Найти имена и фамилии клиентов с топ-3 минимальной и топ-3 максимальной суммой транзакций за весь период
--    (учесть клиентов, у которых нет заказов)

with customers_total as (
    select 
        c.customer_id,
        c.first_name,
        c.last_name,
        coalesce(sum(oi.quantity * oi.item_list_price_at_sale), 0) as total
    from customer c 
    left join orders o on c.customer_id = o.customer_id
    left join order_items oi on o.order_id = oi.order_id 
    group by 
    	c.customer_id,
    	c.first_name,
    	c.last_name
)
select * from (
    select *
    from customers_total
    order by total desc
    limit 3
)
union all
select * from (
    select *
    from customers_total
    where total > 0
    order by total asc
    limit 3
)
order by total;


-- 6. Вывести только вторые транзакции клиентов (если они есть).
--    Решить с помощью оконных функций. Если у клиента меньше двух транзакций, он не должен попасть в результат

with numbered_orders as (
    select
        *,
        row_number() over (partition by customer_id order by order_date) as order_num
    from orders
)
select *
from numbered_orders
where order_num = 2
order by order_id;


-- 7. Вывести имена, фамилии и профессии клиентов,
--    а также длительность максимального интервала (в днях) между двумя последовательными заказами.
--    Исключить клиентов, у которых только один или меньше заказов.

with orders_with_prev_date as (
    select
        o.customer_id,
        c.first_name,
        c.last_name,
        c.job_title,
        o.order_date,
        lag(o.order_date) over (partition by o.customer_id order by o.order_date) as prev_order_date
    from orders o
    join customer c on o.customer_id = c.customer_id
),
order_intervals as (
    select
        customer_id,
        first_name,
        last_name,
        job_title,
        order_date - prev_order_date as days_between_orders
    from orders_with_prev_date
    where prev_order_date is not null
),
max_intervals as (
    select
        customer_id,
        first_name,
        last_name,
        job_title,
        max(days_between_orders) as max_interval_days
    from order_intervals
    group by 
    	customer_id,
    	first_name,
    	last_name,
    	job_title
)
select
    first_name,
    last_name,
    job_title,
    max_interval_days
from max_intervals
order by max_interval_days desc;

-- 8. Найти топ-5 клиентов (по общему доходу) в каждом сегменте благосостояния (wealth_segment).
--    Вывести имя, фамилию, сегмент и общий доход. Если в сегменте менее 5 клиентов, вывести всех.

with customers_total as (
    select 
        c.customer_id,
        c.first_name,
        c.last_name,
        c.wealth_segment,
        coalesce(sum(oi.quantity * oi.item_list_price_at_sale), 0) as orders_total
    from customer c 
    left join orders o on c.customer_id = o.customer_id
    left join order_items oi on o.order_id = oi.order_id 
    group by 
    	c.customer_id,
    	c.first_name,
    	c.last_name,
    	c.wealth_segment
),
customers_range_by_segments as (
    select
        *,
        row_number() over (partition by wealth_segment order by orders_total desc) as range_by_segment
    from customers_total
)
select
    first_name,
    last_name,
    wealth_segment,
    orders_total
from customers_range_by_segments
where range_by_segment <= 5
order by wealth_segment, orders_total desc;


