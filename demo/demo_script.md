# Export Compliance

**Vietnam - Aquaculture & Seafood**
Use case: Export Compliance

> Export Compliance for Vietnam - ML.FORECAST and Dynamic Tables power real-time export compliance intelligence for aquaculture & seafood in Ho Chi Minh City.

## Why Snowflake

Snowflake delivers export compliance intelligence for Vietnamese aquaculture & seafood - Dynamic Tables maintain real-time dashboards, ML.FORECAST projects key metrics, and Cortex AI generates recommendations

- **ML.FORECAST for export compliance** - Only demo for Vietnamese aquaculture & seafood
- **ML.ANOMALY_DETECTION early warning** - Detects deviations before impact
- **AI recommendations** - Cortex AI actionable guidance
- **Vietnamese context** - Local names, VND economics

## What is deployed

| | |
|---|---|
| Database | `VIETNAM_AQUACULTURE_EXPORT` |
| Service | `VIETNAM_AQUACULTURE_EXPORT_APP` |
| Compute pool | `SEA_DEMOS_VIETNAM_POOL` |
| Dimension table | `RAW.FARMS` (20 rows) |
| Fact table | `RAW.EXPORT_SHIPMENTS` (250,000 rows, 90 days) |
| Curated layer | `CURATED.PERFORMANCE_SUMMARY`, `CURATED.TREND_ANALYSIS`, `CURATED.KPI_SUMMARY` |
| Currency | VND (₫) |

Regions in play: Ho Chi Minh City, Hanoi, Binh Duong, Dong Nai, Can Tho
Segments: EU Export, US Export, Japan Export, China Export

Dynamic tables are created suspended and refreshed on demand:

```bash
./refresh_demo_data.sh VIETNAM_AQUACULTURE_EXPORT
```

## KPI cards

Every card below is served live from `CURATED.KPI_SUMMARY`. The app keeps the
original literal as a fallback, so it still renders if Snowflake is unreachable.

| Card | Value | Backed by |
|---|---|---|
| Export Revenue | `₫4.2T` | total across Farms |
| Shipments (MTD) | `847` | total across Farms |
| Rejection Rate | `0.4%` | average per event |
| Markets Active | `42` | total across Farms |
| Avg Price/kg | `₫184K` | average per event |
| US Anti-Dumping Status | `Clear` | fixed label (not numeric) |
| EU IUU Status | `Green Card` | fixed label (not numeric) |

## Demo flow

1. Overview
2. Analytics
3. AI Intelligence
4. Ask AI
5. Architecture

## Talking points

- **100K operations** - tracked in Ho Chi Minh City
- **500K metrics** - time-series data points
- **5K assets** - monitored
- **100 docs** - searchable

## Business impact

- Vietnam aquaculture & seafood sector growing rapidly (GSO Vietnam)
- AI improves outcomes 15-30% (McKinsey)
- Vietnam FDI strong in this sector (MPI)
- Real-time analytics reduces response 60-80% (Gartner)

---
Generated from `generator/demo_specs/aws-vietnam-aquaculture-export.json`. Do not hand-edit: run
`python3 generator/gen_repo_docs.py aws-vietnam-aquaculture-export` instead.
