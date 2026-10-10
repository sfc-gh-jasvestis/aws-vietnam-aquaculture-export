-- ============================================================================
-- 06_INTELLIGENCE.SQL - search, anomaly detection, semantic view, agent,
-- live-shipment alert and on-demand refresh DAG.
-- Run with snowflake/run_intelligence.py (substitutes checked __DEMO_DB__ /
-- __DEMO_WH__ / __ALERT_EMAIL__). Requires 00-05, plus 08 (Snowflake only) or
-- aws/setup_aws.py (AWS build) for RAW.LIVE_SHIPMENTS.
-- Alerts and tasks are created SUSPENDED; run them with EXECUTE ALERT / EXECUTE TASK.
-- ============================================================================
USE DATABASE __DEMO_DB__;
CREATE SCHEMA IF NOT EXISTS SEARCH;
CREATE SCHEMA IF NOT EXISTS APP;

-- ---------- Synthetic shipment-issue knowledge base (clearly synthetic SOPs) ----------
CREATE OR REPLACE TABLE SEARCH.ISSUE_DOCS AS
WITH types AS (
  SELECT DISTINCT r.ISSUE_TYPE, a.CATEGORY
  FROM RAW.EXPORTER_DAILY r JOIN RAW.EXPORTERS a ON a.ID = r.ENTITY_ID
  WHERE r.REJECTED_COUNT > 0
)
SELECT
  'SOP-' || LPAD(ROW_NUMBER() OVER (ORDER BY CATEGORY, ISSUE_TYPE)::VARCHAR, 3, '0') AS DOC_ID,
  'SOP' AS DOC_TYPE,
  CATEGORY,
  ISSUE_TYPE,
  CATEGORY || ' - ' || ISSUE_TYPE || ' shipment issue handling' AS TITLE,
  'Synthetic demo SOP. Product line: ' || CATEGORY || '. Shipment issue type: ' || ISSUE_TYPE || '. '
  || 'Step 1: log a shipment case in the export operations system, notify the export manager, and hold the next container for the same buyer until a reviewer triages the case. '
  || 'Step 2: ' || CASE
       WHEN ISSUE_TYPE = 'Health certificate mismatch' THEN 'compare the health certificate against the commercial invoice, packing list and lot codes line by line, request a corrected certificate from the issuing office, and send the buyer the corrected copy before the reefer arrives.'
       WHEN ISSUE_TYPE = 'Antibiotic residue retest' THEN 'quarantine the retained samples for the lot, send a split sample to a second accredited laboratory, and release the next lot from the same grow-out farm only after both results are within the buyer specification.'
       WHEN ISSUE_TYPE = 'Reefer booking rollover' THEN 'ask the forwarder for the next sailing with reefer plugs available, confirm cold store space for the held containers, and give the buyer a revised arrival date in writing.'
       WHEN ISSUE_TYPE = 'Glazing net weight shortfall' THEN 'reweigh retained cartons after deglazing, check the glazing line settings for the production date, and agree a credit or replacement with the buyer.'
       WHEN ISSUE_TYPE = 'Thaw drip loss out of specification' THEN 'retest drip loss on retained cartons, check freezing tunnel and cold store temperature records for the lot, and agree sorting or replacement with the buyer.'
       WHEN ISSUE_TYPE = 'Catch certificate mismatch' THEN 'check the catch certificate against the vessel, landing date, species and net weight on the invoice, request a corrected document from the issuing office, and hold release until the buyer confirms it.'
       WHEN ISSUE_TYPE = 'Can seam defect' THEN 'pull retained cans from the same retort batch for a seam teardown, hold the batch until quality assurance signs off, and agree replacement or credit with the buyer.'
       WHEN ISSUE_TYPE = 'Buyer specification change' THEN 'confirm the revised pack size, count per kilogram, labelling and quantity with the buyer in writing, reissue the proforma invoice, and update the production plan before the next run.'
       ELSE 'review the issue against the exporter shipment history and escalate to the regional export manager if the cause is unclear.'
     END
  || ' Step 3: keep the case open and schedule an exporter quality review when, after triage, the exporter document discrepancy rate is above 20% or the average certificate turnaround time is above 36 hours. '
  || 'Step 4: close the case with the outcome; for a rejected or late shipment, send the buyer an update and add the case to the weekly export quality report.' AS CONTENT
FROM types;

CREATE OR REPLACE CORTEX SEARCH SERVICE SEARCH.ISSUE_SOP_SEARCH
  ON CONTENT
  ATTRIBUTES CATEGORY, ISSUE_TYPE
  WAREHOUSE = __DEMO_WH__
  TARGET_LAG = '7 days'
AS (SELECT DOC_ID, TITLE, CATEGORY, ISSUE_TYPE, CONTENT FROM SEARCH.ISSUE_DOCS);

-- ---------- Document discrepancy rate anomaly detection (train first 75 days, detect last 15) ----------
CREATE OR REPLACE VIEW ML.DOC_DISCREPANCY_SERIES AS
SELECT ENTITY_ID, EVENT_DATE::TIMESTAMP_NTZ AS TS, DOC_DISCREPANCY_PCT::FLOAT AS DOC_DISCREPANCY
FROM RAW.EXPORTER_DAILY;
CREATE OR REPLACE VIEW ML.DOC_DISCREPANCY_TRAIN AS
SELECT * FROM ML.DOC_DISCREPANCY_SERIES WHERE TS < (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.DOC_DISCREPANCY_SERIES);
CREATE OR REPLACE VIEW ML.DOC_DISCREPANCY_DETECT AS
SELECT * FROM ML.DOC_DISCREPANCY_SERIES WHERE TS >= (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.DOC_DISCREPANCY_SERIES);

CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION ML.DOC_DISCREPANCY_ANOMALY_MODEL(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.DOC_DISCREPANCY_TRAIN'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'DOC_DISCREPANCY',
  LABEL_COLNAME => '');

CREATE OR REPLACE TABLE ML.DOC_DISCREPANCY_ANOMALIES AS
SELECT SERIES::VARCHAR AS ENTITY_ID, TS::DATE AS EVENT_DATE, Y AS DOC_DISCREPANCY, FORECAST AS EXPECTED,
       LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, PERCENTILE
FROM TABLE(ML.DOC_DISCREPANCY_ANOMALY_MODEL!DETECT_ANOMALIES(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.DOC_DISCREPANCY_DETECT'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'DOC_DISCREPANCY'));

-- ---------- Semantic view ----------
CREATE OR REPLACE SEMANTIC VIEW APP.SEAFOOD_EXPORT_ANALYTICS
  TABLES (
    exporters AS CURATED.PERFORMANCE_SUMMARY PRIMARY KEY (ENTITY_ID)
      WITH SYNONYMS = ('entities', 'seafood exporters', 'processors')
      COMMENT = 'One row per exporter (city and product line), 90-day totals',
    risk AS ML.REJECT_RISK_SCORES PRIMARY KEY (ENTITY_ID)
      COMMENT = 'Latest next-7-day shipment-rejection probability per exporter',
    issues AS CURATED.ISSUE_SUMMARY PRIMARY KEY (ISSUE_TYPE)
      COMMENT = 'Shipment issues, rejected shipments and late deliveries by issue type, 90 days',
    daily AS CURATED.TREND_ANALYSIS PRIMARY KEY (METRIC_DATE)
      COMMENT = 'All-exporter totals per day'
  )
  RELATIONSHIPS (risk_exporter AS risk (ENTITY_ID) REFERENCES exporters)
  FACTS (
    exporters.issues_f AS ISSUE_COUNT,
    exporters.rejected_f AS REJECTED_COUNT,
    exporters.late_f AS LATE_DELIVERY_COUNT,
    exporters.shipments_f AS SHIPMENT_COUNT,
    exporters.value_f AS SHIPMENT_VALUE_USD,
    exporters.lab_due_f AS LAB_TEST_DUE,
    exporters.lab_done_f AS LAB_TEST_DONE,
    risk.reject_prob_f AS REJECT_PROB_7D,
    issues.type_issues_f AS ISSUE_COUNT,
    issues.type_rejected_f AS REJECTED_COUNT,
    issues.type_late_f AS LATE_DELIVERY_COUNT,
    issues.type_value_f AS EXPOSED_VALUE_USD,
    daily.day_issues_f AS ISSUE_COUNT,
    daily.day_rejected_f AS REJECTED_COUNT,
    daily.day_value_f AS SHIPMENT_VALUE_USD
  )
  DIMENSIONS (
    exporters.exporter_id AS ENTITY_ID WITH SYNONYMS = ('exporter', 'processing plant', 'entity', 'seafood shipper'),
    exporters.exporter_name AS ENTITY_NAME,
    exporters.city AS REGION WITH SYNONYMS = ('city', 'region', 'location')
      COMMENT = 'Vietnamese city of the processing plant',
    exporters.category AS CATEGORY WITH SYNONYMS = ('product line', 'product', 'category'),
    exporters.risk_tier AS RISK_TIER COMMENT = 'Exporter operating risk tier 1 (low) to 3 (high)',
    risk.risk_band AS RISK_BAND COMMENT = 'High >= 0.5, Medium >= 0.25, else Low',
    risk.scored_as_of AS SCORED_AS_OF,
    issues.issue_type AS ISSUE_TYPE WITH SYNONYMS = ('issue', 'shipment issue type', 'issue reason'),
    daily.metric_date AS METRIC_DATE
  )
  METRICS (
    exporters.exporter_count AS COUNT(exporters.exporter_id) WITH SYNONYMS = ('number of exporters', 'number of entities', 'how many exporters'),
    exporters.clean_shipment_rate_pct AS 100 * (SUM(exporters.shipments_f) - SUM(exporters.issues_f)) / NULLIF(SUM(exporters.shipments_f), 0)
      WITH SYNONYMS = ('clean shipment rate', 'issue-free shipment rate')
      COMMENT = 'Shipments without an issue / shipments dispatched',
    exporters.issue_rejection_pct AS 100 * SUM(exporters.rejected_f) / NULLIF(SUM(exporters.issues_f), 0)
      COMMENT = 'Rejected shipments / shipment issues raised',
    exporters.issues_raised AS SUM(exporters.issues_f) WITH SYNONYMS = ('shipment issues', 'shipment problems'),
    exporters.rejected_shipments_total AS SUM(exporters.rejected_f) WITH SYNONYMS = ('rejections', 'rejected', 'import rejections'),
    exporters.late_deliveries AS SUM(exporters.late_f) WITH SYNONYMS = ('late arrivals', 'missed arrival dates'),
    exporters.shipments_dispatched AS SUM(exporters.shipments_f) WITH SYNONYMS = ('shipments', 'export shipments', 'reefer shipments'),
    exporters.total_shipment_value_usd AS SUM(exporters.value_f) WITH SYNONYMS = ('shipment value', 'export value', 'export value in USD'),
    exporters.lab_test_compliance_pct AS 100 * SUM(exporters.lab_done_f) / NULLIF(SUM(exporters.lab_due_f), 0)
      COMMENT = 'Lab tests completed / lab tests due',
    risk.avg_reject_prob AS AVG(risk.reject_prob_f),
    issues.type_issues AS SUM(issues.type_issues_f),
    issues.type_rejected AS SUM(issues.type_rejected_f),
    issues.type_late AS SUM(issues.type_late_f),
    issues.type_reject_share_pct AS 100 * SUM(issues.type_rejected_f) / NULLIF(SUM(issues.type_issues_f), 0),
    daily.daily_issues AS SUM(daily.day_issues_f),
    daily.daily_rejected AS SUM(daily.day_rejected_f),
    daily.daily_shipment_value_usd AS SUM(daily.day_value_f)
  )
  COMMENT = 'Synthetic Vietnam seaseafood export shipment analytics (demo)';

-- ---------- Cortex Agent ----------
CREATE OR REPLACE AGENT APP.SEAFOOD_EXPORT_AGENT
  COMMENT = 'Export quality assistant over a synthetic network of Vietnamese seafood exporters'
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-5
instructions:
  response: "Answer only from tool results. State that data is synthetic. Give exporter IDs and numbers with units (USD, %)."
  orchestration: "Use seafood_export_analyst for shipments, shipment value in USD, shipment issues, rejected shipments, late deliveries, clean shipment rate, lab test compliance, exporters, cities, product lines, issue types and rejection risk. Use sop_search for shipment-issue handling procedures."
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: seafood_export_analyst
      description: "Shipments dispatched, shipment value in USD, shipment issues, rejected shipments, late deliveries, clean shipment rate, lab test compliance, issue types and shipment-rejection risk scores by exporter, city and product line"
  - tool_spec:
      type: cortex_search
      name: sop_search
      description: "Synthetic shipment-issue handling SOPs by product line and issue type"
tool_resources:
  seafood_export_analyst:
    semantic_view: __DEMO_DB__.APP.SEAFOOD_EXPORT_ANALYTICS
    execution_environment:
      type: warehouse
      warehouse: __DEMO_WH__
  sop_search:
    name: __DEMO_DB__.SEARCH.ISSUE_SOP_SEARCH
    max_results: 3
    id_column: DOC_ID
    title_column: TITLE
$$;

-- ---------- Live-shipment alert ----------
CREATE TABLE IF NOT EXISTS APP.ALERT_LOG (
  ALERTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(), EXPORTER_ID VARCHAR,
  EVENT_TS TIMESTAMP_NTZ, AMOUNT_USD FLOAT, RESPONSE_MINUTES FLOAT, SOP_HINT VARCHAR);

CREATE OR REPLACE NOTIFICATION INTEGRATION VN_AQUACULTURE_EXPORT_EMAIL_INT
  TYPE = EMAIL ENABLED = TRUE ALLOWED_RECIPIENTS = ('__ALERT_EMAIL__');

CREATE OR REPLACE PROCEDURE APP.LOG_LIVE_ALERTS()
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  n NUMBER;
BEGIN
  INSERT INTO APP.ALERT_LOG (EXPORTER_ID, EVENT_TS, AMOUNT_USD, RESPONSE_MINUTES, SOP_HINT)
    SELECT p.EXPORTER_ID, p.EVENT_TS, p.AMOUNT_USD, p.RESPONSE_MINUTES,
           'Check ' || r.CATEGORY || ' shipment-issue SOPs; current risk band ' || COALESCE(s.RISK_BAND, 'n/a')
    FROM RAW.LIVE_SHIPMENTS p
    JOIN RAW.EXPORTERS r ON r.ID = p.EXPORTER_ID
    LEFT JOIN ML.REJECT_RISK_SCORES s ON s.ENTITY_ID = p.EXPORTER_ID
    WHERE p.STATUS = 'ISSUE'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.EXPORTER_ID = p.EXPORTER_ID AND l.EVENT_TS = p.EVENT_TS);
  n := SQLROWCOUNT;
  IF (n > 0) THEN
    CALL SYSTEM$SEND_EMAIL('VN_AQUACULTURE_EXPORT_EMAIL_INT', '__ALERT_EMAIL__',
      '[Demo] Shipment issue alert',
      'New live shipment issues logged in APP.ALERT_LOG: ' || :n || '. Data is synthetic.');
  END IF;
  RETURN n;
END;
$$;

CREATE OR REPLACE ALERT APP.LIVE_SHIPMENT_ALERT
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '5 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM RAW.LIVE_SHIPMENTS p
    WHERE p.STATUS = 'ISSUE'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.EXPORTER_ID = p.EXPORTER_ID AND l.EVENT_TS = p.EVENT_TS)))
  THEN CALL APP.LOG_LIVE_ALERTS();

-- ---------- On-demand refresh DAG (suspended; run with EXECUTE TASK APP.TASK_REFRESH_CURATED) ----------
CREATE OR REPLACE PROCEDURE APP.REFRESH_CURATED()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  ALTER DYNAMIC TABLE CURATED.PERFORMANCE_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.TREND_ANALYSIS REFRESH;
  ALTER DYNAMIC TABLE CURATED.ISSUE_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.KPI_SUMMARY REFRESH;
  RETURN 'refreshed';
END;
$$;

CREATE OR REPLACE TASK APP.TASK_REFRESH_CURATED
  WAREHOUSE = __DEMO_WH__
AS
  CALL APP.REFRESH_CURATED();

CREATE OR REPLACE TASK APP.TASK_RESCORE_RISK
  WAREHOUSE = __DEMO_WH__
  AFTER APP.TASK_REFRESH_CURATED
AS
  CREATE OR REPLACE TABLE ML.REJECT_RISK_SCORES COPY GRANTS AS
  WITH latest AS (
    SELECT * FROM ML.REJECT_FEATURES QUALIFY ROW_NUMBER() OVER (PARTITION BY ENTITY_ID ORDER BY EVENT_DATE DESC) = 1
  ), p AS (
    SELECT ENTITY_ID, EVENT_DATE,
           ML.REJECT_RISK_MODEL!PREDICT(INPUT_DATA => OBJECT_CONSTRUCT(
             'CATEGORY', CATEGORY, 'RISK_TIER', RISK_TIER, 'EXPORTER_AGE_YEARS', EXPORTER_AGE_YEARS,
             'DOC_DISCREPANCY_PCT', DOC_DISCREPANCY_PCT, 'AVG_CERT_TURNAROUND_HRS', AVG_CERT_TURNAROUND_HRS,
             'DOC_DISCREPANCY_7D', DOC_DISCREPANCY_7D, 'REJECTED_30D', REJECTED_30D)) AS PRED
    FROM latest
  )
  SELECT ENTITY_ID, EVENT_DATE AS SCORED_AS_OF, ROUND(PRED:probability:REJECT::FLOAT, 4) AS REJECT_PROB_7D,
         CASE WHEN PRED:probability:REJECT::FLOAT >= 0.5 THEN 'High'
              WHEN PRED:probability:REJECT::FLOAT >= 0.25 THEN 'Medium' ELSE 'Low' END AS RISK_BAND,
         CURRENT_TIMESTAMP() AS SCORED_AT
  FROM p;
