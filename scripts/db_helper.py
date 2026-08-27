#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
db_helper.py
终生成长知识库 Supabase 数据库通用封装
所有网络请求均通过本机运行，AI 不直接调用外部接口。
"""

import os
import logging
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any
from dotenv import load_dotenv
from supabase import create_client, Client

# 加载 .env（默认读取脚本所在目录上级或当前目录）
script_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.dirname(script_dir)
load_dotenv(os.path.join(project_root, ".env"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler()],
)
logger = logging.getLogger("db_helper")


class SupabaseHelper:
    """Supabase 客户端封装，支持业务表常用操作。"""

    def __init__(self, url: Optional[str] = None, key: Optional[str] = None):
        self.url = url or os.getenv("SUPABASE_URL")
        self.service_key = key or os.getenv("SUPABASE_SERVICE_ROLE_KEY")
        self.anon_key = os.getenv("SUPABASE_ANON_KEY")

        if not self.url or not self.service_key:
            raise ValueError("请在 .env 中配置 SUPABASE_URL 与 SUPABASE_SERVICE_ROLE_KEY")

        self.client: Client = create_client(self.url, self.service_key)

    # ---------------- 通用 CRUD ----------------

    def insert(self, table: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """向指定表插入单条数据，返回插入结果。"""
        resp = self.client.table(table).insert(data).execute()
        return resp.data

    def insert_many(self, table: str, data: List[Dict[str, Any]]) -> Dict[str, Any]:
        """向指定表批量插入数据。"""
        if not data:
            return []
        resp = self.client.table(table).insert(data).execute()
        return resp.data

    def select(self, table: str, columns: str = "*", filters: Optional[Dict[str, Any]] = None,
               order: Optional[tuple] = None, limit: Optional[int] = None) -> List[Dict[str, Any]]:
        """通用查询，支持简单等值过滤、排序、分页。"""
        q = self.client.table(table).select(columns)
        if filters:
            for col, val in filters.items():
                q = q.eq(col, val)
        if order:
            col, desc = order
            q = q.order(col, desc=desc)
        if limit:
            q = q.limit(limit)
        resp = q.execute()
        return resp.data or []

    def update(self, table: str, data: Dict[str, Any], filters: Dict[str, Any]) -> List[Dict[str, Any]]:
        """按条件更新。"""
        q = self.client.table(table).update(data)
        for col, val in filters.items():
            q = q.eq(col, val)
        resp = q.execute()
        return resp.data or []

    def delete(self, table: str, filters: Dict[str, Any]) -> List[Dict[str, Any]]:
        """按条件删除。"""
        q = self.client.table(table).delete()
        for col, val in filters.items():
            q = q.eq(col, val)
        resp = q.execute()
        return resp.data or []

    # ---------------- 业务封装 ----------------

    def upsert_profile(self, user_id: str, role: str, expire_at: Optional[datetime] = None,
                       assigned_packages: Optional[List[str]] = None):
        """创建或更新用户业务 profile。"""
        data = {
            "user_id": user_id,
            "user_role": role,
            "trial_expire_at": expire_at.isoformat() if expire_at else None,
            "assigned_packages": assigned_packages or [],
        }
        return self.client.table("user_profile").upsert(data).execute().data

    def create_trial_user(self, email: str, password: str, assigned_packages: Optional[List[str]] = None):
        """使用 Supabase Auth 创建 trial 账号并写入 profile。"""
        expire_at = datetime.utcnow() + timedelta(days=7)
        auth_resp = self.client.auth.admin.create_user({
            "email": email,
            "password": password,
            "email_confirm": True,
        })
        if not auth_resp.user:
            raise RuntimeError(f"创建用户失败: {email}")

        self.upsert_profile(
            user_id=str(auth_resp.user.id),
            role="trial",
            expire_at=expire_at,
            assigned_packages=assigned_packages,
        )
        return {
            "user_id": str(auth_resp.user.id),
            "email": email,
            "trial_expire_at": expire_at.isoformat(),
            "password": password,
        }

    def list_users(self) -> List[Dict[str, Any]]:
        """调用 RPC 获取用户列表（owner 用）。"""
        resp = self.client.rpc("get_all_users").execute()
        return resp.data or []

    def admin_update_user(self, user_id: str, **kwargs):
        """调用 RPC 更新用户业务字段。"""
        return self.client.rpc("admin_update_user", {
            "p_user_id": user_id,
            **kwargs,
        }).execute().data

    def insert_daily_news(self, items: List[Dict[str, Any]]):
        """批量写入每日新闻。"""
        return self.insert_many("daily_news", items)

    def insert_knowledge_card(self, item: Dict[str, Any]):
        """写入知识卡片。"""
        return self.insert("knowledge_card", item)

    def insert_explore_candidates(self, items: List[Dict[str, Any]]):
        """批量写入认知拓展候选话题。"""
        return self.insert_many("explore_candidate", items)

    def list_subscribe_packages(self) -> List[Dict[str, Any]]:
        """列出所有订阅包。"""
        return self.select("subscribe_package", order=("created_at", True))

    def clean_old_browse_logs(self) -> int:
        """清理 90 天前的浏览日志。"""
        resp = self.client.rpc("clean_old_browse_logs").execute()
        return resp.data or 0

    def get_table_rows(self, table: str) -> List[Dict[str, Any]]:
        """获取整张表全部数据（备份用）。"""
        # 一次性拉取全部，若数据量大应分批
        rows = []
        page_size = 1000
        start = 0
        while True:
            resp = self.client.table(table).select("*").range(start, start + page_size - 1).execute()
            chunk = resp.data or []
            if not chunk:
                break
            rows.extend(chunk)
            if len(chunk) < page_size:
                break
            start += page_size
        return rows

    # ---------------- 采集任务队列 ----------------

    def get_pending_collection_job(self) -> Optional[Dict[str, Any]]:
        """取一条最早提交的 pending 采集任务。"""
        resp = self.client.table("collection_jobs") \
            .select("*") \
            .eq("status", "pending") \
            .order("created_at", desc=False) \
            .limit(1) \
            .execute()
        data = resp.data or []
        return data[0] if data else None

    def update_collection_job(self, job_id: str, status: str, result_summary: Optional[Dict[str, Any]] = None,
                                started_at: Optional[str] = None, finished_at: Optional[str] = None):
        """更新采集任务状态与结果。"""
        payload: Dict[str, Any] = {"status": status}
        if result_summary is not None:
            payload["result_summary"] = result_summary
        if started_at is not None:
            payload["started_at"] = started_at
        if finished_at is not None:
            payload["finished_at"] = finished_at
        return self.update("collection_jobs", payload, {"id": job_id})

    def insert_collection_job(self, created_by: Optional[str] = None, source_type: str = "all") -> Dict[str, Any]:
        """创建新的采集任务。"""
        data: Dict[str, Any] = {"status": "pending", "source_type": source_type}
        if created_by:
            data["created_by"] = created_by
        return self.insert("collection_jobs", data)

    def list_recent_collection_jobs(self, limit: int = 20) -> List[Dict[str, Any]]:
        """列出最近采集任务。"""
        return self.select("collection_jobs", order=("created_at", True), limit=limit)
