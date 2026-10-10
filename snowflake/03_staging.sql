-- Validate the producer contract before building downstream objects.
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA RAW;
USE WAREHOUSE IDENTIFIER($DEMO_WH);

EXECUTE IMMEDIATE $$
DECLARE
  violations INTEGER;
  invalid_source EXCEPTION (-20001, 'Synthetic source failed grain or measure validation');
BEGIN
  SELECT COUNT(*) INTO :violations FROM (
    SELECT ENTITY_ID, EVENT_DATE
    FROM RAW.EXPORTER_DAILY
    GROUP BY ENTITY_ID, EVENT_DATE HAVING COUNT(*) <> 1
    UNION ALL
    SELECT observation.ENTITY_ID, observation.EVENT_DATE
    FROM RAW.EXPORTER_DAILY observation
    LEFT JOIN RAW.EXPORTERS exporter ON exporter.ID = observation.ENTITY_ID
    WHERE exporter.ID IS NULL OR observation.SHIPMENT_COUNT < 0
       OR observation.SHIPMENT_VALUE_USD < 0
       OR observation.REJECTED_COUNT < 0 OR observation.REJECTED_COUNT > observation.ISSUE_COUNT
       OR observation.ISSUE_COUNT > observation.SHIPMENT_COUNT
       OR observation.LATE_DELIVERY > observation.REJECTED_COUNT
       OR observation.LAB_TEST_DONE > observation.LAB_TEST_DUE
  );
  IF (violations > 0) THEN
    RAISE invalid_source;
  END IF;
END;
$$;
