#!/usr/bin/env python3
"""Start a new release: bump exactly 0.01. Rebuilds do not run this script."""
from decimal import Decimal
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
version_file = root / "VERSION"
old = version_file.read_text(encoding="utf-8").strip()
if not re.fullmatch(r"\d+\.\d{2}", old):
    raise SystemExit("VERSION 必须使用 1.00 格式")
new = f"{Decimal(old) + Decimal('0.01'):.2f}"
version_file.write_text(new + "\n", encoding="utf-8")
for name in ["README.md", "使用说明.txt", "THIRD-PARTY-NOTICES.txt", "Docs/OAuthSetup.txt"]:
    path = root / name
    if path.exists():
        text = path.read_text(encoding="utf-8")
        text = text.replace("搞邮件 V" + old, "搞邮件 V" + new)
        text = text.replace("GaoYouJian-" + old + ".dmg", "GaoYouJian-" + new + ".dmg")
        text = text.replace("当前版本 V" + old, "当前版本 V" + new)
        text = text.replace("当前正式版本 V" + old, "当前正式版本 V" + new)
        path.write_text(text, encoding="utf-8")
print(f"搞邮件 V{old} → V{new}；请构建、验证后运行安装脚本。")
