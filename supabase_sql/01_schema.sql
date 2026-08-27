-- 终生成长知识库 Web 系统
-- 数据库表结构 (PostgreSQL / Supabase)
-- 文件：supabase_sql/01_schema.sql

-- 启用需要的扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- 全文检索/相似度搜索

-- ============================================================
-- 1. daily_news 每日新闻表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.daily_news (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    create_date     DATE NOT NULL DEFAULT CURRENT_DATE,
    source_level    VARCHAR(50) NOT NULL CHECK (source_level IN ('部委', '官方媒体', '机构研报', '自媒体', '其他')),
    category        VARCHAR(100) NOT NULL,
    raw_fact        TEXT NOT NULL,
    original_url    TEXT,                                 -- 多条以英文逗号分隔
    structured_content JSONB DEFAULT '{}',                 -- AI 结构化拆解
    is_read         BOOLEAN DEFAULT FALSE,
    visible_packages TEXT[] DEFAULT '{}',                  -- 空数组表示对所有用户可见
    url_dead_flag   BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.daily_news IS '每日新闻采集表';

-- ============================================================
-- 2. knowledge_card 知识库卡片表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.knowledge_card (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    create_date     DATE NOT NULL DEFAULT CURRENT_DATE,
    main_category   VARCHAR(120) NOT NULL,
    tags            TEXT[] DEFAULT '{}',
    card_content    TEXT NOT NULL,
    original_urls   TEXT[] DEFAULT '{}',
    visible_packages TEXT[] DEFAULT '{}',
    latest_version  INTEGER DEFAULT 1,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.knowledge_card IS '知识库卡片主表';

-- ============================================================
-- 2.1 knowledge_card_history 知识卡片版本快照表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.knowledge_card_history (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_id         UUID NOT NULL REFERENCES public.knowledge_card(id) ON DELETE CASCADE,
    version         INTEGER NOT NULL,
    card_content    TEXT NOT NULL,
    tags            TEXT[] DEFAULT '{}',
    original_urls   TEXT[] DEFAULT '{}',
    main_category   VARCHAR(120),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(card_id, version)
);

COMMENT ON TABLE public.knowledge_card_history IS '知识卡片历史版本快照';

-- ============================================================
-- 2.2 user_card_note 用户个人备注表（按用户隔离）
-- ============================================================
CREATE TABLE IF NOT EXISTS public.user_card_note (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    card_id         UUID NOT NULL REFERENCES public.knowledge_card(id) ON DELETE CASCADE,
    note_content    TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, card_id)
);

COMMENT ON TABLE public.user_card_note IS '用户对知识卡片的个人备注，按用户隔离';

-- ============================================================
-- 3. explore_candidate 拓展候选话题表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.explore_candidate (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    topic_name      VARCHAR(255) NOT NULL,
    reason_value    TEXT,
    controversy     TEXT,
    status          VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'subscribe', 'skip')),
    create_day      DATE NOT NULL DEFAULT CURRENT_DATE,
    reference_urls  TEXT[] DEFAULT '{}',
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.explore_candidate IS 'AI 挖掘的认知盲区候选话题';

-- ============================================================
-- 4. subscribe_task 订阅专题任务表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.subscribe_task (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    topic_name      VARCHAR(255) NOT NULL,
    start_day       DATE NOT NULL DEFAULT CURRENT_DATE,
    day_count       INTEGER DEFAULT 0,
    max_cycle       INTEGER DEFAULT 7,
    status          VARCHAR(50) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'end', 'archive')),
    task_type       VARCHAR(50) DEFAULT 'short' CHECK (task_type IN ('short', 'long')), -- short=7天，long=长期跟踪
    reference_urls  TEXT[] DEFAULT '{}',
    visible_packages TEXT[] DEFAULT '{}',
    created_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.subscribe_task IS '7天专题订阅或长期跟踪任务';

-- ============================================================
-- 4.1 subscribe_package 订阅包 / 可见范围定义表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.subscribe_package (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(120) NOT NULL,
    description     TEXT,
    created_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.subscribe_package IS 'owner 定义的订阅包/用户可见范围';

-- ============================================================
-- 2.3 user_news_read 用户新闻已读状态表（按用户隔离）
-- ============================================================
CREATE TABLE IF NOT EXISTS public.user_news_read (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    news_id         UUID NOT NULL REFERENCES public.daily_news(id) ON DELETE CASCADE,
    is_read         BOOLEAN DEFAULT TRUE,
    read_at         TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, news_id)
);

COMMENT ON TABLE public.user_news_read IS '用户对每日新闻的阅读状态，按用户隔离';

-- ============================================================
-- 2.4 user_bookmark 用户书签/收藏表（按用户隔离）
-- ============================================================
CREATE TABLE IF NOT EXISTS public.user_bookmark (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    resource_type   VARCHAR(50) NOT NULL CHECK (resource_type IN ('daily_news', 'knowledge_card')),
    resource_id     UUID NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, resource_type, resource_id)
);

COMMENT ON TABLE public.user_bookmark IS '用户对新闻和卡片的书签/收藏，按用户隔离';

-- ============================================================
-- 5. user_profile 用户业务扩展表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.user_profile (
    user_id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    user_role       VARCHAR(50) NOT NULL DEFAULT 'member' CHECK (user_role IN ('owner', 'trial', 'member')),
    trial_expire_at TIMESTAMPTZ,
    is_active       BOOLEAN DEFAULT TRUE,
    assigned_packages TEXT[] DEFAULT '{}',                 -- 空数组表示可见无限制内容
    create_at       TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.user_profile IS '用户业务角色与订阅包扩展表';

-- ============================================================
-- 6. login_log 登录审计日志
-- ============================================================
CREATE TABLE IF NOT EXISTS public.login_log (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    login_time      TIMESTAMPTZ DEFAULT NOW(),
    user_agent      TEXT,
    ip_addr         INET,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.login_log IS '用户登录审计日志';

-- ============================================================
-- 7. browse_log 内容浏览日志
-- ============================================================
CREATE TABLE IF NOT EXISTS public.browse_log (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    browse_time     TIMESTAMPTZ DEFAULT NOW(),
    resource_type   VARCHAR(50) NOT NULL CHECK (resource_type IN ('daily_news', 'knowledge_card', 'subscribe_topic')),
    resource_id     UUID NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.browse_log IS '用户内容浏览行为日志';

-- ============================================================
-- 8. operation_log 关键操作日志（可选扩展）
-- ============================================================
CREATE TABLE IF NOT EXISTS public.operation_log (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    op_time         TIMESTAMPTZ DEFAULT NOW(),
    op_type         VARCHAR(100) NOT NULL,
    table_name      VARCHAR(100),
    record_id       UUID,
    detail          JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.operation_log IS '关键数据库操作日志（可选）';

-- ============================================================
-- 9. collection_jobs 采集任务队列（管理员点击触发 + 本机 poller 执行）
-- ============================================================
CREATE TABLE IF NOT EXISTS public.collection_jobs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    status          VARCHAR(50) NOT NULL DEFAULT 'pending',
    source_type     VARCHAR(50) DEFAULT 'all',
    result_summary  JSONB DEFAULT '{}',
    started_at      TIMESTAMPTZ,
    finished_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.collection_jobs IS '采集任务队列：管理员点击触发，本机 poller 轮询执行';

-- ============================================================
-- 索引优化
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_daily_news_create_date ON public.daily_news(create_date DESC);
CREATE INDEX IF NOT EXISTS idx_daily_news_category ON public.daily_news(category);
CREATE INDEX IF NOT EXISTS idx_knowledge_card_category ON public.knowledge_card(main_category);
CREATE INDEX IF NOT EXISTS idx_knowledge_card_tags ON public.knowledge_card USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_card_history_card_id ON public.knowledge_card_history(card_id);
CREATE INDEX IF NOT EXISTS idx_user_note_user_id ON public.user_card_note(user_id);
CREATE INDEX IF NOT EXISTS idx_user_note_card_id ON public.user_card_note(card_id);
CREATE INDEX IF NOT EXISTS idx_explore_status ON public.explore_candidate(status);
CREATE INDEX IF NOT EXISTS idx_subscribe_status ON public.subscribe_task(status);
CREATE INDEX IF NOT EXISTS idx_login_user_id ON public.login_log(user_id);
CREATE INDEX IF NOT EXISTS idx_browse_user_id ON public.browse_log(user_id);
CREATE INDEX IF NOT EXISTS idx_browse_time ON public.browse_log(browse_time);
CREATE INDEX IF NOT EXISTS idx_user_news_read_user_id ON public.user_news_read(user_id);
CREATE INDEX IF NOT EXISTS idx_user_news_read_news_id ON public.user_news_read(news_id);
CREATE INDEX IF NOT EXISTS idx_user_bookmark_user_id ON public.user_bookmark(user_id);
CREATE INDEX IF NOT EXISTS idx_user_bookmark_resource ON public.user_bookmark(resource_type, resource_id);
CREATE INDEX IF NOT EXISTS idx_collection_jobs_status ON public.collection_jobs(status);
CREATE INDEX IF NOT EXISTS idx_collection_jobs_created_at ON public.collection_jobs(created_at DESC);
-- 全文检索/相似搜索用 trigram GIN 索引（中文子串匹配）
-- 数组转字符串需要 IMMUTABLE 函数才能用于索引表达式
CREATE OR REPLACE FUNCTION immutable_array_to_string(text[], text)
RETURNS text AS $$
  SELECT array_to_string($1, $2);
$$ LANGUAGE sql IMMUTABLE;

CREATE INDEX IF NOT EXISTS idx_daily_news_search ON public.daily_news USING GIN (raw_fact gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_knowledge_card_search ON public.knowledge_card USING GIN (card_content gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_knowledge_card_tags_search ON public.knowledge_card USING GIN (immutable_array_to_string(tags, ' ') gin_trgm_ops);
