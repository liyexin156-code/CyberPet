# Phase 1 前半验收说明：今日任务 CRUD + 持久化

## 运行

SwiftData 宏需要完整 Xcode toolchain。当前机器的 `xcode-select` 指向 Command Line Tools，因此请用：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=.build/module-cache swift run PetTaskBuddy
```

## 验收点

- 点击桌宠会弹出主面板。
- 主面板目前只有「今日」标签。
- 可以手动添加今日任务。
- 可以勾选 / 取消勾选任务完成状态。
- 可以删除任务。
- 退出并重新启动 App 后，今日任务和完成状态仍然保留。
- 本阶段不改变宠物状态、数值、喂食动画或其它宠物反应。

## 自动 smoke test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=.build/module-cache swift run PetTaskBuddy --smoke-test-tasks
```

预期输出：

```text
Task persistence smoke test passed.
```

## 数据位置

SwiftData 持久化文件位于：

```text
~/Library/Application Support/PetTaskBuddy/PetTaskBuddy.store
```
