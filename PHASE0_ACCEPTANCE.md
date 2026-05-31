# Phase 0 验收说明

## 运行

```bash
swift run PetTaskBuddy
```

退出方式：右键点击桌宠，选择「退出」。

## 验收点

- 桌宠以透明、无边框、置顶窗口出现在桌面。
- idle 动画由 `Assets/pet/manifest.json` 驱动，占位精灵为 64×64 PNG sprite strip，可直接替换真图。
- 桌宠会在启动约 1 秒后开始漫游，之后约每 8 秒移动一次；移动时切换到 walk 动画，停下回 idle。
- 左键拖拽宠物可移动窗口。
- 右键菜单只包含「退出」。
- App 使用 accessory activation policy，不显示普通主窗口，不主动抢其它 App 焦点。
