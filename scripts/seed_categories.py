#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
seed_categories.py
从 config/categories.json 初始化分类树到 Supabase。
"""

import os
import json
from typing import List, Dict, Any

from db_helper import SupabaseHelper, logger

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(PROJECT_ROOT, "config", "categories.json")


def load_categories() -> List[Dict[str, Any]]:
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data.get("categories", [])


def flatten(categories: List[Dict[str, Any]], parent_id: str = None, parent_path: str = "") -> List[Dict[str, Any]]:
    """把嵌套分类展平为 (parent_id, name, full_path, level, sort_order) 列表。"""
    rows = []
    for item in categories:
        name = item["name"]
        full_path = f"{parent_path}/{name}" if parent_path else name
        level = full_path.count("/")
        sort_order = item.get("sort_order", 0)
        rows.append({
            "parent_id": parent_id,
            "name": name,
            "full_path": full_path,
            "level": level,
            "sort_order": sort_order,
        })
        children = item.get("children", [])
        if children:
            # 占位 parent_id，后续回填
            rows.append({"__placeholder": True, "name": name, "full_path": full_path})
            child_rows = flatten(children, parent_id=None, parent_path=full_path)
            rows.extend(child_rows)
    return rows


def seed():
    db = SupabaseHelper()
    categories = load_categories()

    # 先清空已有分类（owner 初始化时使用，谨慎运行）
    # db.client.table("category_tree").delete().neq("id", "").execute()

    def insert_level(items: List[Dict[str, Any]], parent_id: str = None, parent_path: str = ""):
        for item in items:
            name = item["name"]
            full_path = f"{parent_path}/{name}" if parent_path else name
            level = full_path.count("/")
            sort_order = item.get("sort_order", 0)

            resp = db.client.table("category_tree").insert({
                "parent_id": parent_id,
                "name": name,
                "full_path": full_path,
                "level": level,
                "sort_order": sort_order,
            }).execute()
            inserted = resp.data or []
            new_id = inserted[0]["id"] if inserted else None

            logger.info("插入分类：%s (id=%s)", full_path, new_id)

            children = item.get("children", [])
            if children and new_id:
                insert_level(children, parent_id=new_id, parent_path=full_path)

    insert_level(categories)
    logger.info("分类树初始化完成")


if __name__ == "__main__":
    seed()
