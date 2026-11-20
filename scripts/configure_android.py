"""Configure a generated Flutter runner. Saves backups; safe to run repeatedly."""

from pathlib import Path
import shutil
import argparse
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument("--project", type=Path)
args = parser.parse_args()
root = (
    args.project.resolve()
    if args.project
    else Path(__file__).resolve().parents[1] / "mobile"
)
android = root / "android"
if not android.exists():
    raise SystemExit(
        "Generate Android runner first: cd mobile; flutter create --project-name med_ai --platforms=android,ios ."
    )
ns = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ns)
a = lambda key: "{" + ns + "}" + key
manifest = android / "app/src/main/AndroidManifest.xml"
backup = manifest.with_suffix(".xml.medai-backup")
if not backup.exists():
    shutil.copy2(manifest, backup)
tree = ET.parse(manifest)
doc = tree.getroot()
app = doc.find("application")
for permission in [
    "android.permission.INTERNET",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.SCHEDULE_EXACT_ALARM",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECEIVE_BOOT_COMPLETED",
]:
    if not any(x.get(a("name")) == permission for x in doc.findall("uses-permission")):
        ET.SubElement(doc, "uses-permission", {a("name"): permission})
for name, boot in [
    ("com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver", False),
    ("com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver", True),
]:
    if not any(x.get(a("name")) == name for x in app.findall("receiver")):
        r = ET.SubElement(app, "receiver", {a("name"): name, a("exported"): "false"})
        if boot:
            f = ET.SubElement(r, "intent-filter")
            for action in [
                "android.intent.action.BOOT_COMPLETED",
                "android.intent.action.MY_PACKAGE_REPLACED",
                "android.intent.action.QUICKBOOT_POWERON",
                "com.htc.intent.action.QUICKBOOT_POWERON",
            ]:
                ET.SubElement(f, "action", {a("name"): action})
ET.indent(tree)
tree.write(manifest, encoding="utf-8", xml_declaration=True)
# HTTP is allowed only in DEBUG builds for local LAN development.
debug = android / "app/src/debug/AndroidManifest.xml"
debug.parent.mkdir(parents=True, exist_ok=True)
if debug.exists():
    if not debug.with_suffix(".xml.medai-backup").exists():
        shutil.copy2(debug, debug.with_suffix(".xml.medai-backup"))
    t = ET.parse(debug)
    d = t.getroot()
    application = d.find("application")
    if application is None:
        application = ET.SubElement(d, "application")
    application.set(a("usesCleartextTraffic"), "true")
    ET.indent(t)
    t.write(debug, encoding="utf-8", xml_declaration=True)
else:
    debug.write_text(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:usesCleartextTraffic="true"/></manifest>'
    )
kts = android / "app/build.gradle.kts"
groovy = android / "app/build.gradle"
gradle = kts if kts.exists() else groovy
text = gradle.read_text()
marker = "// MEDAI_NOTIFICATION_DESUGARING"
if marker not in text:
    shutil.copy2(gradle, gradle.with_suffix(gradle.suffix + ".medai-backup"))
    extra = (
        """
// MEDAI_NOTIFICATION_DESUGARING
android {
    compileOptions { isCoreLibraryDesugaringEnabled = true }
}
dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }
"""
        if kts.exists()
        else """
// MEDAI_NOTIFICATION_DESUGARING
android {
    compileOptions { coreLibraryDesugaringEnabled true }
}
dependencies { coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4' }
"""
    )
    gradle.write_text(text + extra)
print(
    "Android permissions, receiver registration, debug HTTP and desugaring configured. Existing Gradle versions and Java settings retained."
)

icon = root / "android/app/src/main/res/drawable/ic_stat_medai.xml"
icon.parent.mkdir(parents=True, exist_ok=True)
icon.write_text(
    '<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24"><path android:fillColor="#FFFFFFFF" android:pathData="M9,2h6v7h7v6h-7v7H9v-7H2V9h7z"/></vector>'
)
