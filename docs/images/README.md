# 文档截图与复现

更新日期：2026-09-11。README、功能说明和外观说明共用本目录的图片；当前图片来自工作区的 SwiftUI / AppKit 组件，使用固定日期的匿名示例数据，不包含真实任务、项目路径、会话内容或本机用量。

## 一次性导出

在仓库根目录执行：

```bash
python3 script/export_screenshots.py
```

需要 Python 3、完整 Xcode 和已登录的 macOS 图形会话。默认使用 `/Applications/Xcode.app/Contents/Developer`；其他安装位置可通过 `DEVELOPER_DIR` 指定。脚本使用系统库，不安装第三方依赖。

脚本在临时目录构建独立的 `CodexVistaDocs.app`，通过 LaunchServices 启动，完成后退出并清理临时产物。首次编译可能需要几分钟。若受限执行环境禁止 Swift 宏进程或 WindowServer / LaunchServices，需由运行环境授权这次本地编译与导出。

所有截图生成成功后才更新本目录及 [manifest.json](manifest.json)。生成失败时不会用半套图片覆盖现有文档。

## 数据与表现边界

- `script/screenshots/DocumentationFixture.swift` 提供手写快照，固定基准时间为 `2026-09-04T08:00:00Z`。`example-model` 是用于展示参考价回退的虚构模型标识。
- 数据、通知与更新服务全部注入替身，不扫描 `.codex`，不打开正式数据库，不请求系统通知权限，不查询 GitHub 或下载更新。
- 截图应用使用独立 Bundle ID 和进程内易失偏好，不修改正式应用的外观、订阅日期、通知或刷新设置。
- 正式源码和 Target 不变。脚本仅在临时副本中开放私有组件与状态入口、固定日期，便于直接展示各个标签和悬浮明细。
- 页面标题中的“示例数据”属于文档标识，不是产品系统标题栏。设置长图展开现有分区，单独的悬浮卡用于展示完整内容，不模拟实际鼠标或窗口定位。
- 重建确认图使用原生 `NSAlert` 显示设置中的相同文案，系统样式可能因 macOS 版本而不同；没有点击确认或执行数据清理。
- 图片使用 2× 像素比例。源码与场景固定，但字体栅格化、系统控件和材质可能随 macOS / Xcode 版本变化，因此不要求跨机器逐像素相同。

## 覆盖清单

| 场景 | 图片 |
| --- | --- |
| 菜单栏与刘海 | [状态栏](codexvista-status-bar.png)、[刘海摘要](codexvista-notch-summary.png)、[用量弹窗](codexvista-popover.png) |
| 看板四个分析页 | [今日任务](codexvista-today-tasks.png)、[用量趋势](codexvista-dashboard.png)、[Skills / Tools](codexvista-activity-usage.png)、[项目用量](codexvista-project-usage.png) |
| 看板状态 | [加载骨架](codexvista-loading.png)、[空数据](codexvista-empty.png) |
| 项目详情 | [概览](codexvista-project-overview.png)、[任务明细](codexvista-task-details.png)、[回复明细](codexvista-reply-details.png)、[趋势节点](codexvista-project-trend-hover.png) |
| 任务与回复调用 | [任务调用](codexvista-task-activity-detail.png)、[回复调用](codexvista-reply-activity-detail.png)、[今日任务详情](codexvista-today-task-detail.png)、[今日任务回复调用](codexvista-today-task-reply-hover.png) |
| 趋势和日历 | [趋势节点](codexvista-trend-hover.png)、[日期明细](codexvista-calendar-day-hover.png)、[图例明细](codexvista-calendar-legend-hover.png) |
| Skill 细分 | [命名空间调用构成](codexvista-skill-breakdown-hover.png) |
| 模型 | [前五名预览](codexvista-model-preview.png)、[完整排行](codexvista-model-hover-details.png)、[Token 明细](codexvista-model-token-hover-details.png)、[费用明细](codexvista-model-cost-hover-details.png)、[价格目录](codexvista-model-pricing-popover.png) |
| 设置分区 | [外观、看板与摘要](codexvista-settings-appearance.png)、[额度提醒](codexvista-settings-reminders.png)、[数据与更新](codexvista-settings-data.png)、[订阅与套餐](codexvista-settings-plans.png) |
| 设置总览与确认 | [全部设置长图](codexvista-settings.png)、[重建确认同文案示例](codexvista-rebuild-confirmation.png) |
| 经典与水墨 | [经典浅色](themes/codexvista-light.png)、[经典深色](themes/codexvista-dark.png)、[水墨浅色](themes/codexvista-ink-light.png) |
| 青瓷与暮霞 | [青瓷浅色](themes/codexvista-celadon-light.png)、[青瓷深色](themes/codexvista-celadon-dark.png)、[暮霞浅色](themes/codexvista-dusk-light.png)、[暮霞深色](themes/codexvista-dusk-dark.png) |
| 固定色系与摘要 | [未来科技](themes/codexvista-cyber-dark.png)、[仙侠](themes/codexvista-xianxia-light.png)、[全部摘要配色](themes/codexvista-summary-themes.png) |

## 来源核验与维护

`manifest.json` 记录导出时的源码提交、源码、资源及导出工具联合 SHA-256、固定示例日期、每张图片的尺寸和 SHA-256。代码仍有未提交改动时，提交号只标识基础提交，联合指纹用于标识实际输入。

新增页面或更改入口后，应同步修改 `DocumentationCapture.swift` 的导出清单及本文引用，再重新运行脚本。发布版本从 `Config/Version.xcconfig` 读取，不在导出代码中硬编码。

导出后检查主要页面、全部皮肤、长设置页和悬浮卡是否存在裁切、重叠、乱码或遗漏，同时检查相对链接及 `git diff --check`。组件截图不能证明真实鼠标悬浮、键盘操作、通知投递或刘海屏幕定位正确；这些行为通过项目脚本构建最新 App 后单独验证。

旧版产品截图与早期模型排行设计草图已由当前组件图片替换，避免把历史设计当作已实现界面。
