# pg_migration_v001 · PG 迁移脚本 v001

> Phase 0 第五步 · 把 `family_profile_schema.json` 落到 PostgreSQL DDL
> 2026-08-31 · 01-健康-Health

## 一、这份脚本做了什么

把 Phase 0 设计的家庭档案 5 张表(`member / allergy / medication / history / family_history`)落为可一键执行的 PG DDL,顺手补了原 schema `next_steps #1` 缺的 `family` 主表,并完成:

| 维度 | 数量 | 说明 |
|------|------|------|
| Schema | 1 | `health` (隔离业务与 `public`) |
| 扩展 | 1 | `pgcrypto` (列加密) |
| ENUM 类型 | 8 | relationship / gender / blood_type / allergy_category / allergy_severity / medication_status / history_category / relative_relation |
| 表 | 6 | family + 5 张主表 |
| 索引 | 14 | 唯一 / 部分索引 (`archived_at IS NULL` 是软删常用前缀) |
| 触发器 | 6 | 自动维护 `updated_at` |
| CHECK 约束 | 2 | 身高 30-250cm、用药 end_date ≥ start_date、家族史 onset_age 0-130 |

**严格对照** `content/family_profile_schema.json` 的 `tables` / `enums_summary`,字段、类型、索引一对一映射,**没有自行发挥**。

## 二、关键设计决策

### 2.1 pgcrypto 列加密

`member.id_card_enc` / `member.phone_enc` 用 `pgp_sym_encrypt(plaintext, key)` → `BYTEA` 存储,密钥通过 PG GUC `app.encrypt_key` 传递,**不**写在 SQL 里。

```sql
-- 加密写入
INSERT INTO health.member (..., id_card_enc, phone_enc) VALUES (
    ...,
    pgp_sym_encrypt('110101199001011234', current_setting('app.encrypt_key')),
    pgp_sym_encrypt('13800138000',      current_setting('app.encrypt_key'))
);

-- 解密读取
SELECT pgp_sym_decrypt(id_card_enc, current_setting('app.encrypt_key'))
FROM health.member WHERE member_id = $1;
```

Phase 1 FastAPI 启动时 `SET LOCAL app.encrypt_key = ...`,密钥从环境变量 / Vault 来,**绝不**进代码。

### 2.2 顺手补 family 主表

原 schema `next_steps #1` 提到"补 family 主表用于多家庭隔离",本脚本一并补上,字段极简:

| 字段 | 类型 | 用途 |
|------|------|------|
| family_id | UUID PK | 主键 |
| name | VARCHAR(64) | 家庭名(如"张家") |
| created_by | VARCHAR(64) | 飞书 user_id / 本地 user_id |
| 3 时间戳 | TIMESTAMPTZ | created_at / updated_at / archived_at |

Phase 1 实施时再扩展 `owner / shared_with / plan_tier` 等业务字段。

### 2.3 部分索引 (`WHERE archived_at IS NULL`)

家庭档案场景下,删除影响追踪,默认 `archived` 而非硬删。查询时 99% 关心未删除记录,部分索引让查询计划跳过软删数据:

```sql
CREATE INDEX idx_member_family_active
    ON health.member (family_id) WHERE archived_at IS NULL;
```

`medication` 的"在用药物"也用部分索引: `WHERE status = 'active' AND archived_at IS NULL`,这是慢病追踪 + 用药提醒的高频路径。

### 2.4 CHECK 约束

- `height_cm` 30-250(覆盖婴儿到巨人症罕见值,正常 50-220)
- `medication` `end_date >= start_date`(防止录错)
- `family_history.onset_age` 0-130(防止录错)

## 三、Phase 1 实施要点(给后续用)

### 3.1 SQLAlchemy 模型生成

```python
# Phase 1 实施时, 推荐用 sqlacodegen 反向生成
sqlacodegen postgresql://health:***@localhost/healthadvisor \
    --schema health --outfile app/models/health.py
```

或者手写 `app/models/`,**字段名 / 类型与本 SQL 一一对应**。

### 3.2 Alembic 迁移

```bash
alembic init app/migrations
# 把本 SQL 内容拆成 upgrade() / downgrade() 步骤
# 升级:  CREATE EXTENSION → CREATE TYPE → CREATE TABLE → CREATE INDEX → CREATE TRIGGER
# 降级:  反向
```

### 3.3 加密密钥管理

```python
# FastAPI 启动 (lifespan)
@asynccontextmanager
async def lifespan(app: FastAPI):
    key = os.environ["HEALTH_ENCRYPT_KEY"]  # 从 Vault / K8s Secret
    async with app.state.db.begin() as conn:
        await conn.execute(text("SET app.encrypt_key = :k"), {"k": key})
    yield
```

**生产环境强制要求**: key 不进 SQL / 不进 Git / 不进日志,定期轮换。

## 四、验证步骤

```bash
# 1. 创建数据库 (一次性)
createdb healthadvisor

# 2. 执行迁移
psql -U health -d healthadvisor -f content/pg_migration_v001.sql

# 3. 验证 schema 与表
psql -U health -d healthadvisor -c "\dn"
psql -U health -d healthadvisor -c "\dt health.*"
psql -U health -d healthadvisor -c "\dT health.*"

# 4. 验证加密写入/读取 (临时,验证完即弃)
psql -U health -d healthadvisor <<'EOF'
SET app.encrypt_key = 'phase1-dev-test-key';
INSERT INTO health.family (name, created_by) VALUES ('测试家庭', 'test') RETURNING family_id;
INSERT INTO health.member (family_id, name, relationship, gender, birth_date, id_card_enc, phone_enc) VALUES
    ('<上一步返回>', '张三', 'self', 'male', '1990-01-01',
     pgp_sym_encrypt('110101199001011234', current_setting('app.encrypt_key')),
     pgp_sym_encrypt('13800138000', current_setting('app.encrypt_key')))
RETURNING member_id;
SELECT name, pgp_sym_decrypt(id_card_enc, current_setting('app.encrypt_key')) AS id_card
FROM health.member;
EOF
```

预期: schema `health` 存在,6 张表 + 8 个 ENUM 存在,id_card 解密后回到 `'110101199001011234'`。

## 五、回滚

```sql
-- dev 环境一键回滚
DROP SCHEMA IF EXISTS health CASCADE;
DROP EXTENSION IF EXISTS pgcrypto;  -- 若无其他 schema 依赖
```

**生产环境禁止** `DROP SCHEMA CASCADE`,需走 Alembic downgrade。

## 六、与既有文档的关联

- **设计稿**: `content/family_profile_schema.json` (本脚本的事实源,字段/索引一对一映射)
- **架构稿**: `../健康顾问开发架构与计划.md` §4.2 技术栈 (PG 选型 / 加密策略)
- **主计划**: `../项目开发计划.md` §五 Phase 0 第 4 项 (本脚本对应)
- **下游**: Phase 1 Alembic 迁移 + SQLAlchemy 模型(待启动)

## 七、变更记录

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-08-31 | v001 | 首版:6 表 + 8 ENUM + pgcrypto + family 顺手补 |
