-- ============================================================
-- 终生成长知识库 树状分类 + 全文检索扩展
-- 文件：supabase_sql/04_tree_search.sql
-- 说明：新增 category_tree 分类树，扩展 daily_news/knowledge_card
--       的 category_path 字段，并建立全文检索相关索引与函数。
-- ============================================================

-- ============================================================
-- 1. 分类树表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.category_tree (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_id   UUID REFERENCES public.category_tree(id) ON DELETE CASCADE,
    name        VARCHAR(120) NOT NULL,
    full_path   TEXT NOT NULL,
    level       INTEGER NOT NULL DEFAULT 0,
    sort_order  INTEGER DEFAULT 0,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(parent_id, name)
);

COMMENT ON TABLE public.category_tree IS '知识库树状分类表';

-- ============================================================
-- 2. 扩展内容表：增加 category_path
-- ============================================================
ALTER TABLE public.daily_news
    ADD COLUMN IF NOT EXISTS category_path TEXT;

ALTER TABLE public.knowledge_card
    ADD COLUMN IF NOT EXISTS category_path TEXT;

-- ============================================================
-- 3. 分类路径与全文检索索引
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_daily_news_category_path
    ON public.daily_news USING BTREE(category_path);

CREATE INDEX IF NOT EXISTS idx_knowledge_card_category_path
    ON public.knowledge_card USING BTREE(category_path);

CREATE INDEX IF NOT EXISTS idx_daily_news_raw_fact_trgm
    ON public.daily_news USING GIN(raw_fact gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_knowledge_card_content_trgm
    ON public.knowledge_card USING GIN(card_content gin_trgm_ops);

-- ============================================================
-- 4. 全文搜索函数（增强版）
-- ============================================================
CREATE OR REPLACE FUNCTION public.search_resources(
    p_query TEXT,
    p_category_path TEXT DEFAULT NULL,
    p_source_level TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
    resource_type TEXT,
    id UUID,
    title TEXT,
    content TEXT,
    original_url TEXT,
    category TEXT,
    category_path TEXT,
    source_level TEXT,
    score REAL
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_role TEXT;
    v_packages TEXT[];
BEGIN
    SELECT user_role, COALESCE(assigned_packages, '{}')
    INTO v_role, v_packages
    FROM public.user_profile
    WHERE user_id = auth.uid();

    IF v_role IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT 'daily_news'::TEXT AS resource_type,
           n.id,
           LEFT(n.raw_fact, 100)::TEXT AS title,
           n.raw_fact::TEXT AS content,
           n.original_url::TEXT,
           n.category::TEXT,
           n.category_path::TEXT,
           n.source_level::TEXT,
           similarity(n.raw_fact, p_query)::REAL AS score
    FROM public.daily_news n
    WHERE (v_role = 'owner' OR n.visible_packages = '{}' OR n.visible_packages && v_packages)
      AND (
          n.raw_fact ILIKE '%' || p_query || '%'
          OR n.category ILIKE '%' || p_query || '%'
          OR n.category_path ILIKE '%' || p_query || '%'
      )
      AND (p_category_path IS NULL OR n.category_path LIKE p_category_path || '%')
      AND (p_source_level IS NULL OR n.source_level = p_source_level)

    UNION ALL

    SELECT 'knowledge_card'::TEXT AS resource_type,
           c.id,
           LEFT(c.card_content, 100)::TEXT AS title,
           c.card_content::TEXT AS content,
           COALESCE(c.original_urls[1], '')::TEXT AS original_url,
           c.main_category::TEXT,
           c.category_path::TEXT,
           NULL::TEXT AS source_level,
           similarity(c.card_content, p_query)::REAL AS score
    FROM public.knowledge_card c
    WHERE (v_role = 'owner' OR c.visible_packages = '{}' OR c.visible_packages && v_packages)
      AND (
          c.card_content ILIKE '%' || p_query || '%'
          OR c.main_category ILIKE '%' || p_query || '%'
          OR c.tags && ARRAY[p_query]
          OR c.category_path ILIKE '%' || p_query || '%'
      )
      AND (p_category_path IS NULL OR c.category_path LIKE p_category_path || '%')

    ORDER BY score DESC
    LIMIT p_limit;
END;
$$;

-- ============================================================
-- 5. 分类树查询与管理函数
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_category_tree()
RETURNS TABLE (
    id UUID,
    parent_id UUID,
    name TEXT,
    full_path TEXT,
    level INTEGER,
    sort_order INTEGER,
    children_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT ct.id,
           ct.parent_id,
           ct.name::TEXT,
           ct.full_path::TEXT,
           ct.level,
           ct.sort_order,
           (SELECT COUNT(*) FROM public.category_tree c2 WHERE c2.parent_id = ct.id) AS children_count
    FROM public.category_tree ct
    ORDER BY ct.level, ct.sort_order, ct.full_path;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_upsert_category(
    p_name TEXT,
    p_parent_id UUID DEFAULT NULL,
    p_sort_order INTEGER DEFAULT 0,
    p_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_level INTEGER;
    v_full_path TEXT;
    v_new_id UUID;
BEGIN
    IF public.current_user_role() <> 'owner' THEN
        RAISE EXCEPTION 'permission denied';
    END IF;

    IF p_parent_id IS NOT NULL THEN
        SELECT level, full_path INTO v_level, v_full_path
        FROM public.category_tree WHERE id = p_parent_id;
        v_level := COALESCE(v_level, 0) + 1;
        v_full_path := COALESCE(v_full_path || '/', '') || p_name;
    ELSE
        v_level := 0;
        v_full_path := p_name;
    END IF;

    IF p_id IS NOT NULL THEN
        UPDATE public.category_tree
        SET parent_id = p_parent_id,
            name = p_name,
            full_path = v_full_path,
            level = v_level,
            sort_order = p_sort_order,
            updated_at = NOW()
        WHERE id = p_id
        RETURNING id INTO v_new_id;
    ELSE
        INSERT INTO public.category_tree (parent_id, name, full_path, level, sort_order)
        VALUES (p_parent_id, p_name, v_full_path, v_level, p_sort_order)
        RETURNING id INTO v_new_id;
    END IF;

    RETURN v_new_id;
END;
$$;

-- ============================================================
-- 6. category_tree updated_at 自动触发器
-- ============================================================
DROP TRIGGER IF EXISTS trg_category_tree_updated_at ON public.category_tree;
CREATE TRIGGER trg_category_tree_updated_at
    BEFORE UPDATE ON public.category_tree
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
