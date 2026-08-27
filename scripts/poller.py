#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
poller.py
终生成长知识库采集任务轮询器。

设计约束：
- 常驻本机运行，所有外部网络请求由本机 Python 脚本发起。
- 前端管理员点击「立即采集」后，向 Supabase 写入 pending 任务。
- poller 轮询读取任务，调用 collect_daily.py 执行，回写结果。

运行方式：
    python scripts/poller.py

退出方式：Ctrl + C
"""

import os
import sys
import time
import json
import logging
import subprocess
from datetime import datetime
from typing import Optional

# poller.py 与 db_helper.py 在同一 scripts 目录下，直接导入即可
from db_helper import SupabaseHelper, logger

script_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.dirname(script_dir)

# 轮询间隔（秒）
POLL_INTERVAL = 30


def read_summary_file() -> Optional[Dict]:
    """读取 collect_daily.py 生成的今日运行摘要文件。"""
    summary_path = os.path.join(project_root, "logs", f"collect_summary_{datetime.utcnow().date().isoformat()}.json")
    if not os.path.exists(summary_path):
        return None
    try:
        with open(summary_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def run_collection_job(job_id: str, source_type: str) -> tuple[bool, str, Optional[Dict]]:
    """
    调用 collect_daily.py 执行采集。
    返回 (success, message, summary)。
    """
    python_exe = sys.executable
    collect_script = os.path.join(script_dir, "collect_daily.py")
    cmd = [
        python_exe,
        collect_script,
        "--source", source_type,
        "--job-id", job_id,
    ]

    try:
        logger.info("启动采集任务 %s，source=%s", job_id, source_type)
        result = subprocess.run(
            cmd,
            cwd=project_root,
            capture_output=True,
            text=True,
            timeout=300,
        )
        summary = read_summary_file()
        if result.returncode == 0:
            return True, result.stdout[-500:] if result.stdout else "ok", summary
        else:
            err = result.stderr[-800:] if result.stderr else "unknown error"
            return False, err, summary
    except subprocess.TimeoutExpired:
        return False, "采集超时（超过 300 秒）", None
    except Exception as e:
        return False, str(e), None


def process_pending_job(db: SupabaseHelper) -> bool:
    """
    处理一条 pending 任务。返回是否处理了一条。
    """
    job = db.get_pending_collection_job()
    if not job:
        return False

    job_id = str(job["id"])
    source_type = job.get("source_type", "all") or "all"

    logger.info("发现 pending 任务：%s", job_id)

    # 标记为 running
    try:
        db.update_collection_job(
            job_id=job_id,
            status="running",
            started_at=datetime.utcnow().isoformat(),
        )
    except Exception as e:
        logger.error("标记任务 running 失败：%s", e)
        return True  # 标记失败也返回 True，避免立即重试同一条

    # 执行采集
    success, message, summary = run_collection_job(job_id, source_type)

    # 回写结果：合并 collect_daily 的摘要
    result_summary = {
        "success": success,
        "message": message,
        "finished_at": datetime.utcnow().isoformat(),
    }
    if isinstance(summary, dict):
        result_summary.update(summary)
    try:
        db.update_collection_job(
            job_id=job_id,
            status="done" if success else "failed",
            result_summary=result_summary,
            finished_at=datetime.utcnow().isoformat(),
        )
        logger.info("任务 %s 执行%s", job_id, "成功" if success else "失败")
    except Exception as e:
        logger.error("回写任务 %s 结果失败：%s", job_id, e)

    return True


def main():
    logger.info("==== poller 启动，轮询间隔 %d 秒 ====", POLL_INTERVAL)
    db = SupabaseHelper()

    try:
        while True:
            processed = process_pending_job(db)
            if not processed:
                logger.debug("没有 pending 任务，继续轮询...")
            time.sleep(POLL_INTERVAL)
    except KeyboardInterrupt:
        logger.info("==== poller 收到退出信号，已停止 ====")
    except Exception as e:
        logger.error("poller 异常退出：%s", e)
        raise


if __name__ == "__main__":
    main()
