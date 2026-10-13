#!/usr/bin/env python3
"""
Quick — 生成日历插件的两份内置数据（Swift 源码）。

  python3 Scripts/gen-calendar-data.py            重新拉取并覆盖生成
  python3 Scripts/gen-calendar-data.py --years 2024 2025 2026

数据来源（都是公开权威数据，不是手填）：
  - 24 节气：香港天文台「公历与农历日期对照表」，1901–2100 年，按顺序取每年 24 个节气所在日。
  - 法定节假日与调休：holiday-cn（按国务院办公厅放假通知整理的年度 JSON）。
    拉取后必须对照 JSON 里 `papers` 指向的国务院公告原文核对一遍，再提交。

输出（**不要手改**，改数据请重跑本脚本）：
  Packages/PluginCalendar/Sources/PluginCalendar/Model/SolarTermTable.swift
  Packages/PluginCalendar/Sources/PluginCalendar/Model/BundledHolidays.swift

只依赖标准库。
"""

import argparse
import json
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL_DIR = ROOT / "Packages/PluginCalendar/Sources/PluginCalendar/Model"
FIRST_YEAR, LAST_YEAR = 1901, 2100
DEFAULT_HOLIDAY_YEARS = [2024, 2025, 2026]
HKO = "https://www.hko.gov.hk/tc/gts/time/calendar/text/files/T{year}c.txt"
HOLIDAY_CN = "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/{year}.json"
DAY_DIGITS = "0123456789abcdefghijklmnopqrstuv"
LINE = re.compile(r"(\d+)年(\d+)月(\d+)日\s+\S+\s+星期\S\s*(\S*)")


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read()


def solar_term_row(year: int) -> str:
    """一年 24 个节气所在的「日」，按小寒→冬至的顺序编成 24 个字符。"""
    text = fetch(HKO.format(year=year)).decode("utf-8-sig")
    days: list[int] = []
    for line in text.splitlines():
        match = LINE.match(line)
        if match and match.group(4):
            days.append(int(match.group(3)))
    if len(days) != 24:
        sys.exit(f"{year} 年节气数量不是 24：{len(days)}")
    return "".join(DAY_DIGITS[d] for d in days)


def write_solar_terms() -> None:
    years = list(range(FIRST_YEAR, LAST_YEAR + 1))
    with ThreadPoolExecutor(max_workers=12) as pool:
        rows = list(pool.map(solar_term_row, years))
    body = "\n".join(f'        "{row}",' for row in rows)
    source = f"""// SolarTermTable.swift
// Quick — 原生 macOS 效率启动器
// @author ygw
//
// 由 Scripts/gen-calendar-data.py 生成，不要手改。数据来源：香港天文台公历农历对照表。

/// 1901–2100 年 24 节气所在的「日」
///
/// 每年一个 24 字符的字符串，按小寒、大寒、立春……冬至排列，第 k 个节气落在 `k / 2 + 1` 月；
/// 每个字符是 0–31 的日号（`0-9a-v`）。查表而不是用公式：节气交接时刻离午夜只差几分钟时，
/// 任何天文近似都会差一天，而这张表是权威数据。
enum SolarTermTable {{
    static let firstYear = {FIRST_YEAR}
    static let digits = Array("{DAY_DIGITS}")
    static let rows: [String] = [
{body}
    ]
}}
"""
    (MODEL_DIR / "SolarTermTable.swift").write_text(source, encoding="utf-8")
    print(f"节气表：{len(rows)} 年")


def write_holidays(years: list[int]) -> None:
    entries = []
    for year in years:
        data = json.loads(fetch(HOLIDAY_CN.format(year=year)))
        if not data.get("days"):
            sys.exit(f"{year} 年还没有公布的节假日数据")
        compact = {
            "year": data["year"],
            "papers": data.get("papers", []),
            "days": [
                {"name": d["name"], "date": d["date"], "isOffDay": d["isOffDay"]} for d in data["days"]
            ],
        }
        text = json.dumps(compact, ensure_ascii=False, separators=(",", ":"))
        entries.append(f'        {year}: #"""\n{text}\n"""#,')
        print(f"{year} 年：{len(data['days'])} 天，公告 {compact['papers']}")
    body = "\n".join(entries)
    source = f"""// BundledHolidays.swift
// Quick — 原生 macOS 效率启动器
// @author ygw
//
// 由 Scripts/gen-calendar-data.py 生成，不要手改。来源：holiday-cn，已对照国务院办公厅放假通知核对。

/// 随包内置的法定节假日安排（离线可用）
///
/// 内容是 holiday-cn 的年度 JSON 原样（只保留 year / papers / days）。放在 Swift 源码里而不是
/// 资源文件：本仓库没有任何包用资源包，为这一份数据引入 `Bundle.module` 的打包路径不值得。
/// 联网更新拿到的数据与它同一个格式，由同一个解码器处理。
enum BundledHolidays {{
    static let json: [Int: String] = [
{body}
    ]
}}
"""
    (MODEL_DIR / "BundledHolidays.swift").write_text(source, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--years", nargs="+", type=int, default=DEFAULT_HOLIDAY_YEARS)
    args = parser.parse_args()
    write_solar_terms()
    write_holidays(sorted(args.years))


if __name__ == "__main__":
    main()
