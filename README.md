# 终生成长知识库 Web 系统

一套面向个人中长期知识储备的 Web 系统，采集国内政策、宏观经济、产业、金融监管、前沿科技、全球地缘等重大事件，支持 7 天专题订阅、认知盲区挖掘、多用户分发、手机/电脑双向同步。

## 目录结构

```
终生成长知识库/
├─ supabase_sql/           # 数据库 SQL 文件
│   ├─ 01_schema.sql     # 8 张业务表结构 + 订阅包 + 版本快照 + 用户备注/阅读/书签隔离表
│   ├─ 02_rls.sql        # 行级安全策略（RLS）：owner 全权限、trial/member 只读隔离、过期拦截
│   └─ 03_functions.sql  # RPC 函数、触发器、90 天日志清理、版本快照
├─ scripts/                # 本地 Python 脚本
│   ├─ db_helper.py        # Supabase 通用封装
│   ├─ collect_daily.py    # 每日新闻采集 + 候选话题生成
│   ├─ create_trial_user.py # 创建 7 天试用账号
│   └─ backup_db.py        # 本地备份 + 浏览日志 90 天清理 + 每周备份提醒
├─ frontend/               # Vue 3 + Vite + Tailwind 纯前端
│   ├─ package.json
│   ├─ vite.config.js
│   ├─ index.html
│   └─ src/...
├─ config/
│   └─ sources.json        # RSS/采集源配置
├─ data/
│   └─ daily_input.example.json  # 本地新闻输入示例
├─ .env.example            # 环境变量模板
├─ requirements.txt        # Python 依赖
└─ README.md               # 本文件
```

## 技术栈

- **数据库**：Supabase 免费 PostgreSQL
- **认证**：Supabase Auth（邮箱/密码）
- **前端**：Vue 3 + Vite + Vue Router + Pinia + Tailwind CSS + Supabase JS SDK
- **脚本**：Python 3 + supabase-py + requests

## 核心设计约束

1. **AI 不直接调用外部网络 API**：所有 Supabase 数据库写入由本机 Python 脚本完成。
2. **图片不落地数据库**：只保存原文 URL，页面新标签页跳转外部查看原图。
3. **前端纯静态**：`npm run build` 生成 dist，可部署到任意静态托管。
4. **权限严格隔离**：trial/member 看不到管理后台，也读不到其他用户数据。
5. **试用过期数据库层拦截**：RLS 中判断 `trial_expire_at < now()` 时拒绝业务表 SELECT。
6. **个人备注按用户隔离**：`user_card_note` 表确保多用户下备注不串。
7. **阅读状态与书签按用户隔离**：`user_news_read`、`user_bookmark` 表保证阅读进度与收藏不串。
8. **订阅包/可见范围**：owner 可通过 `assigned_packages` 与 `visible_packages` 控制不同用户可见内容。
9. **全文检索可控**：基于 PostgreSQL `pg_trgm` 实现，检索逻辑完全由数据库层控制，不依赖黑盒 RAG。

## 已包含的功能特性

- **PWA 支持**：`manifest.json` + `sw.js`，手机可添加到桌面。
- **深色模式**：顶部导航栏一键切换，自动记忆偏好。
- **今日情报摘要**：默认折叠展示，重点新闻一目了然。
- **已读/未读进度**：未读新闻带蓝色小圆点，顶部显示“已读 X/Y”。
- **书签/收藏**：新闻和知识卡片均可收藏，按用户隔离。
- **全文检索**：独立的搜索页，支持新闻和卡片内容、分类、标签匹配。
- **相关卡片推荐**：基于标签交集自动推荐相关卡片。
- **订阅专题进度条**：7 天专题可视化进度 + 日程条。
- **Owner 仪表盘**：总新闻、今日新闻、知识卡片、活跃用户、活跃订阅等关键指标。
- **版本快照**：知识卡片修改自动保存历史版本。

## 快速开始

### 1. 初始化 Supabase 项目

1. 在 [Supabase](https://supabase.com/) 创建新项目（免费版即可）。
2. 进入 Project Settings -> API，复制：
   - `Project URL`
   - `anon public`
   - `service_role`（**不要泄露**）
3. 开启 Authentication -> Email，启用「Email Confirm」或按需关闭。

### 2. 运行数据库 SQL

在 Supabase SQL Editor 按顺序执行：

```sql
\i supabase_sql/01_schema.sql
\i supabase_sql/02_rls.sql
\i supabase_sql/03_functions.sql
```

或复制粘贴三个文件内容依次运行。

### 3. 配置环境变量

```bash
cp .env.example .env
```

编辑 `.env`：

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

### 4. 安装 Python 依赖

```bash
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### 5. 安装前端依赖并运行

```bash
cd frontend
npm install
npm run dev
```

打包：

```bash
npm run build
```

打包后的 `frontend/dist/` 可上传到任意静态托管（Vercel、Netlify、Cloudflare Pages、对象存储等）。

### 6. 创建第一个 owner 账号

由于前端不使用 service_role_key，创建账号需通过 Python 脚本或 Supabase Dashboard：

```bash
python scripts/create_trial_user.py --email owner@example.com --password yourpassword
```

然后到 Supabase Dashboard -> Table Editor -> `user_profile`，将该用户的 `user_role` 改为 `owner`。

> 也可以直接写一段一次性脚本调用 `db_helper.create_trial_user` 后再更新 role 为 owner。

### 7. 运行每日采集

```bash
# 从本地 data/daily_input.json + 配置源采集
python scripts/collect_daily.py

# 仅本地输入
python scripts/collect_daily.py --source local

# 仅 RSS（需在 config/sources.json 配置源）
python scripts/collect_daily.py --source rss

# 仅打印，不写入
python scripts/collect_daily.py --dry-run
```

### 8. 备份与日志清理

```bash
# 全库备份 + 清理 90 天前浏览日志 + 每周提醒
python scripts/backup_db.py

# 仅清理日志
python scripts/backup_db.py --clean-only
```

建议用 Windows 任务计划程序 / Linux cron 每周或每日自动运行 `backup_db.py`。

## 使用说明

### 角色与权限

| 角色 | 权限 |
|------|------|
| owner | 读写全部，可进入管理员后台 |
| member | 只读业务数据，可写个人备注 |
| trial | 只读业务数据，7 天后过期被数据库层拦截 |
| 匿名 | 禁止访问 |

### 订阅专题生命周期

- 7 天专题：`active` 状态推送 7 天，到期后 owner 可选择：
  - **永续**：转为长期跟踪
  - **续 7 天**：重置 day_count，继续 7 天
  - **归档**：标记为 archive
  - **删除**：彻底删除
- 长期跟踪：无 7 天限制，owner 手动归档或删除
- 同时最多 3 个活跃订阅

### 采集源配置

编辑 `config/sources.json`：

```json
{
  "sources": {
    "部委": ["https://example.gov/rss.xml"],
    "官方媒体": ["https://example.com/rss.xml"],
    "机构研报": []
  }
}
```

也可直接编辑 `data/daily_input.json` 手动录入新闻，格式见 `data/daily_input.example.json`。

### 本地 LLM 生成候选话题

如需更高质量候选话题，可在 `.env` 配置本地 LLM HTTP 接口：

```env
LLM_ENDPOINT=http://localhost:8000/generate
```

接口需接收 `{ "prompt": "..." }` 并返回 JSON 数组。

## 关键问答

### 这套数据库能支持多少人同时使用？

Supabase 免费版限制：
- 数据库连接数：约 60
- API 请求数：每月 50 万（足够数十个只读用户）
- 存储：500 MB

本项目只存文本/URL，不存图片，单条记录很小。对于几十个 trial/member 只读用户完全够用。若用户超过 50 人或采集量很大，建议升级到 Pro 版或自建 PostgreSQL。

> 注意：每个人的个人知识库范围不同，数据库里是**并集**，通过 `visible_packages` 和 `assigned_packages` 做行级过滤，不是每人独立数据库。

### 试用过期是否只靠前端判断？

不是。02_rls.sql 中的 `current_user_expired()` 在数据库层拦截过期的 trial 账号，无法通过抓包绕过。

### 前端能否直接删除/创建用户？

不能。创建/删除 auth 用户需要 service_role_key，前端只持有 anon key。管理员在后台填写信息后，复制命令在本机终端执行。

### 图片怎么处理的？

数据库只保存 `original_url` 原文链接。前端点击「查看原文」时新标签页跳转到外部网页，不下载或展示图片二进制。

## 安全与维护建议

1. **不要提交 `.env`**：已加入 `.gitignore`。
2. **service_role_key 仅限本地脚本**：不要写入前端或分享给他人。
3. **上线前权限测试**：分别用 owner/trial/member/匿名账号测试各表读写权限。
4. **定期备份**：设置 cron/任务计划每周运行 `backup_db.py`。
5. **浏览日志自动清理**：`backup_db.py` 会调用 `clean_old_browse_logs()` 清理 90 天前日志。

## 可能遇到的坑

1. **Supabase 免费实例休眠**：长时间无访问会休眠，首次访问需等待 1~2 秒。
2. **RLS 未启用**：执行 02_rls.sql 后确认各表已 `ENABLE ROW LEVEL SECURITY`。
3. **匿名用户仍能访问**：确认没有为 `anon` 角色设置任何 policy。
4. **RPC 403**：调用 `get_all_users` / `admin_update_user` 时，需当前用户 role 为 owner，否则触发 `permission denied`。

## 后续可扩展

- 接入网页归档服务，处理原文链接失效
- 增加 PostgreSQL 全文检索（pg_trgm / fts）
- 增加 PWA 离线缓存
- 增加 operation_log 详细审计
- 批量导入/导出账号
