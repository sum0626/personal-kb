#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
migrate_category_path.py
为已有 daily_news / knowledge_card 记录回填 category_path。
"""

from collect_daily import classify_news
from db_helper import SupabaseHelper, logger


def migrate_daily_news(db: SupabaseHelper, batch_size: int = 200):
    rows = db.get_table_rows("daily_news")
    updated = 0
    for i, row in enumerate(rows):
        if row.get("category_path"):
            continue
        main_cat, cat_path = classify_news(row.get("raw_fact", ""))
        if not row.get("category"):
            db.client.table("daily_news").update({
                "category": main_cat,
                "category_path": cat_path,
            }).eq("id", row["id"]).execute()
        else:
            db.client.table("daily_news").update({
                "category_path": cat_path,
            }).eq("id", row["id"]).execute()
        updated += 1
        if (i + 1) % batch_size == 0:
            logger.info("daily_news 已更新 %d/%d 条", updated, len(rows))
    logger.info("daily_news 回填完成：%d 条", updated)


def migrate_knowledge_cards(db: SupabaseHelper, batch_size: int = 200):
    rows = db.get_table_rows("knowledge_card")
    updated = 0
    for i, row in enumerate(rows):
        if row.get("category_path"):
            continue
        main_cat, cat_path = classify_news(row.get("card_content", ""))
        if not row.get("main_category"):
            db.client.table("knowledge_card").update({
                "main_category": main_cat,
                "category_path": cat_path,
            }).eq("id", row["id"]).execute()
        else:
            db.client.table("knowledge_card").update({
                "category_path": cat_path,
            }).eq("id", row["id"]).execute()
        updated += 1
        if (i + 1) % batch_size == 0:
            logger.info("knowledge_card 已更新 %d/%d 条", updated, len(rows))
    logger.info("knowledge_card 回填完成：%d 条", updated)


def main():
    db = SupabaseHelper()
    migrate_daily_news(db)
    migrate_knowledge_cards(db)
    logger.info("category_path 回填全部完成")


if __name__ == "__main__":
    main()
