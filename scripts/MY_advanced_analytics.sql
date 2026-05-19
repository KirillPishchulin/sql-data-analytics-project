-- Historical analysis

SELECT	
	YEAR(order_date) order_year,
	MONTH(order_date) order_month,
	FORMAT(SUM(sales_amount), 'N', 'en-gb') AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date), MONTH(order_date)
ORDER BY 1 ASC, 2 ASC;


SELECT	
	DATETRUNC(month, order_date) AS year_month_sales,
	FORMAT(SUM(sales_amount), 'N', 'en-gb') AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(month, order_date)
ORDER BY DATETRUNC(month, order_date);


-- Cumulative analysis
-- Total Sales of each month + running total sales

SELECT 
	*, 
	SUM(total_sales) OVER(PARTITION BY order_year ORDER BY order_year_month) as running_total_sales,
	AVG(avg_price) OVER(PARTITION BY order_year ORDER BY order_year_month) as moving_avg_price
FROM (
	SELECT	
		YEAR(order_date) AS order_year,
		DATETRUNC(month, order_date) AS order_year_month,
		SUM(sales_amount) AS total_sales,
		AVG(price) as avg_price

	FROM gold.fact_sales
	WHERE order_date IS NOT NULL
	GROUP BY YEAR(order_date), DATETRUNC(month, order_date)
) t
ORDER BY order_year_month;

-- Performance analysis

-- Analyze the yearly performance of proudcts by comparing thier sales 
-- to both the averae sales performance of the product and the previus year's sales
WITH 
yearly_product_sales AS (
	SELECT 
		YEAR(s.order_date) order_year,
		p.product_name,
		SUM(s.sales_amount) current_sales
	FROM gold.fact_sales s
	LEFT JOIN gold.dim_products p
	ON p.product_key = s.product_key
	WHERE s.order_date IS NOT NULL
	GROUP BY YEAR(s.order_date), p.product_name
),
avg_and_prev_year_sales AS(
	SELECT 
		order_year,
		product_name,
		current_sales,
		AVG(current_sales) OVER(PARTITION BY product_name) AS avg_product_sales,
		LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year ASC) AS prev_year_sales
	FROM yearly_product_sales
)
SELECT 
	order_year,
	product_name,
	current_sales,
	avg_product_sales,
	current_sales - avg_product_sales AS sales_diff_with_avg,
	CASE 
		WHEN current_sales - avg_product_sales > 0 THEN 'above avg'
		WHEN current_sales - avg_product_sales < 0 THEN 'below avg'
		ELSE 'avg'
	END as flag_avg,
	prev_year_sales,
	current_sales - COALESCE(prev_year_sales, 0) AS sales_diff_with_prev_year,
	CASE 
		WHEN current_sales - COALESCE(prev_year_sales, 0) > 0 THEN 'increase'
		WHEN current_sales - COALESCE(prev_year_sales, 0) < 0 THEN 'decrease'
		ELSE 'same as prev year'
	END as prev_year_change
FROM avg_and_prev_year_sales;

-- Part-to-whole analysis
-- Which categories contribute the most to overall sales?

WITH sales_by_category AS(
	SELECT 
		p.category,
		SUM(s.sales_amount) category_sales
	FROM gold.fact_sales s
	LEFT JOIN gold.dim_products p
	ON p.product_key = s.product_key
	WHERE s.order_date IS NOT NULL
	GROUP BY p.category
)
SELECT 
	category,
	category_sales,
	ROUND(CAST(category_sales AS FLOAT) / SUM(category_sales) OVER() * 100 , 2) percent_of_total
FROM sales_by_category
ORDER BY category_sales DESC;


-- Data segmentation
-- Segment products into cost ranges and count how many products fall into each segment

WITH 
products_segmented_by_cost AS (
	SELECT
		product_key,
		product_name,
		cost,
		CASE 
			WHEN cost < 100 THEN 'Below 100'
			WHEN cost BETWEEN 100 AND 500 THEN '100-500'
			WHEN cost BETWEEN 500 AND 1000 THEN '500-1000' 
			ELSE 'Above 1000'
		END AS cost_range
	FROM gold.dim_products
)
SELECT 
	cost_range,
	COUNT(product_key) as total_products
FROM products_segmented_by_cost
GROUP BY cost_range
ORDER BY total_products DESC


-- Group customers into 3 segments based on their spending behavior:
--	1. VIP: at least 12 months of history and spending more than 5000;
--	2. Regular: at least 12 months of history but spending 5000 or less;
--	3. New: lifespan less than 12 months
-- And find the total number of customers by each group.

WITH 
customers_spending_and_lifespan AS(
	SELECT 
		c.customer_key,
		SUM(s.sales_amount) AS total_spending,
		MIN(s.order_date) AS first_order_date,
		MAX(s.order_date) AS last_order_date,
		DATEDIFF(month, MIN(s.order_date), MAX(s.order_date)) AS lifespan_months
	FROM gold.fact_sales s
	LEFT JOIN gold.dim_customers c
	ON c.customer_key = s.customer_key
--	WHERE s.order_date IS NOT NULL
	GROUP BY c.customer_key
),
customers_segmented AS (
	SELECT 
		customer_key,
		total_spending,
		lifespan_months,
		CASE 
			WHEN lifespan_months >= 12 AND total_spending > 5000 THEN 'VIP'
			WHEN lifespan_months >= 12 AND total_spending <= 5000 THEN 'Regular'
			ELSE 'New'
		END AS customer_segment
	FROM customers_spending_and_lifespan
)
SELECT 
	customer_segment,
	COUNT(customer_key) as total_customers
FROM customers_segmented
GROUP BY customer_segment
ORDER BY total_customers DESC




