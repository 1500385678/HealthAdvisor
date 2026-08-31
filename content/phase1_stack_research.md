# phase1_stack_research · Phase 1 技术栈预研

> Phase 1 启动前预研 · 09-01 巡检建议兑现 · 2026-09-01 · 01-健康-Health
> **状态**:纯文档调研 · **不**含代码 / **不**含 `package.json` / `requirements.txt` / `Dockerfile`
> **目的**:Phase 0 已 5/6 收尾(仅 OCR 样本等张勇本人),提前 1-2 周启动 Phase 1 选型调研,避免"Phase 0 完成 → Phase 1 启动空窗期"

---

## 一、为什么是现在做这个

| 触发 | 时间 | 来源 |
|------|------|------|
| Phase 0 收尾到 5/6(83%) | 2026-08-31 | commit `8c46db7` PG migration v001 |
| 巡检建议"T2 窗口做 Phase 1 调研" | 2026-09-01 02:00 | `.Log/巡检-健康-20260901.md` 第四条 |
| Phase 1 累计 7 工作日 0/7 未启动 | 2026-08-25 → 09-01 | 巡检持续标记 |

**核心目标**:**不写代码,只定选型**。让 Phase 1 真正开工时(`src/` `app.py` `package.json` 第一行),不再为"用 FastAPI 还是 Flask""React 还是 Vue"这类基础问题纠结。

---

## 二、API 框架选型: FastAPI (推荐)

### 2.1 候选对比

| 维度 | FastAPI (推荐) | Flask | Django REST | NestJS |
|------|----------------|-------|-------------|--------|
| 异步支持 | ✅ 原生 async/await | ⚠️ 需 gevent/Quart | ⚠️ ASGI 模式 | ✅ 原生 |
| Pydantic 校验 | ✅ 内置 | ❌ 需 marshmallow | ❌ 需 serializer | ⚠️ class-validator |
| OpenAPI 文档 | ✅ 自动生成 | ❌ 需 flask-restx | ⚠️ drf-spectacular | ✅ 自动 |
| 类型提示 | ✅ 全栈 Python 3.10+ | ❌ 无强制 | ⚠️ 部分 | ✅ TypeScript |
| AI/LLM 生态 | ✅ 主流(OpenAI/LangChain 文档默认) | ⚠️ 滞后 | ⚠️ 偏企业级 | ⚠️ 偏前端转岗 |
| 医疗数据校验 | ✅ 强类型 + Pydantic | ⚠️ 弱 | ✅ 强 | ✅ 强 |
| 学习曲线 | 🟢 中(Python 熟) | 🟢 低 | 🟡 中(全家桶) | 🟡 中(TS) |

### 2.2 推荐理由(3 条硬理由)

1. **Pydantic v2 内置**:`family_profile_schema.json` 已定义 67 字段,直接转 `BaseModel`,零样板代码
2. **异步 OCR/LLM 调用**:`await openai.ChatCompletion.acreate()` / `await paddleocr.ainfer()`,体检报告批处理不会阻塞
3. **自动 OpenAPI 文档**:`/docs` 即时调试,前端可基于 schema 自动生成 TypeScript 类型(避免手抄)

### 2.3 拒绝的方案

- **Flask**:同步阻塞,OCR + LLM 慢任务会卡 worker
- **Django REST**:全家桶太重,Phase 1 不需要 admin/auth/orm 全套
- **NestJS**:团队无 TS 主力,引入即增 1 个技术栈

---

## 三、前端选型: React 18 + Vite + TypeScript(推荐)

### 3.1 候选对比

| 维度 | React 18 + Vite + TS (推荐) | Vue 3 + Vite | Next.js 14 | SvelteKit |
|------|------------------------------|--------------|------------|-----------|
| 家庭档案管理 | ✅ 组件丰富 | ✅ 更轻 | ✅ SSR | ⚠️ 偏小项目 |
| 体检报告上传 + 预览 | ✅ react-pdf / pdf.js | ✅ 类似 | ✅ 类似 | ⚠️ 生态薄 |
| 慢病曲线(Recharts) | ✅ 主流 | ✅ 类似 | ✅ 类似 | ⚠️ 需自撸 |
| AI 问诊聊天 UI | ✅ react-markdown + 流式 | ✅ 类似 | ✅ 类似 | ⚠️ 需自撸 |
| TypeScript 类型生成 | ✅ openapi-typescript | ✅ 类似 | ✅ 内置 | ⚠️ 弱 |
| 国内招聘/外包友好度 | ✅ 最高 | 🟡 中 | ✅ 高 | ❌ 低 |
| 老人端大字体改造 | ✅ CSS variables | ✅ 更易 | ✅ 中等 | ✅ 最易 |

### 3.2 推荐理由(3 条)

1. **OpenAPI → TypeScript 自动生成**:`openapi-typescript http://localhost:8000/openapi.json -o src/api/types.ts`,API 字段与 Pydantic schema 强一致
2. **生态最厚**:Recharts(曲线)/ react-pdf(报告预览)/ react-markdown(AI 回答)/ react-hook-form(家庭档案录入)全部有现成
3. **团队/外包友好**:React 工程师市场最大,后续招人或合作门槛低

### 3.3 拒绝的方案

- **Vue 3**:生态略薄,Recharts/ECharts 主流绑定 React
- **Next.js**:SSR 对本地化部署增加复杂度,Phase 1 不需要 SEO
- **SvelteKit**:老人端友好是亮点,但生态太薄,5 成员 × 3 报告 demo 阶段不必冒险

---

## 四、数据层选型: PostgreSQL 16 + SQLAlchemy 2.0(异步)

### 4.1 候选对比

| 维度 | PG 16 + SQLAlchemy 2.0 async (推荐) | PG 16 + asyncpg 直连 | SQLite + aiosqlite | MongoDB |
|------|--------------------------------------|----------------------|-------------------|---------|
| `pg_migration_v001.sql` 复用 | ✅ 100%(已写好) | ✅ 100% | ❌ 需重写 | ❌ schema 不同 |
| pgcrypto 列加密 | ✅ 原生 | ✅ 原生 | ⚠️ 需应用层 | ⚠️ 字段级加密 |
| 关系查询(家族史关联) | ✅ JOIN/外键 | ✅ 手写 SQL | ⚠️ 弱 | ❌ 反范式 |
| 异步驱动 | ✅ asyncpg + SQLAlchemy | ✅ 原生 async | ✅ aiosqlite | ✅ motor |
| 备份/迁移 | ✅ pg_dump / Alembic | ✅ 同 | ⚠️ 文件级 | ⚠️ mongodump |

### 4.2 推荐理由(3 条)

1. **Phase 0 已就位**:`content/pg_migration_v001.sql` 6 表 / 8 ENUM / pgcrypto 列加密 全部就绪,直接 `psql -f` 即可
2. **SQLAlchemy 2.0 async 范式**:`async with async_session() as s: ... await s.execute(...)`,与 FastAPI 异步对齐
3. **Alembic 迁移**:`alembic init` + `alembic revision --autogenerate`,后续 `pg_migration_v002` 可走版本化

### 4.3 拒绝的方案

- **asyncpg 直连**:ORM 关系映射/迁移管理都要手撸,67 字段表会变成样板地狱
- **SQLite**:Phase 0 PG 迁移已写,回退 = 浪费
- **MongoDB**:家族史/过敏/用药强关系,反范式是负担

---

## 五、项目结构骨架(规划,不创建)

```
_HealthLib/HealthWeb/
├── backend/                          # FastAPI
│   ├── app/
│   │   ├── main.py                   # FastAPI() 入口 + CORS + lifespan
│   │   ├── api/
│   │   │   ├── profile.py            # /api/profile 家庭档案 CRUD
│   │   │   ├── report.py             # /api/report 体检报告上传 + OCR
│   │   │   ├── track.py              # /api/track 指标录入 + 曲线
│   │   │   └── ai.py                 # /api/ai 问诊(OpenAI/LangChain)
│   │   ├── core/
│   │   │   ├── config.py             # Pydantic Settings(env 读取)
│   │   │   ├── security.py           # OAuth + 加密 key 注入
│   │   │   └── db.py                 # async_session 工厂
│   │   ├── models/                   # SQLAlchemy ORM(对应 pg_migration_v001)
│   │   ├── schemas/                  # Pydantic(BaseModel)
│   │   ├── services/                 # 业务逻辑(OCR/LLM/指标计算)
│   │   └── alembic/                  # 迁移版本
│   ├── tests/
│   ├── pyproject.toml                # uv / poetry 二选一
│   └── Dockerfile
├── frontend/                         # React 18 + Vite + TS
│   ├── src/
│   │   ├── main.tsx
│   │   ├── App.tsx
│   │   ├── api/                      # openapi-typescript 生成的 client
│   │   ├── pages/
│   │   │   ├── Profile.tsx           # 家庭档案管理
│   │   │   ├── Report.tsx            # 报告上传 + 解读
│   │   │   ├── Track.tsx             # 慢病曲线
│   │   │   └── AI.tsx                # 问诊聊天
│   │   ├── components/
│   │   └── styles/                   # 老人端大字体 CSS variables
│   ├── package.json
│   ├── vite.config.ts
│   └── Dockerfile
├── docker-compose.yml                # postgres + backend + frontend 一键起
├── .env.example                      # OPENAI_API_KEY / APP_ENCRYPT_KEY / DATABASE_URL
└── content/                          # Phase 0 资产(已有 6 文件)
```

---

## 六、待决策项(等张勇本人,不抢答)

| 决策点 | 选项 | 阻塞原因 |
|--------|------|---------|
| 部署目标 | 家庭 NAS / 阿里云轻量 / 群晖 | 隐私 + 成本 |
| 域名 + SSL | 家庭公网 IP / 阿里云备案 / 内网穿透 | 飞书 OAuth 需公网回调 |
| LLM 选型 | GPT-4o / DeepSeek-V3 / Qwen3-Max | 成本 + 中文医疗 |
| OCR 引擎 | PaddleOCR(本地) / 百度 OCR(API) / Tesseract | 报告格式复杂度 |
| 老人端入口 | Web 大字体 / 微信 H5 / 飞书 Bot | 张勇父母使用习惯 |
| OpenAI 兼容层 | LiteLLM / 直接调 | 多模型切换成本 |

> 上述 6 项**全部等张勇本人拍板**,agent 不预设,不在 Phase 1 启动时定。

---

## 七、Phase 1 启动条件 checklist

- [x] Phase 0 资产盘点 5/6 收尾(2026-08-31 完成)
- [x] 技术栈选型定稿(本文档)
- [ ] 张勇本人定 6 项决策(部署/域名/LLM/OCR/老人端/兼容层)
- [ ] OCR 样本到位 5-10 份(等张勇本人,可先公开报告走通流程)
- [ ] 域名 + SSL 准备就绪(飞书 OAuth 必需)
- [ ] OPENAI_API_KEY / APP_ENCRYPT_KEY 安全落地(macOS Keychain / 1Password)

**预计启动窗口**:`2026-09-08` 当周(W2 末),张勇 6 项决策 + OCR 样本任一到位即开工。

---

## 八、变更记录

| 日期 | 变更 | 作者 |
|------|------|------|
| 2026-09-01 | 初稿:API/前端/数据层 3 项选型 + 项目结构骨架 + 6 项待决策 | 01-健康-Health |

---

## 九、关联文档

- `content/pg_migration_v001.md` — Phase 0 数据层基础(已被本文档第 4 章引用)
- `content/family_profile_schema.json` — 67 字段 Pydantic 化来源
- `项目开发计划.md` 第六节 Phase 1 — 7 项 MVP 任务清单
- `.Log/巡检-健康-20260901.md` — 巡检建议源头
