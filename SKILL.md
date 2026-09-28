---
name: data-disk-cleaner
description: Windows 数据盘（D:/E:/F: 等非系统盘）安全清理与空间回收流程。参数化驱动器扫描→分类报告（安装包残留/项目构建垃圾/虚拟机磁盘/旧归档/重复文件）→批量回收站清理→复核，绝不硬删除。当用户提到 D盘满了、F盘清理、数据盘清理、清理下载目录、安装包清理、项目垃圾清理、node_modules 清理、虚拟机磁盘、旧文件归档、清理某个盘、磁盘空间分析某个盘，或要求对非系统盘做空间审计时，都应使用本 skill。与 c-disk-cleaner-pro（系统盘清理）互为姊妹篇，同样基于 kunlun-pc-cleaner（第三方 skill）的分级处置框架。
---

# Data Disk Cleaner — Windows 数据盘安全清理

> **出处声明**：沿用第三方 skill **kunlun-pc-cleaner** 的分级处置框架（只读扫描→哈希比对→风险分级→移入废纸篓），与姊妹 skill **c-disk-cleaner-pro**（系统盘清理）共享清理引擎与安全原则，聚焦非系统数据盘的特殊目标。

## 数据盘与系统盘的原则差异

1. **数据盘上几乎没有"绝对安全"的文件**——用户是主动把数据放这里的。🟢 绿区只限"机器生成的可再生内容"（构建产物、缓存、解压后的安装包），其余一律 🟡 起步。
2. **回收站按卷独立**：每个盘有自己的回收站和配额，清盘前同样先调大该卷配额。
3. **虚拟磁盘 = 用户资产**：`*.vhdx/*.vmdk/*.vdi/*.qcow2` 可能是虚拟机/WSL/Docker 的整块磁盘，删除等于删整个系统，永远只报告。
4. **大媒体/模型/备份文件只报告**：音色库、模型权重、备份归档是用户花钱换来的数据，分级为 🔴，除非用户点名。
5. **硬链接与 junction 计数陷阱**：同一文件可能被多个项目引用，删除前确认引用关系。

## 目录处理目标（数据盘特有）

| 目标类别 | 识别模式 | 分级 | 动作 |
|---|---|---|---|
| 安装包残留 | `*.zip/*.7z/*.rar/*.iso/*.exe/*.msi` 且 >100MB、mtime 老于阈值，或同目录已存在解压产物 | 🟡 | 确认后清 |
| 项目构建垃圾 | `node_modules/target/dist/build/out/obj/bin/__pycache__/.venv/.pytest_cache` | 🟢 | 可直接清（可由包管理器重建） |
| 虚拟机磁盘 | `*.vhdx/*.vmdk/*.vdi/*.qcow2/*.img` | 🔴 | 只报告，附"最后使用时间" |
| 旧归档/旧导出 | mtime > 阈值的媒体/文档目录 | 🟡 | 用户逐项确认 |
| 重复文件 | SHA-256 相同、>100MB | 🟡 | 每组保留一份 |
| 压缩包内已解压 | 同名目录与同名压缩包并存 | 🟡 | 保留哪个由用户定 |
| 本盘回收站 | 每卷独立，SHQueryRecycleBin 查询 | 🟢 | 用户清空 |
| 用户重要资产 | 备份、音色库、模型权重、照片视频库 | 🔴 | 只报告不动 |

## 操作流程（SOP）

### Step 1 — 参数化扫描

    powershell -File scripts/scan-drive.ps1 -Drive F: [-OldDays 180] [-BigFileGB 1] [-TopN 20]

输出：驱动器现状 → Top 目录 → 安装包清单 → 项目垃圾目录清单 → 虚拟磁盘 → 大文件 → 旧文件 → 本盘回收站占用。**只读。**

### Step 2 — 分级报告交用户确认

按文末模板。数据盘的报告要**宁可保守**：拿不准的一律 🟡 并附"最后使用时间"。

### Step 3 — 回收站配额

对目标卷执行配额防护（`MaxCapacity=102400`、`NukeOnDelete=0`，clean-batch.ps1 自动做）。

### Step 4 — 锁定预检

    powershell -File scripts/find-lockers.ps1 -Path "F:\some\target"

数据盘常见锁定者：虚拟机（vhdx/vmdk 被 hypervisor 挂载）、正在运行的 IDE（项目文件）、下载器（未完成的下载）、资源管理器预览窗口。

### Step 5 — 批量清理

    powershell -File scripts/clean-batch.ps1 -Manifest clean.json

与系统盘同一引擎：批量 SHFileOperation → 回收站 → 失败降级隔离。

### Step 6 — 复核与提醒

复核该盘 free；提醒用户清空**该盘**的回收站。

## 项目垃圾清理细则（最高频需求）

构建垃圾是数据盘上最常见的可再生空间，但有例外：

- `node_modules` → 🟢 可删（`npm install` 重建）。若项目离线/内网部署，先确认有 lockfile 和缓存。
- `target`（Rust/Maven）、`dist`/`build`/`out` → 🟢 可删，除非是**发布产物**（检查是否有版本号/日期命名的最终产物）。
- `.venv`/`venv` → 🟢 可删（pip 重建），内网环境先确认有离线包。
- `.gradle` → 🟡 默认可删，但如果它就是用户的 `GRADLE_USER_HOME`（全局缓存仓库），删了要重下全部依赖——先查环境变量。
- `bin/obj`（C#）→ 🟢 可删。
- 判据：**目录的父级是否是源码项目**（有 `.git`/`package.json`/`pom.xml`/`Cargo.toml`）。孤立的 `dist` 目录可能是网站部署产物，标 🟡。

## 参考文件

| 文件 | 何时读 |
|---|---|
| `references/data-disk-targets.md` | 识别目标类别、垃圾模式与例外情况 |
| `references/pitfalls.md` | 删除/迁移操作动手前必读（与 c-disk-cleaner-pro 同源） |

## 脚本清单

| 脚本 | 用途 |
|---|---|
| `scripts/scan-drive.ps1` | 参数化数据盘扫描（本 skill 主力） |
| `scripts/clean-batch.ps1` | 批量回收站清理（配额防护 + 200/批 + 锁定隔离） |
| `scripts/find-lockers.ps1` | 通用锁定排查（参数化路径，无预设应用） |
| `scripts/recycle-stats.ps1` + `recycle-bin-api.cs` | 回收站真实占用 |

## 报告输出模板

    ## 数据盘清理报告：F:（日期）
    ### 空间现状
    F: 总 XXX GB，free XX GB
    ### Top 目录
    | 目录 | 大小 |
    ### 🟢 可直接清（构建垃圾/缓存）
    | 路径 | 大小 | 类型 |
    ### 🟡 需确认（安装包/旧文件/重复）
    | 路径 | 大小 | 最后使用 |
    ### 🔴 只报告不动（虚拟磁盘/资产）
    | 路径 | 大小 | 最后使用 |
    ### 执行结果 & 待用户操作

## 致谢

- **kunlun-pc-cleaner**（第三方 skill）— 分级处置框架源自该 skill。
- **c-disk-cleaner-pro**（姊妹 skill）— 清理引擎与其同源，本 skill 聚焦数据盘目标。