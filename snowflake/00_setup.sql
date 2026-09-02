-- Generated from generator/demo_specs/aws-vietnam-aquaculture-export.json
-- Regenerate with: python3 generator/gen_repo_docs.py aws-vietnam-aquaculture-export
-- This is the schema that is actually deployed for VIETNAM_AQUACULTURE_EXPORT.

-- VIETNAM_AQUACULTURE_EXPORT  (Export Compliance)
-- generated from generator/demo_specs/aws-vietnam-aquaculture-export.json - do not hand-edit
CREATE DATABASE IF NOT EXISTS VIETNAM_AQUACULTURE_EXPORT;
CREATE SCHEMA IF NOT EXISTS VIETNAM_AQUACULTURE_EXPORT.RAW;
CREATE SCHEMA IF NOT EXISTS VIETNAM_AQUACULTURE_EXPORT.CURATED;
CREATE SCHEMA IF NOT EXISTS VIETNAM_AQUACULTURE_EXPORT.APP;
USE DATABASE VIETNAM_AQUACULTURE_EXPORT;

-- 5 real regions; entity names carry their region so the two always agree
