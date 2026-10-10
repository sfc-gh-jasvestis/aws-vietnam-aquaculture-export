import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from publish_shipments import make_event
from setup_aws import firehose_request, ident, names


class SetupAwsTests(unittest.TestCase):
    def test_names_are_scoped_to_prefix_account_region(self):
        n = names('vn-aquaculture-export', '123456789012', 'us-west-2')
        self.assertEqual(n['bucket'], 'vn-aquaculture-export-123456789012-us-west-2')
        self.assertEqual(n['storage_int'], 'VN_AQUACULTURE_EXPORT_S3_INT')
        self.assertEqual(n['firehose_stream'], 'vn-aquaculture-export-shipments')

    def test_rejects_unsafe_identifiers(self):
        for bad in ['DB; DROP', 'a-b', '1abc', '']:
            with self.assertRaises(ValueError):
                ident(bad)

    def test_firehose_request_matches_aws_schema(self):
        import botocore.session
        from botocore.validate import validate_parameters
        n = names('vn-aquaculture-export', '123456789012', 'us-west-2')
        req = firehose_request(n, n['bucket'], 'arn:aws:iam::123456789012:role/vn-aquaculture-export-firehose-s3')
        model = botocore.session.get_session().get_service_model('firehose')
        validate_parameters(req, model.operation_model('CreateDeliveryStream').input_shape)
        dest = req['ExtendedS3DestinationConfiguration']
        self.assertEqual(dest['Prefix'], 'shipments/')
        self.assertFalse(dest['ErrorOutputPrefix'].startswith('shipments/'))

    def test_order_event_matches_pipe_columns(self):
        import random
        event = make_event(random.Random(7))
        self.assertEqual(set(event), {'exporter_id', 'event_ts', 'amount_usd', 'response_minutes', 'status', 'sent_ms'})
        self.assertRegex(event['exporter_id'], r'^EXP-00[0-3]\d$')
        self.assertIn(event['status'], ('ISSUE', 'OK'))


if __name__ == '__main__':
    unittest.main()
