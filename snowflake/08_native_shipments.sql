-- ============================================================================
-- 08_native_shipments.sql - Snowflake-only build: live shipment feed without AWS.
-- Creates RAW.LIVE_SHIPMENTS (same columns as the Snowpipe target created by
-- aws/setup_aws.py) and APP.SIMULATE_SHIPMENTS(N), which inserts synthetic
-- shipment events with the same value ranges and ~10% ISSUE rate as
-- aws/publish_shipments.py. Rows are inserted directly; this simulates a shipment
-- feed and is not Snowpipe Streaming.
-- Run before 06_intelligence.sql (the alert reads RAW.LIVE_SHIPMENTS).
-- Idempotent: safe to run in the AWS build too.
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS APP;

CREATE TABLE IF NOT EXISTS RAW.LIVE_SHIPMENTS (
  EXPORTER_ID VARCHAR, EVENT_TS TIMESTAMP_NTZ, AMOUNT_USD FLOAT, RESPONSE_MINUTES FLOAT,
  STATUS VARCHAR, SENT_TS TIMESTAMP_NTZ, SOURCE_FILE VARCHAR,
  LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP());

CREATE OR REPLACE PROCEDURE APP.SIMULATE_SHIPMENTS(N NUMBER)
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  IF (N < 1 OR N > 1000) THEN
    RETURN 0;
  END IF;
  INSERT INTO RAW.LIVE_SHIPMENTS (EXPORTER_ID, EVENT_TS, AMOUNT_USD, RESPONSE_MINUTES, STATUS, SENT_TS, SOURCE_FILE)
    WITH g AS (
      SELECT 'EXP-' || LPAD(UNIFORM(0, 39, RANDOM())::VARCHAR, 4, '0') AS EXPORTER_ID,
             UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.1 AS IS_ISSUE,
             SYSDATE() AS TS, SEQ4() AS I
      FROM TABLE(GENERATOR(ROWCOUNT => 1000))
    )
    -- NORMAL() needs constant arguments, so the issue offset is applied outside it.
    SELECT EXPORTER_ID, TS,
           ROUND(IFF(IS_ISSUE, 230000, 150000) * EXP(NORMAL(0, 0.5, RANDOM())), 0),
           ROUND(IFF(IS_ISSUE, 2700, 1200) * EXP(NORMAL(0, 0.4, RANDOM())), 0),
           IFF(IS_ISSUE, 'ISSUE', 'OK'), TS, 'APP.SIMULATE_SHIPMENTS'
    FROM g
    WHERE I < :N;
  RETURN SQLROWCOUNT;
END;
$$;

-- Optional continuous feed for longer demos (suspended; RESUME to start, SUSPEND after).
CREATE OR REPLACE TASK APP.TASK_SIMULATE_SHIPMENTS
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '1 MINUTE'
AS
  CALL APP.SIMULATE_SHIPMENTS(5);
