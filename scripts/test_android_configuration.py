"""Run with Python; no Android SDK needed. Validates idempotent runner edits."""

import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


class AndroidConfigurationTest(unittest.TestCase):
    def check_variant(self, kts):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = root / "android/app/src/main/AndroidManifest.xml"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="Original"><activity android:name=".MainActivity"/></application></manifest>'
            )
            gradle = root / (
                "android/app/build.gradle.kts" if kts else "android/app/build.gradle"
            )
            gradle.write_text("// Existing build settings retained\n")
            script = Path(__file__).with_name("configure_android.py")
            for _ in range(2):
                subprocess.run(
                    [sys.executable, str(script), "--project", str(root)],
                    check=True,
                    capture_output=True,
                )
            ns = "{http://schemas.android.com/apk/res/android}"
            doc = ET.parse(manifest).getroot()
            app = doc.find("application")
            permissions = [p.get(ns + "name") for p in doc.findall("uses-permission")]
            self.assertEqual(len(permissions), len(set(permissions)))
            self.assertIn("android.permission.INTERNET", permissions)
            self.assertEqual(app.get(ns + "label"), "Original")
            self.assertIsNone(app.get(ns + "usesCleartextTraffic"))
            self.assertEqual(len(app.findall("receiver")), 2)
            self.assertEqual(
                gradle.read_text().count("MEDAI_NOTIFICATION_DESUGARING"), 1
            )
            self.assertIn("Existing build settings retained", gradle.read_text())
            debug = ET.parse(
                root / "android/app/src/debug/AndroidManifest.xml"
            ).getroot()
            self.assertEqual(
                debug.find("application").get(ns + "usesCleartextTraffic"), "true"
            )
            self.assertTrue(
                (root / "android/app/src/main/res/drawable/ic_stat_medai.xml").exists()
            )

    def test_kotlin_dsl(self):
        self.check_variant(True)

    def test_groovy_dsl(self):
        self.check_variant(False)


if __name__ == "__main__":
    unittest.main()
