-- ============================================================================
-- 05_SEARCH.SQL — Cortex Search for Export Compliance
-- ============================================================================
USE DATABASE AQUACULTURE_EXPORT;
USE SCHEMA SEARCH;

CREATE OR REPLACE CORTEX SEARCH SERVICE SEARCH.AQUACULTURE_EXPORT_SEARCH
  ON CONTENT
  ATTRIBUTES DOC_TYPE, CATEGORY
  WAREHOUSE = AQUACULTURE_WH
  TARGET_LAG = '1 hour'
AS (
  SELECT * FROM RAW.DOCUMENTS
);
