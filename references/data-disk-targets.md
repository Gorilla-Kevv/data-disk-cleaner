# Data Disk Targets — 数据盘清理目标识别手册

## 目标识别与例外

### 1. 构建垃圾（🟢 最高频）

| 目录名 | 归属 | 重建方式 | 例外情况 |
|---|---|---|---|
| node_modules | Node.js | npm/pnpm install | 内网部署项目先确认离线源 |
| target | Rust / Maven / Java | cargo build / mvn package | 确认不是发布产物目录 |
| dist / build / out | 各种打包器 | 重新构建 | 孤立的 dist 可能是网站部署产物 → 🟡 |
| obj / bin | C#/.NET | dotnet build | — |
| __pycache__ | Python | 自动生成 | — |
| .venv / venv | Python | pip install | 内网环境确认离线包 |
| .pytest_cache / .mypy_cache / .ruff_cache | Python 工具 | 自动生成 | — |
| .next / .nuxt | 前端框架 | 重新构建 | — |

**归属判据**：向上找父级是否有 `.git` / `package.json` / `pom.xml` / `Cargo.toml` / `*.sln`。有 → 项目内构建垃圾 🟢；没有 → 可能是部署产物或独立数据 🟡。

**统计陷阱**：`node_modules` 内部还有 `dist`/`build`/`test` 子目录，扫描器会重复报告——按最外层命中去重，只统计一次。

### 2. 安装包与压缩包（🟡）

识别：`*.zip/*.7z/*.rar/*.iso/*.exe/*.msi/*.tar*.gz` 且 >100MB。
检查清单：
- 同目录/近邻是否存在**同名解压目录** → 已解压，包可清
- 压缩包内含 `setup.exe`/`installer` → 软件安装包，装完可清
- 用户下载目录（BaiduNetdiskDownload、Downloads 类）+ mtime 很老 → 典型清理对象
- ⚠️ 音色库/游戏资源常以大压缩包形态存在且**必须保留在原地**（程序直接读包）→ 看 mtime 和同目录是否有解压版

### 3. 虚拟磁盘（🔴 永远只报告）

`*.vhdx/*.vhd`（Hyper-V/WSL/Docker）、`*.vmdk`（VMware）、`*.vdi`（VirtualBox）、`*.qcow2`（QEMU）。
删除 = 删除其中整个操作系统/所有镜像。处置：报告路径/大小/最后使用时间，让用户决定迁移（wsl --export 或虚拟机软件自带迁移）还是删除。

### 4. 应用缓存类（🟢/🟡）

数据盘上常见的机器生成内容：
- 网盘下载缓存、视频/音乐软件缓存目录（注意与用户主动下载的音乐/视频区分——通常 `Cache` 子目录可清，`Download` 子目录是用户资产）
- 备份软件的版本快照目录
- 数据库导出/转储（`.sql`/`.bak`/`.dump`）→ 🟡，可能是唯一备份

### 5. 本盘回收站与系统目录

- `<盘>:\$Recycle.Bin`：每卷独立，SHQueryRecycleBin 查询真实占用，由用户清空
- `<盘>:\System Volume Information`：系统还原/VSS，磁盘清理工具管理，手动删会破坏系统保护
- `<盘>:\pagefile.sys` / `swapfile.sys`：如果用户把虚拟内存移到了该盘（常见于给 C 盘减负），这是**正常的**，不要当垃圾报告；大小会随内存压力波动

## 分级决策树

```
目标文件/目录
├─ 是构建垃圾目录名，且父级是源码项目？        → 🟢 直接清
├─ 是缓存/临时/日志/更新残留？                 → 🟢 直接清
├─ 是虚拟磁盘/数据库/备份/音色库/模型/照片？   → 🔴 只报告
├─ 是安装包且已解压/已安装？                   → 🟡 确认后清
├─ mtime 很老且 >100MB？                       → 🟡 确认后清
└─ 拿不准                                     → 🟡 附最后使用时间，交用户
```

## 实测参考值（供预期管理）

来自一次真实数据盘扫描（551 GB 机械盘，44 万文件）：
- 单次遍历约 1-2 分钟（机械盘），SSD 更快
- 构建垃圾 11,913 个目录但总量仅 1.68 GB（site-packages 里的碎片 __pycache__）——垃圾目录数量多 ≠ 空间大，报告必须按总量排序
- 最大可清项往往是：老安装包（单文件 3+ GB）、旧版本包缓存（如 conda clean 场景）、多年前的旧下载
- 数据盘上注意 pagefile.sys/swapfile.sys：用户把虚拟内存迁到该盘后它们是正常的系统文件