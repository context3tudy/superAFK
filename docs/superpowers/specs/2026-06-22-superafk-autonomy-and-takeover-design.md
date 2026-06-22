# superAFK v4 — 自主性档位 + 结局无关接管（设计 / Spec 增量）

**日期：** 2026-06-22
**状态：** 设计，待 review
**基线：** 在 v3（`docs/superpowers/specs/2026-06-19-superafk-github-issue-tracking-design.md`）之上做增量；本文只写**变了什么**，未提及的部分一律沿用 v3。
**一句话：** 给 idea issue 加一个**自主性档位**（用户预授权后，design 批准就全自动跑到出 PR），并把 **takeover 从"只在出 PR 时"改成"finishing-a-development-branch 一结束就接管，结局无关，且未完成一律留 handoff"**。

---

## 1. 改了什么（相对 v3 的 delta 总览）

| 项 | v3 | v4（本文） |
|---|---|---|
| **takeover 触发** | 仅"用户在 finishing 里选了出 PR"时 | finishing-a-development-branch **一结束就触发，结局无关**（PR / merge / keep / discard / 其它） |
| **非 PR 结局** | 不触发，记为"已知覆盖缺口" | 全覆盖：discard/keep 强制按"未完成"留 handoff；merge/PR 走完成度判断 |
| **handoff** | 仅"未完成"时写 | **未完成一律写**（任何结局），完成则打 `finished` |
| **自主性** | 无；每个人工 gate 都靠人 | 新增两档 `manual` / `auto-after-design`，用 `superafk-auto` label 表达 |
| **读侧** | 第一期严格"写侧 only / 绝不读 issue 决定行为" | **有意拉前一小块读侧**：读 `superafk-auto` label 决定本 session 的自主程度（§8 明示越界） |
| **续传** | 靠人手动开新 session | 不变：**本阶段仍不自动开新 session 续**；handoff 只写给下一个（人开的）session |

---

## 2. A+B 自主性模型

自主性由两件事合成，各补对方短板：

- **B｜权威来源（descriptor）：** 自主级别由**用户开局 opt-in 声明**（绑 issue 时 或 design 批准那一刻，用自然语言说"自动跑"）。因为指令源自用户，它天然是最高优先级，**合法盖过 superpowers 自己的人工 gate** —— 不是 superAFK 擅自跟 superpowers 打架。默认是 `manual`，不声明就不开。
- **A｜执行与续航（driver）：** superAFK 把级别**写成 `superafk-auto` label 存到 issue**（持久化），并在每个 gate 到来时**注入"按已声明级别放行"的指令**真正推动模型；续 session 绑定同一 issue 时**读这个 label**，无需用户重述即按 auto 跑。

> **一句话定位变化：** v3 的 superAFK 是"只读锁、只写进度的旁挂镜子"；v4 在用户预授权的范围内，额外成为"推 superpowers 自动跑完单轮"的驱动器。权威始终回溯到用户的 opt-in。

---

## 3. 数据模型变更：新增 `superafk-auto` label

v3 的载体（issue body / `superafk`+`finished` label / comments / 文件 front-matter）全部不变，**仅新增一个 label**：

| label | 含义 | 取态 |
|---|---|---|
| `superafk-auto` | 本 idea 已被用户预授权"design 批准后自动跑到出 PR" | **有 = auto-after-design；无 = manual** |

- 命名跟现有扁平风格（`superafk` / `finished`）一致，无命名空间冒号。
- 自主性只有"有/无"两态，无中间档（逐 gate 开关属 v3 讨论里否掉的形状③，不做）。
- `ensure-labels` 幂等创建时一并建好 `superafk-auto`。

---

## 4. 自主性档位与 gate 映射

superpowers 沿工作流的人工 gate（按顺序）：

| # | gate | 在哪 | `manual` | `auto-after-design` |
|---|---|---|---|---|
| 1 | **design doc 批准**（HARD-GATE） | brainstorming 结束 | 人批准 | **仍由人批准**（自主性的起点，永不自动跳） |
| 2 | plan 成文 / 过目 | writing-plans | 人过目 | 自动放行 |
| 3 | 每个 task 的 review checkpoint | executing-plans | 人确认 | 自动放行 |
| 4 | code review | requesting / receiving-code-review | 人签字 | **照跑** review，自动处理 findings，**不停下等签字** |
| 5 | 选 merge / PR / keep / discard | finishing-a-development-branch | 人选 | **自动选"出 PR"** |
| — | takeover | finishing 结束后 | 触发（§6） | 触发（§6） |

- `auto-after-design` 的自动范围 = **gate 2–5**；gate 1 永远留人。
- 收尾天花板 = **出 PR**；**merge 仍由人在 PR 上点**（保留最后一道人工兜底，与 v3"绝不自动 close、人来收"哲学一致）。
- 自动只在**单轮 design→PR 之内**；轮与轮之间停下等人（人 merge 该 PR 后再开新 session 续）。

---

## 5. 驱动机制：不改 superpowers，怎么让模型放行 gate

superpowers 的人工 gate 写在它自己的 skill 里（如 brainstorming 的 `HARD-GATE`、finishing 把选项摆给用户）。superAFK **不改** superpowers，靠两步把"放行"注入上下文：

1. **guide 注入条款**（SessionStart additionalContext，`superafk-guide`）新增：
   > 若绑定的 idea issue 带 `superafk-auto`，**用户已预授权自主执行**：design doc 批准后，自动连跑 writing-plans → 执行 → code-review → finishing-a-development-branch，中途**不停下征求批准**；finishing **自动选"出 PR"**；随后跑接管。任何时候用户可打断（Esc）。

2. **worker 在 Touchpoint 1 把级别带进上下文**：绑定后读 issue 的 label，若有 `superafk-auto`，明确把"本 idea autonomy = auto"声明进对话；若用户此刻才 opt-in，则打上 label。

> **为什么能盖过 superpowers 的 gate：** 优先级是「用户显式指令 > superpowers skill > 系统默认」。`superafk-auto` 的值**源自用户的 opt-in**，故模型把它当作一条**用户的常驻指令**来执行，合法优先于 superpowers 的"问用户"默认。superAFK 只是这条用户决定的持久化容器 + 执行臂。

---

## 6. 接管变更：结局无关 + 永远 handoff

**触发：** finishing-a-development-branch **一结束就接管，结局无关**（不再绑"出 PR"）。算法：

```
0. 前置降级门（gh 在？已登录？有 GitHub origin？）+ ensure-labels（含 superafk-auto），同 v3
1. issue 号从 session 绑定取得
2. 链接结局到 issue（comment，溯源；永不用 closing keyword、永不 gh issue close）：
     PR      → "superAFK: PR #<n> — <url>"
     merge   → "superAFK: 已直接合并 <sha>"
     keep    → "superAFK: 分支 <name> 保留未合"
     discard → "superAFK: 本次分支已弃 (discard)"
3. 完成度判断：
     discard / keep → 跳过判断，强制按「未完成」
     merge / PR     → 读 idea body + 扫 front-matter==<号> 的 spec/plan
                      → LLM 判断这些已落地产物是否覆盖整个 idea
4. 分支：
     完成   → add-finished（打 finished 标；PR 已在步骤 2 链上；仍 open，人来 close）
     未完成 → 追加 handoff comment（已落地 / 还缺 vs idea / 下一步；文案随结局，
              discard 注明"本次尝试已弃、idea 仍开放"，keep 注明分支名）
5. 释放锁（清空 body 里 active-session）
6. 退出。**本阶段不自动开新 session 续**；handoff 只写给下一个（人开的）session。
```

> auto 模式下 finishing 一律出 PR，故 auto 走的恒是「PR → 判断 → finished 或 handoff」这一支；discard/keep/merge 三支只可能出现在 manual 模式（人手选）。两种模式最终都收敛到「接管 →（finished | handoff）→ 放锁 → 停」。

---

## 7. 文案变更（guide + worker）

- **`superafk-guide`：**
  - Touchpoint 3 触发词：「`finishing-a-development-branch` **结束后（任何结局）**」取代「出 PR 后」。
  - 新增 §5 的自主性条款。
- **`skills/superafk`（worker）：**
  - `ensure-labels` 增建 `superafk-auto`。
  - Touchpoint 1：绑定后读 label / 处理 opt-in，声明本 idea autonomy。
  - Touchpoint 3：重写为 §6 算法（结局无关、永远 handoff-or-finished）。
  - 其 front-matter `description` 触发词同步：「…just after finishing-a-development-branch **concludes (any outcome)**」。
- **新增 `gh.sh` 帮手（实现提示，非硬约束）：** `add-auto <n>`（打 `superafk-auto`）、读 label 判断是否 auto（`gh issue view <n> --json labels`）。

---

## 8. 边界声明：有意拉前的一小块读侧

v3 第一期原则是「**写侧 only / 绝不读 issue 决定开发干什么**」，唯一的读是开局读锁（协调用）。v4 **有意越过这条边界一小步**：

- 新增的读 = **读 `superafk-auto` label 决定本 session 的自主程度**。这是「读 issue 决定行为」，属读侧。
- 但范围被刻意收窄：**只读一个布尔 label**，不读 handoff 内容、不据 issue 内容决定"建什么"。完整的"读 handoff 自动续传"仍属第二期，**不做**（§本文 §10）。
- 记为**有意决策**，非疏漏：用户明确要这个自主性，代价是这一小块读侧。

---

## 9. 错误处理 delta（其余沿用 v3 §8）

| 情况 | 处理 |
|---|---|
| `superafk-auto` 标不存在 | `ensure-labels` 幂等补建。 |
| auto 模式下某 gate 模型仍停下问人 | 软触发可靠性问题（同 superpowers 同源风险）；不致命，用户可口头再放行。不加强制兜底。 |
| auto 误把未做完的活推到出 PR | 接管的完成度判断会判"未完成"→ 留 handoff；PR 仍待人 merge，人可在 PR 上拦。 |
| 非 PR 结局（discard/keep/merge） | 已全覆盖（§6），不再是 v3 的"已知缺口"。 |

> **安全闸：本设计不额外加。** auto 仍是交互式，用户可随时 Esc 打断 —— 这已是兜底，不再单列机制（讨论中明确去掉）。

---

## 10. 明确不做（沿用 v3 §11，外加）

- **读 handoff 自动续传 / 自动开新 session**：仍是第二期。v4 只读一个 `superafk-auto` 布尔，不读 handoff 内容续工作。
- **逐 gate 独立开关**（形状③）、中间档：不做，自主性只有有/无两态。
- **auto 模式自动 merge / 跨多 PR 一路到底**（形状②）：不做，天花板恒为"出 PR、人 merge"。

---

## 11. 成功标准 delta（其余沿用 v3 §12）

1. 用户在绑 idea 时可 opt-in 自主性；issue 据此带/不带 `superafk-auto`，续 session 读它即按 auto 跑，无需重述。
2. `auto-after-design` 下，design 批准后到出 PR 全程不再停下问人；finishing 自动选出 PR；merge 仍留人。
3. **takeover 对 finishing 的任何结局都触发**：完成 → 链 PR + `finished`；未完成 → 一律 handoff（含 discard/keep）。
4. 全程不改 superpowers；自主性靠"用户 opt-in → label → 注入"实现，权威回溯到用户。
5. 越过第一期写侧边界的部分仅限"读一个 label"，已在 §8 明示。

---

## 12. 已知风险 delta（其余沿用 v3 §13）

- **自主性靠软注入推动**：与 superpowers 同源的软触发可靠性 —— 模型可能在某 gate 仍停下，或漏读 label。无强制兜底，靠用户当场补。
- **auto 放大了完成判断误判的影响**：没人逐 gate 把关时，错误更容易一路滑到出 PR；唯一的人工兜底是"人 merge PR"。用户已接受（选了形状① / 去掉额外安全闸）。
- **读侧边界已被有意打开一小口**（§8）：第二期完整读侧若做，需以此为起点谨慎扩展。
