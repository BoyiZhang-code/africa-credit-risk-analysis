-- Make sure all of tables exist
SELECT *
FROM sqlite_master
WHERE type = 'table'
ORDER by name;
	
-- Check the row number of each tables	
SELECT 'customer' AS table_name, count(*) AS row_count
FROM customers
UNION ALL
SELECT 'loan', count(*) FROM loans
UNION ALL
SELECT 'repayment', count(*) FROM repayments
UNION ALL
SELECT 'transactions', count(*) FROM transactions;
-- Check each tables	
SELECT *
FROM customers
LIMIT 10;
	
SELECT *
FROM loans
LIMIT 10;
	
SELECT *
FROM repayments
LIMIT 10;
SELECT *
FROM transactions
LIMIT 10;
	
-- Check the columns name of each tables	
PRAGMA table_info(loans);
PRAGMA table_info(repayments);
	
-- Check each loan record match how many of repayment records	
SELECT loan_id, count(*) AS repayment_records
FROM repayments
GROUP BY loan_id
ORDER BY repayment_records DESC
LIMIT 10;
	
-- Create a loan analytical VIEW	
DROP VIEW IF EXISTS loan_level_analysis;
CREATE VIEW loan_level_analysis AS
SELECT	
	l.loan_id,
	l.customer_id,
	l.loan_date,
	l.loan_amount_usd,
	l.term_days,
	l.credit_score,
	l.status,
	coalesce(r.repayment_record_count,0) AS repayment_record_count,
	coalesce(r.total_repaid,0) AS total_repaid,
	MAX(l.loan_amount_usd - coalesce(r.total_repaid,0),0) AS estimated_outstanding_amount,
	coalesce(r.max_days_late,0) AS max_days_late,
	coalesce(r.late_repayment_count,0) AS late_repayment_count
FROM loans AS l	
LEFT JOIN (
	SELECT loan_id,
	count(*) AS repayment_record_count,
	SUM(amount_paid_usd) AS total_repaid,
	MAX(days_late) AS max_days_late,
	SUM(CASE WHEN days_late > 0 THEN 1 ELSE 0 END ) AS late_repayment_count
	FROM repayments	
	GROUP BY loan_id
) AS r 
ON l.loan_id = r.loan_id
;	

-- Check the result of our veiw
SELECT *
FROM loan_level_analysis
LIMIT 10;

-- The view should have one row per loan_amount_usd
SELECT count(*) AS total_rows,
	   count(DISTINCT loan_id) AS dsitinct_loan
FROM loan_level_analysis;

-- Check the columns of customer TABLE
PRAGMA table_info(customers);

-- Check the missing values and error values in loan_level_analysis
SELECT 
	count(*) AS total_rows,
	count(DISTINCT loan_id) AS distinct_loans,
	SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS missing_customer_id,
	SUM(CASE WHEN loan_amount_usd IS NULL THEN 1 ELSE 0 END) AS missing_loan_amount,
	SUM(CASE WHEN loan_amount_usd < 0 THEN 1 ELSE 0 END) AS negative_loan_amount
FROM loan_level_analysis;

-- Get the distribution of loan status
SELECT 
	status,
	count(*) AS loan_count,
	round(avg(loan_amount_usd),2) AS avg_loan_amount
FROM loan_level_analysis
GROUP BY status
ORDER BY loan_count DESC;

-- Get the max outstanding days
SELECT
	max_days_late,
	count(*) AS loan_count
FROM loan_level_analysis
GROUP BY max_days_late
ORDER BY max_days_late DESC
LIMIT 15;

-- Build the country level analysis

-- Objective 1: Compare lending risk across countries

SELECT
    c.country,
    COUNT(DISTINCT c.customer_id) AS customer_count,
    COUNT(l.loan_id) AS loan_count,

    ROUND(SUM(l.loan_amount_usd), 2) AS total_loan_amount_usd,
    ROUND(AVG(l.loan_amount_usd), 2) AS avg_loan_amount_usd,

    SUM(
        CASE WHEN l.status = 'overdue' THEN 1 ELSE 0 END
    ) AS overdue_loan_count,

    ROUND(
        100.0 * SUM(
            CASE WHEN l.status = 'overdue' THEN 1 ELSE 0 END
        ) / NULLIF(COUNT(l.loan_id), 0),
        2
    ) AS overdue_status_share_pct,

    SUM(
        CASE WHEN l.max_days_late > 0 THEN 1 ELSE 0 END
    ) AS loans_with_late_repayment_history,

    ROUND(
        100.0 * SUM(
            CASE WHEN l.max_days_late > 0 THEN 1 ELSE 0 END
        ) / NULLIF(COUNT(l.loan_id), 0),
        2
    ) AS historical_late_loan_share_pct

FROM customers AS c
INNER JOIN loan_level_analysis AS l
    ON c.customer_id = l.customer_id

GROUP BY c.country
ORDER BY overdue_status_share_pct DESC;

-- AS result of analysis, we can try to position the problematic contry, nigeria

-- Divide the costumer into different level
SELECT
	CASE 
		WHEN c.monthly_income_usd < 400 THEN 'low income'
		WHEN c.monthly_income_usd < 700 THEN 'medium income'
		ELSE 'high income'
	END AS income_segment,
	
	count(DISTINCT c.customer_id) AS customer_count,
	count(l.loan_id) AS loan_count,
	
	ROUND(AVG(l.loan_amount_usd),2) AS avg_loan_amount,
	
	SUM(
		CASE WHEN l.status = 'overdue' THEN 1 ELSE 0 END
		) AS overdue_loan_count,
	ROUND(100*SUM(CASE WHEN l.status = 'overdue' THEN 1 ELSE 0 END)/nullif(count(l.loan_id),0),2) AS overdue_status_share_pct,
	
	SUM(CASE WHEN l.max_days_late > 0 THEN 1 ELSE 0 END) AS loan_with_late_history,
	
	ROUND(100*SUM(CASE WHEN l.max_days_late > 0 THEN 1 ELSE 0 END)/nullif(count(l.loan_id),0),2) AS historical_late_share_pct
	
FROM customers c
LEFT JOIN loan_level_analysis l ON c.customer_id = l.customer_id

WHERE c.monthly_income_usd IS NOT NULL

GROUP BY income_segment
ORDER BY overdue_status_share_pct;
	
-- Check how many loans a customer matchs
SELECT
	customer_id,
	count(*) AS loan_count
FROM loan_level_analysis
GROUP BY customer_id
HAVING count(*) > 1
ORDER BY loan_count DESC
LIMIT 10;

-- Check how many customer haven't loan record
SELECT count(*) AS unmatch_loan_record
FROM loan_level_analysis l
LEFT JOIN customers c
	ON l.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- Create a new view to save my result

-- Objective 1: Country-level credit risk summary
DROP VIEW IF EXISTS country_risk_summary;

CREATE VIEW country_risk_summary AS
SELECT
    c.country,
    COUNT(DISTINCT c.customer_id) AS customer_count,
    COUNT(l.loan_id) AS loan_count,

    ROUND(SUM(l.loan_amount_usd), 2) AS total_loan_amount_usd,
    ROUND(AVG(l.loan_amount_usd), 2) AS avg_loan_amount_usd,

    SUM(
        CASE WHEN l.status = 'overdue'
        THEN 1 ELSE 0 END
    ) AS overdue_loan_count,

    ROUND(
        100.0 * SUM(
            CASE WHEN l.status = 'overdue'
            THEN 1 ELSE 0 END
        ) / NULLIF(COUNT(l.loan_id), 0),
        2
    ) AS overdue_loan_rate_pct,

    SUM(
        CASE WHEN l.max_days_late > 0
        THEN 1 ELSE 0 END
    ) AS loans_with_late_repayment,

    ROUND(
        100.0 * SUM(
            CASE WHEN l.max_days_late > 0
            THEN 1 ELSE 0 END
        ) / NULLIF(COUNT(l.loan_id), 0),
        2
    ) AS historical_late_rate_pct

FROM customers c
INNER JOIN loan_level_analysis l
    ON c.customer_id = l.customer_id

GROUP BY c.country;

SELECT * FROM country_risk_summary ORDER BY overdue_loan_rate_pct DESC;


-- Objective 2: Risk analysis by customer income segment
DROP VIEW IF EXISTS income_risk_summary;

CREATE VIEW income_risk_summary AS
SELECT
    CASE
        WHEN c.monthly_income_usd < 400
            THEN 'Low income'
        WHEN c.monthly_income_usd < 700
            THEN 'Medium income'
        ELSE 'High income'
    END AS income_segment,

    COUNT(DISTINCT c.customer_id) AS customer_count,
    COUNT(l.loan_id) AS loan_count,

    ROUND(AVG(l.loan_amount_usd), 2)
        AS avg_loan_amount_usd,

    SUM(
        CASE WHEN l.status = 'overdue'
        THEN 1 ELSE 0 END
    ) AS overdue_loan_count,

    ROUND(
        100.0 * SUM(
            CASE WHEN l.status = 'overdue'
            THEN 1 ELSE 0 END
        ) / NULLIF(COUNT(l.loan_id), 0),
        2
    ) AS overdue_loan_rate_pct,

    SUM(
        CASE WHEN l.max_days_late > 0
        THEN 1 ELSE 0 END
    ) AS loans_with_late_repayment,

    ROUND(
        100.0 * SUM(
            CASE WHEN l.max_days_late > 0
            THEN 1 ELSE 0 END
        ) / NULLIF(COUNT(l.loan_id), 0),
        2
    ) AS historical_late_rate_pct

FROM customers c
INNER JOIN loan_level_analysis l
    ON c.customer_id = l.customer_id

WHERE c.monthly_income_usd IS NOT NULL

GROUP BY
    CASE
        WHEN c.monthly_income_usd < 400
            THEN 'Low income'
        WHEN c.monthly_income_usd < 700
            THEN 'Medium income'
        ELSE 'High income'
    END;

SELECT * FROM income_risk_summary ORDER BY overdue_loan_rate_pct DESC;

-- Cehck repeat borrowing by income segment
SELECT 
	income_segment,
	count(*) AS customer_count,
	SUM(CASE WHEN loan_count > 1 THEN 1 ELSE 0 END) AS repeat_borrow_count,
	ROUND(100*SUM(CASE WHEN loan_count > 1 THEN 1 ELSE 0 END)/nullif(count(*),0),2) AS repeat_borrow_share_pct,
	ROUND(avg(loan_count),2) AS avg_loan_share_pct
FROM 
	(SELECT
		c.customer_id,
		CASE
			WHEN c.monthly_income_usd < 400 THEN 'low income'
			WHEN c.monthly_income_usd < 700 THEN 'medium income'
			ELSE 'high income'
		END AS income_segment,
		COUNT(l.loan_id) AS loan_count
	FROM customers c
	LEFT JOIN loan_level_analysis l ON c.customer_id = l.customer_id
	WHERE c.monthly_income_usd IS not NULL
	GROUP BY c.customer_id, income_segment
	) customer_loan_count
GROUP BY income_segment
ORDER BY repeat_borrow_share_pct DESC;
	
SELECT * FROM country_risk_summary
