"""Publish simulated exporter shipment events to Amazon Data Firehose (stream <prefix>-shipments).

Firehose batches the records into S3 (shipments/); Snowpipe loads them into RAW.LIVE_SHIPMENTS.
Exporter IDs come from RAW.EXPORTERS (EXP-0000..EXP-0039). Values are seeded random.
"""
import argparse
import json
import random
import time
from datetime import datetime, timezone


def make_event(rng):
    issue = rng.random() < 0.1
    return {'exporter_id': f'EXP-{rng.randint(0, 39):04d}',
            'event_ts': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3],
            'amount_usd': round((230000 if issue else 150000) * rng.lognormvariate(0, 0.5)),
            'response_minutes': round((2700 if issue else 1200) * rng.lognormvariate(0, 0.4)),
            'status': 'ISSUE' if issue else 'OK',
            'sent_ms': int(time.time() * 1000)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--region', default='us-west-2')
    ap.add_argument('--prefix', default='vn-aquaculture-export')
    ap.add_argument('--count', type=int, default=40)
    ap.add_argument('--seed', type=int)
    args = ap.parse_args()
    import boto3
    firehose = boto3.client('firehose', region_name=args.region)
    stream = f'{args.prefix}-shipments'
    rng = random.Random(args.seed)
    records = [{'Data': (json.dumps(make_event(rng)) + '\n').encode()} for _ in range(args.count)]
    for start in range(0, len(records), 500):
        out = firehose.put_record_batch(DeliveryStreamName=stream, Records=records[start:start + 500])
        if out['FailedPutCount']:
            raise RuntimeError(f"{out['FailedPutCount']} records were rejected by Firehose")
    print(f'published {args.count} shipment events to Firehose stream {stream}; S3 delivery buffers up to 60 s')


if __name__ == '__main__':
    main()
