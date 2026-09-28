# Pitfalls — Windows 磁盘清理实战踩坑大全

> 全部来自真实清理会话验证。每条 = 症状 → 根因 → 解法。动手前通读一遍可避免 90% 的失败。

## A. 回收站与文件删除

### A1. VB FileSystem.DeleteDirectory 回收站模式直接报错
症状：`The system call level is not correct`。
根因：`Microsoft.VisualBasic.FileIO.FileSystem.DeleteDirectory(..., RecycleOption)` 在部分 UAC/完整性级别环境下必然失败。
解法：改用 Win32 `SHFileOperation`（P/Invoke），`wFunc=3(FO_DELETE)` + `fFlags=FOF_ALLOWUNDO|FOF_NOCONFIRMATION|FOF_NOERRORUI|FOF_SILENT`。C# 定义见 `scripts/recycle-bin-api.cs`。

### A2. 大文件进回收站被静默永久删除
根因：Windows 回收站有每卷配额，超配额的删除请求不报错、直接永久删除。
解法：清理前把配额调大——
`HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\<vol>` 设 `MaxCapacity=102400`（MB）、`NukeOnDelete=0`。

### A3. 移入回收站后磁盘 free 不变
根因：回收站在同一卷上，文件只是换了目录，占用不变。
解法：这不是失败。真正的释放发生在用户清空回收站时。复核时要把"回收站当前占用"单独统计（用 SHQueryRecycleBin，见 A4）。

### A4. 枚举 C:\$Recycle.Bin 统计回收站大小得到 0
根因：`$Recycle.Bin\<SID>\` 子目录 ACL 拒绝枚举，`EnumerateFiles` 抛异常中断整个遍历，结果虚报 0。
解法：用 `SHQueryRecycleBin` Win32 API（`scripts/recycle-bin-api.cs`）。

### A5. SHFileOperation 返回非 0
| 返回码 | 含义 | 处置 |
|---|---|---|
| 124 (0x7C DE_INVALIDFILES) | 路径过长或非法字符 | 逐文件重试；仍失败的单独报告 |
| 120 (0x78 DE_ACCESSDENIEDSRC) | 源 ACL 拒绝 | 提权或跳过 |
| 32 (ERROR_SHARING_VIOLATION) | 文件被进程占用 | 关闭对应应用后重试 |
策略：先整批（200 路径/批，NUL 分隔）调用，失败再逐个隔离。整目录调用对深层缓存目录经常整体失败，批量逐文件几乎总成功（除锁定项）。

### A6. 逐文件删除太慢
实测 SHFileOperation 每次调用 ~6-25 文件/秒，万级文件要数十分钟。
解法：一次调用传 200 个 NUL 分隔路径（`string.Join("\0", paths)` + 末尾双 `\0`），速度提升约 100 倍。

### A7. "文件被占用"但找不到占用进程
根因：① 前一个后台清理任务自身持有句柄；② 服务级进程（SYSTEM）持有。
解法：枚举所有 powershell/pwsh 进程 CommandLine 确认无残留任务；服务用 `Stop-Service`（提权）而非杀进程。隔一段时间重试往往直接成功。

## B. PowerShell 环境

### B1. 内联命令的 $ 变量消失
`powershell -Command "...$var..."` 在很多宿主环境下 `$var` 被外层解析吞掉。
解法：一律写 .ps1 文件用 `powershell -File` 执行。绝不用长内联命令。

### B2. PowerShell 5.1 语法限制
不支持三元运算符 `? :`。脚本要兼容 Windows PowerShell 5.1（系统默认）。

### B3. 循环变量残留导致误删（最高危）
`$dn = Get-ItemPropertyValue $key -Name 'DisplayName' -ErrorAction SilentlyContinue` 失败时 `$dn` **保留上一轮循环的值**。在遍历注册表 Uninstall 键判断"是否目标软件"时，会把无关键（如 Windows 占位键 DirectDrawEx/DXM_Runtime）误判为软件残留并删除。
解法：循环体内第一行显式 `$dn = $null; $il = $null` 再赋值；判断条件同时校验多个字段。

### B4. 提权子进程输出丢失
`Start-Process -Verb RunAs -Wait` 的子进程 stdout 不回传。
解法：子脚本把结果 `Out-File` 到日志，父进程 `Get-Content` 读取。

### B5. 安全守卫拦截 Get-Content
部分环境对无 `-Encoding` 的 `Get-Content` 有写回风险守卫。
解法：读文件用 `Get-Content -Encoding UTF8` 或编辑器工具。

## C. Windows 功能与软件卸载

### C1. dism 启用功能后不重启 → 卸载器无限挂死
启用 WSL/Hyper-V/VMP 后，系统处于"功能已注册但服务未就绪"半初始化态（`wsl --version` 输出乱码、LxssManager 服务缺失）。此时运行依赖这些组件的卸载器/安装器（如 Docker Desktop Uninstall.exe），其清理钩子会无限等待，卸载窗口永远空白。
解法：**启用任何 Windows 可选功能后，先重启电脑，再做装/卸操作。** 挂起的卸载器可直接强杀（通常尚未删除任何文件）。

### C2. 官方卸载器静默模式秒退 ≠ 删干净
`Uninstall.exe /S` 可能 10 秒退出且目录原封未动。
解法：卸载后必须核验安装目录/服务/注册表 Uninstall 条目是否还在，残留用脚本补刀。

### C3. SYSTEM 服务进程杀不掉
`Stop-Process` 对以 SYSTEM 运行的服务进程无效（典型：厂商后台更新服务）。
解法：`Stop-Service <服务名>`（提权）。清完缓存记得把服务 `Start-Service` 拉回来、重启应用。服务名用 `Get-CimInstance Win32_Service | Where-Object { $_.PathName -match '<厂商关键词>' }` 定位。

### C4. 零数据判断四条件
判断某软件"可以放心硬清残留"需要同时满足：无 WSL 发行版（如适用）+ 无 vhdx/数据文件 + 无服务 + 无 Uninstall 注册表条目。任一不满足则先走数据迁移/备份。

## D. 数据迁移

### D1. 缓存迁移要设环境变量并实测
`HF_HOME/HF_HUB_CACHE/TORCH_HOME/MODELSCOPE_CACHE/UV_CACHE_DIR/PIP_CACHE_DIR/NPM_CONFIG_CACHE` 设置后：
- Machine 级要提权；广播 WM_SETTINGCHANGE 只影响新进程
- **必须实测**：跑一次真实落盘（如 `pip download six` 检查新目录增长），只看 `echo $env:X` 不算数
- `-UseNewEnvironment` 启动子进程在本机不可靠（8009001d）

### D2. 便携开发环境迁移三处同步
JDK/SDK/Gradle 类绿色环境整体搬迁时：环境变量、脚本内硬编码路径、项目内 `local.properties`（`sdk.dir`）三处必须同步更新；先杀 java/adb/gradle daemon。

### D3. 聊天软件数据位置以应用内配置为准
微信 4.x 的文件位置存在 `%APPDATA%\Tencent\xwechat\config\*.ini`（纯文本一行路径）；企业微信在注册表 `HKCU:\Software\Tencent\WXWork`。判断"是否需要迁移"先读配置，别靠猜。