# Test Spec — VoiceCaptioner UI Console Redesign

日期：2026-05-15  
适用计划：`.omx/plans/plan-ui-console-redesign.md`

## 1. 测试目标

验证中控台 UI 重构不会破坏现有本地录音/转写/导出路径，并新增可靠的用户编辑 Markdown 存储行为。

## 2. 自动化测试

### 2.1 AppModel 单元测试

新增或扩展 `Tests/VoiceCaptionerAppModelTests/VoiceCaptionerAppModelTests.swift`：

1. `loadsFinalMarkdownAsEditableDraftWhenNoEditedMarkdownExists`
   - Given：会议 `transcript/final.md` 存在，`edited.md` 不存在。
   - When：AppModel 刷新历史并选中会议/显式加载编辑内容。
   - Then：编辑器文本等于 `final.md` 内容；状态显示来源为机器原文或可保存为编辑版。

2. `savingEditableMarkdownWritesEditedMarkdownWithoutChangingFinal`
   - Given：`final.md` 内容为 A。
   - When：编辑器修改为 B 并保存。
   - Then：`transcript/edited.md` 为 B，`transcript/final.md` 仍为 A。

3. `loadsEditedMarkdownBeforeFinalMarkdown`
   - Given：`final.md` 为 A，`edited.md` 为 B。
   - When：选中会议。
   - Then：编辑器显示 B。

4. `exportArtifactsIncludesEditedMarkdown`
   - Given：会议有 `final.md/final.srt/final.json`，可选 `edited.md`。
   - Then：`exportArtifacts` 包含机器 Markdown、SRT、JSON、用户编辑版 Markdown，并准确标记 exists。

5. `transcriptionCompletionDoesNotOverwriteExistingEditedMarkdown`
   - Given：会议已有 `edited.md`。
   - When：重新运行 final transcription。
   - Then：`final.md` 可更新，但 `edited.md` 不被 AppModel 覆盖。

6. `selectingAnotherMeetingAutosavesDirtyMarkdownToOriginalMeeting`
   - Given：会议 A 加载后用户修改编辑器但未点保存，会议 B 存在。
   - When：调用 `selectMeeting(id: B)`。
   - Then：A 的 `transcript/edited.md` 写入修改内容，B 加载自己的内容。

7. `saveEditableMarkdownWritesToLoadedMeetingNotCurrentSelectionRace`
   - Given：`editableMarkdownMeetingID` 为 A，当前 selection 被刷新到 B。
   - When：调用 `saveEditableMarkdown()`。
   - Then：内容写入 A 的 `edited.md`，不写入 B。

8. `markdownReadFailureDoesNotCrashAndReportsStatus`
   - Given：`final.md` 或 `edited.md` 读取失败/不可读。
   - When：加载编辑内容。
   - Then：AppModel 不崩溃，状态暴露错误，编辑器不会错误覆盖文件。

### 2.2 本地化/文案测试

可在 AppModel tests 中断言关键 strings：

- 中文：`界面语言`、`转写语言：中文`、`用户编辑版 Markdown`。
- 英文/德文至少存在对应 key，避免编译分支遗漏。
- 原 `language` key 若保留，应不再用于录音设置；新增明确 key 如 `interfaceLanguage`。

### 2.3 现有回归测试

必须继续通过：

```bash
swift test
```

尤其关注：

- `WhisperProcessTranscriberTests`：中文识别配置保持不翻译。
- `LiveTranscriptionPipelineTests`：延迟实时草稿不被 UI 改动影响。
- `MeetingStoreTests`：会议目录结构兼容新增 `edited.md`。

## 3. 构建与打包验证

执行：

```bash
swift build
swift test
./scripts/package-local-app.sh
```

仓库当前实际打包脚本为 `scripts/package-local-app.sh`，执行记录必须写明。

## 4. 手动验收脚本

1. 打开 `dist/VoiceCaptioner.app`。
2. 默认界面应为中文。
3. 检查主界面为左历史 / 中当前会议 / 右设置。
4. 检查右侧“应用/界面”里有“界面语言”，而录音设置区域没有模糊的“语言” picker。
5. 检查右侧或中心状态中显示“转写语言：中文”。
6. 选择历史会议或新录一段会议。
7. 录音中确认中心显示录音状态与延迟实时字幕草稿。
8. 停止后运行本地转写。
9. 在 Markdown 编辑器中修改文字并保存。
10. 到会议目录检查：
    - `transcript/final.md` 仍为机器原文。
    - `transcript/edited.md` 为用户修改内容。
11. 重新打开/刷新 App，选中会议，应优先显示 `edited.md` 内容。

## 5. 失败处理要求

- 若 `swift test` 失败，不得宣称完成；必须修复或明确记录阻塞。
- 若打包失败，不得让用户双击旧 app 验收；必须重打包或说明未完成。
- 若不能自动化验证 SwiftUI 三栏视觉布局，必须至少提供手动验收截图/描述证据。
