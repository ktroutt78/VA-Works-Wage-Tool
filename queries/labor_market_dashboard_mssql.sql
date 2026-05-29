-- =============================================================================
-- LABOR MARKET SNAPSHOT DASHBOARD — SQL Server (T-SQL) — v3
-- Aligned to actual data conventions discovered in WID.dbo:
--
--   AreaType:          '01' = state-level (used by both LABORFORCE and INDUSTRY)
--                      '04' = counties + independent cities (single AreaType)
--                      '15' = LWDAs (in INDUSTRY directly; in LABORFORCE: not
--                             present, so LWDA roll-up via SUBGEOGRAPHIES)
--   AreaTypeVersion:   MAX(AreaTypeVersion) per (StFips, AreaType) — anchored
--                      separately per table since fact/dim vintages diverge
--                      (e.g. INDUSTRY '15' is at '0001'; GEOGRAPHIES '15' is at
--                      '0002'). Each table's vintage CTE filters that table.
--   LABORFORCE.Adjusted: '1' = seasonally adjusted, '0' = unadjusted.
--   PeriodType (LABORFORCE): '01' = Annual, '03' = Monthly.
--   PeriodType (INDUSTRY):   '01' = Annual, '02' = Quarterly.
--   Period: '00' (annual), '01'..'12' (monthly), '01'..'04' (quarterly).
--
-- Region scheme: 14 Virginia LWDAs. The synthetic "Combined Projections Area
-- (LWDA XI and XII)" is excluded by AreaName.
--
-- Target: SQL Server 2016+ (recursive CTE for month offsets).
-- Read-only on LABORFORCE, INDUSTRY, GEOGRAPHIES, SUBGEOGRAPHIES.
-- =============================================================================


-- =============================================================================
-- QUERY 1: EMPLOYMENT RATE BY LOCALITY
-- =============================================================================
WITH
-- ── vintage anchors (per table) ─────────────────────────────────────────────
lf_vintage AS (
    SELECT StFips, AreaType, MAX(AreaTypeVersion) AS AreaTypeVersion
    FROM WID.dbo.LABORFORCE
    GROUP BY StFips, AreaType
),
g_vintage AS (
    SELECT StFips, AreaType, MAX(AreaTypeVersion) AS AreaTypeVersion
    FROM WID.dbo.GEOGRAPHIES
    GROUP BY StFips, AreaType
),
sg_vintage AS (
    SELECT StFips, AreaType, MAX(AreaTypeVersion) AS AreaTypeVersion
    FROM WID.dbo.SUBGEOGRAPHIES
    GROUP BY StFips, AreaType
),
-- ── LWDA mapping (SubGeographies, joined to GEOGRAPHIES for the name) ───────
region_mapping AS (
    SELECT
        sg.SubArea          AS Area,
        sg.SubAreaType      AS AreaType,
        sg.Area             AS lwda_code,
        g.AreaName          AS lwda_name,
        -- Strip " Region" and " (LWDA X)" suffix for clean display:
        --   "Shenandoah Valley Region (LWDA IV)" -> "Shenandoah Valley"
        --   "Hampton Roads (LWDA XIV)"           -> "Hampton Roads"
        --   "New River/Mt. Rogers Region (LWDA II)" -> "New River/Mt. Rogers"
        LTRIM(RTRIM(REPLACE(
            LEFT(g.AreaName, CHARINDEX(' (LWDA', g.AreaName + ' (LWDA') - 1),
            ' Region', ''
        ))) AS lwda_short_name
    FROM WID.dbo.SUBGEOGRAPHIES sg
    JOIN sg_vintage sgv
      ON sg.StFips = sgv.StFips AND sg.AreaType = sgv.AreaType
     AND sg.AreaTypeVersion = sgv.AreaTypeVersion
    JOIN WID.dbo.GEOGRAPHIES g
      ON g.StFips = sg.StFips AND g.AreaType = sg.AreaType AND g.Area = sg.Area
    JOIN g_vintage gv
      ON g.StFips = gv.StFips AND g.AreaType = gv.AreaType
     AND g.AreaTypeVersion = gv.AreaTypeVersion
    WHERE sg.StFips = '51' AND sg.AreaType = '15'
      AND g.AreaName NOT LIKE '%Combined%'
),
-- ── period anchors ──────────────────────────────────────────────────────────
latest_period AS (
    -- Anchor to county NSA (lags state SA by ~1 mo); state SA always exists
    -- at this month too, keeping the choropleth and the KPIs at the same period.
    SELECT MAX(CONCAT(lf.PeriodYear, '-', lf.Period)) AS max_ym
    FROM WID.dbo.LABORFORCE lf
    JOIN lf_vintage lfv
      ON lf.StFips = lfv.StFips AND lf.AreaType = lfv.AreaType
     AND lf.AreaTypeVersion = lfv.AreaTypeVersion
    WHERE lf.StFips = '51' AND lf.AreaType = '04'
      AND lf.Adjusted = '0' AND lf.PeriodType = '03'
      AND lf.UnemployedRate IS NOT NULL
),
current_month AS (
    SELECT SUBSTRING(max_ym, 1, 4) AS yr, SUBSTRING(max_ym, 6, 2) AS mo FROM latest_period
),
prior_month AS (
    SELECT
        CASE WHEN mo = '01' THEN CAST(CAST(yr AS INT) - 1 AS VARCHAR(4)) ELSE yr END AS yr,
        CASE WHEN mo = '01' THEN '12' ELSE RIGHT('0' + CAST(CAST(mo AS INT) - 1 AS VARCHAR(2)), 2) END AS mo
    FROM current_month
),
-- ── locality data ───────────────────────────────────────────────────────────
county_data AS (
    SELECT
        lf.Area, g.AreaName, lf.AreaType,
        lf.Employed, lf.LaborForce AS LF,
        lf.UnemployedRate,
        ROUND(100.0 - lf.UnemployedRate, 1) AS employment_rate,
        rm.lwda_code, rm.lwda_name, rm.lwda_short_name
    FROM WID.dbo.LABORFORCE lf
    JOIN lf_vintage lfv
      ON lf.StFips = lfv.StFips AND lf.AreaType = lfv.AreaType
     AND lf.AreaTypeVersion = lfv.AreaTypeVersion
    JOIN WID.dbo.GEOGRAPHIES g
      ON g.StFips = lf.StFips AND g.AreaType = lf.AreaType AND g.Area = lf.Area
    JOIN g_vintage gv
      ON g.StFips = gv.StFips AND g.AreaType = gv.AreaType
     AND g.AreaTypeVersion = gv.AreaTypeVersion
    LEFT JOIN region_mapping rm
      ON lf.Area = rm.Area AND lf.AreaType = rm.AreaType
    CROSS JOIN current_month cm
    WHERE lf.StFips = '51' AND lf.AreaType = '04'
      AND lf.Adjusted = '0' AND lf.PeriodType = '03'
      AND lf.PeriodYear = cm.yr AND lf.Period = cm.mo
),
va_current AS (
    SELECT lf.UnemployedRate, ROUND(100.0 - lf.UnemployedRate, 1) AS employment_rate
    FROM WID.dbo.LABORFORCE lf
    JOIN lf_vintage lfv
      ON lf.StFips = lfv.StFips AND lf.AreaType = lfv.AreaType
     AND lf.AreaTypeVersion = lfv.AreaTypeVersion
    CROSS JOIN current_month cm
    WHERE lf.StFips = '51' AND lf.AreaType = '01'
      AND lf.Adjusted = '1' AND lf.PeriodType = '03'
      AND lf.PeriodYear = cm.yr AND lf.Period = cm.mo
),
va_prior AS (
    SELECT lf.UnemployedRate, ROUND(100.0 - lf.UnemployedRate, 1) AS employment_rate
    FROM WID.dbo.LABORFORCE lf
    JOIN lf_vintage lfv
      ON lf.StFips = lfv.StFips AND lf.AreaType = lfv.AreaType
     AND lf.AreaTypeVersion = lfv.AreaTypeVersion
    CROSS JOIN prior_month pm
    WHERE lf.StFips = '51' AND lf.AreaType = '01'
      AND lf.Adjusted = '1' AND lf.PeriodType = '03'
      AND lf.PeriodYear = pm.yr AND lf.Period = pm.mo
),
us_current AS (
    SELECT
        ROUND(100.0 - (CAST(SUM(lf.Unemployed) AS FLOAT) / NULLIF(SUM(lf.LaborForce),0) * 100), 1) AS employment_rate,
        ROUND(CAST(SUM(lf.Unemployed) AS FLOAT) / NULLIF(SUM(lf.LaborForce),0) * 100, 1) AS unemployedrate
    FROM WID.dbo.LABORFORCE lf
    JOIN lf_vintage lfv
      ON lf.StFips = lfv.StFips AND lf.AreaType = lfv.AreaType
     AND lf.AreaTypeVersion = lfv.AreaTypeVersion
    CROSS JOIN current_month cm
    WHERE lf.AreaType = '01'
      AND lf.Adjusted = '1' AND lf.PeriodType = '03'
      AND lf.PeriodYear = cm.yr AND lf.Period = cm.mo
      AND lf.Unemployed IS NOT NULL
    HAVING COUNT(*) >= 50
),
us_prior AS (
    SELECT
        ROUND(100.0 - (CAST(SUM(lf.Unemployed) AS FLOAT) / NULLIF(SUM(lf.LaborForce),0) * 100), 1) AS employment_rate,
        ROUND(CAST(SUM(lf.Unemployed) AS FLOAT) / NULLIF(SUM(lf.LaborForce),0) * 100, 1) AS unemployedrate
    FROM WID.dbo.LABORFORCE lf
    JOIN lf_vintage lfv
      ON lf.StFips = lfv.StFips AND lf.AreaType = lfv.AreaType
     AND lf.AreaTypeVersion = lfv.AreaTypeVersion
    CROSS JOIN prior_month pm
    WHERE lf.AreaType = '01'
      AND lf.Adjusted = '1' AND lf.PeriodType = '03'
      AND lf.PeriodYear = pm.yr AND lf.Period = pm.mo
      AND lf.Unemployed IS NOT NULL
    HAVING COUNT(*) >= 50
)
SELECT 'COUNTY' AS record_type, cd.Area, cd.AreaName, cd.AreaType,
       cd.employment_rate, cd.UnemployedRate, cd.Employed, cd.LF AS LaborForce,
       CAST(NULL AS DECIMAL(5,1)) AS delta_vs_prior,
       cd.lwda_code, cd.lwda_name, cd.lwda_short_name
FROM county_data cd
UNION ALL
SELECT 'KPI_VIRGINIA', '000051', 'Virginia', '01',
       vc.employment_rate, vc.UnemployedRate,
       CAST(NULL AS INT), CAST(NULL AS INT),
       ROUND(vc.employment_rate - vp.employment_rate, 1),
       CAST(NULL AS VARCHAR(6)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS VARCHAR(60))
FROM va_current vc, va_prior vp
UNION ALL
SELECT 'KPI_US_AVERAGE', CAST(NULL AS VARCHAR(6)), 'U.S. Average', CAST(NULL AS VARCHAR(2)),
       uc.employment_rate, uc.unemployedrate,
       CAST(NULL AS INT), CAST(NULL AS INT),
       ROUND(uc.employment_rate - up.employment_rate, 1),
       CAST(NULL AS VARCHAR(6)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS VARCHAR(60))
FROM us_current uc, us_prior up
ORDER BY record_type, AreaName;
GO


-- =============================================================================
-- QUERY 2: UNEMPLOYMENT RATE TRENDING
--   state_sa     — Virginia statewide, seasonally adjusted (always shown)
--   national_sa  — U.S. National, seasonally adjusted (always shown)
--   county_nsa   — per county/independent city, NSA (shown only when county is
--                  selected on the choropleth; front-end filters to one)
-- =============================================================================
WITH
lf_vintage AS (
    SELECT StFips, AreaType, MAX(AreaTypeVersion) AS AreaTypeVersion
    FROM WID.dbo.LABORFORCE GROUP BY StFips, AreaType
),
latest AS (
    -- Anchor to county NSA (lags state SA by ~1 mo) so the 36-month window
    -- ends where county data is available; state SA at that month always exists.
    SELECT MAX(CONCAT(lf.PeriodYear, '-', lf.Period)) AS max_ym
    FROM WID.dbo.LABORFORCE lf
    JOIN lf_vintage lfv
      ON lf.StFips = lfv.StFips AND lf.AreaType = lfv.AreaType
     AND lf.AreaTypeVersion = lfv.AreaTypeVersion
    WHERE lf.StFips = '51' AND lf.AreaType = '04'
      AND lf.Adjusted = '0' AND lf.PeriodType = '03'
      AND lf.UnemployedRate IS NOT NULL
),
end_date AS (
    SELECT CONVERT(date, SUBSTRING(max_ym, 1, 4) + '-' + SUBSTRING(max_ym, 6, 2) + '-01', 23) AS dt
    FROM latest
),
month_offsets AS (
    SELECT 0 AS n UNION ALL SELECT n + 1 FROM month_offsets WHERE n < 35
),
month_series AS (
    SELECT FORMAT(DATEADD(month, -mo.n, ed.dt), 'yyyy') AS yr,
           FORMAT(DATEADD(month, -mo.n, ed.dt), 'MM')   AS mo
    FROM end_date ed CROSS JOIN month_offsets mo
),
virginia_trend AS (
    SELECT lf.PeriodYear, lf.Period, lf.UnemployedRate AS urate,
           'Virginia' AS series, 'virginia' AS region_code, 'state_sa' AS lvl
    FROM WID.dbo.LABORFORCE lf
    JOIN lf_vintage lfv
      ON lf.StFips = lfv.StFips AND lf.AreaType = lfv.AreaType
     AND lf.AreaTypeVersion = lfv.AreaTypeVersion
    JOIN month_series ms ON lf.PeriodYear = ms.yr AND lf.Period = ms.mo
    WHERE lf.StFips = '51' AND lf.AreaType = '01'
      AND lf.Adjusted = '1' AND lf.PeriodType = '03'
      AND lf.UnemployedRate IS NOT NULL
),
us_trend AS (
    SELECT lf.PeriodYear, lf.Period,
           ROUND(CAST(SUM(lf.Unemployed) AS FLOAT) / NULLIF(SUM(lf.LaborForce), 0) * 100, 1) AS urate,
           'U.S. National' AS series, 'us_national' AS region_code, 'national_sa' AS lvl
    FROM WID.dbo.LABORFORCE lf
    JOIN lf_vintage lfv
      ON lf.StFips = lfv.StFips AND lf.AreaType = lfv.AreaType
     AND lf.AreaTypeVersion = lfv.AreaTypeVersion
    JOIN month_series ms ON lf.PeriodYear = ms.yr AND lf.Period = ms.mo
    WHERE lf.AreaType = '01'
      AND lf.Adjusted = '1' AND lf.PeriodType = '03'
      AND lf.Unemployed IS NOT NULL
    GROUP BY lf.PeriodYear, lf.Period
    HAVING COUNT(*) >= 50
),
county_trend AS (
    SELECT lf.Area, lf.AreaType, lf.PeriodYear, lf.Period, lf.UnemployedRate, 'county_nsa' AS lvl
    FROM WID.dbo.LABORFORCE lf
    JOIN lf_vintage lfv
      ON lf.StFips = lfv.StFips AND lf.AreaType = lfv.AreaType
     AND lf.AreaTypeVersion = lfv.AreaTypeVersion
    JOIN month_series ms ON lf.PeriodYear = ms.yr AND lf.Period = ms.mo
    WHERE lf.StFips = '51' AND lf.AreaType = '04'
      AND lf.Adjusted = '0' AND lf.PeriodType = '03'
)
SELECT PeriodYear, Period, series, region_code, urate, lvl,
       CAST(NULL AS VARCHAR(6))  AS Area,
       CAST(NULL AS VARCHAR(2))  AS AreaType,
       CAST(NULL AS DECIMAL(5,1)) AS UnemployedRate
FROM virginia_trend
UNION ALL
SELECT PeriodYear, Period, series, region_code, urate, lvl,
       CAST(NULL AS VARCHAR(6)), CAST(NULL AS VARCHAR(2)), CAST(NULL AS DECIMAL(5,1))
FROM us_trend
UNION ALL
SELECT PeriodYear, Period,
       CAST(NULL AS VARCHAR(60)) AS series,
       CAST(NULL AS VARCHAR(6))  AS region_code,
       CAST(NULL AS DECIMAL(5,1)) AS urate,
       lvl, Area, AreaType, UnemployedRate
FROM county_trend
ORDER BY lvl, region_code, Area, PeriodYear, Period;
GO


-- =============================================================================
-- QUERY 3: JOBS ADDED BY INDUSTRY (TOP 5) — STATEWIDE + PER LWDA
-- INDUSTRY has LWDA rows directly at AreaType='15' — no county rollup needed.
-- =============================================================================
WITH
i_vintage AS (
    -- Scoped to VA + only the AreaTypes Q3 reads (state + LWDA)
    SELECT AreaType, MAX(AreaTypeVersion) AS AreaTypeVersion
    FROM WID.dbo.INDUSTRY
    WHERE StFips = '51' AND AreaType IN ('01', '15')
    GROUP BY AreaType
),
g_vintage AS (
    -- Scoped to VA LWDA dim lookups
    SELECT AreaType, MAX(AreaTypeVersion) AS AreaTypeVersion
    FROM WID.dbo.GEOGRAPHIES
    WHERE StFips = '51' AND AreaType = '15'
    GROUP BY AreaType
),
-- LWDA list (with names) at current GEOGRAPHIES vintage, excluding the synthetic
lwda_dim AS (
    SELECT g.Area AS lwda_code,
           g.AreaName AS lwda_name,
           LTRIM(RTRIM(REPLACE(
               LEFT(g.AreaName, CHARINDEX(' (LWDA', g.AreaName + ' (LWDA') - 1),
               ' Region', ''
           ))) AS lwda_short_name
    FROM WID.dbo.GEOGRAPHIES g
    JOIN g_vintage gv
      ON g.AreaType = gv.AreaType AND g.AreaTypeVersion = gv.AreaTypeVersion
    WHERE g.StFips = '51' AND g.AreaType = '15'
      AND g.AreaName NOT LIKE '%Combined%'
),
latest_quarter AS (
    SELECT MAX(CONCAT(i.PeriodYear, '-', i.Period)) AS max_yq
    FROM WID.dbo.INDUSTRY i
    JOIN i_vintage iv
      ON i.AreaType = iv.AreaType AND i.AreaTypeVersion = iv.AreaTypeVersion
    WHERE i.StFips = '51' AND i.AreaType = '01' AND i.PeriodType = '02'
      AND i.Period <> '00'
),
current_q AS (
    SELECT SUBSTRING(max_yq, 1, 4) AS yr, SUBSTRING(max_yq, 6, 2) AS qtr FROM latest_quarter
),
prior_q AS (
    SELECT
        CASE WHEN qtr = '01' THEN CAST(CAST(yr AS INT) - 1 AS VARCHAR(4)) ELSE yr END AS yr,
        CASE WHEN qtr = '01' THEN '04' ELSE RIGHT('0' + CAST(CAST(qtr AS INT) - 1 AS VARCHAR(2)), 2) END AS qtr
    FROM current_q
),
industry_sectors AS (
    SELECT * FROM (VALUES
        ('1024','50','Professional & Business'),
        ('1025','50','Education & Health'),
        ('1026','50','Leisure & Hospitality'),
        ('1021','50','Trade & Transportation'),
        ('1013','50','Manufacturing'),
        ('1012','50','Construction'),
        ('1011','50','Natural Resources & Mining'),
        ('1022','50','Information'),
        ('1023','50','Financial Activities'),
        ('1027','50','Other Services')
    ) AS t(indcode, ownership, sector_name)
),
-- ── STATEWIDE (AreaType='01') ───────────────────────────────────────────────
state_both_qtrs AS (
    SELECT TRIM(i.IndCode) AS indcode, i.Ownership, i.PeriodYear, i.Period, i.QuarterAvgEmp
    FROM WID.dbo.INDUSTRY i
    JOIN i_vintage iv
      ON i.AreaType = iv.AreaType AND i.AreaTypeVersion = iv.AreaTypeVersion
    CROSS JOIN current_q cq CROSS JOIN prior_q pq
    WHERE i.StFips = '51' AND i.AreaType = '01' AND i.PeriodType = '02'
      -- Push supersector + ownership filters down to the scan
      AND i.IndCode IN ('1011','1012','1013','1021','1022','1023','1024','1025','1026','1027','1028')
      AND i.Ownership IN ('10','20','30','50')
      AND ((i.PeriodYear = cq.yr AND i.Period = cq.qtr)
        OR (i.PeriodYear = pq.yr AND i.Period = pq.qtr))
),
state_change AS (
    SELECT indcode, Ownership, PeriodYear, Period,
           QuarterAvgEmp AS current_emp,
           LAG(QuarterAvgEmp) OVER (PARTITION BY indcode, Ownership ORDER BY PeriodYear, Period) AS prior_emp
    FROM state_both_qtrs
),
state_current_only AS (
    SELECT sc.indcode, sc.Ownership, sc.current_emp, sc.prior_emp
    FROM state_change sc
    WHERE EXISTS (SELECT 1 FROM current_q cq WHERE sc.PeriodYear = cq.yr AND sc.Period = cq.qtr)
),
private_change_state AS (
    SELECT 'statewide' AS scope,
           CAST(NULL AS VARCHAR(60)) AS lwda_name,
           CAST(NULL AS VARCHAR(60)) AS lwda_short_name,
           s.sector_name,
           COALESCE(sc.current_emp, 0) AS current_emp,
           COALESCE(sc.prior_emp, 0)   AS prior_emp,
           COALESCE(sc.current_emp, 0) - COALESCE(sc.prior_emp, 0) AS jobs_added
    FROM industry_sectors s
    LEFT JOIN state_current_only sc ON sc.indcode = s.indcode AND sc.Ownership = s.ownership
),
gov_change_state AS (
    SELECT 'statewide' AS scope,
           CAST(NULL AS VARCHAR(60)) AS lwda_name,
           CAST(NULL AS VARCHAR(60)) AS lwda_short_name,
           'Government' AS sector_name,
           SUM(COALESCE(current_emp, 0)) AS current_emp,
           SUM(COALESCE(prior_emp, 0))   AS prior_emp,
           SUM(COALESCE(current_emp, 0)) - SUM(COALESCE(prior_emp, 0)) AS jobs_added
    FROM state_current_only
    WHERE indcode = '1028' AND Ownership IN ('10','20','30')
),
-- ── PER-LWDA (AreaType='15' direct — no county rollup) ──────────────────────
region_both_qtrs AS (
    SELECT i.Area AS lwda_code, TRIM(i.IndCode) AS indcode, i.Ownership,
           i.PeriodYear, i.Period, i.QuarterAvgEmp AS total_emp
    FROM WID.dbo.INDUSTRY i
    JOIN i_vintage iv
      ON i.AreaType = iv.AreaType AND i.AreaTypeVersion = iv.AreaTypeVersion
    JOIN lwda_dim ld ON i.Area = ld.lwda_code
    CROSS JOIN current_q cq CROSS JOIN prior_q pq
    WHERE i.StFips = '51' AND i.AreaType = '15' AND i.PeriodType = '02'
      -- Push supersector + ownership filters down to the scan
      AND i.IndCode IN ('1011','1012','1013','1021','1022','1023','1024','1025','1026','1027','1028')
      AND i.Ownership IN ('10','20','30','50')
      AND ((i.PeriodYear = cq.yr AND i.Period = cq.qtr)
        OR (i.PeriodYear = pq.yr AND i.Period = pq.qtr))
),
region_change AS (
    SELECT lwda_code, indcode, Ownership, PeriodYear, Period,
           total_emp AS current_emp,
           LAG(total_emp) OVER (PARTITION BY lwda_code, indcode, Ownership ORDER BY PeriodYear, Period) AS prior_emp
    FROM region_both_qtrs
),
region_current_only AS (
    SELECT rc.lwda_code, rc.indcode, rc.Ownership, rc.current_emp, rc.prior_emp
    FROM region_change rc
    WHERE EXISTS (SELECT 1 FROM current_q cq WHERE rc.PeriodYear = cq.yr AND rc.Period = cq.qtr)
),
private_change_region AS (
    SELECT ld.lwda_code AS scope, ld.lwda_name, ld.lwda_short_name, s.sector_name,
           COALESCE(rc.current_emp, 0) AS current_emp,
           COALESCE(rc.prior_emp, 0)   AS prior_emp,
           COALESCE(rc.current_emp, 0) - COALESCE(rc.prior_emp, 0) AS jobs_added
    FROM lwda_dim ld
    CROSS JOIN industry_sectors s
    LEFT JOIN region_current_only rc
      ON rc.lwda_code = ld.lwda_code AND rc.indcode = s.indcode AND rc.Ownership = s.ownership
),
gov_change_region AS (
    SELECT ld.lwda_code AS scope,
           MAX(ld.lwda_name) AS lwda_name,
           MAX(ld.lwda_short_name) AS lwda_short_name,
           'Government' AS sector_name,
           SUM(COALESCE(rc.current_emp, 0)) AS current_emp,
           SUM(COALESCE(rc.prior_emp, 0))   AS prior_emp,
           SUM(COALESCE(rc.current_emp, 0)) - SUM(COALESCE(rc.prior_emp, 0)) AS jobs_added
    FROM lwda_dim ld
    LEFT JOIN region_current_only rc
      ON rc.lwda_code = ld.lwda_code AND rc.indcode = '1028' AND rc.Ownership IN ('10','20','30')
    GROUP BY ld.lwda_code
),
all_sectors AS (
    SELECT * FROM private_change_state
    UNION ALL SELECT * FROM gov_change_state
    UNION ALL SELECT * FROM private_change_region
    UNION ALL SELECT * FROM gov_change_region
),
ranked AS (
    SELECT scope, lwda_name, lwda_short_name, sector_name, current_emp, prior_emp, jobs_added,
           ROW_NUMBER() OVER (PARTITION BY scope ORDER BY jobs_added DESC) AS rn
    FROM all_sectors
)
SELECT scope, lwda_name, lwda_short_name, sector_name, current_emp, prior_emp, jobs_added
FROM ranked
WHERE rn <= 5
ORDER BY scope, jobs_added DESC;
GO
