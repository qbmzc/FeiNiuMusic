import unittest

from prepare_preview import preview_metadata


class PreviewMetadataTest(unittest.TestCase):
    def test_platforms_share_numeric_versions_and_preview_label(self):
        self.assertEqual(
            preview_metadata('name: app\nversion: 1.6.9+1\n', 3),
            {'version': '1.6.9-preview.3', 'build_name': '1.6.9', 'build_number': '4'},
        )

    def test_pushes_increase_build_number_and_label(self):
        first = preview_metadata('version: 1.6.9+1\n', 1)
        second = preview_metadata('version: 1.6.9+1\n', 2)
        self.assertGreater(int(second['build_number']), int(first['build_number']))
        self.assertNotEqual(first['version'], second['version'])

    def test_missing_optional_build_number(self):
        self.assertEqual(preview_metadata('version: 1.6.9\n', 1)['build_number'], '1')

    def test_invalid_version_and_run_fail(self):
        with self.assertRaises(ValueError):
            preview_metadata('version: invalid\n', 1)
        with self.assertRaises(ValueError):
            preview_metadata('version: 1.6.9+1\n', 0)


if __name__ == '__main__':
    unittest.main()
