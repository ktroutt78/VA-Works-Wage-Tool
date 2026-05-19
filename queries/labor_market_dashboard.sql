-- =============================================================================
-- LABOR MARKET SNAPSHOT DASHBOARD - SQL Queries
-- Source: WID_DB (BLS LAUS + QCEW)
-- =============================================================================
-- Parameters:
--   @months_back: 3, 6, 12, or 36 (for 3M, 6M, 1Y, 3Y time range toggle)
--   Queries auto-detect the most recent available data period
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

-- =============================================================================
-- MACRO-REGION COUNTY MAPPING
-- Derived from VA Works Dashboard design REGIONS object
-- =============================================================================
region_mapping AS (
    SELECT AREA, AREATYPE, region_code FROM (VALUES
        -- nova (Northern Virginia)
        ('013000','04','nova'), ('510000','05','nova'), ('600000','05','nova'),
        ('107000','04','nova'), ('153000','04','nova'), ('179000','04','nova'),
        ('683000','05','nova'), ('685000','05','nova'), ('059000','04','nova'),
        ('061000','04','nova'), ('187000','04','nova'), ('630000','05','nova'),
        ('099000','04','nova'), ('157000','04','nova'),
        -- hampton (Hampton Roads)
        ('810000','05','hampton'), ('800000','05','hampton'), ('700000','05','hampton'),
        ('740000','05','hampton'), ('735000','05','hampton'), ('650000','05','hampton'),
        ('830000','05','hampton'), ('093000','04','hampton'), ('095000','04','hampton'),
        ('073000','04','hampton'), ('115000','04','hampton'), ('199000','04','hampton'),
        ('181000','04','hampton'), ('550000','05','hampton'), ('620000','05','hampton'),
        ('665000','05','hampton'), ('175000','04','hampton'), ('001000','04','hampton'),
        -- rva (Richmond Metro)
        ('760000','05','rva'), ('087000','04','rva'), ('041000','04','rva'),
        ('085000','04','rva'), ('127000','04','rva'), ('145000','04','rva'),
        ('149000','04','rva'), ('007000','04','rva'), ('033000','04','rva'),
        ('097000','04','rva'), ('101000','04','rva'), ('103000','04','rva'),
        ('119000','04','rva'), ('570000','05','rva'), ('670000','05','rva'),
        ('730000','05','rva'),
        -- swva (Southwest Virginia)
        ('105000','04','swva'), ('027000','04','swva'), ('051000','04','swva'),
        ('167000','04','swva'), ('169000','04','swva'), ('185000','04','swva'),
        ('195000','04','swva'), ('197000','04','swva'), ('021000','04','swva'),
        ('023000','04','swva'), ('035000','04','swva'), ('045000','04','swva'),
        ('063000','04','swva'), ('067000','04','swva'), ('071000','04','swva'),
        ('077000','04','swva'), ('089000','04','swva'), ('141000','04','swva'),
        ('143000','04','swva'), ('163000','04','swva'), ('191000','04','swva'),
        ('720000','05','swva'), ('770000','05','swva'), ('775000','05','swva'),
        ('520000','05','swva'), ('580000','05','swva'), ('590000','05','swva'),
        ('640000','05','swva'), ('690000','05','swva'), ('750000','05','swva')
    ) AS t(AREA, AREATYPE, region_code)
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
    LEFT JOIN region_mapping rm
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
-- QUERY 2: UNEMPLOYMENT RATE TRENDING (ALL REGIONS)
-- Returns: Monthly unemployment rate for Virginia (SA), U.S. National (SA),
--          and 5 macro-regions (NSA, aggregated from county-level) over 36 months
-- region_code: virginia, us_national, nova, rva, hampton, swva, central
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

-- =============================================================================
-- MACRO-REGION COUNTY MAPPING (same as Query 1)
-- =============================================================================
region_mapping AS (
    SELECT AREA, AREATYPE, region_code FROM (VALUES
        -- nova (Northern Virginia)
        ('013000','04','nova'), ('510000','05','nova'), ('600000','05','nova'),
        ('107000','04','nova'), ('153000','04','nova'), ('179000','04','nova'),
        ('683000','05','nova'), ('685000','05','nova'), ('059000','04','nova'),
        ('061000','04','nova'), ('187000','04','nova'), ('630000','05','nova'),
        ('099000','04','nova'), ('157000','04','nova'),
        -- hampton (Hampton Roads)
        ('810000','05','hampton'), ('800000','05','hampton'), ('700000','05','hampton'),
        ('740000','05','hampton'), ('735000','05','hampton'), ('650000','05','hampton'),
        ('830000','05','hampton'), ('093000','04','hampton'), ('095000','04','hampton'),
        ('073000','04','hampton'), ('115000','04','hampton'), ('199000','04','hampton'),
        ('181000','04','hampton'), ('550000','05','hampton'), ('620000','05','hampton'),
        ('665000','05','hampton'), ('175000','04','hampton'), ('001000','04','hampton'),
        -- rva (Richmond Metro)
        ('760000','05','rva'), ('087000','04','rva'), ('041000','04','rva'),
        ('085000','04','rva'), ('127000','04','rva'), ('145000','04','rva'),
        ('149000','04','rva'), ('007000','04','rva'), ('033000','04','rva'),
        ('097000','04','rva'), ('101000','04','rva'), ('103000','04','rva'),
        ('119000','04','rva'), ('570000','05','rva'), ('670000','05','rva'),
        ('730000','05','rva'),
        -- swva (Southwest Virginia)
        ('105000','04','swva'), ('027000','04','swva'), ('051000','04','swva'),
        ('167000','04','swva'), ('169000','04','swva'), ('185000','04','swva'),
        ('195000','04','swva'), ('197000','04','swva'), ('021000','04','swva'),
        ('023000','04','swva'), ('035000','04','swva'), ('045000','04','swva'),
        ('063000','04','swva'), ('067000','04','swva'), ('071000','04','swva'),
        ('077000','04','swva'), ('089000','04','swva'), ('141000','04','swva'),
        ('143000','04','swva'), ('163000','04','swva'), ('191000','04','swva'),
        ('720000','05','swva'), ('770000','05','swva'), ('775000','05','swva'),
        ('520000','05','swva'), ('580000','05','swva'), ('590000','05','swva'),
        ('640000','05','swva'), ('690000','05','swva'), ('750000','05','swva')
    ) AS t(AREA, AREATYPE, region_code)
),

-- Virginia statewide (seasonally adjusted)
virginia_trend AS (
    SELECT
        lf.PERIODYEAR,
        lf.PERIOD,
        lf.UNEMPLOYEDRATE AS urate,
        'Virginia' AS series,
        'virginia' AS region_code
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
        'us_national' AS region_code
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
    LEFT JOIN region_mapping rm ON lf.AREA = rm.AREA AND lf.AREATYPE = rm.AREATYPE
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
        region_code
    FROM region_trend
)

SELECT PERIODYEAR, PERIOD, series, region_code, urate FROM virginia_trend
UNION ALL
SELECT PERIODYEAR, PERIOD, series, region_code, urate FROM us_trend
UNION ALL
SELECT PERIODYEAR, PERIOD, series, region_code, urate FROM region_trend_labeled
ORDER BY region_code, PERIODYEAR, PERIOD;


-- =============================================================================
-- QUERY 3: JOBS ADDED BY INDUSTRY (TOP 5) - STATEWIDE + PER REGION
-- Returns: Quarter-over-quarter employment change by BLS supersector
--          Uses QCEW (Quarterly Census of Employment and Wages)
-- Note: "Government" combines federal + state + local ownership
-- scope: 'statewide' or region_code (nova, rva, hampton, swva, central)
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
-- STATEWIDE (AREATYPE = '01') - same as original
-- =============================================================================
curr_emp_state AS (
    SELECT TRIM(i.INDCODE) AS indcode, i.OWNERSHIP, i.QUARTERAVGEMP
    FROM WID_DB.WID.INDUSTRY i
    CROSS JOIN current_q cq
    WHERE i.STFIPS = '51' AND i.AREATYPE = '01'
      AND i.PERIODYEAR = cq.yr AND i.PERIOD = cq.qtr
),
prev_emp_state AS (
    SELECT TRIM(i.INDCODE) AS indcode, i.OWNERSHIP, i.QUARTERAVGEMP
    FROM WID_DB.WID.INDUSTRY i
    CROSS JOIN prior_q pq
    WHERE i.STFIPS = '51' AND i.AREATYPE = '01'
      AND i.PERIODYEAR = pq.yr AND i.PERIOD = pq.qtr
),

-- Private sector changes (statewide)
private_change_state AS (
    SELECT
        'statewide' AS scope,
        s.sector_name,
        c.QUARTERAVGEMP AS current_emp,
        p.QUARTERAVGEMP AS prior_emp,
        c.QUARTERAVGEMP - p.QUARTERAVGEMP AS jobs_added
    FROM industry_sectors s
    JOIN curr_emp_state c ON c.indcode = s.indcode AND c.OWNERSHIP = s.ownership
    JOIN prev_emp_state p ON p.indcode = s.indcode AND p.OWNERSHIP = s.ownership
),

-- Government: combine federal (1) + state (2) + local (3) for indcode 1028 (statewide)
gov_change_state AS (
    SELECT
        'statewide' AS scope,
        'Government' AS sector_name,
        SUM(c.QUARTERAVGEMP) AS current_emp,
        SUM(p.QUARTERAVGEMP) AS prior_emp,
        SUM(c.QUARTERAVGEMP) - SUM(p.QUARTERAVGEMP) AS jobs_added
    FROM curr_emp_state c
    JOIN prev_emp_state p ON c.indcode = p.indcode AND c.OWNERSHIP = p.OWNERSHIP
    WHERE c.indcode = '1028' AND c.OWNERSHIP IN ('1','2','3')
),

-- =============================================================================
-- PER-REGION (AREATYPE IN '04','05') - aggregated by macro-region
-- =============================================================================
region_mapping AS (
    SELECT AREA, AREATYPE, region_code FROM (VALUES
        -- nova (Northern Virginia)
        ('013000','04','nova'), ('510000','05','nova'), ('600000','05','nova'),
        ('107000','04','nova'), ('153000','04','nova'), ('179000','04','nova'),
        ('683000','05','nova'), ('685000','05','nova'), ('059000','04','nova'),
        ('061000','04','nova'), ('187000','04','nova'), ('630000','05','nova'),
        ('099000','04','nova'), ('157000','04','nova'),
        -- hampton (Hampton Roads)
        ('810000','05','hampton'), ('800000','05','hampton'), ('700000','05','hampton'),
        ('740000','05','hampton'), ('735000','05','hampton'), ('650000','05','hampton'),
        ('830000','05','hampton'), ('093000','04','hampton'), ('095000','04','hampton'),
        ('073000','04','hampton'), ('115000','04','hampton'), ('199000','04','hampton'),
        ('181000','04','hampton'), ('550000','05','hampton'), ('620000','05','hampton'),
        ('665000','05','hampton'), ('175000','04','hampton'), ('001000','04','hampton'),
        -- rva (Richmond Metro)
        ('760000','05','rva'), ('087000','04','rva'), ('041000','04','rva'),
        ('085000','04','rva'), ('127000','04','rva'), ('145000','04','rva'),
        ('149000','04','rva'), ('007000','04','rva'), ('033000','04','rva'),
        ('097000','04','rva'), ('101000','04','rva'), ('103000','04','rva'),
        ('119000','04','rva'), ('570000','05','rva'), ('670000','05','rva'),
        ('730000','05','rva'),
        -- swva (Southwest Virginia)
        ('105000','04','swva'), ('027000','04','swva'), ('051000','04','swva'),
        ('167000','04','swva'), ('169000','04','swva'), ('185000','04','swva'),
        ('195000','04','swva'), ('197000','04','swva'), ('021000','04','swva'),
        ('023000','04','swva'), ('035000','04','swva'), ('045000','04','swva'),
        ('063000','04','swva'), ('067000','04','swva'), ('071000','04','swva'),
        ('077000','04','swva'), ('089000','04','swva'), ('141000','04','swva'),
        ('143000','04','swva'), ('163000','04','swva'), ('191000','04','swva'),
        ('720000','05','swva'), ('770000','05','swva'), ('775000','05','swva'),
        ('520000','05','swva'), ('580000','05','swva'), ('590000','05','swva'),
        ('640000','05','swva'), ('690000','05','swva'), ('750000','05','swva')
    ) AS t(AREA, AREATYPE, region_code)
),

-- All VA counties with region assignment (central = everything else)
all_va_counties AS (
    SELECT DISTINCT lf.AREA, lf.AREATYPE, COALESCE(rm.region_code, 'central') AS region_code
    FROM WID_DB.WID.LABORFORCE lf
    LEFT JOIN region_mapping rm ON lf.AREA = rm.AREA AND lf.AREATYPE = rm.AREATYPE
    WHERE lf.STFIPS = '51' AND lf.AREATYPE IN ('04','05')
),

-- Aggregate county INDUSTRY data to region level FIRST, then compare quarters
curr_region_agg AS (
    SELECT
        ac.region_code,
        TRIM(i.INDCODE) AS indcode,
        i.OWNERSHIP,
        SUM(i.QUARTERAVGEMP) AS total_emp
    FROM WID_DB.WID.INDUSTRY i
    JOIN all_va_counties ac ON i.AREA = ac.AREA AND i.AREATYPE = ac.AREATYPE
    CROSS JOIN current_q cq
    WHERE i.STFIPS = '51' AND i.AREATYPE IN ('04','05')
      AND i.PERIODYEAR = cq.yr AND i.PERIOD = cq.qtr
    GROUP BY ac.region_code, TRIM(i.INDCODE), i.OWNERSHIP
),
prev_region_agg AS (
    SELECT
        ac.region_code,
        TRIM(i.INDCODE) AS indcode,
        i.OWNERSHIP,
        SUM(i.QUARTERAVGEMP) AS total_emp
    FROM WID_DB.WID.INDUSTRY i
    JOIN all_va_counties ac ON i.AREA = ac.AREA AND i.AREATYPE = ac.AREATYPE
    CROSS JOIN prior_q pq
    WHERE i.STFIPS = '51' AND i.AREATYPE IN ('04','05')
      AND i.PERIODYEAR = pq.yr AND i.PERIOD = pq.qtr
    GROUP BY ac.region_code, TRIM(i.INDCODE), i.OWNERSHIP
),

-- Private sector per-region
private_change_region AS (
    SELECT
        c.region_code AS scope,
        s.sector_name,
        c.total_emp AS current_emp,
        p.total_emp AS prior_emp,
        c.total_emp - p.total_emp AS jobs_added
    FROM industry_sectors s
    JOIN curr_region_agg c ON c.indcode = s.indcode AND c.OWNERSHIP = s.ownership
    JOIN prev_region_agg p ON p.indcode = s.indcode AND p.OWNERSHIP = s.ownership
      AND p.region_code = c.region_code
),

-- Government per-region: combine federal (1) + state (2) + local (3) for indcode 1028
gov_change_region AS (
    SELECT
        c.region_code AS scope,
        'Government' AS sector_name,
        SUM(c.total_emp) AS current_emp,
        SUM(p.total_emp) AS prior_emp,
        SUM(c.total_emp) - SUM(p.total_emp) AS jobs_added
    FROM curr_region_agg c
    JOIN prev_region_agg p ON c.indcode = p.indcode AND c.OWNERSHIP = p.OWNERSHIP
      AND c.region_code = p.region_code
    WHERE c.indcode = '1028' AND c.OWNERSHIP IN ('1','2','3')
    GROUP BY c.region_code
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


-- =============================================================================
-- QUERY 2B: PER-COUNTY UNEMPLOYMENT TREND
-- Returns: Monthly NSA unemployment rate per county/independent city over 36 months
-- Same month window as Query 2 (DATEADD-based month_series)
-- Output columns: AREA, AREATYPE, PERIODYEAR, PERIOD, UNEMPLOYEDRATE
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
)

SELECT
    lf.AREA,
    lf.AREATYPE,
    lf.PERIODYEAR,
    lf.PERIOD,
    lf.UNEMPLOYEDRATE
FROM WID_DB.WID.LABORFORCE lf
JOIN month_series ms ON lf.PERIODYEAR = ms.yr AND lf.PERIOD = ms.mo
WHERE lf.STFIPS = '51'
  AND lf.AREATYPE IN ('04','05')
  AND lf.ADJUSTED = 'U'
  AND lf.PERIODTYPE = 'MN'
ORDER BY lf.AREA, lf.PERIODYEAR, lf.PERIOD;
