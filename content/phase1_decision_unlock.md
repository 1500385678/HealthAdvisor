# phase1_decision_unlock · 6 决策 → 解锁任务映射

> Phase 1 决策落地后的执行清单 · 配合 `phase1_decision_brief.md` 使用
> 创建日期:2026-09-03 · 01-健康-Health 行业顾问(T5 03:00)
> **状态**:决策就绪后的"任务展开" — 6 决策勾选后,直接按本文档 T1 拉 issues
> **依赖**:`phase1_decision_brief.md`(决策脚手架,0902 入仓)+ `phase1_stack_research.md`(技术栈,0901 入仓)

---

## 一、为什么需要这份映射

`phase1_decision_brief.md` 给出了 6 项决策的"勾选框",但**勾选之后到底要写什么代码/配什么文件/跑什么命令**,本身不是显性知识。

本文档做 3 件事:

1. **每项决策的"解锁清单"**——勾选后必出/可选出的具体文件 / 脚本 / 配置
2. **6 决策全部勾完后的"启动顺序"**——按 `phase1_decision_brief.md` 第三节"决策依赖关系"的推荐顺序 6→1→3→4→2→5
3. **首个 PR 范围**——Phase 1 骨架第 1 周交付的最小可运行 demo

**本清单**:**仅文档**,不写代码 / 不动 schema / 不改 commit 计划。决策勾完 6 框后,T1 窗口拉 issues 直接按本文档执行。

---

## 二、6 决策 → 解锁清单

### 决策 1:部署方式

| 选项 | 解锁文件 |
|------|---------|
| **A. 本地 Docker Compose**(推荐) | `docker-compose.yml`(postgres:16-alpine + redis:7-alpine + backend + frontend 4 service)+ `.env.example`(DATABASE_URL / OPENAI_API_KEY / APP_ENCRYPT_KEY 模板)+ 根目录 `Makefile`(`make up` / `make down` / `make logs` 3 快捷命令) |
| B. 云 ECS + Docker | A 的全部 + `terraform/`(阿里云 ECS / PG / Redis 资源定义)+ `deploy/nginx.conf` + SSL 证书挂载脚本 |
| C. Serverless | `backend/app/core/serverless.py`(阿里云函数计算适配层)+ 冷启动优化(SQLAlchemy 懒加载) |

### 决策 2:域名与备案

| 选项 | 解锁文件 |
|------|---------|
| **A. 暂不申请**(推荐) | 无新文件(本地 + 飞书 Bot 形态,公网走 `https://open.feishu.cn` 回调) |
| B. 申请 `.cn` / `.com.cn` | A 的全部 + `deploy/icp-record/` 备案材料清单 + `deploy/ssl/` Let's Encrypt 自动续期脚本 |
| C. `.com` 境外域 | `deploy/cloudflare/` DNS + CDN 配置(**医疗数据不合规,不推荐**) |

### 决策 3:LLM 接入

| 选项 | 解锁文件 |
|------|---------|
| **A. Claude Sonnet 4 / 4.5**(推荐) | `backend/app/core/llm.py`(anthropic SDK 封装)+ `backend/app/services/prompts/medical_consult.py`(医疗问诊 system prompt 模板,含"非诊断"免责声明)+ `backend/tests/test_llm.py`(mock 测试,1 美元封顶) |
| B. GPT-4o / 4.1 | A 的 `llm.py` 换 `openai` SDK 导入 + prompts 文件同步 |
| C. 国内合规云(通义 / 文心 / 豆包) | A 的全部 + `backend/app/core/llm_router.py`(多 provider 路由)+ 各家 SDK 适配层 |
| D. 本地 LLaMA / Qwen2.5 | A 的 `llm.py` 换 `ollama` / `vllm` 客户端 + `docker-compose.yml` 加 `ollama` service |

### 决策 4:OCR 引擎

| 选项 | 解锁文件 |
|------|---------|
| **A. PaddleOCR**(推荐) | `backend/app/services/ocr/paddle.py`(PP-Structure 表格识别封装)+ `backend/tests/fixtures/sample_report_*.png`(2-3 份公开匿名样本,验证流程)+ `backend/app/services/ocr/postprocess.py`(关键词库 + LLM 兜底,消费 `medical_ner.json`) |
| B. 百度 OCR | A 的 `paddle.py` 换 `baidu-aip` SDK + API key 注入(`backend/app/core/config.py` 增 `BAIDU_OCR_AK` / `SK`) |
| C. 腾讯云 OCR | A 的全部 + 腾讯云 SDK 适配 |
| D. Tesseract 5 | `paddle.py` 换 `pytesseract`(能力弱,Phase 1 不推荐) |

### 决策 5:老人端

| 选项 | 解锁文件 |
|------|---------|
| **A. 大字体 + 简化界面**(推荐) | `frontend/src/styles/elder.css`(CSS variables,根字号 18px→24px 可切)+ `frontend/src/components/ElderModeToggle.tsx`(右上角开关) |
| B. 大字体 + 语音输入 | A 的全部 + `frontend/src/components/VoiceInput.tsx`(浏览器 `Web Speech API`)+ 兼容性降级(不支持时隐藏入口) |
| C. 子女代办 | 无新代码(纯模式选择,数据权限上区分"代管"标记) |
| D. 暂不做老人端 | 无新代码(Phase 1 内测可接受) |

### 决策 6:数据库兼容层

| 选项 | 解锁文件 |
|------|---------|
| **A. 直接切 PG**(推荐) | `pg_migration_v001.sql` 已在仓(0831),启动时 `docker compose exec postgres psql -U health -d healthdb -f /docker-entrypoint-initdb.d/pg_migration_v001.sql` 自动跑;新建 `backend/app/models/` 6 个 ORM 文件(对应 6 表)+ `backend/app/core/db.py`(async_session 工厂) |
| B. SQLite + PG 并行 | A 的全部 + `backend/app/core/db_router.py`(读写分流)+ 数据双写一致性测试 |
| C. 仅 SQLite | A 的 `models/*.py` 改 SQLAlchemy SQLite 方言 + `pg_migration_v001.sql` 改 SQLite 版(放弃 pgcrypto,改应用层加密) |

---

## 三、6 决策全选 A 后的启动顺序

按 `phase1_decision_brief.md` 第三节"决策依赖关系"推荐顺序 **6→1→3→4→2→5**,Phase 1 骨架第 1 周交付如下(对齐张勇 36 行业 Scheduled Task 火车站调度模型 T1-T5 节奏):

```
Day 1 (T1 拉 issues):
  - 6 决策勾选确认 → 在 项目开发计划.md 第 159 行追加"✅ YYYY-MM-DD 6 项决策已定"
  - 按本文档第二节建 6 个 GitHub Issues 草稿
  - 决策 6 任务(ORM + db.py)第 1 批 PR

Day 2 (T2 改 bug):
  - 决策 1 任务(docker-compose.yml + .env.example + Makefile)第 1 批 PR
  - 决策 3 任务(llm.py + medical_consult.py)第 1 批 PR

Day 3 (T3 加 API):
  - 决策 4 任务(ocr/paddle.py + postprocess.py + 2 份样例)第 1 批 PR
  - /api/profile CRUD 第 1 个接口(GET /api/profile/{member_id})

Day 4 (T4 优化):
  - 决策 5 任务(elder.css + ElderModeToggle.tsx)第 1 批 PR
  - 决策 2 任务(若选 A,跳过;若选 B,启动备案)

Day 5 (T5 推 release):
  - FastAPI 骨架 hello world + docker compose up 一键启动
  - 5 家庭 1 成员 1 份报告 demo 数据 seed
  - tag v0.1.0
```

**预计窗口**:W2 末(2026-09-08)决策落定 → W3 当周(~09-12)骨架可启动 + 首个 PR。

---

## 四、首个 PR 范围(Phase 1 MVP 第 1 批)

满足"1 家庭 5 成员 1 份报告 demo"验收标准的最小代码量:

| 模块 | 文件 | 行数估计 |
|------|------|---------|
| 部署 | `docker-compose.yml` + `.env.example` + `Makefile` | ~80 行 |
| 后端 | `backend/app/main.py` + `core/{config,db,security}.py` + `api/profile.py` + 6 个 models | ~400 行 |
| 前端 | `frontend/src/{main,App}.tsx` + `pages/Profile.tsx` + `components/MemberCard.tsx` | ~250 行 |
| 数据库 | `pg_migration_v001.sql` 已就位 | 0(复用) |
| 测试 | `backend/tests/test_profile.py` + sample 报告 fixture | ~120 行 |
| **合计** | | **~850 行** |

**目标**:Phase 1 骨架 W1 末(~2026-09-12)可 `docker compose up` 启动,`/docs` 自动生成 OpenAPI,前端 `localhost:5173` 可访问家庭档案页,5 成员 CRUD 跑通。

---

## 五、不做什么(避免范围蔓延)

- ❌ 不在本 PR 写 `/report /track /ai` 接口(留给 W2-W3)
- ❌ 不在本 PR 接飞书 OAuth(留 Phase 1.5,与域名决策联动)
- ❌ 不在本 PR 做 SSR / Next.js(本地部署,纯 SPA 够用)
- ❌ 不在本 PR 引入 CI/CD(Phase 2 商用时再上 GitHub Actions)
- ❌ 不动 `content/manifest.json` / `medical_ner.json` / `metric_baseline.json` 等 Phase 0 资产(已定稿,Phase 1 只消费)

---

## 六、关联文档

| 文档 | 关系 | 状态 |
|------|------|------|
| `content/phase1_decision_brief.md` | 上游(本文档展开) | ✅ 已 commit(0902) |
| `content/phase1_stack_research.md` | 上游(技术栈已定) | ✅ 已 commit(0901) |
| `content/pg_migration_v001.sql` / `.md` | 决策 6 落地直接依赖 | ✅ 已 commit(0831) |
| `content/medical_ner.json` | 决策 4 OCR 后处理消费 | ✅ 已 commit(0825) |
| `content/family_profile_schema.json` | ORM / Pydantic 来源 | ✅ 已 commit(0826) |
| `项目开发计划.md` 第 161 行 | 上游触发 | ✅ 已 commit |

---

## 七、变更记录

| 日期 | 变更 | 作者 |
|------|------|------|
| 2026-09-03 | 初稿:6 决策解锁清单 + 6 决策全选 A 启动顺序 + 首个 PR 范围(~850 行) | 01-健康-Health (T5 03:00) |

---

> **本清单不写代码**——它是把 `phase1_decision_brief.md` 的 6 决策脚手架"展开"为"6 决策勾选后具体写什么文件",闭合 Phase 1 文档侧"技术栈 → 决策 → 解锁"三段链路;**唯一缺失环节仍是张勇本人「勾 6 框」**,agent 不预设、不抢答。
