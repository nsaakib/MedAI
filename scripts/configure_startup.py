"""Match the native Android launch surface to Med.ai. No Gradle edits."""

from pathlib import Path
import argparse
import shutil
import xml.etree.ElementTree as ET


def write_resource(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    res = next(parent for parent in path.parents if parent.name == "res")
    backup = res.parents[3] / "medai-resource-backups" / path.relative_to(res)
    backup.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and not backup.exists():
        shutil.copy2(path, backup)
    path.write_text(content, encoding="utf-8")


def configure(project):
    res = Path(project) / "android/app/src/main/res"
    if not res.is_dir():
        raise SystemExit(
            "Generate the Android runner first; pass --project with its Flutter project folder."
        )
    # Repair backups created by older releases: Android compiles every file under res.
    for old in res.rglob("*.medai-backup"):
        target = res.parents[3] / "medai-resource-backups/legacy" / old.relative_to(res)
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            shutil.move(str(old), str(target))
        else:
            import hashlib

            suffix = hashlib.sha256(old.read_bytes()).hexdigest()[:12]
            alternate = target.with_name(target.name + "." + suffix)
            if not alternate.exists():
                shutil.copy2(old, alternate)
            old.unlink()
    write_resource(
        res / "drawable/medai_launch_mark.xml",
        """<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="96dp" android:height="96dp" android:viewportWidth="96" android:viewportHeight="96">
<path android:fillColor="#6848FF" android:pathData="M38,20Q34,20 34,24V34H24Q20,34 20,38V54Q20,58 24,58H34V72Q34,76 38,76H54Q58,76 58,72V58H72Q76,58 76,54V38Q76,34 72,34H58V24Q58,20 54,20Z"/>
<path android:fillColor="#22B6FB" android:pathData="M34,58L58,34H72Q76,34 76,38V54Q76,58 72,58H58V72Q58,76 54,76H38Q34,76 34,72Z"/>
</vector>""",
    )
    write_resource(
        res / "drawable/medai_launch_background.xml",
        """<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
<item><shape><solid android:color="#001631"/></shape></item>
<item android:gravity="center" android:drawable="@drawable/medai_launch_mark"/>
</layer-list>""",
    )
    for folder in ["values", "values-night", "values-v31", "values-night-v31"]:
        path = res / folder / "styles.xml"
        tree = (
            ET.parse(path) if path.exists() else ET.ElementTree(ET.Element("resources"))
        )
        root = tree.getroot()
        theme = next(
            (s for s in root.findall("style") if s.get("name") == "LaunchTheme"), None
        )
        if theme is None:
            theme = ET.SubElement(
                root,
                "style",
                name="LaunchTheme",
                parent="@android:style/Theme.Light.NoTitleBar",
            )
        values = {"android:windowBackground": "@drawable/medai_launch_background"}
        if "v31" in folder:
            values.update(
                {
                    "android:windowSplashScreenBackground": "#001631",
                    "android:windowSplashScreenAnimatedIcon": "@drawable/medai_launch_mark",
                }
            )
        for name, value in values.items():
            item = next(
                (i for i in theme.findall("item") if i.get("name") == name), None
            )
            if item is None:
                item = ET.SubElement(theme, "item", name=name)
            item.text = value
        normal = next(
            (s for s in root.findall("style") if s.get("name") == "NormalTheme"), None
        )
        if normal is not None:
            background = next(
                (
                    i
                    for i in normal.findall("item")
                    if i.get("name") == "android:windowBackground"
                ),
                None,
            )
            if background is None:
                background = ET.SubElement(
                    normal, "item", name="android:windowBackground"
                )
            background.text = "#001631"
        ET.indent(tree)
        write_resource(path, ET.tostring(root, encoding="unicode"))
    print(
        "Med.ai native launch theme configured; existing styles backed up and unrelated theme settings retained."
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    configure(parser.parse_args().project)
