-- =============================================================================
-- HealthAdvisor · Phase 0 第五步
-- PostgreSQL DDL 迁移脚本 v001
--
-- 项目:        01-健康-Health · HealthAdvisor
-- 脚本来源:    content/family_profile_schema.json (schema_version 1.0)
-- 设计稿:      见 ../健康顾问开发架构与计划.md §4.2 技术栈
-- 关联文档:    content/pg_migration_v001.md
-- 目标库:      PostgreSQL 15+
-- 加密扩展:    pgcrypto (pgp_sym_encrypt / pgp_sym_decrypt)
-- 编码:        UTF-8
-- 生成时间:    2026-08-31
-- 维护者:      01-健康-Health (agent-cb68289aa08d)
--
-- 设计原则:
--   1. 严格对照 family_profile_schema.json 的 tables / enums_summary
--   2. 敏感字段 (id_card_enc / phone_enc) 用 pgcrypto 列加密
--   3. 软删除: archived_at IS NULL 的部分索引覆盖所有 5 张主表
--   4. 时间戳三件套: created_at / updated_at / archived_at
--   5. 顺手补 family 主表 (原 schema 的 next_steps #1),供多家庭隔离
--
-- 使用方式:
--   一次性:  psql -U health -d healthadvisor -f pg_migration_v001.sql
--   验证:    \dt+ health_*    \dT+ health.*    SELECT count(*) FROM health.member;
--
-- 回滚:
--   DROP SCHEMA health CASCADE;  -- 仅在 dev 环境
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. schema 隔离
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS health;
SET search_path TO health, public;

-- -----------------------------------------------------------------------------
-- 1. 扩展
-- -----------------------------------------------------------------------------
-- pgcrypto: 提供 pgp_sym_encrypt(bytea, text) / pgp_sym_decrypt(bytea, text)
--          用于身份证 / 手机号的列级加密 (BYTEA 存储)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- uuid-ossp: 提供 gen_random_uuid() (PG 13+ 内置,无需扩展)
-- 若部署到 PG 12 及以下,改为: CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- -----------------------------------------------------------------------------
-- 2. ENUM 类型 (5 个, 与 schema 的 enums_summary 对齐)
-- -----------------------------------------------------------------------------
DO $$ BEGIN
    CREATE TYPE health.relationship AS ENUM (
        'self', 'spouse', 'father', 'mother', 'son', 'daughter', 'grandparent', 'other'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE health.gender AS ENUM ('male', 'female', 'other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE health.blood_type AS ENUM ('A', 'B', 'AB', 'O', 'unknown');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE health.allergy_category AS ENUM ('food', 'drug', 'contact', 'inhalant', 'other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE health.allergy_severity AS ENUM ('mild', 'moderate', 'severe', 'anaphylaxis');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE health.medication_status AS ENUM ('active', 'paused', 'stopped', 'completed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE health.history_category AS ENUM ('chronic', 'acute', 'surgery', 'hospitalization', 'trauma', 'other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE health.relative_relation AS ENUM (
        'father', 'mother',
        'paternal_grandfather', 'paternal_grandmother',
        'maternal_grandfather', 'maternal_grandmother',
        'sibling', 'child', 'other'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- -----------------------------------------------------------------------------
-- 3. family 主表 (顺手补, 原 schema next_steps #1)
--    字段极简, Phase 1 实施时再扩展 (owner / shared_with / plan_tier)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS health.family (
    family_id    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name         VARCHAR(64)  NOT NULL,
    created_by   VARCHAR(64)  NOT NULL,  -- 飞书 user_id 或本地 user_id, 字符串灵活
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    archived_at  TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_family_active_name
    ON health.family (name) WHERE archived_at IS NULL;

-- -----------------------------------------------------------------------------
-- 4. member 主档
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS health.member (
    member_id        UUID                 PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id        UUID                 NOT NULL REFERENCES health.family(family_id),
    name             VARCHAR(64)          NOT NULL,
    relationship     health.relationship  NOT NULL,
    gender           health.gender        NOT NULL,
    birth_date       DATE                 NOT NULL,
    id_card_enc      BYTEA,                              -- pgp_sym_encrypt 加密
    phone_enc        BYTEA,                              -- pgp_sym_encrypt 加密
    blood_type       health.blood_type,
    height_cm        DECIMAL(5,1),
    occupation       VARCHAR(64),
    lifestyle_tags   JSONB,                              -- {smoke, drink, exercise_freq, sleep_late}
    avatar_url       VARCHAR(256),
    created_at       TIMESTAMPTZ          NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ          NOT NULL DEFAULT now(),
    archived_at      TIMESTAMPTZ,
    CONSTRAINT chk_member_height CHECK (height_cm IS NULL OR (height_cm BETWEEN 30 AND 250))
);

-- 唯一约束: 同一家庭下, 姓名 + 出生日期唯一 (软删前)
CREATE UNIQUE INDEX IF NOT EXISTS uq_member_family_name_birth
    ON health.member (family_id, name, birth_date);

-- 部分索引: 软删外的成员
CREATE INDEX IF NOT EXISTS idx_member_family_active
    ON health.member (family_id) WHERE archived_at IS NULL;

COMMENT ON COLUMN health.member.id_card_enc IS
    '身份证号,pgp_sym_encrypt(id_card, current_setting(''app.encrypt_key'')) 加密后的 BYTEA';
COMMENT ON COLUMN health.member.phone_enc IS
    '手机号,pgp_sym_encrypt(phone, current_setting(''app.encrypt_key'')) 加密后的 BYTEA';

-- -----------------------------------------------------------------------------
-- 5. allergy 过敏史
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS health.allergy (
    allergy_id    UUID                    PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id     UUID                    NOT NULL REFERENCES health.member(member_id),
    allergen      VARCHAR(128)            NOT NULL,
    category      health.allergy_category NOT NULL,
    severity      health.allergy_severity NOT NULL,
    reaction      TEXT,
    diagnosed_at  DATE,
    note          TEXT,
    created_at    TIMESTAMPTZ             NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ             NOT NULL DEFAULT now(),
    archived_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_allergy_member_active
    ON health.allergy (member_id) WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_allergy_member_category_active
    ON health.allergy (member_id, category) WHERE archived_at IS NULL;

-- -----------------------------------------------------------------------------
-- 6. medication 用药记录
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS health.medication (
    medication_id      UUID                    PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id          UUID                    NOT NULL REFERENCES health.member(member_id),
    drug_name          VARCHAR(128)            NOT NULL,
    brand_name         VARCHAR(128),
    dosage             VARCHAR(64),
    frequency          VARCHAR(64),
    indication         VARCHAR(256),
    start_date         DATE,
    end_date           DATE,
    prescribed_by      VARCHAR(64),
    status             health.medication_status NOT NULL DEFAULT 'active',
    reminder_enabled   BOOLEAN                 NOT NULL DEFAULT false,
    created_at         TIMESTAMPTZ             NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ             NOT NULL DEFAULT now(),
    archived_at        TIMESTAMPTZ,
    CONSTRAINT chk_medication_dates CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_medication_member_active
    ON health.medication (member_id) WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_medication_member_status_active
    ON health.medication (member_id, status) WHERE status = 'active' AND archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_medication_drug_name
    ON health.medication (drug_name);

-- -----------------------------------------------------------------------------
-- 7. history 既往病史
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS health.history (
    history_id     UUID                   PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id      UUID                   NOT NULL REFERENCES health.member(member_id),
    condition_name VARCHAR(128)           NOT NULL,
    icd10_code     VARCHAR(16),
    category       health.history_category NOT NULL,
    diagnosed_at   DATE,
    is_chronic     BOOLEAN                NOT NULL DEFAULT false,
    is_resolved    BOOLEAN                NOT NULL DEFAULT false,
    treatment      TEXT,
    hospital       VARCHAR(128),
    note           TEXT,
    created_at     TIMESTAMPTZ            NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ            NOT NULL DEFAULT now(),
    archived_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_history_member_active
    ON health.history (member_id) WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_history_member_chronic_active
    ON health.history (member_id, is_chronic)
    WHERE is_chronic = true AND archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_history_condition_name
    ON health.history (condition_name);

-- -----------------------------------------------------------------------------
-- 8. family_history 家族史
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS health.family_history (
    family_history_id     UUID                    PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id             UUID                    NOT NULL REFERENCES health.member(member_id),
    relative_relation     health.relative_relation NOT NULL,
    condition_name        VARCHAR(128)            NOT NULL,
    icd10_code            VARCHAR(16),
    onset_age             INT,
    is_deceased_from_it   BOOLEAN                 NOT NULL DEFAULT false,
    note                  TEXT,
    created_at            TIMESTAMPTZ             NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ             NOT NULL DEFAULT now(),
    archived_at           TIMESTAMPTZ,
    CONSTRAINT chk_onset_age CHECK (onset_age IS NULL OR (onset_age BETWEEN 0 AND 130))
);

CREATE INDEX IF NOT EXISTS idx_family_history_member_active
    ON health.family_history (member_id) WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_family_history_member_condition
    ON health.family_history (member_id, condition_name);

-- -----------------------------------------------------------------------------
-- 9. updated_at 自动维护 trigger
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION health.tg_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    t TEXT;
BEGIN
    FOR t IN
        SELECT unnest(ARRAY['family', 'member', 'allergy', 'medication', 'history', 'family_history'])
    LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_%1$s_updated_at ON health.%1$s; '
            'CREATE TRIGGER trg_%1$s_updated_at '
            'BEFORE UPDATE ON health.%1$s '
            'FOR EACH ROW EXECUTE FUNCTION health.tg_set_updated_at();',
            t
        );
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 10. 加密密钥 GUC (Phase 1 FastAPI 启动时 SET LOCAL)
--     示例:  SET app.encrypt_key = 'phase1-dev-key-change-in-prod';
--     加密示例:
--       INSERT INTO health.member (..., id_card_enc, phone_enc)
--       VALUES (..., pgp_sym_encrypt('110101199001011234',
--                                     current_setting('app.encrypt_key')),
--                     pgp_sym_encrypt('13800138000',
--                                     current_setting('app.encrypt_key')));
--     解密示例:
--       SELECT pgp_sym_decrypt(id_card_enc, current_setting('app.encrypt_key'))
--       FROM health.member WHERE member_id = $1;
-- -----------------------------------------------------------------------------

COMMIT;

-- =============================================================================
-- 验证清单 (Phase 1 实施时跑一遍)
-- =============================================================================
-- \dn                            -- 应含 health
-- \dt health.*                   -- 应含 6 张表: family/member/allergy/medication/history/family_history
-- \dT health.*                   -- 应含 8 个 ENUM
-- SELECT count(*) FROM health.member;  -- 应 0
-- INSERT INTO health.family (name, created_by) VALUES ('测试家庭', 'test') RETURNING family_id;
-- INSERT INTO health.member (family_id, name, relationship, gender, birth_date)
--   VALUES ('<上一步 family_id>', '张三', 'self', 'male', '1990-01-01') RETURNING member_id;
-- =============================================================================
