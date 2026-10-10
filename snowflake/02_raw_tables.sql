-- Synthetic exporter-day observations for fictional Vietnamese seafood exporters.
-- An exporter is one fictional seafood processing plant in one Vietnamese city shipping one product line.
-- Nothing is seeded as a prediction. Randomness is HASH-seeded, so every rebuild
-- is reproducible: per-exporter rejection propensity, hygiene drift between
-- pre-shipment lab tests, missed lab tests, product-weighted shipment issue types,
-- issues resolved without rejection, and two city-wide storm port closures.
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA RAW;
USE WAREHOUSE IDENTIFIER($DEMO_WH);

CREATE TABLE RAW.EXPORTERS AS
WITH exporters AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS EXPORTER_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 40))
), draws AS (
  SELECT EXPORTER_INDEX,
         MOD(ABS(HASH(EXPORTER_INDEX, 'vnaqx-age')), 1000000) / 1e6 AS U_AGE,
         MOD(ABS(HASH(EXPORTER_INDEX, 'vnaqx-rate')), 1000000) / 1e6 AS U_RATE,
         MOD(ABS(HASH(EXPORTER_INDEX, 'vnaqx-labtest')), 1000000) / 1e6 AS U_LABTEST,
         MOD(ABS(HASH(EXPORTER_INDEX, 'vnaqx-discipline')), 1000000) / 1e6 AS U_DISCIPLINE,
         MOD(ABS(HASH(EXPORTER_INDEX, 'vnaqx-tier')), 1000000) / 1e6 AS U_TIER
  FROM exporters
)
SELECT 'EXP-' || LPAD(EXPORTER_INDEX::VARCHAR, 4, '0') AS ID,
       'Synthetic exporter ' || LPAD(EXPORTER_INDEX::VARCHAR, 4, '0') AS NAME,
       -- 5 and 8 are coprime, so 40 exporters cover every city and product slot once.
       CASE MOD(EXPORTER_INDEX, 5) WHEN 0 THEN 'Ho Chi Minh City' WHEN 1 THEN 'Ca Mau'
            WHEN 2 THEN 'Can Tho' WHEN 3 THEN 'Long Xuyen' ELSE 'Nha Trang' END AS REGION,
       CASE MOD(EXPORTER_INDEX, 8) WHEN 0 THEN 'Whiteleg shrimp' WHEN 1 THEN 'Whiteleg shrimp'
            WHEN 2 THEN 'Whiteleg shrimp' WHEN 3 THEN 'Pangasius fillet' WHEN 4 THEN 'Pangasius fillet'
            WHEN 5 THEN 'Black tiger shrimp' WHEN 6 THEN 'Frozen squid' ELSE 'Canned tuna' END AS CATEGORY,
       EXPORTER_INDEX,
       1 + FLOOR(U_TIER * 3) AS RISK_TIER,
       ROUND(0.5 + U_AGE * 14.5, 1) AS EXPORTER_AGE_YEARS,
       -- Base daily probability of a rejected shipment 0.5%-3%; ~15% of exporters are
       -- chronically weak (x3).
       (0.005 + U_RATE * 0.025) * IFF(U_RATE > 0.85, 3, 1) AS BASE_REJECT_RATE,
       7 * (1 + FLOOR(U_LABTEST * 3)) AS LAB_TEST_INTERVAL_DAYS,
       0.5 + U_DISCIPLINE * 0.5 AS LAB_TEST_COMPLETION_PROB,
       'Active' AS STATUS
FROM draws;

CREATE TABLE RAW.EXPORTER_DAILY AS
WITH days AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS DAY_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 90))
), city_events AS (
  -- Two city-wide storm port closures; every exporter in the city raises a shipment
  -- issue that is resolved once the port reopens and reefer vessels sail again.
  SELECT * FROM VALUES (27, 'Nha Trang'), (64, 'Ca Mau') AS o(DAY_INDEX, REGION)
), base AS (
  SELECT s.ID AS ENTITY_ID, s.EXPORTER_INDEX, s.CATEGORY, s.REGION, s.EXPORTER_AGE_YEARS,
         s.BASE_REJECT_RATE, s.LAB_TEST_INTERVAL_DAYS, s.LAB_TEST_COMPLETION_PROB,
         d.DAY_INDEX,
         DATEADD('day', d.DAY_INDEX - 89, CURRENT_DATE()) AS EVENT_DATE,
         MOD(d.DAY_INDEX + s.EXPORTER_INDEX * 3, s.LAB_TEST_INTERVAL_DAYS) AS DAYS_SINCE_LAB_TEST,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'vnaqx-reject')), 1000000) / 1e6 AS U_REJECT,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'vnaqx-detect')), 1000000) / 1e6 AS U_DETECT,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'vnaqx-resolve')), 1000000) / 1e6 AS U_RESOLVE,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'vnaqx-type')), 1000000) / 1e6 AS U_TYPE,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'vnaqx-done')), 1000000) / 1e6 AS U_DONE,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'vnaqx-volume')), 1000000) / 1e6 AS U_VOLUME,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'vnaqx-noise')), 1000000) / 1e6 AS U_NOISE,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'vnaqx-late')), 1000000) / 1e6 AS U_LATE,
         e.REGION IS NOT NULL AS CITY_EVENT
  FROM RAW.EXPORTERS s CROSS JOIN days d
  LEFT JOIN city_events e ON e.DAY_INDEX = d.DAY_INDEX AND e.REGION = s.REGION
), labtest AS (
  SELECT *,
         IFF(DAYS_SINCE_LAB_TEST = 0, 1, 0) AS LAB_TEST_DUE,
         IFF(DAYS_SINCE_LAB_TEST = 0 AND U_DONE < LAB_TEST_COMPLETION_PROB, 1, 0) AS LAB_TEST_DONE,
         -- Hygiene drift rises between pre-shipment lab tests; weak lab test
         -- discipline carries it over.
         DAYS_SINCE_LAB_TEST / LAB_TEST_INTERVAL_DAYS + (1 - LAB_TEST_COMPLETION_PROB) AS DRIFT
  FROM base
), rejects AS (
  SELECT *,
         CASE WHEN U_REJECT < LEAST(0.5, BASE_REJECT_RATE * (0.4 + 1.6 * DRIFT) * (1 + 2 / (2 + EXPORTER_AGE_YEARS))) / 4 THEN 2
              WHEN U_REJECT < LEAST(0.5, BASE_REJECT_RATE * (0.4 + 1.6 * DRIFT) * (1 + 2 / (2 + EXPORTER_AGE_YEARS))) THEN 1
              ELSE 0 END AS REJECT_RISK_COUNT
  FROM labtest
), issues AS (
  SELECT *,
         -- About 80% of at-risk shipments raise an issue and end rejected at the
         -- destination; the rest arrive late without an issue.
         IFF(CITY_EVENT, 0, IFF(U_DETECT < 0.8, REJECT_RISK_COUNT, 0)) AS REJECTED_COUNT,
         -- Issues resolved without rejection: higher for squid, pangasius and black tiger shrimp.
         IFF(CITY_EVENT, 1, IFF(U_RESOLVE < CASE CATEGORY WHEN 'Frozen squid' THEN 0.18
                                                          WHEN 'Pangasius fillet' THEN 0.13
                                                          WHEN 'Black tiger shrimp' THEN 0.15 ELSE 0.09 END, 1, 0)) AS RESOLVED_COUNT
  FROM rejects
), measured AS (
  SELECT *,
         REJECTED_COUNT + RESOLVED_COUNT AS ISSUE_COUNT,
         CASE CATEGORY WHEN 'Whiteleg shrimp' THEN 6 WHEN 'Pangasius fillet' THEN 5 WHEN 'Black tiger shrimp' THEN 3
                       WHEN 'Frozen squid' THEN 2.5 ELSE 1.5 END
           * (0.7 + 0.6 * U_VOLUME) * (1 + 0.5 * REJECT_RISK_COUNT) AS SHIPMENT_RAW,
         CASE CATEGORY WHEN 'Whiteleg shrimp' THEN 210000 WHEN 'Pangasius fillet' THEN 95000
                       WHEN 'Black tiger shrimp' THEN 260000 WHEN 'Frozen squid' THEN 130000 ELSE 85000 END
           * (0.85 + 0.3 * U_NOISE) AS AVG_PRICE_USD
  FROM issues
), counted AS (
  -- A shipment issue always belongs to a shipment dispatched that day.
  SELECT *, GREATEST(ISSUE_COUNT, ROUND(SHIPMENT_RAW)) AS SHIPMENT_COUNT FROM measured
)
SELECT ENTITY_ID || '-' || TO_CHAR(EVENT_DATE, 'YYYYMMDD') AS EVENT_ID,
       ENTITY_ID, EVENT_DATE,
       SHIPMENT_COUNT,
       ROUND(SHIPMENT_COUNT * AVG_PRICE_USD, 0) AS SHIPMENT_VALUE_USD,
       ISSUE_COUNT, REJECTED_COUNT,
       IFF(REJECTED_COUNT > 0 AND U_LATE < 0.55, 1, 0) AS LATE_DELIVERY,
       CASE WHEN ISSUE_COUNT = 0 THEN 'None'
            WHEN CITY_EVENT THEN 'Storm port closure'
            WHEN CATEGORY = 'Whiteleg shrimp' THEN IFF(U_TYPE < 0.5, 'Health certificate mismatch', IFF(U_TYPE < 0.8, 'Antibiotic residue retest', 'Reefer booking rollover'))
            WHEN CATEGORY = 'Pangasius fillet' THEN IFF(U_TYPE < 0.55, 'Health certificate mismatch', 'Glazing net weight shortfall')
            WHEN CATEGORY = 'Black tiger shrimp' THEN IFF(U_TYPE < 0.45, 'Reefer booking rollover', IFF(U_TYPE < 0.8, 'Antibiotic residue retest', 'Thaw drip loss out of specification'))
            WHEN CATEGORY = 'Frozen squid' THEN IFF(U_TYPE < 0.45, 'Reefer booking rollover', IFF(U_TYPE < 0.8, 'Catch certificate mismatch', 'Health certificate mismatch'))
            ELSE IFF(U_TYPE < 0.5, 'Buyer specification change', IFF(U_TYPE < 0.75, 'Catch certificate mismatch', 'Can seam defect')) END AS ISSUE_TYPE,
       LAB_TEST_DUE, LAB_TEST_DONE,
       ROUND(4 + 6 * DRIFT + 9 * REJECT_RISK_COUNT + U_NOISE * 3, 2) AS DOC_DISCREPANCY_PCT,
       ROUND(18 + 12 * DRIFT + 16 * REJECT_RISK_COUNT + U_NOISE * 6, 1) AS AVG_CERT_TURNAROUND_HRS,
       CURRENT_TIMESTAMP() AS LOADED_AT
FROM counted;

-- Exporter document coverage (snapshot).
CREATE TABLE RAW.COMPLIANCE_DOCUMENTS AS
SELECT ID AS ENTITY_ID,
       CASE CATEGORY WHEN 'Whiteleg shrimp' THEN 'Health certificate file'
                     WHEN 'Pangasius fillet' THEN 'Farm registration record'
                     WHEN 'Black tiger shrimp' THEN 'Antibiotic test report'
                     WHEN 'Frozen squid' THEN 'Catch certificate file'
                     ELSE 'Retort process record' END AS DOC_TYPE,
       1 + MOD(ABS(HASH(ID, 'vnaqx-req')), 4) AS REQUIRED_QTY,
       MOD(ABS(HASH(ID, 'vnaqx-file')), 5) AS ON_FILE_QTY,
       IFF(MOD(ABS(HASH(ID, 'vnaqx-file')), 5) < 1 + MOD(ABS(HASH(ID, 'vnaqx-req')), 4),
           MOD(ABS(HASH(ID, 'vnaqx-pending')), 3), 0) AS PENDING_QTY,
       CURRENT_DATE() AS SNAPSHOT_DATE
FROM RAW.EXPORTERS;
