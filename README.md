# data-disk-cleaner

Windows 数据盘（D:/E:/F: 等非系统盘）安全清理与空间审计的 Agent Skill。参数化扫描 → 分类报告 → 批量回收站清理，绝不硬删除。

出处声明：沿用第三方 skill kunlun-pc-cleaner 的分级处置框架（只读扫描→哈希比对→风险分级→移入废纸篓），与姊妹 skill c-disk-cleaner-pro（系统盘清理）共享清理引擎。

## 与系统盘清理的区别

数据盘上的文件是用户主动存放的，没有"绝对安全"的文件。本 skill 的绿区只包含机器生成的可再生内容：

- 🟢 项目构建垃圾：node_modules / target / dist / build / __pycache__ / .venv / bin / obj
- 🟢 应用缓存/更新残留/临时导出
- 🟡 需确认：安装包（已解压的）、旧下载、旧归档、重复文件（SHA-256 判定）
- 🔴 只报告不动：虚拟机磁盘（vhdx/vmdk/vdi）、音色库、模型权重、备份、照片视频

## 快速上手

    # 1. 只读扫描某个数据盘
    powershell -ExecutionPolicy Bypass -File scripts/scan-drive.ps1 -Drive F:
    # 可调参数：-OldDays 365 -BigFileGB 2 -TopN 30

    # 2. 按报告勾选目标，写入 clean.json，批量清理（移入回收站，可还原）
    powershell -ExecutionPolicy Bypass -File scripts/clean-batch.ps1 -Manifest clean.json

    # 3. 清理后清空该盘回收站，空间才真正释放

## 实测效果

一次真实数据盘扫描（551 GB 机械盘，44 万文件，约 1 分钟）：
- 自动发现 11,913 个构建垃圾目录（按总量排序，避免碎片噪音）
- 定位 3.36 GB 的多年前的旧安装包、旧版本包缓存等大额可清项
- 正确识别 44 GB 的 pagefile.sys 为正常系统文件（用户迁移的虚拟内存），避免误报

## 脚本

| 脚本 | 用途 |
|---|---|
| scripts/scan-drive.ps1 | 参数化数据盘扫描：单次遍历多桶统计 |
| scripts/clean-batch.ps1 | 批量移入回收站：自动调配额 + 200/批 SHFileOperation + 锁定隔离 |
| scripts/find-lockers.ps1 | 通用锁定排查（服务/进程/命令行/独占打开试探，零预设应用） |
| scripts/recycle-stats.ps1 + recycle-bin-api.cs | 回收站真实占用 |

## 文档

- SKILL.md — Agent 主文档：数据盘与系统盘的原则差异、目标识别、SOP
- references/data-disk-targets.md — 目标识别手册：垃圾模式、例外情况、分级决策树
- references/pitfalls.md — 踩坑大全（与 c-disk-cleaner-pro 同源）

## 安全承诺

- 数据盘文件以 🟡 起步，宁可保守
- 虚拟磁盘/数据库/备份/媒体库永远只报告
- 全程回收站兜底，先报告后执行

## License

MIT