# superAFK — 用 GitHub Issue 追踪 superpowers 开发进度（设计 / Spec，v3）

**日期：** 2026-06-19（v3 重写）
**状态：** 第一阶段设计，待 review
**一句话：** 一个 superpowers 风格的旁挂插件——**不改 superpowers、用户照常用 superpowers**——用**一个 idea = 一个 GitHub issue** 把开发进度沉淀下来，接触面只有 3 个点。

---

## 1. 目标与分期

superAFK 不修改 superpowers，作为独立插件补一件事：**让开发进度反映到 issue 上**。核心载体是 **idea issue**：一个想法一个 issue，跨多个 session、多个 PR 持续累积，直到这个 idea 真正做完。

| 阶段 | 做什么 | 本 spec |
|---|---|---|
| **第一期（本文）** | **写侧**：开局建/绑定 idea issue、给产物文件盖 issue-id front-matter、出 PR 后链接 PR + 判断完成度 + 写 `finished` 标记或 handoff 评论 + 释放锁 | ✅ |
| 第二期（以后） | **读侧**：新 session **自动读 handoff** 接着干（issue→superpowers） | ❌ 不做 |

**方向边界**：第一期是 superpowers→issue（把进度写上去）。唯一的"读 issue"是**开局读一下锁**（判断这个 idea 是否已被别的 session 占用）——这是协调用的读，不是"读 issue 决定开发干什么"。**读 handoff 自动续工作**属于读侧，留给第二期；第一期 handoff 只写给人看，续传靠人手动开 session。

---

## 2. 背景：机制与 superpowers 同源

superpowers 只用**一个 SessionStart hook**，把 `using-superpowers` skill 作为 `additionalContext` 注入；没有任何工具监视，全靠"开局注入规则 + 模型遵循 + compact 重注入"的软性机制。

**superAFK 用完全相同的机制**：一个 SessionStart hook 注入 `superafk-guide`（规则），真正的活在被规则引导调用的 `superafk` worker skill 里。可靠性与 superpowers 同源。

---

## 3. 和 superpowers 的接触面：只有 3 个点

除以下三点，superAFK **完全不碰** superpowers 的工作流（不监视 spec/plan 写入、不追 checkbox、不管 task）：

1. **brainstorm 之前**：确定/创建 idea issue，并把本 session 绑定到它（加锁）。
2. **产物文件 front-matter**：每个 spec/plan 文件写上 `superafk-issue: <issue号>`。
3. **`finishing-a-development-branch` 出 PR 之后**：superAFK 接管——链接 PR、判断完成度、写状态/ handoff、释放锁、退出。

---

## 4. 数据模型：一个 idea = 一个 issue

**只有一种 issue 类型：`idea`。** issue 的 **GitHub 编号**就是它的身份（id）。

| 载体 | 放什么 | 为什么 |
|---|---|---|
| **issue body** | ① idea 原文（目标，brainstorm 后可更新）；② 锁标记 `<!-- superafk-active-session: <id> -->`（空=未占用） | body 存"当前可变状态" |
| **label** | `superafk` + `finished`（有=已完成，无=未完成） | 简单状态位；**finished 仍 open，由人 close** |
| **comments** | handoff（每次没做完留一条：还剩什么、下一步）；人也能写 | 评论是**append-only 历史**，且人类可写 |
| **产物文件 front-matter** | `superafk-issue: <issue号>` | 任何 spec/plan 文件能反查到所属 idea issue；身份零漂移 |

> 因为身份就是 issue 号、写在文件 front-matter 里，定位 issue 只需 `gh issue view <号>`——**没有搜索、没有分页、没有 marker 匹配、没有 slug 漂移**（旧设计里 H1/H3/H5/M2/M6 等问题随之消失）。也**不需要 sub-issue**（无层级）。

### idea issue body 模板
```markdown
# 💡 <Idea 标题>

<idea 原文 / 目标。brainstorm 后可更新成更准确的一段话。>

---
<!-- superafk-active-session: 84ab1096-7ae4-... -->   ← 锁；释放时清空
```

### handoff 评论模板（未完成时追加）
```markdown
🤖 **superAFK handoff** · <时间由 gh 自动盖>
- **本次 PR：** #123  （<url>）
- **已落地：** specs/x-design.md, plans/x.md（已出 PR）
- **还缺：** 依 idea 原文，settings 持久化这块还没 spec/plan
- **建议下一步：** 给 "persist settings" 写 spec → plan → 执行
```

### 产物文件 front-matter
```yaml
---
superafk-issue: 123
---
# （spec 或 plan 原有内容）
```

---

## 5. 组件

| 组件 | 职责 | 变化 |
|---|---|---|
| `hooks/hooks.json` | 唯一 SessionStart hook（`startup\|clear\|compact`） | 同 superpowers |
| `hooks/session-start`（+ `run-hook.cmd`） | 注入 `superafk-guide`；并把 hook 拿到的**本 session id** 一并注入 context，供锁使用 | 不调 gh |
| `skills/superafk-guide/SKILL.md` | 注入的规则：3 个触点 + 出 PR 后接管流程 | — |
| `skills/superafk/SKILL.md` | worker：建/绑定 issue、盖 front-matter、出 PR 后接管（链接 PR / 完成判断 / 写状态 / handoff / 释放锁） | — |

无本地 state 文件。GitHub issue 本身是唯一真相源。

---

## 6. 完整生命周期

```
session 开始
  │  SessionStart hook 注入 superafk-guide
  ▼
绑定 idea issue（brainstorm 之前）
  ├─ 新 idea：gh issue create（body=idea 原文，打 superafk 标，写锁=本 session）
  └─ 续做旧 idea：gh issue view <号> 读锁
        ├─ 锁空 → 写锁=本 session（占用）
        └─ 锁被别的 session 占 → 警告，避免重复开发
  ▼
照常用 superpowers：brainstorm→spec / writing-plans→plan / 执行
  └─ 每产出 spec/plan 文件，盖 front-matter: superafk-issue=<号>
  ▼
finishing-a-development-branch 选择"出 PR"
  ▼
superAFK 接管（仅在出 PR 时）：
  1. 在 idea issue 评论里链接 PR（非关闭式引用，不写 Closes，避免 merge 自动关）
  2. 完成判断：读 idea 原文（body）+ 本仓库所有 front-matter 带此 issue 号的 spec/plan
     → LLM 判断整个 idea 是否已实现
  3. 完成 → 打 finished 标记（仍 open，留给人 close）
     未完成 → 追加 handoff 评论（剩什么 + 下一步）
  4. 清空锁（active-session 置空）
  5. 退出
```

下一块工作 = 新 session，重新绑定同一 issue（人读评论里的 handoff 自己指挥），干、出 PR、再接管……直到打上 finished、由人 close。

---

## 7. 接管算法：`superafk`（出 PR 后）

```
0. 前置：gh 在？已登录？cwd 有 GitHub origin remote？任一否 → 提示一次并退出（绝不中断 superpowers）
   首次运行：幂等创建标签 gh label create superafk / finished --force
1. issue 号从 session 绑定（body 锁 / 当时建的号）取得
2. 评论链接 PR：gh issue comment <号> --body "superAFK: PR #<pr> <url>"（无 Closes 关键字）
3. 完成判断：
   - idea 原文 = gh issue view <号> 的 body
   - 相关产物 = 扫 docs/superpowers/{specs,plans} 中 front-matter superafk-issue==<号> 的文件
   - LLM 判断：这些已落地的 spec/plan 是否已覆盖 idea 原文的全部目标？
4. 完成 → gh issue edit <号> --add-label finished
   未完成 → gh issue comment <号> --body "<handoff 模板>"
5. gh issue edit <号> 清空 body 里的 active-session 锁标记
6. 退出
```

---

## 8. 错误处理与边界

| 情况 | 处理 |
|---|---|
| gh 未装 / 未登录 / 无 GitHub remote | 前置检查拦下，提示一次后静默跳过；不阻断 superpowers。hook 纯静态注入，始终正常。 |
| 标签不存在 | 首次运行 `gh label create … --force` 幂等创建（superpowers/gh 不会自动建标签）。 |
| 锁竞争 | 两个 session 同时读到锁空可能都占——窄窗口、单仓库少见；列为已知限制，第一期不加分布式锁。 |
| 完成判断误判 | 纯 LLM 软判断，可能过早 finished / 长期 unfinished。可接受（用户选择依赖 LLM）；handoff/标记都可被人覆盖修正。 |
| 非 PR 结局（直接 merge / keep / discard） | **不触发**接管（用户选择）。这些路径上 issue 不更新——记为已知覆盖缺口。 |
| 隐私：自动把 idea 原文/handoff 发到 issue | 首次在某 repo 创建 issue 前，检查 `gh repo view --json visibility` 并做一次性确认（点名目标 repo）；public repo 时显著提示。 |
| 多平台 | **仅支持 Claude Code**（§11 明示限制）；其它宿主不注入、不工作、也不报错。 |

**总原则：superAFK 出任何问题都不能让用户的 superpowers 工作流挂掉。**

---

## 9. 插件文件结构

```
superAFK/                       # 插件 repo
  .claude-plugin/plugin.json
  hooks/
    hooks.json
    run-hook.cmd
    session-start               # 注入 superafk-guide
  skills/
    superafk-guide/SKILL.md
    superafk/SKILL.md
  scripts/                      # 可选：front-matter 读写 / gh 包装（可单测）
  tests/
  README.md
```

---

## 10. 测试策略

- **可单测纯逻辑**：front-matter 读写、按 issue 号扫描相关产物、handoff/标记渲染。
- **集成测试**（一次性测试 repo + gh）：
  - 开局新 idea → 建 issue（body=原文、打 superafk 标、写锁）；
  - 产物盖 front-matter 正确；
  - 出 PR → 评论链接 PR（无 Closes）、完成判断走通、未完成追加 handoff 评论、完成打 finished 标、锁清空；
  - 续做：第二个 session 绑定同一 issue，锁被占时给出警告；
  - **降级**：无 gh/未登录时静默跳过、退出码 0、不抛错。
- **hook 测试**：session-start 输出合法 JSON、`additionalContext` 含 guide（仿 superpowers）。

---

## 11. 明确不做（第二期 / 范围外）

- **读侧自动续传**：新 session 自动读 handoff 接着开发（issue→superpowers）。第一期只写 handoff、续传靠人。
- 追踪 merge/keep/discard 三种非 PR 结局。
- spec/plan/task 级 issue、层级 sub-issue、checkbox 镜像（v3 全不做）。
- 多平台（Codex/Cursor/Gemini）。
- 分布式锁、自动 close issue（close 永远交给人）。

---

## 12. 成功标准

1. 用户照常用 superpowers；每个 idea 在 GitHub 上有**一个** issue，记录 idea 原文，并随每次出 PR 累积 PR 链接与 handoff。
2. 产物文件都带 `superafk-issue` front-matter，能反查所属 idea。
3. session 绑定锁能防止两个 session 同时做一个 idea。
4. 出 PR 后能判断 idea 完成度：完成打 `finished`（仍 open，人来 close），未完成留 handoff 评论。
5. **全程不改 superpowers**；gh 不可用时优雅降级，绝不破坏 superpowers 工作流。

---

## 13. 已知风险

- **软触发可靠性**：与 superpowers 同源——模型可能漏掉"出 PR 后接管"或"开局绑定 issue"。第一期无对账兜底；漏了靠下次或人工补。
- **完成判断是 LLM 软判断**（§8）。
- **锁竞争窄窗口**（§8）。
- **只覆盖出 PR 这一条收尾路径**（§8）。
