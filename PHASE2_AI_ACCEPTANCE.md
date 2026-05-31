# Phase 2 验收说明：AI 目标到今日任务

## 运行

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=.build/module-cache swift run PetTaskBuddy
```

## 验收点

- 主面板新增「目标」标签，可增删改长期目标、启用/停用。
- 主面板新增「设置」标签，可设置每日 AI 任务数量 `3...5`。
- Claude API key 通过设置页写入 macOS Keychain，不写入 SwiftData 或配置文件。
- 「今日」标签新增「AI 帮我想想」按钮。
- AI 生成结果先进入草稿区，可编辑、删除、手动加草稿。
- 点击「确认加入今日」后，草稿变成普通今日任务，`source=ai`。
- 确认后的 AI 任务会进入今日列表和思考泡泡，完成时复用喂宠物逻辑。
- 无 API key、网络失败、解析失败时不崩溃，会温和提示并保留手动添加能力。

## 自动 smoke test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=.build/module-cache swift run PetTaskBuddy --smoke-test-ai
```

预期输出：

```text
AI task smoke test passed.
```

该测试使用 mock LLM 和临时 SwiftData store，不读取或覆盖真实 Keychain API key。
