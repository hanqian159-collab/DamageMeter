# DamageMeter 项目说明

## 项目定位

`DamageMeter` 是《Witch's Apocalyptic Journey》的纯 Lua 输出统计模组，只负责战斗内统计展示，不再承载木桩事件、训练关卡或训练台 UI。

## 技术栈

- Lua Template Hook
- Unity `CS.*` 运行时访问
- TextMeshPro 悬浮 UI

## 入口文件

- [Entry.lua](C:\Users\admin\Desktop\object\DamageMeter\Scripts\Entry.lua)

游戏加载模组后会执行 `ModConfig:Setup()`，在这里注册伤害、回合、BUFF 和 UI 刷新相关 Hook。

## 运行方式

将 `DamageMeter` 整个目录放到游戏 `Mods` 目录，启用后进入战斗，按 `F8` 显示或隐藏统计面板。

静态校验命令：

```powershell
python "C:\Users\admin\.codex\skills\WAJ-Modder-main\scripts\validate_mod.py" "C:\Users\admin\Desktop\object\DamageMeter"
```

## 目录结构

```text
DamageMeter/
├─ ModConfig.json
├─ DamageMeter.modproj
├─ Icon.png
├─ README.md
├─ MAINTAINER_GUIDE.md
├─ PROJECT_OVERVIEW.md
└─ Scripts/
   └─ Entry.lua
```

木桩模式已拆分到独立项目 `DamageMeterTraining`。
