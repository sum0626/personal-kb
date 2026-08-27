#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
create_trial_user.py
一键创建 7 天试用账号

运行方式：
    python scripts/create_trial_user.py --email test@example.com --password xxxxxxxx
    python scripts/create_trial_user.py --email test@example.com --password xxxxxxxx --packages pkg1 pkg2

说明：
- 使用 SUPABASE_SERVICE_ROLE_KEY 创建 Auth 用户。
- 自动写入 user_profile，角色 trial，7 天后过期。
- 可指定该用户可见的订阅包（assigned_packages）。
"""

import argparse
import json
from typing import Optional, List

from db_helper import SupabaseHelper, logger


def main():
    parser = argparse.ArgumentParser(description="创建 7 天试用账号")
    parser.add_argument("--email", required=True, help="账号邮箱")
    parser.add_argument("--password", required=True, help="账号密码")
    parser.add_argument("--packages", nargs="*", default=[], help="分配的订阅包名称列表")
    parser.add_argument("--output", default=None, help="账号信息输出 JSON 文件路径")
    args = parser.parse_args()

    logger.info("开始创建 trial 账号：%s", args.email)

    db = SupabaseHelper()
    account = db.create_trial_user(
        email=args.email,
        password=args.password,
        assigned_packages=args.packages,
    )

    logger.info("账号创建成功：%s", account["user_id"])
    logger.info("试用到期时间：%s", account["trial_expire_at"])
    logger.info("分配订阅包：%s", account.get("assigned_packages", []))

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(account, f, ensure_ascii=False, indent=2)
        logger.info("账号信息已保存到：%s", args.output)

    print(json.dumps(account, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
