-- ============================================================================
-- 07_SEMANTIC_VIEW.SQL — Semantic View for Export Compliance
-- ============================================================================
USE DATABASE AQUACULTURE_EXPORT;
USE SCHEMA APP;

CREATE OR REPLACE SEMANTIC VIEW APP.AQUACULTURE_EXPORT_ANALYTICS
  COMMENT = 'Aquaculture & Seafood export compliance analytics'
AS
  TABLES (
    CURATED.PERFORMANCE_DASHBOARD AS performance_dashboard,CURATED.TREND_ANALYTICS AS trend_analytics,CURATED.FORECAST_INPUT AS forecast_input,CURATED.OPERATIONAL_RISK AS operational_risk
  );
