import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable, Codable {
  case zhHans
  case en
  case de

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .zhHans: return "中文"
    case .en: return "English"
    case .de: return "Deutsch"
    }
  }
}

public struct AppStrings: Sendable {
  public let language: AppLanguage

  public init(language: AppLanguage) {
    self.language = language
  }

  public func text(_ key: Key) -> String {
    switch language {
    case .zhHans: return key.zh
    case .en: return key.en
    case .de: return key.de
    }
  }

  public enum Key: Sendable {
    case meetings, refresh, tagline, language, interfaceLanguage, transcriptionLanguage
    case fixedChineseTranscriptionLanguage, currentMeetingWorkspace, settingsInspector
    case commonSettings, appSettings, liveDraftSettings, advancedDiagnostics
    case machineMarkdown, editedMarkdown, markdownEditor, saveEditedMarkdown
    case markdownSourceFinal, markdownSourceEdited, markdownWaitingForTranscript, unsavedChanges
    case capture, outputRoot, choose, meetingTitle, meetingPlaceholder
    case rollingDelay, chunkSize, seconds(Int), localWhisper, whisperExecutable, useBundled
    case downloadedModel, manualNone, rescan, manualModel, startRecording, stop, refreshPermissions
    case transcribeSelectedMeeting, cancel, regenerateChunkManifest, idleTranscriptionHelp
    case completedSegments(Int), transcriptionCancelled, transcriptionFailed(String), capabilities
    case microphone, systemAudio, outputFolder, sandboxEntitlements, model, transcriptPreview
    case transcriptPreviewEmpty, selectedMeeting, openFolder, openArtifact(String), noMeetingSelected
    case noBundledExecutable, sourceBundled, sourceProject, sourceManual, optionalModelPath
    case durationPending, verifiedManifest, statusUnknown

    var zh: String {
      switch self {
      case .meetings: return "会议"
      case .refresh: return "刷新"
      case .tagline: return "本地优先录音，停止后 Whisper 转写，导出并按文件夹保存历史。不会上传云端。"
      case .language: return "语言"
      case .interfaceLanguage: return "界面语言"
      case .transcriptionLanguage: return "转写语言"
      case .fixedChineseTranscriptionLanguage: return "转写语言：中文"
      case .currentMeetingWorkspace: return "当前会议工作台"
      case .settingsInspector: return "设置"
      case .commonSettings: return "常用"
      case .appSettings: return "应用"
      case .liveDraftSettings: return "延迟实时草稿"
      case .advancedDiagnostics: return "高级诊断"
      case .machineMarkdown: return "机器 Markdown"
      case .editedMarkdown: return "用户编辑版 Markdown"
      case .markdownEditor: return "Markdown 编辑器"
      case .saveEditedMarkdown: return "保存用户编辑版 Markdown"
      case .markdownSourceFinal: return "来源：机器 final.md（保存会写入 edited.md，不覆盖原文）"
      case .markdownSourceEdited: return "来源：用户 edited.md"
      case .markdownWaitingForTranscript: return "暂无 Markdown。转写完成后会载入 final.md，也可以先在这里记录笔记。"
      case .unsavedChanges: return "有未保存修改，将在切换会议或刷新前自动保存。"
      case .capture: return "录音"
      case .outputRoot: return "输出目录"
      case .choose: return "选择…"
      case .meetingTitle: return "会议标题"
      case .meetingPlaceholder: return "会议"
      case .rollingDelay: return "滚动延迟"
      case .chunkSize: return "分块大小"
      case .seconds(let value): return "\(value) 秒"
      case .localWhisper: return "本地 Whisper"
      case .whisperExecutable: return "whisper.cpp 可执行文件"
      case .useBundled: return "使用内置"
      case .downloadedModel: return "已下载模型"
      case .manualNone: return "手动 / 无"
      case .rescan: return "重新扫描"
      case .manualModel: return "手动模型"
      case .optionalModelPath: return "可选 .bin/.gguf 模型路径"
      case .startRecording: return "开始录音"
      case .stop: return "停止"
      case .refreshPermissions: return "刷新权限"
      case .transcribeSelectedMeeting: return "转写选中会议"
      case .cancel: return "取消"
      case .regenerateChunkManifest: return "重新生成分块清单"
      case .idleTranscriptionHelp: return "录音中会按分块生成延迟实时草稿；停止后可转写/覆盖为最终 Markdown/SRT/JSON 导出。"
      case .completedSegments(let count): return "已完成，生成 \(count) 个最终片段。"
      case .transcriptionCancelled: return "转写已取消。"
      case .transcriptionFailed(let message): return "转写失败：\(message)"
      case .capabilities: return "能力与权限"
      case .microphone: return "麦克风"
      case .systemAudio: return "系统音频"
      case .outputFolder: return "输出文件夹"
      case .sandboxEntitlements: return "沙盒/权限声明"
      case .model: return "模型"
      case .transcriptPreview: return "延迟实时转写 / 最终预览"
      case .transcriptPreviewEmpty: return "录音中生成的延迟实时草稿或最终转写片段会显示在这里。最终导出保存在所选会议的 transcript 文件夹。"
      case .selectedMeeting: return "选中会议"
      case .openFolder: return "打开文件夹"
      case .openArtifact(let label): return "打开 \(label)"
      case .noMeetingSelected: return "未选择会议"
      case .noBundledExecutable: return "未找到内置可执行文件；请选择本地 whisper.cpp 可执行文件"
      case .sourceBundled: return "内置"
      case .sourceProject: return "项目"
      case .sourceManual: return "手动"
      case .durationPending: return "时长待定"
      case .verifiedManifest: return "已验证清单"
      case .statusUnknown: return "未知"
      }
    }

    var en: String {
      switch self {
      case .meetings: return "Meetings"
      case .refresh: return "Refresh"
      case .tagline: return "Local-first recording, post-stop Whisper transcription, exports, and folder-indexed history. No cloud processing."
      case .language: return "Language"
      case .interfaceLanguage: return "Interface Language"
      case .transcriptionLanguage: return "Transcription Language"
      case .fixedChineseTranscriptionLanguage: return "Transcription language: Chinese"
      case .currentMeetingWorkspace: return "Current Meeting Workspace"
      case .settingsInspector: return "Settings"
      case .commonSettings: return "Common"
      case .appSettings: return "App"
      case .liveDraftSettings: return "Delayed Live Drafts"
      case .advancedDiagnostics: return "Advanced Diagnostics"
      case .machineMarkdown: return "Machine Markdown"
      case .editedMarkdown: return "Edited Markdown"
      case .markdownEditor: return "Markdown Editor"
      case .saveEditedMarkdown: return "Save Edited Markdown"
      case .markdownSourceFinal: return "Source: machine final.md (saving writes edited.md, never overwrites original)"
      case .markdownSourceEdited: return "Source: user edited.md"
      case .markdownWaitingForTranscript: return "No Markdown yet. final.md loads after transcription, or you can start notes here."
      case .unsavedChanges: return "Unsaved changes will autosave before switching meetings or refreshing."
      case .capture: return "Capture"
      case .outputRoot: return "Output root"
      case .choose: return "Choose…"
      case .meetingTitle: return "Meeting title"
      case .meetingPlaceholder: return "Meeting"
      case .rollingDelay: return "Rolling delay"
      case .chunkSize: return "Chunk size"
      case .seconds(let value): return "\(value) seconds"
      case .localWhisper: return "Local Whisper"
      case .whisperExecutable: return "whisper.cpp executable"
      case .useBundled: return "Use Bundled"
      case .downloadedModel: return "Downloaded model"
      case .manualNone: return "Manual / none"
      case .rescan: return "Rescan"
      case .manualModel: return "Manual model"
      case .optionalModelPath: return "Optional .bin/.gguf model path"
      case .startRecording: return "Start Recording"
      case .stop: return "Stop"
      case .refreshPermissions: return "Refresh Permissions"
      case .transcribeSelectedMeeting: return "Transcribe Selected Meeting"
      case .cancel: return "Cancel"
      case .regenerateChunkManifest: return "Regenerate Chunk Manifest"
      case .idleTranscriptionHelp: return "During recording, delayed live drafts appear by chunk; after stopping, transcribe/overwrite final Markdown/SRT/JSON exports."
      case .completedSegments(let count): return "Completed with \(count) final segment(s)."
      case .transcriptionCancelled: return "Transcription cancelled."
      case .transcriptionFailed(let message): return "Transcription failed: \(message)"
      case .capabilities: return "Capabilities"
      case .microphone: return "Microphone"
      case .systemAudio: return "System audio"
      case .outputFolder: return "Output folder"
      case .sandboxEntitlements: return "Sandbox/entitlements"
      case .model: return "Model"
      case .transcriptPreview: return "Delayed Live Transcript / Final Preview"
      case .transcriptPreviewEmpty: return "Delayed live drafts during recording or final transcript segments appear here. Final exports stay in the selected meeting’s transcript folder."
      case .selectedMeeting: return "Selected Meeting"
      case .openFolder: return "Open Folder"
      case .openArtifact(let label): return "Open \(label)"
      case .noMeetingSelected: return "No meeting selected"
      case .noBundledExecutable: return "No bundled executable found; choose a local whisper.cpp executable"
      case .sourceBundled: return "bundled"
      case .sourceProject: return "project"
      case .sourceManual: return "manual"
      case .durationPending: return "duration pending"
      case .verifiedManifest: return "verified manifest"
      case .statusUnknown: return "unknown"
      }
    }

    var de: String {
      switch self {
      case .meetings: return "Besprechungen"
      case .refresh: return "Aktualisieren"
      case .tagline: return "Lokale Aufnahme, Whisper-Transkription nach dem Stopp, Exporte und ordnerbasierter Verlauf. Keine Cloud-Verarbeitung."
      case .language: return "Sprache"
      case .interfaceLanguage: return "Oberflächensprache"
      case .transcriptionLanguage: return "Transkriptionssprache"
      case .fixedChineseTranscriptionLanguage: return "Transkriptionssprache: Chinesisch"
      case .currentMeetingWorkspace: return "Aktueller Besprechungsbereich"
      case .settingsInspector: return "Einstellungen"
      case .commonSettings: return "Allgemein"
      case .appSettings: return "App"
      case .liveDraftSettings: return "Verzögerte Live-Entwürfe"
      case .advancedDiagnostics: return "Erweiterte Diagnose"
      case .machineMarkdown: return "Maschinen-Markdown"
      case .editedMarkdown: return "Bearbeitetes Markdown"
      case .markdownEditor: return "Markdown-Editor"
      case .saveEditedMarkdown: return "Bearbeitetes Markdown speichern"
      case .markdownSourceFinal: return "Quelle: maschinelles final.md (Speichern schreibt edited.md, Original bleibt erhalten)"
      case .markdownSourceEdited: return "Quelle: Benutzerdatei edited.md"
      case .markdownWaitingForTranscript: return "Noch kein Markdown. final.md wird nach der Transkription geladen; Notizen sind hier möglich."
      case .unsavedChanges: return "Ungespeicherte Änderungen werden vor dem Wechsel oder Aktualisieren automatisch gespeichert."
      case .capture: return "Aufnahme"
      case .outputRoot: return "Ausgabeordner"
      case .choose: return "Auswählen…"
      case .meetingTitle: return "Besprechungstitel"
      case .meetingPlaceholder: return "Besprechung"
      case .rollingDelay: return "Rollende Verzögerung"
      case .chunkSize: return "Chunk-Größe"
      case .seconds(let value): return "\(value) Sekunden"
      case .localWhisper: return "Lokales Whisper"
      case .whisperExecutable: return "whisper.cpp-Programm"
      case .useBundled: return "Integriertes verwenden"
      case .downloadedModel: return "Heruntergeladenes Modell"
      case .manualNone: return "Manuell / keines"
      case .rescan: return "Neu scannen"
      case .manualModel: return "Manuelles Modell"
      case .optionalModelPath: return "Optionaler .bin/.gguf-Modellpfad"
      case .startRecording: return "Aufnahme starten"
      case .stop: return "Stopp"
      case .refreshPermissions: return "Berechtigungen aktualisieren"
      case .transcribeSelectedMeeting: return "Ausgewählte Besprechung transkribieren"
      case .cancel: return "Abbrechen"
      case .regenerateChunkManifest: return "Chunk-Liste neu erzeugen"
      case .idleTranscriptionHelp: return "Während der Aufnahme erscheinen verzögerte Live-Entwürfe pro Chunk; nach dem Stopp finale Markdown/SRT/JSON-Exporte transkribieren/überschreiben."
      case .completedSegments(let count): return "Abgeschlossen mit \(count) finalen Segment(en)."
      case .transcriptionCancelled: return "Transkription abgebrochen."
      case .transcriptionFailed(let message): return "Transkription fehlgeschlagen: \(message)"
      case .capabilities: return "Funktionen und Rechte"
      case .microphone: return "Mikrofon"
      case .systemAudio: return "Systemaudio"
      case .outputFolder: return "Ausgabeordner"
      case .sandboxEntitlements: return "Sandbox/Berechtigungen"
      case .model: return "Modell"
      case .transcriptPreview: return "Verzögerte Live-Transkription / finale Vorschau"
      case .transcriptPreviewEmpty: return "Verzögerte Live-Entwürfe während der Aufnahme oder finale Transkriptsegmente erscheinen hier. Finale Exporte bleiben im transcript-Ordner der Besprechung."
      case .selectedMeeting: return "Ausgewählte Besprechung"
      case .openFolder: return "Ordner öffnen"
      case .openArtifact(let label): return "\(label) öffnen"
      case .noMeetingSelected: return "Keine Besprechung ausgewählt"
      case .noBundledExecutable: return "Kein integriertes Programm gefunden; lokales whisper.cpp-Programm auswählen"
      case .sourceBundled: return "integriert"
      case .sourceProject: return "Projekt"
      case .sourceManual: return "manuell"
      case .durationPending: return "Dauer ausstehend"
      case .verifiedManifest: return "Manifest geprüft"
      case .statusUnknown: return "unbekannt"
      }
    }
  }
}
