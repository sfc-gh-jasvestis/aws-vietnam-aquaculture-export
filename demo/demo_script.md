# Vietnam Seafood Export Quality

**Vietnam - Aquaculture and Seafood Export Consignment Quality**
Use case: reefer consignment quality, import rejections, export document discrepancies and residue lab test controls

> Consignment monitoring for 40 fictional Vietnamese seafood exporters (processing plants) in Ca Mau, Can Tho, Long Xuyen, Nha Trang and Ho Chi Minh City. The demo covers dynamic tables, an import rejection classifier evaluated on a time-based holdout, a consignment-issue forecast, document discrepancy rate anomaly detection, a Cortex Agent that cites SOPs, a live reefer shipment feed with an alert, and an SPCS app.

## Why Snowflake

- **Dynamic tables** turn exporter-day rows into consignments, consignment issues, import rejections, late arrivals and residue lab test compliance; `run_core.py` reconciles them against RAW on every build
- **Import rejection classification** gives each exporter a next-7-day probability, evaluated on a time-based holdout
- **Consignment-issue forecast** projects 14 days of issues across all exporters with prediction intervals, to plan quality desk cover
- **Grounded AI**: the Cortex Agent (Analyst over a semantic view, Search over SOPs) shows the SQL it ran and the SOPs it cited
- **Live shipments**: a native simulator (Snowflake only) or Amazon Data Firehose, S3 and Snowpipe (AWS build), feeding an alert and email

## What is built

| | |
|---|---|
| Dimension table | `RAW.EXPORTERS` (40 rows) |
| Fact table | `RAW.EXPORTER_DAILY` (3,600 exporter-days, 90 days) |
| Curated layer | `CURATED.KPI_SUMMARY`, `PERFORMANCE_SUMMARY`, `ISSUE_SUMMARY`, `TREND_ANALYSIS` |
| ML | `ML.REJECT_RISK_SCORES`, `ML.REJECT_RISK_HOLDOUT_METRICS`, `ML.ISSUE_FORECAST`, `ML.DOC_DISCREPANCY_ANOMALIES` |

Currency: USD. Cities: Ca Mau, Can Tho, Long Xuyen, Nha Trang, Ho Chi Minh City.
Product lines: Whiteleg shrimp, Black tiger shrimp, Pangasius fillet, Frozen squid, Canned tuna.

## KPI cards (live from `CURATED.KPI_SUMMARY`; no fallback values)

| Card | Value from the seeded data |
|---|---|
| Clean Consignment Rate | 96.03% |
| Consignment Issues Raised | 647 |
| Import Rejections | 218 |
| Issue Rejection Rate | 33.7% |
| Late Arrivals | 94 |
| Export Value (USD M) | 2,759 |
| Consignments Dispatched | 16,282 |
| Residue Lab Test Compliance | 71.4% |
| Seafood Exporters Monitored | 40 |
| Export Document Coverage | 60.6% |
| Export Documents Pending | 18 |

Values are synthetic. The data is HASH-seeded, so a rebuild reproduces them; dates are relative to the build day.

## Demo flow

1. Executive Cockpit: KPI cards, daily consignment issues against import rejections, issues and rejections by issue type, and the exporter table
2. Predictive: holdout metrics, risk bands, the 14-day consignment-issue forecast and document discrepancy rate anomalies
3. Controls: residue lab test compliance, export document coverage and pending documents, lab test compliance against import rejections, then the action memo
4. Live Shipments: run `CALL APP.SIMULATE_SHIPMENTS(20)` (Snowflake only) or `python aws/publish_shipments.py --count 20` (AWS build), then `EXECUTE ALERT APP.LIVE_SHIPMENT_ALERT`, and show the alert log and email
5. Ask AI: the Cortex Agent answers metric questions through the semantic view, cites SOPs from Cortex Search and shows its SQL
6. QuickSight (AWS build): the same Snowflake tables through DIRECT_QUERY
7. Architecture: both builds side by side

## Talking points

- 96.03% of reefer consignments go through without an issue. The 647 consignment issues are where the quality desk spends its time, and about one in three (33.7%) ends as an import rejection.
- Health certificate mismatches cause the most import rejections (82 of 214 issues). The 16 storm port closures in Nha Trang and Ca Mau hit every exporter in the city on one day and were all resolved without a rejection.
- Pangasius fillet plants have the most import rejections (80), ahead of whiteleg shrimp (72); black tiger shrimp has the fewest (5).
- Nha Trang exporters have the most import rejections (78); Ho Chi Minh City has the fewest (19).
- On a time-based holdout the risk model reaches precision 0.51 and recall 0.41 at 0.5, against a 0.30 base rate. Use it to decide which plant gets a quality review first, not as a verdict on an exporter.
- Storm port closures are left out of model training because the exporter did not cause them.

## Business impact

Use only the sourced references in `README.md` (Business Impact).
