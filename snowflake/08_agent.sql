-- ============================================================================
-- 08_AGENT.SQL — Cortex Agent for Export Compliance
-- ============================================================================
USE DATABASE AQUACULTURE_EXPORT;
USE SCHEMA APP;

CREATE OR REPLACE CORTEX AGENT APP.AQUACULTURE_EXPORT_AGENT
  COMMENT = 'Export Compliance AI Assistant'
  MODEL = 'claude-opus-4-8'
  TOOLS = (
    SEMANTIC_VIEW_TOOL(SEMANTIC_VIEW => 'AQUACULTURE_EXPORT.APP.AQUACULTURE_EXPORT_ANALYTICS'),    CORTEX_SEARCH_TOOL(CORTEX_SEARCH_SERVICE => 'AQUACULTURE_EXPORT.SEARCH.AQUACULTURE_EXPORT_SEARCH', TOOL_DESCRIPTION => 'Search documents for Aquaculture & Seafood information')
  )
  SYSTEM_PROMPT = 'You are the Export Compliance Agent for Vietnamese aquaculture & seafood operations in Ho Chi Minh City.';
