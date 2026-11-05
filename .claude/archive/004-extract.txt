# 记忆-VLA Demo：展现并解决 memory conflict

## Context（背景与目标）

目标：**尽快做出一个能「展现 memory conflict 并解决它」的最小 demo，并在过程中发现具体问题。** 仿真平台与对比基线都可替换，关键是「如何把 memory conflict 展现出来 + 解决」。

对 deep-research 前提的**关键修正**（已核实）：

- 官方 RoboTwin2.0 HF 仓库 `cotrain_ckpt/` **没有 Mem_0 checkpoint**（只有 Pi_05 / starVLA / X_VLA / EventVLA / GalaxeaVLA / X_WAM / AHA_WAM 等）。
- `XPolicyLab/policy/Mem_0` 适配器是**面向 RoboDojo** 的：`task_config.json` 只列 RoboDojo 任务（swap_blocks / cover_blocks / build_tower…），README/训练/评测示例全用 `bench_name=RoboDojo`、`arx_x5`。
- 因此「在 RoboTwin 的 blocks_ranking_rgb 上无训练跑 Mem_0」不可行。

已核实的现状：

- 环境 Phase 0 已完成：torch 2.7.1+cu128 / CUDA 12.8 / nvcc 12.8，`/opt/venv` 可 import torch/sapien/warp/pytorch3d/curobo。
- π0.5 基线评测已完成（`eval_result/` 有成功率 5/5=100% 与视频）。
- Mem_0 适配器完整但**未下载任何 checkpoint**（`Mem_0/checkpoints/` 不存在、Qwen3-VL-2B 未下载、无 `.pt`；整目录仅 1.1MB）。
- `blocks_ranking_rgb` 任务存在（`envs/` + `description/task_instruction/`），但不在 Mem_0 的 `task_config.json`。
- **无 conda**；Mem_0 评测链 `setup_eval_policy_server.sh` 硬编码 `conda activate`。

已确认的决策：

- 范围 = MVP + conflict 消融 + **解决**。
- 代码位置 = **fork 成新 adapter** `policy/MemConflict`（不动官方 Mem_0）。
- 平台/基线可替换，以「最快跑通 + 能展现并解决 conflict」为准。

## 推荐路径

1. **Phase 0 — 选定 substrate + 拿到 artifacts（阻塞项）**
2. **Phase 1 — fork Mem_0 → MemConflict + 打通基线**
3. **Phase 2 — 展现 conflict（MemoryBank dump + 冲突检测器）**
4. **Phase 3 — 量化 + 解决 conflict（消融开关 + 冲突解决机制 + 恢复验证）**
5. **Phase 4 — 封装收尾（README / adapter-check / 隔离）**

---

## Phase 0 — 选定 substrate 与 artifacts（阻塞项，先做）

目标：找到「**可下载的 Mem_0 checkpoint + 对应可跑任务**」，避免自己训练。

按优先级探测（用 `hf` / HF API 查）：

1. **RMBench**（README 称 "built upon RoboTwin 2.0"）：是否发布可下载的 Mem_0 checkpoint + 任务（swap_blocks / cover_blocks），且能在其 RoboTwin 2.0 底座上跑。若可，最贴合「RoboTwin 底座」。
2. **RoboDojo**（Mem_0 原生 bench）：官方 Mem_0 cotrain 权重 + 任务列表，clone 其 sim。
3. **兜底 = 在 RoboTwin 上训练 Mem_0**：`process_data.sh` 转换 `blocks_ranking_rgb` 数据 + `train.sh execution`（Qwen3-VL-2B 单卡 5090）。最慢，但在「on RoboTwin + 真 Mem_0 MemoryBank」上最稳。

判定规则：谁能**无需训练**直接跑通 Mem_0 M1，就选谁；都不行才走兜底训练。

产出：选定 substrate、execution_ckpt + norm_stats 下载源、任务名与 M1/Mn 分类。

## Phase 1 — fork + 基线打通

Fork（`cp -r`，无大 checkpoint）：

- `cp -r XPolicyLab/policy/Mem_0 XPolicyLab/policy/MemConflict`
- `MemConflict/deploy.yml`：`policy_name: MemConflict`
- vendored 上游保留原名 `MemConflict/Mem_0/`（`model.py:35` 的 `UPSTREAM_DIR = CURRENT_DIR/"Mem_0"` 无需改）
- `setup_eval_policy_server.sh` 等用 `$(basename $SCRIPT_DIR)` 自动取 policy_name，无需改
- checkpoint 用软链共享，避免重复下载

环境准备：

- 下载 Qwen3-VL-2B 骨干：`python MemConflict/Mem_0/scripts/_download.py --model 2b`（M1 只须 2B；8B 留给 Mn）
- 建 policy 环境：无 conda → 用 uv 建 mem0 等价环境（transformers + Qwen3-VL 依赖，参照 `install.sh`）
- no-conda 补丁：`setup_eval_policy_server.sh:69-70` 与 `setup_eval_env_client.sh` 链加 `command -v conda` 守卫，无 conda 时用 `/opt/venv` / uv env（沿用 init.md Phase 3 做法）

基线验收：

- 先 `EVAL_ENV_TYPE=debug` 离线接线检查（无仿真器）
- 再 sim M1 单任务评测，`eval_result/` 出视频 + 成功率

## Phase 2 — 展现 conflict（核心交付物 1）

在 MemConflict 给 MemoryBank 加**只读**探针（不改行为）：

- `dump_memory()`：读 `self.agent.executor.memory_bank.bank` → 输出 `{episode_id: {anchors:[...], window:[...]}}` 的 size/向量（`memory_bank.py:74,211`）
- 每步把 anchor/window 投影（PCA/UMAP）画时间曲线，可视化「初始状态记忆 vs 最近历史」如何分化
- **conflict_log**：每步算「window 最新向量 vs anchor 向量」余弦相似度，跌破阈值记为冲突事件（`memory_bank.py` `update_on_eval` 的 window/anchor 交叉注意力 ~667-707 处读取）

产出：可 dump、可画、可解释的记忆结构 + 冲突事件日志。

## Phase 3 — 量化 + 解决 conflict（核心交付物 2）

消融开关（沿用 Mem*0 的 `MEM0*_`env 模式，加`MEMC\__`，经 deploy.yml 新键落入 `execution_module.memory_bank`）：

- `enable_window` / `enable_anchor`（默认 true）：gate `memory_bank.py` 的 window 分支（`update_on_eval` ~667-690 + `_upd_to_window` ~710）与 anchor 分支（~692-707 + `_upd_to_anchor` ~712）
- `window_size`：滑窗长度扫描
- 新键在 `memorymatters_executor.py`（~48-53 读 memory_bank 键处）转发进 MemoryBank

量化冲突：full vs no-anchor vs no-window 多路消融，成功率差 = 各记忆组件净贡献；「移除某组件反而变好」= 冗余冲突（对应 RMBench 的 anchor 67%→15%、key 68%→5% 结论）。

解决（**研究贡献点**——deep-research 指出的空白正是「Mem_0 当前没有显式冲突消解步骤」）：

- 加 `resolution` 键（`none | reweight_window | refresh_anchor`）
- 检测到冲突（余弦相似度跌破阈值）时：
  - `reweight_window`：交叉注意力向更新的 window 重加权、抑制 stale anchor
  - `refresh_anchor`：用当前状态重编码/替换过期 anchor
- 在 conflict 任务上对比「no-resolution vs resolution」成功率，展示恢复

## Phase 4 — 封装收尾

- 写 `MemConflict/README.md`（记录新 deploy.yml 键：`enable_window`/`enable_anchor`/`window_size`/`resolution`/`dump_memory`）
- 跑 `xpolicylab-adapter-check` skill 过审（文件齐全、deploy.yml 键集、图像只用 decode_image_bit、action dim 走 `get_robot_action_dim_info`）
- 确认改动只落在 MemConflict，官方 Mem_0 不变

## 关键文件

- fork 源：`XPolicyLab/policy/Mem_0/`（model.py、deploy.yml、eval.sh、setup_eval_policy_server.sh、`Mem_0/source/...`）
- MemoryBank：`XPolicyLab/policy/MemConflict/Mem_0/source/models/execution_module/memory_bank/memory_bank.py`（class line 74；bank dict line 211；window/anchor 写入 ~436/474；eval 交叉注意力 667-707；subtask 清空逻辑 725-727）
- executor 配置转发：`.../memorymatters_executor.py`（~48-53, 76-85）
- adapter 主类：`XPolicyLab/policy/MemConflict/model.py`（`__init__` 85-169；`_handle_subtask_transition` 297-308 的 `memory_bank.reset()` line 306）
- 契约/规范：`XPolicyLab/model_template.py`、`XPolicyLab/AGENTS.md`、`XPolicyLab/.agents/skills/xpolicylab-adapter-check/`

## 风险

1. **Mem_0 checkpoint 可下载性是最大未知**（RoboDojo/RMBench 是否有公开 cotrain 权重）→ Phase 0 硬门禁；没有就走 RoboTwin 训练兜底。
2. Qwen3-VL-2B + DiT-B flow-matching 在单 32GB 5090 显存需实测（M1 应可；Mn 需 vLLM 8B 多卡，MVP 只做 M1）。
3. 无 conda：需 uv 建 policy 环境 + no-conda 守卫（与 π0.5 那次同样要打补丁）。
4. `initial_anchor_size=0` 未必等价于「关 anchor」（代码可能只加首个向量、不读该字段）→ 需在 `memory_bank.py` 显式 gate，不能只改配置。

## Verification（端到端验收）

1. Phase 0：选定的 Mem_0 checkpoint + 任务可下载/可装，M1 无训练可跑。
2. Phase 1：`EVAL_ENV_TYPE=debug` 接线检查通过；sim 单任务出视频 + 成功率。
3. Phase 2：dump JSON 含 anchors/window；conflict_log 记录真实冲突事件；可视化可见 anchor/window 分化。
4. Phase 3：消融表（full / no-anchor / no-window）成功率有差异；resolution 相对 no-resolution 恢复成功率。
5. Phase 4：`xpolicylab-adapter-check` 通过，改动仅限 MemConflict。
