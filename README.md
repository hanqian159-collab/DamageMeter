> **⚠️ 半成品 / Work in Progress** — 此模组已基本完成所有Hook注册（StatusManager.Hit → ScriptExecutor.Damage/ChangeHp/PureChangeHp → ScriptExecutor.AddBuff → StatusManager.AddBuff → BuffItem.ApplyBuff/BuffProcess），统计面板 UI、详情弹窗、拖动、进度条均已完成。已知问题/待完善项请见 Issues 或仓库讨论区。

# DamageMeter

战斗输出统计模组。

- 结算口径按实际生命损失与护盾损失统计。
- 支持本回合、本场、友方整局总计三层输出视角。
- 支持 BUFF 归因、悬浮详情和可拖动详情窗。
- 友方行会显示本场输出占比进度条。
- 默认按 `F8` 显示或隐藏面板，可在 `ModConfig.json` 里修改。

`DamageMeter` 现在只保留输出统计本体；木桩训练与试验台已拆分到独立模组 `DamageMeterTraining`，方便后续分别更新。
