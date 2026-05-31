# Phase 1b 验收说明：宠物状态引擎 + 完成任务反馈

## 运行

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=.build/module-cache swift run PetTaskBuddy
```

## 验收点

- 点击桌宠打开「今日」面板。
- 面板顶部显示饱食度和心情，数值来自 SwiftData 持久化。
- 添加任务并勾选完成后，饱食度增加，心情上升。
- 勾选完成时，桌宠会暂停漫游，掉落占位食物/水，走过去播放 `eat` / `drink`，再回到 idle。
- mood 阈值驱动视觉状态：`>=70` 播 happy，`40...69` idle，`<40` listless。
- fullness 会按每小时约 `-3` 衰减；App 启动时会根据上次更新时间补算离线衰减。
- 状态没有生病/死亡/责备文案，listless 只是轻微蔫，完成任意任务会快速回神。
- 退出并重启 App 后，饱食度、心情和任务完成状态保留。

## 自动 smoke test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=.build/module-cache swift run PetTaskBuddy --smoke-test-tasks
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=.build/module-cache swift run PetTaskBuddy --smoke-test-pet-state
```

预期输出：

```text
Task persistence smoke test passed.
Pet state smoke test passed.
```

自动测试使用 `PetTaskBuddySmokeTest.store`，不会写入正式桌宠数据。
