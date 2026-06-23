# DamageMeter 维护文档

本文面向继续维护输出统计本体的作者。当前 `DamageMeter` 是纯 Lua Hook 模组，木桩模式已拆分到独立项目 `DamageMeterTraining`。

## 文件结构

```text
DamageMeter/
  ModConfig.json
  README.md
  MAINTAINER_GUIDE.md
  Scripts/
    Entry.lua
```

## 核心职责

1. 统计 `StatusManager.Hit` 与 `ScriptExecutor.ChangeHp` 造成的实际生命/护盾损失。
2. 追踪 `ScriptExecutor.AddBuff`、`StatusManager.AddBuff`、`BuffItem.ApplyBuff`、`BuffItem.BuffProcess`，尽量完成 BUFF 伤害归因。
3. 绘制输出面板、悬浮详情和详情弹窗。
4. 在回合开始与战斗切换时重置对应统计。

## 主要入口

- [Entry.lua](C:\Users\admin\Desktop\object\DamageMeter\Scripts\Entry.lua)

游戏加载后执行 `ModConfig:Setup()`，所有 Hook 都在这里注册。

## 不再属于本项目的内容

- 木桩地图事件
- 木桩训练关卡
- `Configuration.json`
- `Scripts/Entry.dll`
- 训练台按钮与 C# 训练 UI

这些内容已迁移到 `DamageMeterTraining`。
