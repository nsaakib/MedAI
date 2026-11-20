import tempfile
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET
from configure_startup import configure


class StartupTests(unittest.TestCase):
    def test_preserves_themes_and_backups_and_is_repeatable(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            res = root / 'android/app/src/main/res'
            (res / 'values').mkdir(parents=True)
            original = '<resources><style name="NormalTheme"><item name="android:windowLightStatusBar">false</item></style><style name="LaunchTheme" parent="CustomParent"><item name="android:windowFullscreen">false</item></style></resources>'
            path = res / 'values/styles.xml'
            path.write_text(original)
            configure(root)
            first = path.read_bytes()
            configure(root)
            self.assertEqual(first, path.read_bytes())
            self.assertEqual(path.with_suffix('.xml.medai-backup').read_text(), original)
            tree = ET.parse(path)
            self.assertEqual(tree.find("./style[@name='LaunchTheme']").get('parent'), 'CustomParent')
            self.assertEqual(tree.find("./style[@name='NormalTheme']/item").text, 'false')
            for v in ['values-v31', 'values-night-v31']:
                tree = ET.parse(res / v / 'styles.xml')
                self.assertEqual(tree.find("./style/item[@name='android:windowSplashScreenAnimatedIcon']").text, '@drawable/medai_launch_mark')
            ET.parse(res / 'drawable/medai_launch_mark.xml')
            ET.parse(res / 'drawable/medai_launch_background.xml')

    def test_missing_runner_is_not_created(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(SystemExit):
                configure(Path(folder))


if __name__ == '__main__':
    unittest.main()
