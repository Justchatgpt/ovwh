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

## 更新记录

### v1.6.1
- 取流更稳更快：`resolveSource` 现在**优先在主域名多次重试**（轮换伪造 X-Forwarded-For 过每日限额），**只有主域名彻底失败才切换镜像**，避免一上来就撞到已失效镜像白等 12s。
- 列表防"错乱"：分类/首页记录**已见页的内容集合**，若某页与任一历史页内容完全相同（源站深页回绕），判定为**可浏览末尾**、停止前进并提示，不再显示重复的"错乱"内容。
- 详情页显示**真实发布时间**（详情 `title-yakov`）。

### v1.6.0
- 深度审计结论：① 源站实际是 **UTF-8**（无乱码，之前是我本地控制台误判）；② 取流主链路正常——详情页 `strencode2` 直链实测 `200 video/mp4` 可播，且直链**不绑定 IP**（伪造 XFF 抓详情后仍可播）。
- 修复 **详情页标题/封面解析失效**：活页面 `#viewvideo-title`/`#vid`/og:image 均不存在，改为 `#videodetails h4`（标题）、`video[poster]`（封面），并以 thumb 图与 `<title>` 兜底（去 " - 91porn" 后缀）。
- 随机页稳健性：**未进入「随机」tab 不预加载/不预取**；某条取流失败会**自动重新解析一次**；播放失败时**点画面可重试**。

### v1.5.2
- 修复「按月份浏览」**只显示几个视频**的问题（深度分析）：
  - 原因：旧版"滚到底自动连续拉取"一旦某天请求失败会**整批中断**，且起始只处理 2 天，早期日期稀疏时就只剩几条；缺显式加载入口。
  - 现改为**稳健分批加载**：起始至少凑够约一屏（约 30 条）才停；**每天独立抓取全部页、单天失败自动跳过继续**；提供明确的 **「加载更多」按钮** + 滚动自动补载；顶部显示「已加载 N 个」。
- 复查：源站网络对本机整体不可达（TCP 超时），无法本地再取数验证；逻辑已按上述重构。

### v1.5.1
- 修复**分类/首页翻页错乱**：此前按"每页视频数 ÷ 单页唯一数"做**块映射**，当"每页视频数"设成 >24 时，App 的"第19页"实际指向源站更深的页，翻页与网站页号对不上。现改为 **App 页码 = 源站页码（严格 1:1）**，跳 19 页就是源站第 19 页，往后翻即 20/21…，不再错位。
- "下一页"仍以"本页是否有内容"判断，翻到空页才停。

### v1.5.0
- 修复**分类页"跳转"后加载不出来**：之前用源站(可能错误偏小的)总页数去 `sp>total` 拦截，跳大页码直接空。现改为**按"本页是否有内容"继续**，可跳到任意页，不再被错误总页数卡死。
- 「按发布时间筛选」改为**按月份浏览**：选择年 + 月 → 自动逐日拉取**该月全部视频**、**无限滚动自动分页**、跨天去重；提供「本月 / 上月」快捷。

### v1.4.4
- 随机页**加速**：不再"一次只取 1 条"。一次日期检索的 ~24 条全部进入**候选池**，从池里轮流出片；池低于阈值才后台补，且**预取后续 3 条直链**。绝大多数滑动**无需网络**，基本即滑即播。

### v1.4.3
- 修复随机页"**向下滑不动**"：列表改为**无限下滑**（`PageView` 无边界），滑到已加载末尾会自动出现"加载中"页并继续随机取数；取数失败时该页有"点我重试"。
- 无论预取快慢，都不会再卡在最后一条。

### v1.4.2
- 随机视频新增**进度条（可拖动）+ 当前时间/总时长 + 播放/暂停**按钮，暂停时显示大播放键。
- **加载加速**：为后续随机视频**预取直链**（滑到下一条时几乎即播）；进入后先显示当前视频再后台预取后续。

### v1.4.1
- 「随机」页改为**真随机、覆盖全站历史（含早年作品）**：随机抽取 **2015 建站至今的任意日期** → 用日期检索拉取当天视频 → 随机取一条。空日期自动重新随机，保证总能取到。
- 不再局限于"评论最多"前若干页，随机范围扩大到整个归档（早年视频也会被随机到）。

### v1.4.0
- 新增底部「**随机**」标签页：进入即自动随机播放；**上下滑动**切换下一条随机视频；点击画面暂停/继续。
- 随机池取自「**评论最多(md)**」分类 → 随到的视频都是评论多的。
- 切到其它标签会自动暂停播放。

### v1.3.2
- 修复日期检索页「当天内翻页错误」：91 对超过末页的 page 会**重复返回最后一页**（而非空页），导致"下一页"看似无变化/错乱。现改用分页里的**下一页(`»`)链接是否存在**来判断末页，到末页即禁用"下一页"；去掉了不可靠的总页数显示。
- 结果：任意日期的当天结果都能正确从第 1 页翻到最后一页，往前/往后翻页不再出错。

### v1.3.1
- 日期检索页新增「**前一天 / 后一天**」日期级翻页，可自由在不同日期间前后浏览。
- 当天内翻页更自由：只要当前页有内容就允许"下一页"（不再受可能不准的总页数限制），到空页自然停止。

### v1.3.0
- 「按发布时间筛选」升级为**按日期检索全站历史**：使用源站 `search_result.php?search_type=date&search_id=YYYY-MM-DD`，**任意历史日期都能取到当天视频**（一年前 / 两年前亦可），并支持当天结果翻页。
- 之前"最近更新列表"只能回溯约两周的问题由此解决（改用日期检索接口访问归档）。
- 快捷标签：今天 / 3天前 / 7天前 / 一年前 / 两年前 现在都会真正返回对应日期的视频。

### v1.2.2
- 「按发布时间筛选」新增快捷标签：**一年前 / 两年前**（连同 今天 / 3天前 / 7天前）。
- 说明：源站「最近更新(rf)」实测仅能回溯约两周，深页会重复返回同一批内容，**拿不到一年前/两年前的视频**；点这些标签会定位到可回溯的最早一页并提示"超出可回溯范围"。

### v1.2.1
- 修复「按发布时间筛选」跳转错误：
  - 时间筛选页**仅使用「最近更新(rf)」**（`hot/top/mf/md/long…` 是按热度/时长排序，不按时间，之前选它们按日期定位必然错）。
  - 日期定位由**二分**改为**从第 1 页线性扫描到日期边界**（近期仅十几页），避免旧二分在同日期长区落入很深的错误页。
  - 目标日期早于现有内容时，明确提示并落到可获取的最早一页。

### v1.2.0
- 新增 **「按发布时间筛选」页**（首页右上角日历图标）：选择分类 + 日期 → 自动定位到最接近该日期的页直接浏览，可用「上一页 / 下一页」微调，底部显示该页约的发布日期。
  - 说明：源站列表页的发布时间被**字体加密**读不到，只有详情页有明文日期（`title-yakov`），故用「详情页日期 + 二分定位页」的方式实现，定位为**按页近似**。定位时需若干次请求，会显示进度。

### v1.1.3
- **修复分类只能翻到 10 多页**：旧逻辑取分页锚点的最大页码，而源站首页只显示 `1…10»`（最后一页锚点常缺），导致总页数被算成 ~10。现在改用页头「视频 1 - 24 共 N」的**总条数 ÷ 每页数**计算真实总页数，并取与锚点的最大值。
- **修复搜索无结果**：按真实搜索表单改用 `search_id` + `category` + `page`（不再强依赖旧的 `search_type`），并做多组参数回退；解析增加**通用锚点兜底**，可识别非标准列表结构。

### v1.1.2
- **彻底修复同页重复**：91 常把同一个视频发布到**多个 viewKey 且共用同一封面**，仅按 viewKey 去重不够。现按「**viewKey + 封面里的真实视频 id**」双重去重（任一相同即折叠）。
- 分页改为按**服务器页整块合并**（`k = ceil(每页数 / 单页唯一数)`），保证每页**无重复、也不漏条**；跳页仍只需拉取 k 个服务器页，很快。

### v1.1.1
- 修复**同一页重复视频**：91 列表页会把同一视频重复渲染多张卡（实测 44 卡/24 唯一），现按 `viewKey` 去重，每页只显示唯一视频（还原站点真实 24/页），分页计数也正确。

### v1.1.0
- 列表改为**分页浏览**：底部「上一页 / 下一页 / 第 x/y 页 / 跳转」，可直接跳到很早的页，方便找以前的视频。
- 新增设置项 **设置 → 列表 → 每页视频数**（10 / 20 / 30 / 50 / 100）：一次显示多少条；受源站每页条数限制时，App 会自动跨多页拼够数量，不丢条目。

## 9. 免责与合规

仅供个人学习与本地研究。所有目标站点、域名均视为本地测试夹具；请遵守所在地法律法规。
