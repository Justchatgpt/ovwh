# P91 Player（91 播放器 iOS 重构版）

基于对 `F:\IPA\1on` 内全部工程（9orn1 / 9orn2 / p91-rex-widget 以及 pure_live、PiliPlus、AnimeFlow、AniBaka、mangayomi、animeko 等成熟播放器）的深度分析，重新实现的 **91 视频播放器**，以 **iOS（Flutter）** 为首要目标，同时代码可跨平台编译。

> 本项目为本地复刻/研究用播放器工程，数据层完全复刻原作对 91 站点的抓取与解析逻辑，未内置任何第三方服务端。

---

## 1. 它做了什么

- **数据源（91 契约）**：首页/分类/搜索/详情/直链解析，完整移植三套原作的解析算法：
  - 新版 `strencode2("…")` → URL 解码取 `<source src>`
  - 旧版 `document.write(strencode("<b64>","<key>",…))` → base64 + XOR + base64
  - 兜底扫描 `.mp4`（排除广告域名 `91p52.com/kwai.net/cdn77.org`）
- **反限制**：每次请求伪造随机 `X-Forwarded-For`，`level=7` 桌面 Cookie，进入站点前 `/index.php` 预热，命中"每天10次"文案自动换 IP 重试。
- **播放器**：`video_player`（iOS = AVPlayer）实现，带手势/倍速/画质/全屏/后台音频/恢复进度。
- **业务功能**：收藏、观看历史、断点续播、离线下载（暂停/继续/删除）、分类浏览、搜索、多镜像站点切换、深/浅色主题。

## 2. 功能对照（借鉴自其它播放器）

| 能力 | 来源参考 | 本项目落点 |
|---|---|---|
| 手势层：单击看/隐控制条、双击播放暂停、横向滑动 seek、左亮右音、长按 3x | animeko `PlayerGestureHost`、PiliPlus `pl_player` | `features/player/player_page.dart` |
| 播放内核抽象 / 多引擎可切换 | AnimeFlow `PlayerEngine`+`PlaybackCoordinator` | 预留 `PlayerBackend` 接口（见 §5 扩展） |
| 倍速 / 画质 / 线路选择菜单 | PiliPlus / pure_live | `_showSpeedSheet` / `_showQualitySheet` |
| 后台音频 + iOS 后台保活 | PiliPlus（`UIBackgroundModes=audio`、AVAudioSession） | `ios/Runner/AppInfo` + `AppDelegate.swift` |
| 来源适配器契约（list/detail/playurl/search） | pure_live `LiveSite`、mangayomi `ExtensionService` | `data/source/p91_api.dart`（对应契约） |
| 本地库：收藏/历史/进度/下载 | AniBaka Hive、mangayomi Isar | `core/storage.dart` + `data/repositories/library_repository.dart` |
| 断点续播、进度持久化 | 全部播放器通用 | `LibraryRepository.recordHistory` |
| 下载管理（暂停/续传/删除） | 9orn2 FileDownloader、PiliPlus 下载 | `features/download/download_service.dart` |
| 多镜像站点切换 | 9orn2 `Constants.BASE_URL` 轮换 | `SettingsController.setHost` |

## 3. 目录结构

```
lib/
  main.dart                       # 初始化 Hive + Provider 装配
  app/                            # MaterialApp / 主题
  core/                           # 常量、Hive 封装、设置
  data/
    models/                       # VideoItem / PagedResult / ResolvedSource / DownloadTask
    source/
      p91_parser.dart             # HTML 解析 + strencode/strencode2 解码
      p91_api.dart                # HTTP 客户端 + 反限制 + 解析编排
    repositories/                 # VideoRepository / LibraryRepository
  features/
    shell/  home/  category/  search/  detail/
    player/                       # 播放页（手势/倍速/画质/全屏）
    library/                      # 收藏 / 历史 / 下载
    settings/                     # 站点、倍速、主题、缓存
    download/download_service.dart
  shared/                         # VideoCard / PagedVideoGrid / StatusView / 工具
ios/
  Podfile  Runner/Info.plist  Runner/AppDelegate.swift
```

## 4. 数据源契约（91）

| 能力 | 端点 |
|---|---|
| 首页 | `GET /index.php`（`#tab-featured`） |
| 分类 | `GET /v.php?category={rf,hot,top,mf,md,long,longer,hd,ori,rp,tf,top1}&viewtype=basic&page=N` |
| 搜索 | `GET /search_result.php?search_id={kw}&search_type=search_videos&viewtype=basic&page=N` |
| 详情 | `GET /view_video.php?viewkey={key}` |
| 直链 | 详情页内 `strencode2(...)` / `strencode(...)` 解出 `.mp4`（play 时现取，绝不缓存签名） |

必需请求头（2026-11-13 在线实测，见 `_analysis/LIVE_VALIDATION.md`）：`User-Agent`（桌面）、`Referer: {host}/v.php?category=rf&viewtype=basic&page=1`（**用 `/index.php` 会让裸 viewkey 详情 404**）、`Cookie`（可选，`level=7` 不再是前提）。客户端 IP 头**只发 `X-Forwarded-For` + `X-Real-IP`**——加 `CF-Connecting-IP` 会被 Cloudflare 403。
媒体请求头：`Referer: {host}/`、`Origin: {host}`、同 UA/Cookie（实测 CDN 不校验，保留无害）。

## 5. 在 macOS 上构建 iOS

本仓库提交了 `lib/`、`pubspec.yaml`、`ios/` 的关键配置（Podfile / Info.plist / AppDelegate）。
Xcode 工程文件（`Runner.xcodeproj`）体积大且包含本机绝对路径，建议用官方命令生成后再覆盖配置：

```bash
# 1) 安装 Flutter 3.22+ 与 Xcode 15+
flutter --version

# 2) 在项目根目录生成缺失的平台脚手架（保留已有 lib/ 与 ios 配置）
cd p91_player_ios
flutter create --platforms=ios --org com.p91 --project-name p91_player .

# 3) 依赖 & Pods
flutter pub get
cd ios && pod install && cd ..

# 4) 真机 / 模拟器运行
flutter run -d <device-id>

# 5) 出包（需签名）
flutter build ios --release
# 或导出 ipa:
flutter build ipa --release
```

> 若 `flutter create` 覆盖了 `ios/Runner/Info.plist` 或 `AppDelegate.swift`，用本仓库同名文件重新覆盖即可（已配置 ATS 与后台音频）。

## 6. 扩展：接入更多引擎

`VideoRepository.resolve()` 返回 `ResolvedSource`；`PlayerPage` 只用 `video_player` 播放直链。若要像 AnimeFlow/pure_live 那样支持多内核（mpv / libmpv / IJK / fvp）与 HLS 分片，可把 `PlayerPage` 的 `_controller` 换成 `PlayerBackend` 抽象（`initialize/play/pause/seekTo/setSpeed/dispose`），在 iOS 默认 AVPlayer、需要 FLV/更多解封装时切 `media_kit`。此抽象已在分析报告 §6 给出接口草案。

## 7. 每日 10 次绕过（反限额）

91 对「游客」按 **(客户端 IP, Cookie 会话, UA)** 限流：当天打开 `view_video.php` 到上限后，页面返回「你每天只可观看10个视频」而不是播放源（参见 `9orn2` 的 `RandomIPAdderssUtils`、`PlayVideoPresenter.cleanCookies`，以及 app-release.apk 的浏览器化请求头）。

本 App 在 `data/source/` 实现了绕过引擎，**每次起播按次数轮换整套身份**：
1. 伪造客户端 IP 头：**仅 `X-Forwarded-For` / `X-Real-IP`**（实测这两个及组合均 200；`CF-Connecting-IP` 会触发 Cloudflare 403，已移除）；
2. User-Agent 池（10 条桌面 UA，源自 Kazumi `constants.dart`）；
3. `Accept-Language` 池（3 条）；
4. Cookie 轮换（时而只发 `language` 让服务端发全新游客会话）；
5. 镜像域名轮换（`91porn.com / 91.91p18.space / 91porn.work / 自定义`）；
6. **代理池**（真实出口 IP，`host:port` 每行一个，随机挑选）——当源站不再信任伪造 IP 头时，这是唯一可靠手段。

命中任一限额文案即判失败 → 换下一套身份重试（默认 8 次）；全部失败会在提示里打印**尝试记录**（host/代理/结果）。

**额外两条已实现的能力：**
- **已解析直链缓存**：解析成功的直链按 `viewKey` 缓存，有效期取自 URL 的 `e=`（-60s 安全边际；无 `e` 时 5 分钟），复播不重新解析、不消耗配额。代码 `lib/data/source/direct_link_cache.dart`。
- **WKWebView 兜底**：镜像返回 `Redirecting…`/Cloudflare 挑战时，用隐藏 WKWebView 执行其 JS 过盾、抓取真实页面并复用其 Cookie（`lib/core/challenge_solver.dart` + `ios/Runner/AppDelegate.swift`）。设置里可开关。

- 代码：[fingerprint.dart](lib/data/source/fingerprint.dart)、[proxy_pool.dart](lib/data/source/proxy_pool.dart)、[p91_api.dart](lib/data/source/p91_api.dart) 的 `resolveSource`
- 设置入口：**设置 → 反限额（每日 10 次）**：开关、代理池、最大尝试次数
- 说明：代理只作用于「抓取 `view_video.php` 解析直链」这一层；拿到直链后由 AVPlayer 直连 CDN 播放（带 Referer/UA 头）。

## 8. 用 GitHub Actions 生成 IPA（推荐，云端出包，无需 Mac）

仓库已带两套 workflow，**都能在 GitHub 的 macOS runner 上直接产出 `p91_player_unsigned.ipa`（未签名、可侧载）**：

| 文件 | 适用场景 |
|---|---|
| `.github/workflows/build-ios-ipa.yml`（本目录内） | 把 `p91_player_ios` 本身当一个 GitHub 仓库 |
| `../.github/workflows/build-ios-ipa.yml`（1on 根） | 把整个 `1on` 当一个仓库（`PROJECT_DIR=p91_player_ios`） |

**用法**：推到 GitHub → Actions → 选 “Build unsigned iOS IPA” → `Run workflow`（默认 unsigned），跑完在 run 页面的 **Artifacts** 下载 `p91-player-unsigned-ipa`。打 tag（`v1.0.0`）会自动附到 Release。

- **未签名**：`flutter build ios --release --no-codesign` → 手动 `Payload/` 打包成 ipa，用 **AltStore / Sideloadly / TrollStore** 自签安装。**不需要 Apple 账号/证书**。
- **已签名（可选）**：`Run workflow` 勾选 `signed=true`，并配置 Secrets：`BUILD_CERTIFICATE_BASE64`、`P12_PASSWORD`、`MOBILEPROVISION_BASE64`、`KEYCHAIN_PASSWORD`；把 `ios/ExportOptions.plist` 里的 `__TEAM_ID__` 换成你的 Team ID。
- workflow 里 `flutter create` 会重建 `Runner.xcodeproj`（本仓库不提交它），再覆盖回我们的 `Info.plist / AppDelegate.swift / Podfile`，因此无需本机 Xcode 工程。

## 9. 免责与合规

仅供个人学习与本地研究。所有目标站点、域名均视为本地测试夹具；请遵守所在地法律法规。
