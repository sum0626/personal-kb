#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
collect_daily.py
每日新闻采集 + 认知拓展候选话题生成脚本

设计约束：
- 不内置大模型 API 调用，避免 AI 直接发起网络请求。
- 新闻来源由用户配置：本地 JSON、RSS、或自行接入的爬虫。
- 生成候选话题时提供规则模板 + 可选本地 LLM 接入点。

运行方式：
    python scripts/collect_daily.py
"""

import os
import json
import uuid
import logging
import argparse
from datetime import datetime, date
from typing import List, Dict, Any, Optional

import requests
from bs4 import BeautifulSoup

from db_helper import SupabaseHelper, logger

# 项目根目录
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(PROJECT_ROOT, "data")
LOG_DIR = os.path.join(PROJECT_ROOT, "logs")
CONFIG_DIR = os.path.join(PROJECT_ROOT, "config")
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(CONFIG_DIR, exist_ok=True)

# 默认 RSS 源示例（用户可修改 config/sources.json）
DEFAULT_SOURCES = {
    "官方媒体": [],
    "部委": [],
    "机构研报": [],
}


def load_config() -> Dict[str, Any]:
    """加载自定义采集源配置。"""
    cfg_path = os.path.join(CONFIG_DIR, "sources.json")
    if os.path.exists(cfg_path):
        with open(cfg_path, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"sources": DEFAULT_SOURCES}


def load_local_input() -> List[Dict[str, Any]]:
    """加载本地手工录入的新闻数据。"""
    input_path = os.path.join(DATA_DIR, "daily_input.json")
    if not os.path.exists(input_path):
        return []
    with open(input_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data if isinstance(data, list) else [data]


def fetch_rss_feed(url: str, source_level: str, category: str) -> List[Dict[str, Any]]:
    """解析 RSS feed，返回新闻列表。"""
    items = []
    try:
        resp = requests.get(url, timeout=20, headers={"User-Agent": "Mozilla/5.0"})
        resp.raise_for_status()
        soup = BeautifulSoup(resp.content, "xml")
        for entry in soup.find_all("item"):
            title = entry.find("title")
            link = entry.find("link")
            desc = entry.find("description") or entry.find("summary")
            if not title:
                continue
            items.append({
                "id": str(uuid.uuid4()),
                "create_date": date.today().isoformat(),
                "source_level": source_level,
                "category": category,
                "raw_fact": title.get_text(strip=True) + "\n" + (desc.get_text(strip=True) if desc else ""),
                "original_url": link.get_text(strip=True) if link else url,
                "structured_content": {},
                "is_read": False,
                "visible_packages": [],
                "url_dead_flag": False,
            })
    except Exception as e:
        logger.error("RSS 解析失败 %s: %s", url, e)
    return items


def deduplicate_news(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """按 original_url + raw_fact 去重。"""
    seen = set()
    out = []
    for it in items:
        key = (it.get("original_url", ""), it.get("raw_fact", "")[:80])
        if key not in seen:
            seen.add(key)
            out.append(it)
    return out


def generate_candidates(news_items: List[Dict[str, Any]], max_candidates: int = 3) -> List[Dict[str, Any]]:
    """
    生成认知拓展候选话题。
    当前版本使用规则模板；若已配置本地 LLM 端点，则调用 LLM 生成更优质候选。
    """
    candidates = []

    templates = [
        ("货币政策", "央行降准/降息信号", "宽松与通胀之间的取舍"),
        ("财政政策", "财政刺激/专项债", "乘数效应与债务可持续性的平衡"),
        ("产业政策", "某行业扶持政策落地", "补贴退坡后的真实竞争力"),
        ("宏观经济", "宏观数据发布", "数据口径与市场预期差"),
        ("金融监管", "监管新规/风险事件", "防范风险与金融创新边界"),
        ("前沿科技", "新技术突破", "商业化路径与监管风险"),
        ("全球地缘", "国际冲突/制裁动态", "对供应链与资本市场的传导"),
    ]

    for item in news_items[:max_candidates]:
        cat = item.get("category", "其他")
        tpl = next((t for t in templates if t[0] in cat), templates[-1])
        candidates.append({
            "id": str(uuid.uuid4()),
            "topic_name": f"{tpl[1]}：{item['raw_fact'][:40]}",
            "reason_value": f"与今日 {cat} 新闻相关，可能形成中长期趋势。",
            "controversy": tpl[2],
            "status": "pending",
            "create_day": date.today().isoformat(),
            "reference_urls": [item.get("original_url", "")] if item.get("original_url") else [],
        })

    # 可选：调用本地 LLM（配置 LLM_ENDPOINT 环境变量）
    llm_endpoint = os.getenv("LLM_ENDPOINT")
    if llm_endpoint:
        try:
            prompt = (
                "请根据以下新闻列表，提炼 3 个值得中长期跟踪的认知拓展话题，"
                "每个话题包含：topic_name、reason_value、controversy。只返回 JSON 数组。\n"
                + json.dumps([{"category": n["category"], "raw_fact": n["raw_fact"]} for n in news_items[:10]],
                             ensure_ascii=False)
            )
            resp = requests.post(llm_endpoint, json={"prompt": prompt}, timeout=60)
            llm_candidates = resp.json()
            if isinstance(llm_candidates, list):
                for c in llm_candidates[:max_candidates]:
                    candidates.append({
                        "id": str(uuid.uuid4()),
                        "topic_name": c.get("topic_name", "未命名话题"),
                        "reason_value": c.get("reason_value", ""),
                        "controversy": c.get("controversy", ""),
                        "status": "pending",
                        "create_day": date.today().isoformat(),
                        "reference_urls": [],
                    })
        except Exception as e:
            logger.warning("本地 LLM 生成候选话题失败：%s", e)

    return candidates[:max_candidates]


def categorize_news(raw_text: str) -> str:
    """简单规则分类。"""
    text = raw_text.lower()
    if any(k in text for k in ["降准", "降息", "mlf", "流动性", "央行", "信贷", "利率", "货币"]):
        return "货币政策"
    if any(k in text for k in ["财政", "专项债", "赤字", "税收", "补贴", "财政政策"]):
        return "财政政策"
    if any(k in text for k in ["产业", "制造业", "新能源", "半导体", "芯片", "人工智能"]):
        return "产业政策"
    if any(k in text for k in ["gdp", "cpi", "ppi", "pmi", "就业", "消费", "投资", "宏观"]):
        return "宏观经济"
    if any(k in text for k in ["监管", "证监会", "银保监会", "金融稳定", "风险"]):
        return "金融监管"
    if any(k in text for k in ["科技", "ai", "大模型", "量子", "航天", "生物科技"]):
        return "前沿科技"
    if any(k in text for k in ["美国", "欧盟", "俄乌", "中东", "台海", "制裁", "地缘", "国际关系"]):
        return "全球地缘"
    return "其他"


def main():
    parser = argparse.ArgumentParser(description="每日新闻采集脚本")
    parser.add_argument("--dry-run", action="store_true", help="仅打印，不写入数据库")
    parser.add_argument("--source", choices=["local", "rss", "all"], default="all", help="数据来源")
    parser.add_argument("--max-candidates", type=int, default=3, help="生成候选话题数量")
    parser.add_argument("--job-id", type=str, default=None, help="关联的 collection_jobs 任务 ID")
    args = parser.parse_args()

    logger.info("==== collect_daily 开始执行：%s ====", datetime.now().isoformat())

    db = SupabaseHelper()
    all_news: List[Dict[str, Any]] = []

    # 1. 本地输入
    if args.source in ("local", "all"):
        local_items = load_local_input()
        for it in local_items:
            if "category" not in it:
                it["category"] = categorize_news(it.get("raw_fact", ""))
            it.setdefault("id", str(uuid.uuid4()))
            it.setdefault("create_date", date.today().isoformat())
            it.setdefault("source_level", "其他")
            it.setdefault("structured_content", {})
            it.setdefault("visible_packages", [])
            it.setdefault("url_dead_flag", False)
        all_news.extend(local_items)
        logger.info("本地输入新闻：%d 条", len(local_items))

    # 2. RSS 源
    if args.source in ("rss", "all"):
        cfg = load_config()
        for source_level, feeds in cfg.get("sources", {}).items():
            for feed_url in feeds:
                if not feed_url:
                    continue
                items = fetch_rss_feed(feed_url, source_level, "待分类")
                for it in items:
                    it["category"] = categorize_news(it["raw_fact"])
                all_news.extend(items)
                logger.info("RSS %s 采集：%d 条", feed_url, len(items))

    # 3. 去重
    all_news = deduplicate_news(all_news)
    logger.info("去重后新闻：%d 条", len(all_news))

    # 4. 写入数据库
    if not args.dry_run and all_news:
        try:
            inserted = db.insert_daily_news(all_news)
            logger.info("写入 daily_news：%d 条", len(inserted) if inserted else 0)
        except Exception as e:
            logger.error("写入 daily_news 失败：%s", e)
            raise
    elif args.dry_run:
        logger.info("[dry-run] 跳过写入 daily_news")

    # 5. 生成认知拓展候选话题
    candidates = generate_candidates(all_news, args.max_candidates)
    if not args.dry_run and candidates:
        try:
            db.insert_explore_candidates(candidates)
            logger.info("写入 explore_candidate：%d 条", len(candidates))
        except Exception as e:
            logger.error("写入 explore_candidate 失败：%s", e)
            raise
    elif args.dry_run:
        logger.info("[dry-run] 跳过写入 explore_candidate")

    # 6. 保存运行摘要
    summary = {
        "run_time": datetime.now().isoformat(),
        "news_count": len(all_news),
        "candidate_count": len(candidates),
        "dry_run": args.dry_run,
    }
    summary_path = os.path.join(LOG_DIR, f"collect_summary_{date.today().isoformat()}.json")
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    logger.info("==== collect_daily 执行结束 ====")


if __name__ == "__main__":
    main()
