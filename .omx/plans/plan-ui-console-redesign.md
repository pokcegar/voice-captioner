# RALPLAN — VoiceCaptioner 中控台式 UI 与用户编辑 Markdown

日期：2026-05-15  
模式：`$ralplan` consensus short mode  
输入：用户 deep-interview 结论 + 当前代码核对  
相关文档：
- `.omx/specs/deep-interview-ui-console-redesign.md`
- `.omx/plans/prd-ui-console-redesign.md`
- `.omx/plans/test-spec-ui-console-redesign.md`

## 0. 当前事实与证据

- 当前详情区是单列 `ScrollView` + `VStack`，依次堆叠 header、capture settings、model settings、controls、capability、preview、meeting details（`Sources/VoiceCaptionerApp/ContentView.swift:16-35`）。
- 左侧历史列表已存在，可保留（`ContentView.swift:44-64`）。
- UI 语言 picker 当前放在 `captureSettings` 内，标签为通用 `language`，容易被误认为会议语言（`ContentView.swift:75-92`；文案 key 在 `Sources/VoiceCaptionerAppModel/Localization.swift:34-50`）。
- 延迟实时/最终片段预览已由 `rollingPreview` 驱动（`ContentView.swift:233-255`；`VoiceCaptionerAppModel.swift:142`、`:403-418`、`:456-459`）。
- 最终导出 artifact 当前只有 `final.md/final.srt/final.json`（`VoiceCaptionerAppModel.swift:490-502`）。
- 本地 Whisper 转写 workflow 已统一通过本地 executable/model，未引入云端（`VoiceCaptionerAppModel.swift:428-459`）。
- AppModel tests 已覆盖模型选择、中文默认、延迟实时草稿、最终导出等现有能力（`Tests/VoiceCaptionerAppModelTests/VoiceCaptionerAppModelTests.swift:62-180`）。

## 1. RALPLAN-DR Summary

### Principles

1. **任务优先**：当前会议操作与内容必须在中心，设置退到右侧。
2. **概念不混淆**：界面语言与转写语言必须用不同标签和区域表达。
3. **原文可追溯**：机器生成 `final.md` 不被用户编辑覆盖。
4. **本地优先诚实表达**：继续强调本地处理；实时能力称为“延迟实时草稿”。
5. **轻量增量**：不引入富编辑器、新依赖或大型架构层。

### Decision Drivers

1. **降低用户认知负担**：从“功能堆叠”改为按会议工作流布局。
2. **防止数据覆盖/误解**：Markdown 编辑必须保留机器原文，语言设置必须语义明确。
3. **可快速安全交付**：基于现有 SwiftUI/AppModel/MeetingFolder 结构，小步重构并由测试锁住。

### Viable Options

#### Option A — 三栏中控台（推荐）

**做法**：保留左侧历史，detail 内构建中间主工作区 + 右侧设置检查器；新增 edited Markdown state。  
**优点**：完全贴合用户提出的“左历史 / 中字幕与状态 / 右设置”；最能降低混乱。  
**缺点**：`ContentView.swift` 重构幅度较大，需要拆分私有 views 避免文件膨胀。

#### Option B — Tab/Segment 分页

**做法**：保持现有 detail 宽度，将“录音 / 转写 / 设置 / 导出”拆成 tabs。  
**优点**：代码改动较小，SwiftUI 实现稳定。  
**缺点**：会议中需要切 tab；不符合用户“中控台一样”的布局目标，历史/设置/字幕不能同时可见。

#### Option C — 保持单列但折叠设置

**做法**：现有单列中把设置折叠，优先展示录音与字幕。  
**优点**：最快。  
**缺点**：本质仍是功能堆叠，不能解决入口混杂的核心问题。

**选择**：Option A。

## 2. ADR

### Decision

采用三栏中控台 UI：左侧保留历史列表，中间为当前会议主工作区，右侧为设置检查器；新增 `transcript/edited.md` 作为用户编辑 Markdown，不覆盖 `transcript/final.md`。

### Drivers

- 用户明确要求降低混乱，偏好中控台结构。
- 当前语言 picker 已造成“界面语言 vs 会议语言”的误解。
- 用户后续会把 Markdown 丢给其他软件处理，因此需要可编辑文本，但不需要重型编辑器。

### Alternatives considered

- Tab 分页：降低同时可见性，不符合“中控台”心智。
- 单列折叠：不能从结构上分离设置和使用。
- 富 Markdown 编辑器：超出 v1，增加依赖与维护成本。

### Why chosen

三栏中控台直接对齐用户提出的信息架构，且可在现有 `NavigationSplitView` 基础上增量实现。`edited.md` 是最小的数据模型扩展，满足“用户改的 md 单独保存，原版不动”。

### Consequences

- `ContentView.swift` 会有较大结构调整，建议拆出若干私有子 view 或小文件。
- AppModel 需要新增编辑文本状态和文件读写方法。
- 本地化 key 会增加；需保证中/英/德三语编译完整。
- 第一版不提供会议语言选择；未来新增时需避免与 UI 语言再次混淆。

### Follow-ups

- 若用户后续需要多会议语言，新增“会议语言/转写语言”设置组，并修改 Whisper configuration，不与 UI language 共用状态。
- 若编辑需求变重，再评估 Markdown preview/格式化/版本比较；当前只做纯文本编辑。

## 3. 实施计划

### Step 1 — AppModel 增加用户编辑 Markdown 状态

文件：`Sources/VoiceCaptionerAppModel/VoiceCaptionerAppModel.swift`

新增状态建议：

- `@Published public var editableMarkdownText: String`
- `@Published public private(set) var editableMarkdownSource: EditableMarkdownSource`
- `@Published public private(set) var editableMarkdownMeetingID: String?`
- `@Published public private(set) var isEditableMarkdownDirty: Bool`
- `@Published public private(set) var editableMarkdownStatus: String?` 或复用 status message

新增 API 建议：

- `public static let editedMarkdownFilename = "edited.md"`
- `public func editedMarkdownURL(for meeting: MeetingFolder) -> URL`
- `public func finalMarkdownURL(for meeting: MeetingFolder) -> URL`
- `public func selectMeeting(id: String?)`：替代外部直接写 `selectedMeetingID`，由 AppModel 独占选择切换副作用。
- `public func loadEditableMarkdown(for meeting: MeetingFolder?)`
- `public func updateEditableMarkdownText(_ text: String)`：设置 dirty flag。
- `public func saveEditableMarkdown()`
- `public func autosaveEditableMarkdownIfDirty()`
- `public var canSaveEditableMarkdown: Bool`

强制状态契约：

- AppModel 是 editable Markdown session 的唯一 owner；UI 不使用临时 editor state，也不通过 `.onChange` 自行读写文件。
- `selectedMeetingID` 应改为 `public private(set)`，List selection 使用自定义 `Binding(get:set:)` 调用 `selectMeeting(id:)`。
- 切换会议、刷新历史导致 selection 变化、转写完成重新加载前，必须先对 `editableMarkdownMeetingID` 对应会议执行 dirty autosave。
- 未保存内容策略采用 **自动保存**：只要用户修改过编辑器，离开会议或 reload 前写入该会议 `transcript/edited.md`；避免弹窗打断会议工作流。
- 保存必须绑定 `editableMarkdownMeetingID`，不能按当前 selection 盲写；防止 A 会议文本在 selection race 下写进 B 会议。
- 加载顺序：`edited.md` > `final.md` > empty placeholder。
- 保存只写 `edited.md`，并创建 transcript directory。
- `transcribeSelectedMeeting()` 成功后重新加载编辑内容：若已有/刚 autosave 的 `edited.md`，继续保留；若没有，则加载新 `final.md`。
- 文件读取失败时不崩溃，编辑器显示空/保留当前文本并通过 status 暴露错误；测试需覆盖。

### Step 2 — 导出 artifact 扩展

文件：`Sources/VoiceCaptionerAppModel/VoiceCaptionerAppModel.swift`

- 将 `exportArtifacts(for:)` 从 3 个扩展为 4 个：
  - Machine Markdown / 机器 Markdown：`final.md`
  - SRT：`final.srt`
  - JSON：`final.json`
  - Edited Markdown / 用户编辑版 Markdown：`edited.md`
- label 用本地化在 UI 层生成更好；若当前 model artifact label 是静态英文，可先用稳定 label，再在 UI button 外层本地化。

### Step 3 — 重构 ContentView 为三栏中控台

文件：`Sources/VoiceCaptionerApp/ContentView.swift`

建议结构：

```swift
NavigationSplitView {
  meetingList
} detail: {
  consoleLayout
}

private var consoleLayout: some View {
  HStack(spacing: 0) {
    meetingWorkspace
      .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
    Divider()
    settingsInspector
      .frame(width: viewModel.isRecording ? 280 : 340)
  }
}
```

必须拆分布局组件，避免继续扩大单个 `ContentView.swift`：

- `Sources/VoiceCaptionerApp/MeetingWorkspaceView.swift`：中心工作区容器。
- `Sources/VoiceCaptionerApp/SettingsInspectorView.swift`：右侧设置检查器。
- `Sources/VoiceCaptionerApp/MarkdownEditorPanel.swift`：纯文本 Markdown 编辑/保存/来源状态。
- `Sources/VoiceCaptionerApp/TranscriptSegmentsView.swift` 或私有子 view：延迟实时/最终片段列表。

中间 `MeetingWorkspaceView` 拆为：

- `workspaceHeader`：标题、状态、只读转写语言中文。
- `primaryControls`：开始/停止/转写/取消。
- `captionPanel`：延迟实时字幕/最终片段，复用 `rollingPreview`。
- `markdownEditorPanel`：通过 AppModel binding/update 方法驱动 `TextEditor` + 保存按钮 + 来源说明。
- `meetingArtifactsPanel`：打开文件夹/打开导出。

右侧 `SettingsInspectorView` 拆为：

- `commonSettingsSection`
- `localWhisperSection`
- `liveDraftSettingsSection`
- `appSettingsSection`
- `diagnosticsDisclosureSection`

录音中处理：

- 中间字幕 panel 提升高度/字体。
- 右侧高级诊断默认折叠，整体可降低 opacity 或禁用不应在录音中修改的项。

### Step 4 — 本地化 key 调整

文件：`Sources/VoiceCaptionerAppModel/Localization.swift`

新增 key 建议：

- `interfaceLanguage`
- `transcriptionLanguage`
- `fixedChineseTranscriptionLanguage`
- `currentMeetingWorkspace`
- `settingsInspector`
- `commonSettings`
- `appSettings`
- `liveDraftSettings`
- `advancedDiagnostics`
- `machineMarkdown`
- `editedMarkdown`
- `markdownEditor`
- `saveEditedMarkdown`
- `markdownSourceFinal`
- `markdownSourceEdited`
- `markdownWaitingForTranscript`

修改原则：

- 避免 UI 上裸露“语言”；中文应优先显示“界面语言”或“转写语言：中文”。
- 英文/德文必须补齐，避免 switch 编译失败。

### Step 5 — 测试补齐

文件：`Tests/VoiceCaptionerAppModelTests/VoiceCaptionerAppModelTests.swift`

按 `.omx/plans/test-spec-ui-console-redesign.md` 添加 tests：

- `final.md` 初始化编辑器。
- 保存写 `edited.md` 且不改 `final.md`。
- `edited.md` 优先加载。
- artifacts 包含 edited Markdown。
- 重新转写不覆盖 edited Markdown。
- 关键本地化文案存在。

### Step 6 — 构建、测试、打包、手动检查

执行：

```bash
swift format --in-place Sources/VoiceCaptionerApp/ContentView.swift Sources/VoiceCaptionerAppModel/VoiceCaptionerAppModel.swift Sources/VoiceCaptionerAppModel/Localization.swift Tests/VoiceCaptionerAppModelTests/VoiceCaptionerAppModelTests.swift || true
swift test
swift build
./scripts/package-local-app.sh
```

如果 `swift format` 不存在，跳过并保持现有风格。打包使用仓库实际脚本 `scripts/package-local-app.sh`。

## 4. 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| `ContentView.swift` 变得过大 | 后续维护困难 | 优先拆私有 computed views；必要时新增小型 SwiftUI view 文件，但不引入新架构层 |
| selection 变化未加载正确 Markdown | 用户看到旧会议文本 | `selectMeeting(id:)` 由 AppModel 统一 autosave + load；测试覆盖 A→B 切换 |
| 未保存编辑在切换会议/刷新/转写完成时丢失 | 数据丢失 | dirty autosave 到 `editableMarkdownMeetingID` 对应会议的 `edited.md` |
| 保存写错会议 | 数据串写 | 保存绑定 `editableMarkdownMeetingID`，不直接按当前 selection 写入 |
| 转写完成覆盖用户编辑版 | 数据丢失 | 保存/转写测试锁定 `edited.md` 不被覆盖 |
| 语言文案仍混淆 | 用户继续误解 | UI 禁止裸“语言”，使用 `界面语言` 与 `转写语言：中文` |
| 录音中修改设置造成状态不一致 | 体验混乱 | 录音中弱化/禁用高风险设置，仅保留必要状态和停止操作 |
| SwiftUI 视觉无法自动测试 | 可能布局不符合预期 | 打包后手动验收三栏结构，并在最终报告写明 evidence |

## 5. 验证路径

最低完成证据：

1. `swift test` 通过。
2. `swift build` 通过。
3. 打包脚本成功生成/刷新 `dist/VoiceCaptioner.app`。
4. 手动打开 app 验证默认中文、三栏布局、右侧“界面语言”、只读“转写语言：中文”。
5. 对一个会议生成/保存 `transcript/edited.md`，确认 `final.md` 未改。

## 6. Available-Agent-Types Roster

可用角色与建议用途：

- `explore`：快速定位现有 SwiftUI/AppModel/测试触点。
- `architect`：复核三栏结构、状态归属、artifact 约束。
- `executor`：实现 Swift/AppModel/UI 改动。
- `designer`：优化三栏信息架构与录音中视觉优先级。
- `test-engineer`：补 AppModel tests 与验收脚本。
- `verifier`：独立运行测试、构建、打包和手动验收清单。
- `code-reviewer`：检查数据覆盖、语言混淆、SwiftUI 可维护性。
- `writer`：如需要，更新 README/使用说明。

## 7. Follow-up Staffing Guidance

### `$ralph` 单 owner 路径

适合一次性顺序完成：

1. Executor（medium）：AppModel Markdown state + tests。
2. Executor/Designer（medium/high）：ContentView 三栏 UI。
3. Test-engineer（medium）：测试补齐。
4. Verifier（high）：swift test/build/package + 手动验收。

建议在 `$ralph` prompt 中要求：不得覆盖 `final.md`，不得新增会议语言 picker，必须重打包。

### `$team` 并行路径

推荐 4 lane：

1. Worker A — AppModel/artifacts：`VoiceCaptionerAppModel.swift`、AppModel tests。
2. Worker B — UI layout：`ContentView.swift` 三栏中控台和 Markdown editor 绑定。
3. Worker C — Localization/copy：`Localization.swift` 中英德文案与语言概念分离。
4. Worker D — Verification/package：等 A/B/C 合并后运行 tests/build/package/manual checklist。

共享文件风险：B 和 C 都可能碰 UI key；leader 应先让 C 定 key，B 按 key 使用，或由 leader 统一 reconcile。

## 8. Launch Hints

### Team

```text
$team "Implement .omx/plans/plan-ui-console-redesign.md for voice-captioner. Build a three-column console UI: left history, center current meeting recording/subtitles/final Markdown editor, right grouped settings. Add transcript/edited.md user Markdown without overwriting final.md. Keep transcription language fixed Chinese and UI language separate. Run swift test/build/package and report evidence."
```

或 CLI：

```bash
omx team start --task "Implement .omx/plans/plan-ui-console-redesign.md for voice-captioner" --workers 4
```

### Ralph

```text
$ralph "Implement .omx/plans/plan-ui-console-redesign.md completely, then verify with swift test, swift build, package app, and edited.md manual artifact check."
```

## 9. Team Verification Path

Team shutdown 前必须证明：

- AppModel tests 覆盖 edited Markdown、dirty autosave、A→B selection、save-to-loaded-meeting，且 `swift test` 通过。
- `ContentView` 已呈现三栏结构，并拆分为工作区/设置/编辑器等小型 SwiftUI views，不再把 settings 堆在中心任务流里。
- UI language 文案为“界面语言”，transcription language 为只读中文。
- `edited.md` 保存路径有效，`final.md` 不被覆盖。
- `dist/VoiceCaptioner.app` 已重新打包。

若 Team 完成后仍有失败或视觉不确定，交给 `$ralph` 做单 owner 修复/验证压力循环。

## 10. Goal-Mode Follow-up Suggestions

- 默认：`$ultragoal` 可将本计划作为 durable goal ledger，适合继续追踪 UI redesign 完成度。
- 并行实现：`$ultragoal` + `$team`，由 Ultragoal 记录目标和证据，Team 并行交付实现。
- 不建议 `$autoresearch-goal`：本任务不是研究型。
- 不建议 `$performance-goal`：本任务不是性能优化。

## 11. Consensus Review Changelog

- 初版已纳入 deep-interview 决策：A/B/C 右侧设置策略、固定中文转写、轻量 Markdown、编辑版单独保存。
- Architect review 后修订：AppModel 独占 editable Markdown session；选择切换/转写 reload 前 dirty autosave；保存绑定 `editableMarkdownMeetingID`；布局拆分从建议升级为必须；测试扩大到 selection、autosave、读取失败和防串写。
- Critic review 批准；按非阻塞建议明确打包脚本为 `scripts/package-local-app.sh`。
