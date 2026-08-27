#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
backup_db.py
本地定时备份 + 90 天浏览日志清理 + 备份提醒

运行方式：
    python scripts/backup_db.py
    python scripts/backup_db.py --clean-only
    python scripts/backup_db.py --backup-dir D:/backup
"""

import os
import json
import argparse
from datetime import datetime, date, timedelta
from typing import List

from db_helper import SupabaseHelper, logger

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKUP_DIR = os.path.join(PROJECT_ROOT, "backups")
LOG_DIR = os.path.join(PROJECT_ROOT, "logs")
os.makedirs(BACKUP_DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)

# 需要备份的业务表（按依赖顺序）
BACKUP_TABLES = [
    "user_profile",
    "subscribe_package",
    "daily_news",
    "knowledge_card",
    "knowledge_card_history",
    "user_card_note",
    "user_news_read",
    "user_bookmark",
    "explore_candidate",
    "subscribe_task",
    "login_log",
    "browse_log",
    "operation_log",
]


def backup_all_tables(db: SupabaseHelper, backup_dir: str) -> dict:
    """备份所有业务表到本地 JSON。"""
    today = date.today().isoformat()
    run_dir = os.path.join(backup_dir, f"backup_{today}_{datetime.now().strftime('%H%M%S')}")
    os.makedirs(run_dir, exist_ok=True)

    summary = {"run_dir": run_dir, "tables": {}}

    for table in BACKUP_TABLES:
        try:
            rows = db.get_table_rows(table)
            file_path = os.path.join(run_dir, f"{table}.json")
            with open(file_path, "w", encoding="utf-8") as f:
                json.dump(rows, f, ensure_ascii=False, indent=2)
            summary["tables"][table] = len(rows)
            logger.info("备份表 %s：%d 条 -> %s", table, len(rows), file_path)
        except Exception as e:
            logger.error("备份表 %s 失败：%s", table, e)
            summary["tables"][table] = -1

    # 写入摘要
    summary_path = os.path.join(run_dir, "summary.json")
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    return summary


def clean_browse_logs(db: SupabaseHelper) -> int:
    """清理 90 天前的浏览日志。"""
    try:
        deleted = db.clean_old_browse_logs()
        logger.info("清理 90 天前 browse_log：%d 条", deleted)
        return deleted
    except Exception as e:
        logger.error("清理 browse_log 失败：%s", e)
        return -1


def check_backup_reminder() -> bool:
    """检查是否需要提醒用户进行备份（每周一次）。"""
    reminder_file = os.path.join(LOG_DIR, "last_backup_remind.json")
    today = date.today()
    if os.path.exists(reminder_file):
        try:
            with open(reminder_file, "r", encoding="utf-8") as f:
                last = json.load(f)
            last_date = datetime.fromisoformat(last["date"]).date()
            if (today - last_date).days < 7:
                return False
        except Exception:
            pass

    # 更新提醒时间
    with open(reminder_file, "w", encoding="utf-8") as f:
        json.dump({"date": today.isoformat()}, f, ensure_ascii=False, indent=2)
    return True


def main():
    parser = argparse.ArgumentParser(description="本地备份与日志清理脚本")
    parser.add_argument("--backup-dir", default=BACKUP_DIR, help="备份目录")
    parser.add_argument("--clean-only", action="store_true", help="仅清理日志，不备份")
    parser.add_argument("--dry-run", action="store_true", help="模拟运行，不写入文件")
    args = parser.parse_args()

    logger.info("==== backup_db 开始执行：%s ====", datetime.now().isoformat())

    db = SupabaseHelper()
    result = {
        "run_time": datetime.now().isoformat(),
        "backup": None,
        "cleaned": 0,
        "remind": False,
    }

    # 1. 清理浏览日志
    if not args.dry_run:
        result["cleaned"] = clean_browse_logs(db)
    else:
        logger.info("[dry-run] 跳过清理 browse_log")

    # 2. 全库备份
    if not args.clean_only and not args.dry_run:
        result["backup"] = backup_all_tables(db, args.backup_dir)
    elif args.dry_run:
        logger.info("[dry-run] 跳过全库备份")

    # 3. 备份提醒
    if not args.dry_run and check_backup_reminder():
        result["remind"] = True
        logger.warning("【备份提醒】已过去 7 天，请检查本地备份是否正常运行。")
    elif args.dry_run:
        logger.info("[dry-run] 跳过备份提醒")

    # 4. 保存运行摘要
    summary_path = os.path.join(LOG_DIR, f"backup_summary_{date.today().isoformat()}.json")
    if not args.dry_run:
        with open(summary_path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)

    logger.info("==== backup_db 执行结束，摘要：%s ====", summary_path)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
