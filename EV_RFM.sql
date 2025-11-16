create database ev_market;
use ev_market;

-- Creating tables:

CREATE TABLE customers (
    customer_id VARCHAR(20) PRIMARY KEY,
    customer_name VARCHAR(100),
    email VARCHAR(50),
    city VARCHAR(50),
    signup_date DATE
);

CREATE TABLE products (
    product_id VARCHAR(20) PRIMARY KEY,
    product_name VARCHAR(100),
    category VARCHAR(50),
    price DECIMAL(10,2)
);

CREATE TABLE orders (
    order_id VARCHAR(20) PRIMARY KEY,
    customer_id VARCHAR(20),
    order_date DATE,
    order_status VARCHAR(20),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
    order_item_id INT AUTO_INCREMENT PRIMARY KEY,
    order_id VARCHAR(20),
    product_id VARCHAR(20),
    quantity INT,
    item_price DECIMAL(10,2),
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);


-- Then the datasets are imported to respective tables:

-- DATA CLEANING:

-- check for nulls
SELECT 
    (SELECT COUNT(*) FROM customers WHERE customer_id IS NULL) AS cust_nulls,
    (SELECT COUNT(*) FROM orders WHERE order_id IS NULL OR customer_id IS NULL) AS order_nulls,
    (SELECT COUNT(*) FROM order_items WHERE order_id IS NULL OR product_id IS NULL) AS item_nulls;

-- check for total rows
SELECT COUNT(*) FROM customers;
SELECT COUNT(*) FROM orders;
SELECT COUNT(*) FROM order_items;
SELECT COUNT(*) FROM products;

select * from customers;
select * from products;
select * from orders;
select * from order_items;

-- 

SELECT o.customer_id
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

SELECT oi.order_id
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

SELECT oi.product_id
FROM order_items oi
LEFT JOIN products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

-- rfm analysis:

-- doing these all using view ( so virtual tables will be formed)

CREATE OR REPLACE VIEW rfm_base AS
SELECT
    c.customer_id,
    DATEDIFF(
        (SELECT MAX(order_date) FROM orders),
        MAX(o.order_date)
    ) AS recency,
    COUNT(DISTINCT o.order_id) AS frequency,
    COALESCE(SUM(oi.quantity * oi.item_price), 0) AS monetary
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
LEFT JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY c.customer_id;

select * from rfm_base;

CREATE OR REPLACE VIEW rfm_scores AS
SELECT
    *,
    NTILE(5) OVER (ORDER BY recency DESC) AS R_Score,
    NTILE(5) OVER (ORDER BY frequency ASC) AS F_Score,
    NTILE(5) OVER (ORDER BY monetary ASC) AS M_Score
FROM rfm_base;

select * from rfm_scores 
order by recency ;

CREATE OR REPLACE VIEW rfm_final AS
SELECT
    customer_id, recency, frequency, monetary, R_Score, F_Score, M_Score,
    CONCAT(R_Score, F_Score, M_Score) AS rfm_segment,
    (R_Score + F_Score + M_Score) AS rfm_score,
    CASE
      WHEN R_Score = 5 AND F_Score >= 4 AND M_Score >= 4 THEN 'Champion'
      WHEN R_Score >= 4 AND F_Score >= 4 THEN 'Loyal Customer'
      WHEN M_Score = 5 AND R_Score <= 3 THEN 'Big Spender'
      WHEN R_Score <= 2 AND F_Score >= 3 THEN 'At Risk'
      WHEN R_Score = 1 AND F_Score = 1 THEN 'Lost'
      WHEN R_Score = 5 AND F_Score = 1 THEN 'New Customer'
      ELSE 'Regular Customer'
    END AS customer_segment
FROM rfm_scores;

select * from rfm_final;


-- 1. Summary of RFM score distribution
SELECT
    R_Score, F_Score, M_Score,
    COUNT(*) AS num_customers
FROM rfm_final
GROUP BY R_Score, F_Score, M_Score
ORDER BY num_customers desc,R_Score DESC, F_Score DESC, M_Score DESC;

-- 2. Top 5 Best Customers (RFM score highest)
SELECT *
FROM rfm_final
ORDER BY rfm_score DESC, monetary DESC
LIMIT 5;

-- 3. How many customers are VIP (scores ≥ 13)?
SELECT COUNT(*) AS vip_customers
FROM rfm_final
WHERE rfm_score >= 13;

-- 4. Customers at high churn risk
SELECT *
FROM rfm_final
WHERE R_Score = 1 AND F_Score = 1;



-- 5. New Customers
SELECT *
FROM rfm_final 
WHERE R_Score = 5 AND F_Score in(1,2) and monetary>0;


-- 6. Loyal Customers (high frequency)
SELECT *
FROM rfm_final
WHERE F_Score = 5
order by monetary desc;

-- 7. Big Spenders (high monetary)
SELECT *
FROM rfm_final
WHERE M_Score = 5
order by monetary desc;

-- 8. Revenue contribution by RFM segment
SELECT
    CONCAT(R_Score, F_Score, M_Score) AS segment,
    COUNT(*) AS customer_count,
    SUM(monetary) AS segment_revenue,
    ROUND(SUM(monetary) / (SELECT SUM(monetary) FROM rfm_final) * 100, 2) AS revenue_share_pct
FROM rfm_final
GROUP BY segment
ORDER BY segment_revenue DESC;

-- 9. Identify the 80/20 Pareto contributors
WITH ranked AS (
    SELECT
        customer_id,
        monetary,
        SUM(monetary) OVER (ORDER BY monetary DESC) AS cumulative_revenue,
        (SELECT SUM(monetary) FROM rfm_final) AS total_revenue
    FROM rfm_final
)
SELECT customer_id, monetary, cumulative_revenue
FROM ranked
WHERE cumulative_revenue <= 0.8 * total_revenue;
