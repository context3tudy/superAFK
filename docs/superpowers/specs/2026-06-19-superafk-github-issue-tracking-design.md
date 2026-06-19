# superAFK — 用 GitHub Issue 追踪 superpowers 开发进度（设计 / Spec）

**日期：** 2026-06-19
**状态：** 第一阶段设计，待 review
**一句话：** 一个 superpowers 风格的旁挂插件——**在不改动 superpowers、用户照常使用 superpowers 的前提下**，把开发进度自动镜像成 GitHub issue。

---

## 1. 目标与分期

superAFK 自己也是一堆 skill（像 obra/superpowers）。它**不修改 superpowers**，而是作为独立插件补足一件事：**用 GitHub issue 追踪开发进度**。

最终愿景是**双向**，但明确分两期，本 spec 只覆盖第一期：

| 阶段 | 方向 | issue 的角色 | 谁驱动工作 | 本 spec |
|---|---|---|---|---|
| **第一期（本文）** | superpowers → issue | **写入目标**：进度的镜子 | superpowers 驱动，issue 被动反映 | ✅ |
| 第二期（以后） | issue → superpowers | **读取来源**：决定该干啥 | issue 驱动 superpowers | ❌ 明确不做 |

**方向判定标准**：看*谁驱动工作*，不是看哪个 API 是读还是写。第一期里，sync 为了"该写哪个 issue"而 `gh issue list` 是允许的（写入侧的身份查找）；为了"接下来干什么"而读 issue 则不允许（那是第二期）。

---

## 2. 背景：superpowers 怎么运转、怎么"保证"调用

superpowers 的工作流以**文件**为载体：

- `brainstorming` → 写出 spec：`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`；可把一个 idea 拆成多个 **sub-project**，每个 sub-project 各走一遍 spec→plan→实现。
- `writing-plans` → 写出 plan：`docs/superpowers/plans/YYYY-MM-DD-<feature>.md`，内含 `### Task N` 块和 bite-sized `- [ ]` step。一个 spec 可拆成多个 plan。
- `executing-plans` / `subagent-driven-development` → 勾 checkbox、逐步 commit。
- `finishing-a-development-branch` → 收尾。

**superpowers 如何"保证"自己被调用（实测其源码）：** 它只用了**一个 hook —— SessionStart**（`hooks.json`，matcher `startup|clear|compact`），脚本把 `skills/using-superpowers/SKILL.md` 整个读出来、包进 `<EXTREMELY_IMPORTANT>` 作为 `hookSpecificOutput.additionalContext` 注入。没有 PreToolUse/PostToolUse/Stop，**完全不监视用户做了什么**。所谓"保证"是纯软性的：开局注入规则 + 强势措辞 + 各 skill 自带 announce/checklist + 模型遵循 + `compact` 时重注入。

**结论（决定我们的机制）：superAFK 采用与 superpowers 完全相同的机制**——一个 SessionStart hook，注入一个"路由器" skill。可靠性与 superpowers 同源（用户既然在用 superpowers，就说明这种软性机制对其够用）。

---

## 3. 架构

```
SessionStart hook ──注入 superafk-guide（静态规则）──▶ 模型
        │
        ▼  用户照常用 superpowers
brainstorm→spec文件 / writing-plans→plan文件 / executing→勾 checkbox+commit
        │  每到里程碑，模型照"注入的规则"主动调 superafk:sync
        ▼
superafk:sync ──读产物──▶ 调 gh：建/更新/关闭 α 树上的 issue（幂等）
```

**4 个组件**（全部在 superAFK 插件内，不碰 superpowers）：

| 组件 | 职责 |
|---|---|
| `hooks/hooks.json` | 注册**唯一**的 SessionStart hook（matcher `startup\|clear\|compact`） |
| `hooks/session-start`（+ `run-hook.cmd` 跨平台包装） | **纯静态**注入 `superafk-guide` 内容为 `additionalContext`。**不调 gh**、不读状态（形态与 superpowers 的 session-start 一致） |
| `skills/superafk-guide/SKILL.md` | 被注入的**路由规则**：映射、触发时机、纪律。指向 worker |
| `skills/superafk-sync/SKILL.md` | **worker**：读产物 → 算节点链 → 调 gh upsert/close → 维护 α 树 |

> 注：第一期的 hook 不做动态读取（不查 gh、不注入"续传指针"、不做对账）——那些都是第二期（issue→superpowers）。因此 hook 没有 gh 依赖。

---

## 4. 数据模型：α 全树

superpowers 产物是一棵多层树，基数如下：

```
Idea
└── 1..N  Sub-project
    └── 1..N  Spec
        └── 1..N  Plan        ◀── issue 最小粒度（对齐 executing-plans）
            └── 1..N  Task     ◀── 进 Plan-issue body 的 - [ ] 清单
                └── 1..N  Step  ◀── 不单独追踪，只留"下一步"指针
```

- **issue 最小粒度 = Plan**（因为 superpowers 里最小的"可独立执行/验证单元"是 executing-plans 执行的 plan）。Task/Step 不开 issue。
- **α 全树**：Idea / Sub-project / Spec / Plan **每层都开 issue**，用**原生 sub-issue** 连父子。
- **层级用 label 区分**：`superafk:idea` / `superafk:subproject` / `superafk:spec` / `superafk:plan`。
- **进度用 open/closed 表达**：open=进行中、closed=完成（不另加 status label，YAGNI）。
- issue **types**（org 级功能）若可用可顺带加，但**不依赖**；个人 repo 仅靠 label。
- 未被拆解的简单 idea 仍走完整 4 层直链（1:1:1:1），遵循 α。

### 端到端示例（"加 dark mode"）

```
#101 💡 Idea: 加 dark mode            [superafk:idea]            open
└─ #102 📦 Sub-project: UI theming    [superafk:subproject]     open
   └─ #103 📄 Spec: dark-mode         [superafk:spec]           open
      └─ #104 🔧 Plan: dark-mode      [superafk:plan]           open
            body: Task 1..4 的 - [ ] + 续传状态块
```

---

## 5. 四层 issue body 模板

每个模板**末尾埋一行 marker**（机器锚点，即"身份"，见 §6）。

**Idea**（`superafk:idea`，epic 顶层）
```markdown
# 💡 <Idea 标题>
<想法的一段话目标，来自 brainstorming>

**进度：** 1/3 sub-project 完成

## Sub-projects
- [x] #102 <sub-project A>
- [ ] #108 <sub-project B>

<!-- superafk v1 key=idea:add-dark-mode parent= -->
```

**Sub-project**（`superafk:subproject`，sub-issue of Idea）
```markdown
# 📦 <Sub-project 标题>
<这块独立范围，来自拆解>

**所属 Idea：** #101 · **进度：** 1/2 spec 完成

## Specs
- [ ] #103 <spec X>

<!-- superafk v1 key=subproject:add-dark-mode/ui-theming parent=idea:add-dark-mode -->
```

**Spec**（`superafk:spec`，sub-issue of Sub-project）
```markdown
# 📄 Spec：<topic>
**文件：** `docs/superpowers/specs/2026-06-19-dark-mode-design.md`
**所属 Sub-project：** #102 · **进度：** 1/2 plan 完成

<spec 摘要：架构 2–3 行>

## Plans
- [ ] #104 <plan 1>

<!-- superafk v1 key=spec:docs/superpowers/specs/2026-06-19-dark-mode-design.md parent=subproject:add-dark-mode/ui-theming -->
```

**Plan**（`superafk:plan`，sub-issue of Spec）◀ 续传锚点，最 richest
```markdown
# 🔧 Plan：<feature>
**Spec：** #103 · **分支：** `feat/dark-mode`
**Plan 文件：** `docs/superpowers/plans/2026-06-19-dark-mode.md`

### 续传状态  （写入侧；第二期续传用，第一期只写不读回）
- **当前 task：** Task 3 — 持久化偏好
- **最后 commit：** `a1b2c3d feat: toggle 组件`
- **下一步：** Task 3 / Step 1 — 写持久化的失败测试

### Tasks
- [x] Task 1：theme tokens
- [x] Task 2：toggle 组件
- [ ] Task 3：持久化偏好
- [ ] Task 4：e2e 测试

<!-- superafk v1 key=plan:docs/superpowers/plans/2026-06-19-dark-mode.md parent=spec:docs/superpowers/specs/2026-06-19-dark-mode-design.md -->
```

---

## 6. 身份与幂等：无本地状态，靠 gh 现查

**不使用本地 state.json。** GitHub 是唯一真相源（没有本地缓存会和现实 drift，也没有"没提交就丢"的问题）。

身份存在 issue 自己 body 里的 marker 行：
```
<!-- superafk v1 key=<key> parent=<parent-key> -->
```

**key 取法**（确定性，可重算）：
- `idea:<slug>`、`subproject:<idea-slug>/<slug>`、`spec:<spec文件路径>`、`plan:<plan文件路径>`
- spec/plan 的 key 用**文件路径**（稳定）；idea/subproject 用**slug**（首次创建时定，之后复用 marker 里的，不重新派生）。

**find_issue(R, level, key)：**
1. 先查"运行内记忆"（同一次 sync 刚建的，避免索引延迟）。
2. 否则 `gh issue list --repo R --label superafk:<level> --state all --json number,body`，在结果里**客户端精确子串匹配** `key=<key>`（不用 GitHub 全文搜索，避开路径里 `/ :` 被分词的坑）。

**幂等**由此达成：sync 是 upsert——找到就 edit，没找到才 create，绝不重复建。

**变更检测**：find 时已把 body 拉下来，直接和产物现状比（checkbox/commit），不一样才 edit。

---

## 7. 同步触发规则（superafk-guide 注入的内容）

guide 注入三件事：

**(1) 映射**：产物 → α 树（§4）。

**(2) 触发时机**（何时调 `superafk:sync`，都在主 session 干活的自然节点）：

| 触发 | 时机 | sync 做什么 |
|---|---|---|
| **T1 spec 写好/改动** | brainstorming 产出 `specs/*-design.md` | 建/更新 Spec issue + 惰性补祖先 |
| **T2 plan 写好** | writing-plans 产出 `plans/*.md` | 建 Plan issue + 祖先，镜像 Task 清单（全未勾） |
| **T3 一个 Task 完成** | 执行中某 Task 全部 step done 且 commit | 勾该 task、刷新续传状态 |
| **T4 plan 全部 Task 完成** | plan 收尾 | 关 Plan issue，向上级联 roll up |

**(3) 纪律**：
- **同步是主 session 的活**——subagent 是独立 context、不会被注入 guide，所以 task 完成后由**主 session** 在编排回合调 sync，不指望 subagent 自己调。
- **单向**——只往 issue 写，绝不读 issue 决定接下来干啥。
- brainstorming 把 idea 拆成 sub-projects 时，**记住 idea 标题 + sub-project 列表**，供 sync 建祖先用。
- **优雅降级**——gh 不可用/未登录/无 GitHub remote 时，**只提示一次**然后静默跳过，**绝不阻断** superpowers 正常工作流。

---

## 8. 同步算法：`superafk:sync(target)`

```
target = 一个 spec文件 / plan文件 / "task完成" / "plan完成"

0. 前置检查：gh 在？已登录？cwd 有 GitHub origin remote？
   任一否 → 提示一次并 return（绝不报错中断开发）

1. R = cwd 的 origin remote（gh repo view）

2. 自顶向下排出 target 的节点链：idea → subproject → spec → plan
   （各节点算 key + title；idea/subproject 的 title 来自 brainstorming 拆解记忆）

3. 惰性建祖先：从 idea 往下逐级
   num = find_issue(R, level, key)
   if 没有:
       num = gh issue create --label superafk:<level> --body <模板+marker>
       if 有 parent: gh api graphql addSubIssue(parent_num, num)
   run_memory[key] = num

4. 更新 target 节点 body 到当前态：
   - 拉现 body，与产物比，不同才 gh issue edit
   - spec/plan：刷新子清单(Plans/Tasks)、进度计数、（plan 还有）续传状态块

5. target = "task 完成"：勾该 task，更新续传状态（当前 task→下一步、最后 commit）

6. target = "plan 完成"：
   gh issue close <plan>
   级联 roll up：
     父 spec：重算 plans done/total，刷新 body；全完 → close
     再上：subproject（specs 完）、idea（subprojects 完），各自全完则 close
```

---

## 9. 错误处理与边界

| 情况 | 处理 |
|---|---|
| **gh 未安装 / 未登录 / 无 GitHub remote** | sync 前置检查拦下，**提示一次**后静默跳过；不阻断 superpowers。hook 本身不依赖 gh（纯静态注入），始终正常。 |
| **单次 sync 失败（网络/gh 报错）** | 不崩开发流；简短提示。因 upsert 幂等，**下一次触发该产物时自然重试补上**（自愈，无需第二期的对账）。 |
| **slug 漂移**（idea/subproject 标题改了 → key 变 → 可能孤立旧 issue） | spec/plan 用文件路径 key，稳定；idea/subproject 的 slug 首建即定、之后复用 marker 里的、不重新派生。残余风险记为已知，完整健壮性留第二期。 |
| **原生 sub-issue 不可用**（gh/API 限制） | 降级：body 里写父引用 + 清单替代原生父子；写 plan 前先验证 `gh api graphql addSubIssue` 可用性。 |
| **issue types 不可用**（个人 repo） | 仅用 label，已是默认。 |
| **索引延迟**（刚建的 issue 查不到） | 同一次 sync 内用 run_memory 拿号，跨运行才靠 list。 |
| **同一 session 重复触发** | upsert 幂等，最多多一次 edit，不产重复 issue。 |

**总原则：superAFK 出任何问题都不能让用户的 superpowers 工作流挂掉。**

---

## 10. 插件文件结构（供 writing-plans 用）

```
superAFK/
  .claude-plugin/
    plugin.json
  hooks/
    hooks.json
    run-hook.cmd          # 跨平台包装（可借鉴 superpowers）
    session-start         # 注入 superafk-guide
  skills/
    superafk-guide/SKILL.md
    superafk-sync/SKILL.md
  scripts/                # 可选：key 派生 / marker 解析 / gh 包装（可单测）
  tests/
  README.md
```

---

## 11. 测试策略

遵循 superpowers 的 TDD 文化：

- **可单测的纯逻辑**（若抽到 `scripts/` 助手）：key 派生、marker 解析/渲染、节点链推导、body diff 判定。
- **集成测试**：用一个一次性测试 GitHub repo + `gh`，对 fixture spec/plan 文件跑 sync，断言：
  - T1/T2 正确建出带 label、连好 sub-issue 的树；
  - **幂等**：连跑两次 sync 不产生重复 issue；
  - T3 勾对 task、续传状态更新；
  - T4 关闭 plan 并**级联** roll up 关祖先；
  - **降级**：无 gh / 未登录时 sync 静默跳过、退出码 0、不抛错。
- **hook 测试**：session-start 输出合法 JSON、`additionalContext` 含 guide 内容（仿 superpowers 的 hook 测试）。

---

## 12. 明确不做（第二期范围）

- 续传：新 session 读 issue 接着开发（issue→superpowers）。
- SessionStart 动态读 gh、注入"续传指针"。
- 对账 / drift 修复。
- issue 驱动工作、从 issue 排队取任务。
- 文件 front-matter 回链、state.json 丢失恢复等健壮性。

第一期对"续传"的**唯一**义务：把 Plan-issue 的状态**写够**（续传状态块），让第二期能据此续传。只写，不读回。

---

## 13. 成功标准

1. 用户照常用 superpowers 开发，GitHub 上**自动**长出一棵准确的 α issue 树（Idea→Sub-project→Spec→Plan，sub-issue 连好、label 正确）。
2. 重复同步**幂等**，无重复 issue。
3. Task 进度、plan 完成、级联关闭都正确反映。
4. Plan-issue 带"够续传"的状态块（为第二期铺路）。
5. **全程不修改 superpowers**；gh 不可用时**优雅降级**，绝不破坏 superpowers 工作流。

---

## 14. 已知风险 / 开放问题

- **软触发可靠性**：与 superpowers 同源的软性机制——模型可能漏触发某次 sync。第一期无对账兜底（那是第二期）；靠 upsert 在下次触发时自愈。
- **`gh api graphql addSubIssue` 可用性**：α 全树依赖程序化连 sub-issue，写 plan 时须先验证，备降级方案（§9）。
- **slug 漂移**（§9）。
