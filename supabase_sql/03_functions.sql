-- 终生成长知识库 辅助函数、触发器与定时清理
-- 文件：supabase_sql/03_functions.sql

-- ============================================================
-- 1. 管理员获取所有用户（owner 后台用）
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_all_users()
RETURNS TABLE (
    id UUID,
    email TEXT,
    created_at TIMESTAMPTZ,
    last_sign_in_at TIMESTAMPTZ,
    user_role TEXT,
    trial_expire_at TIMESTAMPTZ,
    is_active BOOLEAN,
    assigned_packages TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- 仅 owner 可调用
    IF public.current_user_role() <> 'owner' THEN
        RAISE EXCEPTION 'permission denied';
    END IF;

    RETURN QUERY
    SELECT
        au.id,
        au.email::TEXT,
        au.created_at,
        au.last_sign_in_at,
        up.user_role,
        up.trial_expire_at,
        up.is_active,
        up.assigned_packages
    FROM auth.users au
    LEFT JOIN public.user_profile up ON up.user_id = au.id
    ORDER BY au.created_at DESC;
END;
$$;

-- ============================================================
-- 2. 管理员更新用户（owner 后台用）
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_update_user(
    p_user_id UUID,
    p_user_role TEXT DEFAULT NULL,
    p_trial_expire_at TIMESTAMPTZ DEFAULT NULL,
    p_is_active BOOLEAN DEFAULT NULL,
    p_assigned_packages TEXT[] DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF public.current_user_role() <> 'owner' THEN
        RAISE EXCEPTION 'permission denied';
    END IF;

    UPDATE public.user_profile
    SET
        user_role = COALESCE(p_user_role, user_role),
        trial_expire_at = COALESCE(p_trial_expire_at, trial_expire_at),
        is_active = COALESCE(p_is_active, is_active),
        assigned_packages = COALESCE(p_assigned_packages, assigned_packages),
        updated_at = NOW()
    WHERE user_id = p_user_id;
END;
$$;

-- ============================================================
-- 3. 管理员创建 trial 用户并写 profile（service role / Python 脚本用）
--    注：Supabase Auth 创建用户需 service_role_key，本函数仅做 profile 写入示范
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_user_profile(
    p_user_id UUID,
    p_user_role TEXT,
    p_trial_expire_at TIMESTAMPTZ DEFAULT NULL,
    p_assigned_packages TEXT[] DEFAULT '{}'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.user_profile (
        user_id, user_role, trial_expire_at, assigned_packages
    ) VALUES (
        p_user_id, p_user_role, p_trial_expire_at, p_assigned_packages
    )
    ON CONFLICT (user_id) DO UPDATE SET
        user_role = EXCLUDED.user_role,
        trial_expire_at = EXCLUDED.trial_expire_at,
        assigned_packages = EXCLUDED.assigned_packages,
        updated_at = NOW();
END;
$$;

-- ============================================================
-- 4. 订阅专题操作：续期 / 归档 / 删除 / 转长期
-- ============================================================
CREATE OR REPLACE FUNCTION public.renew_or_archive_subscription(
    p_task_id UUID,
    p_action TEXT  -- 'renew7' | 'perpetual' | 'archive' | 'delete'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF public.current_user_role() <> 'owner' THEN
        RAISE EXCEPTION 'permission denied';
    END IF;

    IF p_action = 'renew7' THEN
        UPDATE public.subscribe_task
        SET day_count = 0,
            status = 'active',
            task_type = 'short',
            updated_at = NOW()
        WHERE id = p_task_id;
    ELSIF p_action = 'perpetual' THEN
        UPDATE public.subscribe_task
        SET day_count = 0,
            status = 'active',
            task_type = 'long',
            updated_at = NOW()
        WHERE id = p_task_id;
    ELSIF p_action = 'archive' THEN
        UPDATE public.subscribe_task
        SET status = 'archive',
            updated_at = NOW()
        WHERE id = p_task_id;
    ELSIF p_action = 'delete' THEN
        DELETE FROM public.subscribe_task WHERE id = p_task_id;
    ELSE
        RAISE EXCEPTION 'unknown action: %', p_action;
    END IF;
END;
$$;

-- ============================================================
-- 5. 检查当前活跃订阅数量是否超过 3 个
-- ============================================================
CREATE OR REPLACE FUNCTION public.active_subscription_count()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    cnt INTEGER;
BEGIN
    SELECT COUNT(*) INTO cnt
    FROM public.subscribe_task
    WHERE status = 'active';
    RETURN cnt;
END;
$$;

-- ============================================================
-- 6. 知识卡片更新时：自动生成版本快照
-- ============================================================
CREATE OR REPLACE FUNCTION public.snapshot_knowledge_card()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    next_version INTEGER;
BEGIN
    -- 仅在 card_content / tags / original_urls / main_category 发生变化时生成快照
    IF OLD.card_content IS DISTINCT FROM NEW.card_content
       OR OLD.tags IS DISTINCT FROM NEW.tags
       OR OLD.original_urls IS DISTINCT FROM NEW.original_urls
       OR OLD.main_category IS DISTINCT FROM NEW.main_category THEN

        next_version := COALESCE(NEW.latest_version, 1);

        INSERT INTO public.knowledge_card_history (
            card_id, version, card_content, tags, original_urls, main_category
        ) VALUES (
            OLD.id,
            next_version,
            OLD.card_content,
            OLD.tags,
            OLD.original_urls,
            OLD.main_category
        );

        NEW.latest_version := next_version + 1;
        NEW.updated_at := NOW();
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_knowledge_card_snapshot ON public.knowledge_card;
CREATE TRIGGER trg_knowledge_card_snapshot
    BEFORE UPDATE ON public.knowledge_card
    FOR EACH ROW
    EXECUTE FUNCTION public.snapshot_knowledge_card();

-- ============================================================
-- 6.1 explore_candidate 限制非 owner 只能修改 status 字段
-- ============================================================
CREATE OR REPLACE FUNCTION public.restrict_explore_candidate_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF public.current_user_role() <> 'owner' THEN
        -- 非 owner 只能改 status，其它字段必须保持不变
        IF OLD.topic_name IS DISTINCT FROM NEW.topic_name
           OR OLD.reason_value IS DISTINCT FROM NEW.reason_value
           OR OLD.controversy IS DISTINCT FROM NEW.controversy
           OR OLD.create_day IS DISTINCT FROM NEW.create_day
           OR OLD.reference_urls IS DISTINCT FROM NEW.reference_urls THEN
            RAISE EXCEPTION '非 owner 只能修改 candidate 的状态字段';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_restrict_explore_candidate_update ON public.explore_candidate;
CREATE TRIGGER trg_restrict_explore_candidate_update
    BEFORE UPDATE ON public.explore_candidate
    FOR EACH ROW
    EXECUTE FUNCTION public.restrict_explore_candidate_update();

-- ============================================================
-- 7. 浏览日志 90 天滚动清理（可在 backup_db.py 中定时调用）
-- ============================================================
CREATE OR REPLACE FUNCTION public.clean_old_browse_logs()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM public.browse_log
    WHERE browse_time < NOW() - INTERVAL '90 days';

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- ============================================================
-- 8. 关键操作日志记录函数
-- ============================================================
CREATE OR REPLACE FUNCTION public.log_operation(
    p_op_type TEXT,
    p_table_name TEXT DEFAULT NULL,
    p_record_id UUID DEFAULT NULL,
    p_detail JSONB DEFAULT '{}'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.operation_log (user_id, op_type, table_name, record_id, detail)
    VALUES (auth.uid(), p_op_type, p_table_name, p_record_id, p_detail);
END;
$$;

-- ============================================================
-- 9. 更新 updated_at 自动触发器（通用）
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_daily_news_updated_at ON public.daily_news;
CREATE TRIGGER trg_daily_news_updated_at
    BEFORE UPDATE ON public.daily_news
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_knowledge_card_updated_at ON public.knowledge_card;
CREATE TRIGGER trg_knowledge_card_updated_at
    BEFORE UPDATE ON public.knowledge_card
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_subscribe_task_updated_at ON public.subscribe_task;
CREATE TRIGGER trg_subscribe_task_updated_at
    BEFORE UPDATE ON public.subscribe_task
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_user_profile_updated_at ON public.user_profile;
CREATE TRIGGER trg_user_profile_updated_at
    BEFORE UPDATE ON public.user_profile
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_user_card_note_updated_at ON public.user_card_note;
CREATE TRIGGER trg_user_card_note_updated_at
    BEFORE UPDATE ON public.user_card_note
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================
-- 10. 全文搜索：新闻 + 知识卡片
-- ============================================================
CREATE OR REPLACE FUNCTION public.search_resources(
    p_query TEXT,
    p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
    resource_type TEXT,
    id UUID,
    title TEXT,
    content TEXT,
    original_url TEXT,
    score REAL
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_role TEXT;
    v_packages TEXT[];
BEGIN
    -- 获取当前用户角色和订阅包（用于过滤可见范围）
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
           LEFT(n.raw_fact, 80)::TEXT AS title,
           n.raw_fact::TEXT AS content,
           n.original_url::TEXT,
           similarity(n.raw_fact, p_query)::REAL AS score
    FROM public.daily_news n
    WHERE (
        v_role = 'owner'
        OR n.visible_packages = '{}'
        OR n.visible_packages && v_packages
    )
      AND (
        n.raw_fact ILIKE '%' || p_query || '%'
        OR n.category ILIKE '%' || p_query || '%'
      )

    UNION ALL

    SELECT 'knowledge_card'::TEXT AS resource_type,
           c.id,
           LEFT(c.card_content, 80)::TEXT AS title,
           c.card_content::TEXT AS content,
           COALESCE(c.original_urls[1], '')::TEXT AS original_url,
           similarity(c.card_content, p_query)::REAL AS score
    FROM public.knowledge_card c
    WHERE (
        v_role = 'owner'
        OR c.visible_packages = '{}'
        OR c.visible_packages && v_packages
    )
      AND (
        c.card_content ILIKE '%' || p_query || '%'
        OR c.main_category ILIKE '%' || p_query || '%'
        OR c.tags && ARRAY[p_query]
      )

    ORDER BY score DESC
    LIMIT p_limit;
END;
$$;

-- ============================================================
-- 11. Owner 仪表盘统计
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_admin_dashboard_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_role TEXT;
    result JSONB;
BEGIN
    SELECT user_role INTO v_role
    FROM public.user_profile
    WHERE user_id = auth.uid();

    IF v_role <> 'owner' THEN
        RAISE EXCEPTION 'permission denied';
    END IF;

    SELECT jsonb_build_object(
        'total_news', (SELECT COUNT(*) FROM public.daily_news),
        'news_today', (SELECT COUNT(*) FROM public.daily_news WHERE create_date = CURRENT_DATE),
        'total_cards', (SELECT COUNT(*) FROM public.knowledge_card),
        'cards_this_week', (SELECT COUNT(*) FROM public.knowledge_card WHERE created_at > NOW() - INTERVAL '7 days'),
        'active_subscriptions', (SELECT COUNT(*) FROM public.subscribe_task WHERE status = 'active'),
        'total_users', (SELECT COUNT(*) FROM public.user_profile),
        'active_users_today', (SELECT COUNT(DISTINCT user_id) FROM public.login_log WHERE login_time > NOW() - INTERVAL '24 hours'),
        'trial_users', (SELECT COUNT(*) FROM public.user_profile WHERE user_role = 'trial'),
        'expired_trials', (SELECT COUNT(*) FROM public.user_profile WHERE user_role = 'trial' AND trial_expire_at < NOW())
    ) INTO result;

    RETURN result;
END;
$$;

-- ============================================================
-- 12. 相关卡片推荐：基于标签交集
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_related_cards(
    p_card_id UUID,
    p_limit INTEGER DEFAULT 5
)
RETURNS TABLE (
    id UUID,
    main_category VARCHAR,
    tags TEXT[],
    card_content TEXT,
    common_tags INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tags TEXT[];
    v_role TEXT;
    v_packages TEXT[];
BEGIN
    SELECT c.tags INTO v_tags
    FROM public.knowledge_card c
    WHERE c.id = p_card_id;

    IF v_tags IS NULL OR array_length(v_tags, 1) IS NULL THEN
        RETURN;
    END IF;

    SELECT user_role, COALESCE(assigned_packages, '{}')
    INTO v_role, v_packages
    FROM public.user_profile
    WHERE user_id = auth.uid();

    RETURN QUERY
    SELECT c.id,
           c.main_category,
           c.tags,
           LEFT(c.card_content, 300) AS card_content,
           cardinality(c.tags & v_tags) AS common_tags
    FROM public.knowledge_card c
    WHERE c.id <> p_card_id
      AND (
          v_role = 'owner'
          OR c.visible_packages = '{}'
          OR c.visible_packages && v_packages
      )
      AND c.tags && v_tags
    ORDER BY common_tags DESC, c.updated_at DESC
    LIMIT p_limit;
END;
$$;
