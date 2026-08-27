-- 终生成长知识库 RLS 行级安全策略
-- 文件：supabase_sql/02_rls.sql
-- 运行前提：已执行 01_schema.sql，且启用 RLS

-- ============================================================
-- 辅助函数：当前用户角色 / 是否过期 / 可见包
-- ============================================================

-- 当前登录用户的 user_profile 角色
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT AS $$
DECLARE
    v_role TEXT;
BEGIN
    SELECT user_role INTO v_role
    FROM public.user_profile
    WHERE user_id = auth.uid();
    RETURN COALESCE(v_role, 'anonymous');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 当前登录用户是否已过期（仅 trial 角色需要判断）
CREATE OR REPLACE FUNCTION public.current_user_expired()
RETURNS BOOLEAN AS $$
DECLARE
    v_role TEXT;
    v_expire TIMESTAMPTZ;
BEGIN
    SELECT user_role, trial_expire_at
    INTO v_role, v_expire
    FROM public.user_profile
    WHERE user_id = auth.uid();

    IF v_role = 'trial' AND v_expire IS NOT NULL AND v_expire < NOW() THEN
        RETURN TRUE;
    END IF;
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 当前用户是否可访问某条可见包（包为空数组 或 当前用户 assigned_packages 与 visible_packages 有交集）
CREATE OR REPLACE FUNCTION public.user_can_access_package(pkg TEXT[])
RETURNS BOOLEAN AS $$
DECLARE
    v_role TEXT;
    v_assigned TEXT[];
BEGIN
    -- owner 始终可访问
    SELECT user_role, assigned_packages
    INTO v_role, v_assigned
    FROM public.user_profile
    WHERE user_id = auth.uid();

    IF v_role = 'owner' THEN
        RETURN TRUE;
    END IF;

    -- 空数组或 NULL 表示对所有人可见
    IF pkg IS NULL OR array_length(pkg, 1) IS NULL THEN
        RETURN TRUE;
    END IF;

    -- 用户有交集包即可见
    IF v_assigned IS NOT NULL AND v_assigned && pkg THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 1. daily_news RLS
-- ============================================================
ALTER TABLE public.daily_news ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_news FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS daily_news_owner_all ON public.daily_news;
CREATE POLICY daily_news_owner_all ON public.daily_news
    FOR ALL
    TO authenticated
    USING (public.current_user_role() = 'owner')
    WITH CHECK (public.current_user_role() = 'owner');

DROP POLICY IF EXISTS daily_news_trial_member_select ON public.daily_news;
CREATE POLICY daily_news_trial_member_select ON public.daily_news
    FOR SELECT
    TO authenticated
    USING (
        public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
        AND public.user_can_access_package(visible_packages)
    );

-- ============================================================
-- 2. knowledge_card RLS
-- ============================================================
ALTER TABLE public.knowledge_card ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_card FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS knowledge_card_owner_all ON public.knowledge_card;
CREATE POLICY knowledge_card_owner_all ON public.knowledge_card
    FOR ALL
    TO authenticated
    USING (public.current_user_role() = 'owner')
    WITH CHECK (public.current_user_role() = 'owner');

DROP POLICY IF EXISTS knowledge_card_trial_member_select ON public.knowledge_card;
CREATE POLICY knowledge_card_trial_member_select ON public.knowledge_card
    FOR SELECT
    TO authenticated
    USING (
        public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
        AND public.user_can_access_package(visible_packages)
    );

-- ============================================================
-- 3. knowledge_card_history RLS
-- ============================================================
ALTER TABLE public.knowledge_card_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_card_history FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS card_history_owner_all ON public.knowledge_card_history;
CREATE POLICY card_history_owner_all ON public.knowledge_card_history
    FOR ALL
    TO authenticated
    USING (public.current_user_role() = 'owner')
    WITH CHECK (public.current_user_role() = 'owner');

DROP POLICY IF EXISTS card_history_trial_member_select ON public.knowledge_card_history;
CREATE POLICY card_history_trial_member_select ON public.knowledge_card_history
    FOR SELECT
    TO authenticated
    USING (
        public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
        AND EXISTS (
            SELECT 1 FROM public.knowledge_card k
            WHERE k.id = card_id
              AND public.user_can_access_package(k.visible_packages)
        )
    );

-- ============================================================
-- 4. user_card_note RLS
-- ============================================================
ALTER TABLE public.user_card_note ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_card_note FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_card_note_owner_all ON public.user_card_note;
CREATE POLICY user_card_note_owner_all ON public.user_card_note
    FOR ALL
    TO authenticated
    USING (public.current_user_role() = 'owner')
    WITH CHECK (public.current_user_role() = 'owner');

DROP POLICY IF EXISTS user_card_note_self_all ON public.user_card_note;
CREATE POLICY user_card_note_self_all ON public.user_card_note
    FOR ALL
    TO authenticated
    USING (
        auth.uid() = user_id
        AND public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
    )
    WITH CHECK (
        auth.uid() = user_id
        AND public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
    );

-- ============================================================
-- 4.1 user_news_read RLS
-- ============================================================
ALTER TABLE public.user_news_read ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_news_read FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_news_read_owner_all ON public.user_news_read;
CREATE POLICY user_news_read_owner_all ON public.user_news_read
    FOR ALL
    TO authenticated
    USING (public.current_user_role() = 'owner')
    WITH CHECK (public.current_user_role() = 'owner');

DROP POLICY IF EXISTS user_news_read_self_all ON public.user_news_read;
CREATE POLICY user_news_read_self_all ON public.user_news_read
    FOR ALL
    TO authenticated
    USING (
        auth.uid() = user_id
        AND public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
    )
    WITH CHECK (
        auth.uid() = user_id
        AND public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
    );

-- ============================================================
-- 4.2 user_bookmark RLS
-- ============================================================
ALTER TABLE public.user_bookmark ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_bookmark FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_bookmark_owner_all ON public.user_bookmark;
CREATE POLICY user_bookmark_owner_all ON public.user_bookmark
    FOR ALL
    TO authenticated
    USING (public.current_user_role() = 'owner')
    WITH CHECK (public.current_user_role() = 'owner');

DROP POLICY IF EXISTS user_bookmark_self_all ON public.user_bookmark;
CREATE POLICY user_bookmark_self_all ON public.user_bookmark
    FOR ALL
    TO authenticated
    USING (
        auth.uid() = user_id
        AND public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
    )
    WITH CHECK (
        auth.uid() = user_id
        AND public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
    );

-- ============================================================
-- 5. explore_candidate RLS
-- ============================================================
ALTER TABLE public.explore_candidate ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_candidate FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS explore_candidate_owner_all ON public.explore_candidate;
CREATE POLICY explore_candidate_owner_all ON public.explore_candidate
    FOR ALL
    TO authenticated
    USING (public.current_user_role() = 'owner')
    WITH CHECK (public.current_user_role() = 'owner');

DROP POLICY IF EXISTS explore_candidate_trial_member_select ON public.explore_candidate;
CREATE POLICY explore_candidate_trial_member_select ON public.explore_candidate
    FOR SELECT
    TO authenticated
    USING (
        public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
    );

-- trial/member 可对待处理候选话题点击「同意订阅」或「跳过」
DROP POLICY IF EXISTS explore_candidate_trial_member_update ON public.explore_candidate;
CREATE POLICY explore_candidate_trial_member_update ON public.explore_candidate
    FOR UPDATE
    TO authenticated
    USING (
        public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
        AND status = 'pending'
    )
    WITH CHECK (
        public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
        AND status IN ('subscribe', 'skip')
    );

-- ============================================================
-- 6. subscribe_task RLS
-- ============================================================
ALTER TABLE public.subscribe_task ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscribe_task FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subscribe_task_owner_all ON public.subscribe_task;
CREATE POLICY subscribe_task_owner_all ON public.subscribe_task
    FOR ALL
    TO authenticated
    USING (public.current_user_role() = 'owner')
    WITH CHECK (public.current_user_role() = 'owner');

DROP POLICY IF EXISTS subscribe_task_trial_member_select ON public.subscribe_task;
CREATE POLICY subscribe_task_trial_member_select ON public.subscribe_task
    FOR SELECT
    TO authenticated
    USING (
        public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
        AND public.user_can_access_package(visible_packages)
    );

-- trial/member 仅可创建由本人发起的短期订阅（通过「同意订阅」按钮）
DROP POLICY IF EXISTS subscribe_task_trial_member_insert ON public.subscribe_task;
CREATE POLICY subscribe_task_trial_member_insert ON public.subscribe_task
    FOR INSERT
    TO authenticated
    WITH CHECK (
        public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
        AND created_by = auth.uid()
        AND task_type = 'short'
        AND status = 'active'
    );

-- ============================================================
-- 7. subscribe_package RLS
-- ============================================================
ALTER TABLE public.subscribe_package ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscribe_package FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subscribe_package_owner_all ON public.subscribe_package;
CREATE POLICY subscribe_package_owner_all ON public.subscribe_package
    FOR ALL
    TO authenticated
    USING (public.current_user_role() = 'owner')
    WITH CHECK (public.current_user_role() = 'owner');

DROP POLICY IF EXISTS subscribe_package_trial_member_select ON public.subscribe_package;
CREATE POLICY subscribe_package_trial_member_select ON public.subscribe_package
    FOR SELECT
    TO authenticated
    USING (
        public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
    );

-- ============================================================
-- 8. user_profile RLS
-- ============================================================
ALTER TABLE public.user_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profile FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_profile_owner_all ON public.user_profile;
CREATE POLICY user_profile_owner_all ON public.user_profile
    FOR ALL
    TO authenticated
    USING (public.current_user_role() = 'owner')
    WITH CHECK (public.current_user_role() = 'owner');

DROP POLICY IF EXISTS user_profile_self_select_update ON public.user_profile;
CREATE POLICY user_profile_self_select_update ON public.user_profile
    FOR SELECT
    TO authenticated
    USING (
        auth.uid() = user_id
        AND public.current_user_role() IN ('trial', 'member')
    );

-- member/trial 不允许修改自己的业务字段，只允许读取

-- ============================================================
-- 9. login_log RLS
-- ============================================================
ALTER TABLE public.login_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_log FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS login_log_owner_all ON public.login_log;
CREATE POLICY login_log_owner_all ON public.login_log
    FOR ALL
    TO authenticated
    USING (public.current_user_role() = 'owner')
    WITH CHECK (public.current_user_role() = 'owner');

DROP POLICY IF EXISTS login_log_self_select ON public.login_log;
CREATE POLICY login_log_self_select ON public.login_log
    FOR SELECT
    TO authenticated
    USING (
        auth.uid() = user_id
        AND public.current_user_role() IN ('trial', 'member')
    );

-- trial/member 可在登录时写入自己的登录日志
DROP POLICY IF EXISTS login_log_self_insert ON public.login_log;
CREATE POLICY login_log_self_insert ON public.login_log
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() = user_id
        AND public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
    );

-- ============================================================
-- 10. browse_log RLS
-- ============================================================
ALTER TABLE public.browse_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.browse_log FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS browse_log_owner_all ON public.browse_log;
CREATE POLICY browse_log_owner_all ON public.browse_log
    FOR ALL
    TO authenticated
    USING (public.current_user_role() = 'owner')
    WITH CHECK (public.current_user_role() = 'owner');

DROP POLICY IF EXISTS browse_log_self_insert_select ON public.browse_log;
CREATE POLICY browse_log_self_insert_select ON public.browse_log
    FOR ALL
    TO authenticated
    USING (
        auth.uid() = user_id
        AND public.current_user_role() IN ('trial', 'member')
    )
    WITH CHECK (
        auth.uid() = user_id
        AND public.current_user_role() IN ('trial', 'member')
        AND NOT public.current_user_expired()
    );

-- ============================================================
-- 11. operation_log RLS（仅 owner 可访问）
-- ============================================================
ALTER TABLE public.operation_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operation_log FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS operation_log_owner_all ON public.operation_log;
CREATE POLICY operation_log_owner_all ON public.operation_log
    FOR ALL
    TO authenticated
    USING (public.current_user_role() = 'owner')
    WITH CHECK (public.current_user_role() = 'owner');

-- ============================================================
-- 12. collection_jobs RLS（owner 全权限；trial/member 仅看自己）
-- ============================================================
ALTER TABLE public.collection_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.collection_jobs FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS collection_jobs_owner_all ON public.collection_jobs;
CREATE POLICY collection_jobs_owner_all ON public.collection_jobs
    FOR ALL
    TO authenticated
    USING (public.current_user_role() = 'owner')
    WITH CHECK (public.current_user_role() = 'owner');

DROP POLICY IF EXISTS collection_jobs_self_select ON public.collection_jobs;
CREATE POLICY collection_jobs_self_select ON public.collection_jobs
    FOR SELECT
    TO authenticated
    USING (created_by = auth.uid());

-- ============================================================
-- 匿名用户（anon）禁止访问所有业务表
-- ============================================================
-- 通过 FORCE ROW LEVEL SECURITY + 没有针对 anon 的 policy，
-- 匿名用户所有请求默认被拒绝。

-- ============================================================
-- auth.users 元数据仅允许 owner 查询
-- 通过 public.get_all_users() RPC（SECURITY DEFINER）实现，
-- 避免前端直接查询 auth.users 造成信息泄露。
-- ============================================================
