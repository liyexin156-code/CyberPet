# PRD 第 15 节验收说明：重复任务 / 日程引擎

## 运行

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=.build/module-cache swift run PetTaskBuddy
```

## 验收点

- 主面板新增「日程」标签。
- 可新增、选择编辑、删除日程项。
- 日程类型支持「任务」和「提醒」。
- 重复规则支持「每天」「周几」「特定日期」，特定日期可选每年重复。
- 可启用可选提醒时间。
- App 启动和跨午夜会自动把匹配今天的日程生成到「今日」。
- 同一日程同一天只生成一次，按 `scheduleItemId + 日期` 去重。
- task 型今日条目有勾选框，完成后继续触发 Phase 1b 喂宠物逻辑。
- reminder 型今日条目显示铃铛，无勾选框，不影响宠物状态。
- 设置 reminderTime 后，开发版 `swift run` 会触发宠物气泡；打包为 `.app` 后会同时注册 macOS 系统通知。

## 自动 smoke test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=.build/module-cache swift run PetTaskBuddy --smoke-test-schedule
```

预期输出：

```text
Schedule smoke test passed.
```

该测试覆盖：

- 每天任务会生成。
- 每周一三五任务只在匹配星期生成。
- 特定日期 + 每年重复提醒会生成 reminder 型今日条目。
- 同一天重复生成会去重。
