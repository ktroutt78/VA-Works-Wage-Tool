-- =============================================================================
-- LABOR MARKET SNAPSHOT DASHBOARD - SQL Queries
-- Source: WID_DB (BLS LAUS + QCEW)
-- =============================================================================
-- Parameters:
--   @months_back: 3, 6, 12, or 36 (for 3M, 6M, 1Y, 3Y time range toggle)
--   Queries auto-detect the most recent available data period
-- =============================================================================
-- DEPENDENCIES:
--   WID_DB.WID.V_VA_REGION_MAPPING   — persistent view mapping ~130 VA
--   counties & independent cities to macro-region codes (nova, hampton,
--   rva, swva). Unmapped localities default to 'central'.
-- =============================================================================


-- =============================================================================
-- QUERY 1: EMPLOYMENT RATE BY LOCALITY
-- Returns: County/city-level employment rates for choropleth map + KPI cards
--          (Virginia statewide SA, US Average SA, with delta vs prior period)
-- Employment Rate = 100 - Unemployment Rate
-- Includes region_code mapping for macro-region assignment
-- =============================================================================
WITH latest_period AS (
    SELECT MAX(PERIODYEAR || '-' || PERIOD) AS max_ym
    FROM WID_DB.WID.LABORFORCE
    WHERE STFIPS = '51' AND AREATYPE = '01' AND ADJUSTED = 'S' AND PERIODTYPE = 'MN'
      AND UNEMPLOYEDRATE IS NOT NULL
),
current_month AS (
    SELECT
        SUBSTRING(max_ym, 1, 4) AS yr,
        SUBSTRING(max_ym, 6, 2) AS mo
    FROM latest_period
),
prior_month AS (
    SELECT
        CASE WHEN mo = '01' THEN (yr::INT - 1)::VARCHAR ELSE yr END AS yr,
        CASE WHEN mo = '01' THEN '12' ELSE LPAD((mo::INT - 1)::VARCHAR, 2, '0') END AS mo
    FROM current_month
),

-- County & independent city level (non-seasonally adjusted - only available option)
county_data AS (
    SELECT
        lf.AREA,
        g.AREANAME,
        lf.AREATYPE,
        lf.EMPLOYED,
        lf.LABORFORCE AS LF,
        lf.UNEMPLOYEDRATE,
        ROUND(100.0 - lf.UNEMPLOYEDRATE, 1) AS employment_rate,
        COALESCE(rm.region_code, 'central') AS region_code
    FROM WID_DB.WID.LABORFORCE lf
    JOIN WID_DB.WID.GEOGRAPHIES g
      ON lf.AREA = g.AREA AND lf.AREATYPE = g.AREATYPE AND lf.STFIPS = g.STFIPS
    LEFT JOIN WID_DB.WID.V_VA_REGION_MAPPING rm
      ON lf.AREA = rm.AREA AND lf.AREATYPE = rm.AREATYPE
    CROSS JOIN current_month cm
    WHERE lf.STFIPS = '51'
      AND lf.AREATYPE IN ('04','05')  -- counties + independent cities
      AND lf.ADJUSTED = 'U'
      AND lf.PERIODTYPE = 'MN'
      AND lf.PERIODYEAR = cm.yr
      AND lf.PERIOD = cm.mo
),

-- Virginia statewide KPI (seasonally adjusted)
va_current AS (
    SELECT UNEMPLOYEDRATE, ROUND(100.0 - UNEMPLOYEDRATE, 1) AS employment_rate
    FROM WID_DB.WID.LABORFORCE
    CROSS JOIN current_month cm
    WHERE STFIPS = '51' AND AREATYPE = '01' AND ADJUSTED = 'S' AND PERIODTYPE = 'MN'
      AND PERIODYEAR = cm.yr AND PERIOD = cm.mo
),
va_prior AS (
    SELECT UNEMPLOYEDRATE, ROUND(100.0 - UNEMPLOYEDRATE, 1) AS employment_rate
    FROM WID_DB.WID.LABORFORCE
    CROSS JOIN prior_month pm
    WHERE STFIPS = '51' AND AREATYPE = '01' AND ADJUSTED = 'S' AND PERIODTYPE = 'MN'
      AND PERIODYEAR = pm.yr AND PERIOD = pm.mo
),

-- US Average KPI (seasonally adjusted, all states aggregated)
us_current AS (
    SELECT
        ROUND(100.0 - (SUM(UNEMPLOYED)::FLOAT / NULLIF(SUM(LABORFORCE),0) * 100), 1) AS employment_rate,
        ROUND(SUM(UNEMPLOYED)::FLOAT / NULLIF(SUM(LABORFORCE),0) * 100, 1) AS unemployedrate
    FROM WID_DB.WID.LABORFORCE
    CROSS JOIN current_month cm
    WHERE AREATYPE = '01' AND ADJUSTED = 'S' AND PERIODTYPE = 'MN'
      AND PERIODYEAR = cm.yr AND PERIOD = cm.mo
      AND UNEMPLOYED IS NOT NULL
    HAVING COUNT(*) >= 50  -- exclude months with incomplete state reporting
),
us_prior AS (
    SELECT
        ROUND(100.0 - (SUM(UNEMPLOYED)::FLOAT / NULLIF(SUM(LABORFORCE),0) * 100), 1) AS employment_rate,
        ROUND(SUM(UNEMPLOYED)::FLOAT / NULLIF(SUM(LABORFORCE),0) * 100, 1) AS unemployedrate
    FROM WID_DB.WID.LABORFORCE
    CROSS JOIN prior_month pm
    WHERE AREATYPE = '01' AND ADJUSTED = 'S' AND PERIODTYPE = 'MN'
      AND PERIODYEAR = pm.yr AND PERIOD = pm.mo
      AND UNEMPLOYED IS NOT NULL
    HAVING COUNT(*) >= 50
)

SELECT
    'COUNTY' AS record_type,
    cd.AREA,
    cd.AREANAME,
    cd.AREATYPE,
    cd.employment_rate,
    cd.UNEMPLOYEDRATE,
    cd.EMPLOYED,
    cd.LF AS LABORFORCE,
    NULL AS delta_vs_prior,
    cd.region_code
FROM county_data cd

UNION ALL

SELECT
    'KPI_VIRGINIA' AS record_type,
    '000051' AS AREA,
    'Virginia' AS AREANAME,
    '01' AS AREATYPE,
    vc.employment_rate,
    vc.UNEMPLOYEDRATE,
    NULL AS EMPLOYED,
    NULL AS LABORFORCE,
    ROUND(vc.employment_rate - vp.employment_rate, 1) AS delta_vs_prior,
    NULL AS region_code
FROM va_current vc, va_prior vp

UNION ALL

SELECT
    'KPI_US_AVERAGE' AS record_type,
    NULL AS AREA,
    'U.S. Average' AS AREANAME,
    NULL AS AREATYPE,
    uc.employment_rate,
    uc.unemployedrate AS UNEMPLOYEDRATE,
    NULL AS EMPLOYED,
    NULL AS LABORFORCE,
    ROUND(uc.employment_rate - up.employment_rate, 1) AS delta_vs_prior,
    NULL AS region_code
FROM us_current uc, us_prior up

ORDER BY record_type, AREANAME;


-- =============================================================================
-- QUERY 2: UNEMPLOYMENT RATE TRENDING (ALL GRANULARITIES)
-- Returns: Monthly unemployment rate at FOUR granularities over 36 months:
--   level='state_sa'   — Virginia statewide (seasonally adjusted)
--   level='national_sa'— U.S. National (seasonally adjusted, all-state aggregate)
--   level='region_nsa' — 5 macro-regions (NSA, aggregated from county-level)
--   level='county_nsa' — per county/independent city (NSA)
-- region_code: virginia, us_national, nova, rva, hampton, swva, central, or AREA code
-- =============================================================================
WITH latest AS (
    SELECT MAX(PERIODYEAR || '-' || PERIOD) AS max_ym
    FROM WID_DB.WID.LABORFORCE
    WHERE STFIPS = '51' AND AREATYPE = '01' AND ADJUSTED = 'S' AND PERIODTYPE = 'MN'
      AND UNEMPLOYEDRATE IS NOT NULL
),
end_date AS (
    SELECT TO_DATE(SUBSTRING(max_ym, 1, 4) || '-' || SUBSTRING(max_ym, 6, 2) || '-01', 'YYYY-MM-DD') AS dt
    FROM latest
),
months AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS offset_mo
    FROM TABLE(GENERATOR(ROWCOUNT => 36))
),
month_series AS (
    SELECT
        TO_CHAR(DATEADD('month', -m.offset_mo, ed.dt), 'YYYY') AS yr,
        TO_CHAR(DATEADD('month', -m.offset_mo, ed.dt), 'MM') AS mo
    FROM months m, end_date ed
    WHERE m.offset_mo < 36
),

-- Virginia statewide (seasonally adjusted)
virginia_trend AS (
    SELECT
        lf.PERIODYEAR,
        lf.PERIOD,
        lf.UNEMPLOYEDRATE AS urate,
        'Virginia' AS series,
        'virginia' AS region_code,
        'state_sa' AS level
    FROM WID_DB.WID.LABORFORCE lf
    JOIN month_series ms ON lf.PERIODYEAR = ms.yr AND lf.PERIOD = ms.mo
    WHERE lf.STFIPS = '51' AND lf.AREATYPE = '01' AND lf.ADJUSTED = 'S' AND lf.PERIODTYPE = 'MN'
      AND lf.UNEMPLOYEDRATE IS NOT NULL
),

-- U.S. National (seasonally adjusted, all states aggregated)
us_trend AS (
    SELECT
        lf.PERIODYEAR,
        lf.PERIOD,
        ROUND(SUM(lf.UNEMPLOYED)::FLOAT / NULLIF(SUM(lf.LABORFORCE), 0) * 100, 1) AS urate,
        'U.S. National' AS series,
        'us_national' AS region_code,
        'national_sa' AS level
    FROM WID_DB.WID.LABORFORCE lf
    JOIN month_series ms ON lf.PERIODYEAR = ms.yr AND lf.PERIOD = ms.mo
    WHERE lf.AREATYPE = '01' AND lf.ADJUSTED = 'S' AND lf.PERIODTYPE = 'MN'
      AND lf.UNEMPLOYED IS NOT NULL
    GROUP BY lf.PERIODYEAR, lf.PERIOD
    HAVING COUNT(*) >= 50  -- exclude months with incomplete state reporting
),

-- =============================================================================
-- PER-REGION TRENDS (NSA, aggregated from county-level LABORFORCE)
-- =============================================================================
region_trend AS (
    SELECT
        lf.PERIODYEAR,
        lf.PERIOD,
        ROUND(SUM(lf.UNEMPLOYED)::FLOAT / NULLIF(SUM(lf.LABORFORCE), 0) * 100, 1) AS urate,
        COALESCE(rm.region_code, 'central') AS region_code
    FROM WID_DB.WID.LABORFORCE lf
    LEFT JOIN WID_DB.WID.V_VA_REGION_MAPPING rm ON lf.AREA = rm.AREA AND lf.AREATYPE = rm.AREATYPE
    JOIN month_series ms ON lf.PERIODYEAR = ms.yr AND lf.PERIOD = ms.mo
    WHERE lf.STFIPS = '51'
      AND lf.AREATYPE IN ('04','05')
      AND lf.ADJUSTED = 'U'
      AND lf.PERIODTYPE = 'MN'
    GROUP BY lf.PERIODYEAR, lf.PERIOD, COALESCE(rm.region_code, 'central')
    HAVING SUM(lf.LABORFORCE) IS NOT NULL
),
region_trend_labeled AS (
    SELECT
        PERIODYEAR, PERIOD, urate,
        CASE region_code
            WHEN 'nova' THEN 'Northern Virginia'
            WHEN 'rva' THEN 'Richmond Metro'
            WHEN 'hampton' THEN 'Hampton Roads'
            WHEN 'swva' THEN 'Southwest Virginia'
            WHEN 'central' THEN 'Central / Shenandoah'
        END AS series,
        region_code,
        'region_nsa' AS level
    FROM region_trend
),

-- =============================================================================
-- PER-COUNTY TRENDS (NSA, individual county/independent city)
-- =============================================================================
county_trend AS (
    SELECT
        lf.AREA,
        lf.AREATYPE,
        lf.PERIODYEAR,
        lf.PERIOD,
        lf.UNEMPLOYEDRATE,
        'county_nsa' AS level
    FROM WID_DB.WID.LABORFORCE lf
    JOIN month_series ms ON lf.PERIODYEAR = ms.yr AND lf.PERIOD = ms.mo
    WHERE lf.STFIPS = '51'
      AND lf.AREATYPE IN ('04','05')
      AND lf.ADJUSTED = 'U'
      AND lf.PERIODTYPE = 'MN'
)

-- Macro-level series (state + national + region aggregates)
SELECT
    PERIODYEAR, PERIOD, series, region_code, urate, level,
    NULL AS AREA, NULL AS AREATYPE, NULL AS UNEMPLOYEDRATE
FROM virginia_trend
UNION ALL
SELECT
    PERIODYEAR, PERIOD, series, region_code, urate, level,
    NULL AS AREA, NULL AS AREATYPE, NULL AS UNEMPLOYEDRATE
FROM us_trend
UNION ALL
SELECT
    PERIODYEAR, PERIOD, series, region_code, urate, level,
    NULL AS AREA, NULL AS AREATYPE, NULL AS UNEMPLOYEDRATE
FROM region_trend_labeled

UNION ALL

-- County-level series
SELECT
    PERIODYEAR, PERIOD, NULL AS series, NULL AS region_code, NULL AS urate, level,
    AREA, AREATYPE, UNEMPLOYEDRATE
FROM county_trend

ORDER BY level, region_code, AREA, PERIODYEAR, PERIOD;


-- =============================================================================
-- QUERY 3: JOBS ADDED BY INDUSTRY (TOP 5) - STATEWIDE + PER REGION
-- Returns: Quarter-over-quarter employment change by BLS supersector
--          Uses QCEW (Quarterly Census of Employment and Wages)
-- Note: "Government" combines federal + state + local ownership
-- scope: 'statewide' or region_code (nova, rva, hampton, swva, central)
-- Refactored: uses LAG() window function instead of curr_/prev_ self-join
--             and COALESCE to preserve sectors appearing in only one quarter
-- =============================================================================
WITH latest_quarter AS (
    SELECT
        MAX(PERIODYEAR || '-' || PERIOD) AS max_yq
    FROM WID_DB.WID.INDUSTRY
    WHERE STFIPS = '51' AND AREATYPE = '01' AND PERIODYEAR >= '2024'
      AND PERIOD != '00'  -- exclude annual average (period=00)
),
current_q AS (
    SELECT
        SUBSTRING(max_yq, 1, 4) AS yr,
        SUBSTRING(max_yq, 6, 2) AS qtr
    FROM latest_quarter
),
prior_q AS (
    SELECT
        CASE WHEN qtr = '01' THEN (yr::INT - 1)::VARCHAR ELSE yr END AS yr,
        CASE WHEN qtr = '01' THEN '04' ELSE LPAD((qtr::INT - 1)::VARCHAR, 2, '0') END AS qtr
    FROM current_q
),

-- BLS supersector definitions (private sector = ownership 5)
industry_sectors AS (
    SELECT * FROM (VALUES
        ('1024', '5', 'Professional & Business'),
        ('1025', '5', 'Education & Health'),
        ('1026', '5', 'Leisure & Hospitality'),
        ('1021', '5', 'Trade & Transportation'),
        ('1013', '5', 'Manufacturing'),
        ('1012', '5', 'Construction'),
        ('1011', '5', 'Natural Resources & Mining'),
        ('1022', '5', 'Information'),
        ('1023', '5', 'Financial Activities'),
        ('1027', '5', 'Other Services')
    ) AS t(indcode, ownership, sector_name)
),

-- =============================================================================
-- STATEWIDE (AREATYPE = '01') — LAG-based quarter-over-quarter
-- =============================================================================
state_both_qtrs AS (
    SELECT
        TRIM(i.INDCODE) AS indcode,
        i.OWNERSHIP,
        i.PERIODYEAR,
        i.PERIOD,
        i.QUARTERAVGEMP,
        -- Flag: 1 = current quarter, 0 = prior quarter
        CASE WHEN i.PERIODYEAR = cq.yr AND i.PERIOD = cq.qtr THEN 1 ELSE 0 END AS is_current
    FROM WID_DB.WID.INDUSTRY i
    CROSS JOIN current_q cq
    CROSS JOIN prior_q pq
    WHERE i.STFIPS = '51' AND i.AREATYPE = '01'
      AND ((i.PERIODYEAR = cq.yr AND i.PERIOD = cq.qtr)
        OR (i.PERIODYEAR = pq.yr AND i.PERIOD = pq.qtr))
),
state_change AS (
    SELECT
        indcode,
        OWNERSHIP,
        QUARTERAVGEMP AS current_emp,
        LAG(QUARTERAVGEMP) OVER (PARTITION BY indcode, OWNERSHIP ORDER BY PERIODYEAR, PERIOD) AS prior_emp
    FROM state_both_qtrs
    WHERE is_current = 1 OR is_current = 0
),
state_current_only AS (
    SELECT indcode, OWNERSHIP, current_emp, prior_emp
    FROM state_change
    WHERE prior_emp IS NOT NULL  -- only rows where LAG found the prior quarter
       OR current_emp IS NOT NULL
),

-- Private sector changes (statewide) — COALESCE ensures sectors in only one quarter still appear
private_change_state AS (
    SELECT
        'statewide' AS scope,
        s.sector_name,
        COALESCE(sc.current_emp, 0) AS current_emp,
        COALESCE(sc.prior_emp, 0) AS prior_emp,
        COALESCE(sc.current_emp, 0) - COALESCE(sc.prior_emp, 0) AS jobs_added
    FROM industry_sectors s
    LEFT JOIN state_current_only sc ON sc.indcode = s.indcode AND sc.OWNERSHIP = s.ownership
),

-- Government: combine federal (1) + state (2) + local (3) for indcode 1028 (statewide)
gov_change_state AS (
    SELECT
        'statewide' AS scope,
        'Government' AS sector_name,
        SUM(COALESCE(current_emp, 0)) AS current_emp,
        SUM(COALESCE(prior_emp, 0)) AS prior_emp,
        SUM(COALESCE(current_emp, 0)) - SUM(COALESCE(prior_emp, 0)) AS jobs_added
    FROM state_current_only
    WHERE indcode = '1028' AND OWNERSHIP IN ('1','2','3')
),

-- =============================================================================
-- PER-REGION (AREATYPE IN '04','05') — aggregated by macro-region, LAG-based
-- =============================================================================
all_va_counties AS (
    SELECT DISTINCT lf.AREA, lf.AREATYPE, COALESCE(rm.region_code, 'central') AS region_code
    FROM WID_DB.WID.LABORFORCE lf
    LEFT JOIN WID_DB.WID.V_VA_REGION_MAPPING rm ON lf.AREA = rm.AREA AND lf.AREATYPE = rm.AREATYPE
    WHERE lf.STFIPS = '51' AND lf.AREATYPE IN ('04','05')
),

-- Single scan of INDUSTRY for both quarters, aggregated to region level
region_both_qtrs AS (
    SELECT
        ac.region_code,
        TRIM(i.INDCODE) AS indcode,
        i.OWNERSHIP,
        i.PERIODYEAR,
        i.PERIOD,
        SUM(i.QUARTERAVGEMP) AS total_emp
    FROM WID_DB.WID.INDUSTRY i
    JOIN all_va_counties ac ON i.AREA = ac.AREA AND i.AREATYPE = ac.AREATYPE
    CROSS JOIN current_q cq
    CROSS JOIN prior_q pq
    WHERE i.STFIPS = '51' AND i.AREATYPE IN ('04','05')
      AND ((i.PERIODYEAR = cq.yr AND i.PERIOD = cq.qtr)
        OR (i.PERIODYEAR = pq.yr AND i.PERIOD = pq.qtr))
    GROUP BY ac.region_code, TRIM(i.INDCODE), i.OWNERSHIP, i.PERIODYEAR, i.PERIOD
),
region_change AS (
    SELECT
        region_code,
        indcode,
        OWNERSHIP,
        total_emp AS current_emp,
        LAG(total_emp) OVER (PARTITION BY region_code, indcode, OWNERSHIP ORDER BY PERIODYEAR, PERIOD) AS prior_emp,
        PERIODYEAR,
        PERIOD
    FROM region_both_qtrs
),
region_current_only AS (
    SELECT region_code, indcode, OWNERSHIP, current_emp, prior_emp
    FROM region_change rc
    -- Keep the current-quarter row (which has prior via LAG)
    WHERE EXISTS (SELECT 1 FROM current_q cq WHERE rc.PERIODYEAR = cq.yr AND rc.PERIOD = cq.qtr)
),

-- Private sector per-region
private_change_region AS (
    SELECT
        rc.region_code AS scope,
        s.sector_name,
        COALESCE(rc.current_emp, 0) AS current_emp,
        COALESCE(rc.prior_emp, 0) AS prior_emp,
        COALESCE(rc.current_emp, 0) - COALESCE(rc.prior_emp, 0) AS jobs_added
    FROM industry_sectors s
    JOIN region_current_only rc ON rc.indcode = s.indcode AND rc.OWNERSHIP = s.ownership
),

-- Government per-region: combine federal (1) + state (2) + local (3) for indcode 1028
gov_change_region AS (
    SELECT
        region_code AS scope,
        'Government' AS sector_name,
        SUM(COALESCE(current_emp, 0)) AS current_emp,
        SUM(COALESCE(prior_emp, 0)) AS prior_emp,
        SUM(COALESCE(current_emp, 0)) - SUM(COALESCE(prior_emp, 0)) AS jobs_added
    FROM region_current_only
    WHERE indcode = '1028' AND OWNERSHIP IN ('1','2','3')
    GROUP BY region_code
),

-- All sectors combined (statewide + per-region)
all_sectors AS (
    SELECT * FROM private_change_state
    UNION ALL
    SELECT * FROM gov_change_state
    UNION ALL
    SELECT * FROM private_change_region
    UNION ALL
    SELECT * FROM gov_change_region
),

-- Rank within each scope to get top 5
ranked AS (
    SELECT
        scope,
        sector_name,
        current_emp,
        prior_emp,
        jobs_added,
        ROW_NUMBER() OVER (PARTITION BY scope ORDER BY jobs_added DESC) AS rn
    FROM all_sectors
)

SELECT
    scope,
    sector_name,
    current_emp,
    prior_emp,
    jobs_added
FROM ranked
WHERE rn <= 5
ORDER BY scope, jobs_added DESC;
