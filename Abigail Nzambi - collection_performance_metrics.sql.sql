-- SeECTION B: COLLECTION PERFORMANCE METRICS

-- Preparing the enriched portfolio view, adding Unit Age Days, Unit Age Weeks, UPA, and Status

WITH sample_accounts AS (
  SELECT 
    angaza_id, 
    area, 
    daily_price, 
    upfront_price, 
    expected_repayment_days, 
    registration_date, 
    free_days_included, 
    product_group, 
    country 
  FROM 
    accounts 
  WHERE 
    registration_date BETWEEN '2023-12-01' 
    AND '2024-02-28'
), 
portfolio_enriched AS (
  SELECT 
    p.angaza_id, 
    p.portfolio_date, 
    p.days_to_cutoff, 
    p.amount_toward_follow_on, 
    a.area, 
    a.daily_price, 
    a.upfront_price, 
    a.expected_repayment_days, 
    a.registration_date, 
    a.free_days_included, 
    a.product_group, 
    a.country, 
    (
      p.portfolio_date - a.registration_date
    ) - a.free_days_included AS unit_age_days, 
    FLOOR(
      (
        (
          p.portfolio_date - a.registration_date
        ) - a.free_days_included
      ) / 7.0
    ) AS unit_age_weeks, 
    ROUND(
      CAST(
        (
          p.portfolio_date - a.registration_date
        ) - a.free_days_included AS NUMERIC
      ) / a.expected_repayment_days, 
      1
    ) AS upa, 
    CASE WHEN p.days_to_cutoff > 0 THEN 'ENABLED' ELSE 'DISABLED' END AS status 
  FROM 
    portfolio p 
    INNER JOIN sample_accounts a ON p.angaza_id = a.angaza_id 
  WHERE 
    (
      p.portfolio_date - a.registration_date
    ) - a.free_days_included > 0
) 

-- Question: How many days, on average, does it take each of the product groups to complete 0.1 UPA?
first_upa AS (
  SELECT 
    angaza_id, 
    product_group, 
    MIN(unit_age_days) AS first_unit_age_days 
  FROM 
    portfolio_enriched 
  WHERE 
    upa >= 0.1 
  GROUP BY 
    angaza_id, 
    product_group
) 
SELECT 
  product_group, 
  ROUND(
    AVG(first_unit_age_days), 
    1
  ) AS avg_days_to_01_upa 
FROM 
  first_upa 
GROUP BY 
  product_group 
ORDER BY 
  product_group;

-- Expected results: Product 1: 21.0 days, Product 2: 26.4 days, Product 3: 21.0 days, 
-- Product 4: 33.8 days, Product 5: 20.0 days,Product 6: 22.6 days, Product 7: 31.1 days


-- Compute the Disabled rates for each portfolio date. What is the disabled rate for June 9, 2024, for all accounts in the sample?
SELECT 
  portfolio_date, 
  COUNT(
    DISTINCT CASE WHEN status = 'DISABLED' THEN angaza_id END
  ) AS disabled_accounts, 
  COUNT(DISTINCT angaza_id) AS total_accounts_under_repayment, 
  ROUND(
    COUNT(
      DISTINCT CASE WHEN status = 'DISABLED' THEN angaza_id END
    ) * 1.0 / COUNT(DISTINCT angaza_id), 
    4
  ) AS disabled_rate 
FROM 
  portfolio_enriched 
GROUP BY 
  portfolio_date 
ORDER BY 
  portfolio_date;

-- June 9, 2024 is not present in the extracted portfolio snapshot.



-- What is the Repayment speed for Product 1 in Area A on July 18, 2024? Consider accounts registered in the first half of the month only.
SELECT 
  portfolio_date, 
  area, 
  product_group, 
  SUM(amount_toward_follow_on) AS total_collected, 
  SUM(daily_price) AS total_expected, 
  ROUND(
    SUM(amount_toward_follow_on) * 1.0 / NULLIF(
      SUM(daily_price), 
      0
    ), 
    4
  ) AS repayment_speed 
FROM 
  portfolio_enriched 
WHERE 
  portfolio_date = '2024-07-18' 
GROUP BY 
  portfolio_date, 
  area, 
  product_group;
-- Repayment speed is 56.4%, with KES 21,296 collected against KES 37,740 expected. 


-- Compute and plot disabled rates across portfolio weeks from the week of Jan 15 to July 15, 2024, split by area. How does Area A and Area B compare?
SELECT 
  DATE_TRUNC('week', portfolio_date) AS week_start, 
  area, 
  COUNT(
    DISTINCT CASE WHEN status = 'DISABLED' THEN angaza_id || '|' || portfolio_date :: TEXT END
  ) AS disabled_unit_days, 
  COUNT(
    DISTINCT angaza_id || '|' || portfolio_date :: TEXT
  ) AS total_unit_days, 
  ROUND(
    COUNT(
      DISTINCT CASE WHEN status = 'DISABLED' THEN angaza_id || '|' || portfolio_date :: TEXT END
    ) * 1.0 / NULLIF(
      COUNT(
        DISTINCT angaza_id || '|' || portfolio_date :: TEXT
      ), 
      0
    ), 
    4
  ) AS weekly_disabled_rate 
FROM 
  portfolio_enriched 
WHERE 
  portfolio_date BETWEEN '2024-01-15' 
  AND '2024-07-15' 
GROUP BY 
  week_start, 
  area 
ORDER BY 
  week_start, 
  area;


-- Compute and plot repayment speed across Unit Age Weeks from week 1 to 10, split by area. How does Area A and Area B compare?
SELECT 
  unit_age_weeks, 
  area, 
  SUM(amount_toward_follow_on) AS total_collected, 
  SUM(daily_price) AS total_expected, 
  ROUND(
    SUM(amount_toward_follow_on) * 1.0 / NULLIF(
      SUM(daily_price), 
      0
    ), 
    4
  ) AS repayment_speed 
FROM 
  portfolio_enriched 
WHERE 
  unit_age_weeks BETWEEN 1 
  AND 10 
GROUP BY 
  unit_age_weeks, 
  area 
ORDER BY 
  unit_age_weeks, 
  area;


--Area B consistently outperforms Area A on both metrics throughout the observation period. 
-- On repayment speed, Area B ranges from ~93% in week 1 to ~79% in week 10, 
-- while Area A ranges from ~79% down to ~64%. 
-- On disabled rates, Area B starts at ~12% in January and rises to ~30% by July, 
-- while Area A starts at ~24% and climbs to ~44%.


-- Assuming an experiment to improve customer repayment was launched in February 2024 across both areas, what conclusions can be drawn based on repayment speed and disabled rates?
--T he experiment does not show a clean positive effect on either metric. 
-- Both disabled rates and repayment trends worsen after February in both areas, 
-- which is the opposite of what a successful intervention would produce. 
-- However, this needs significant qualification: the entire sample consists of accounts registered between December 2023 and February 2024, 
-- so all accounts are aging through the same portfolio weeks simultaneously. 
-- This makes it nearly impossible to separate the experiment effect from natural portfolio aging dynamics. 
-- To draw valid causal conclusions, we would need a proper difference-in-differences design comparing a control cohort 
-- (unaffected by the experiment) against the treated group, 
-- with registration cohorts that span both pre and post-treatment windows. 
-- Without that, the upward trend in disabled rates is better attributed to portfolio maturation than to the experiment failing outright.