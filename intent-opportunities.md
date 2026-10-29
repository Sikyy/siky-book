# 已阅 App Intents 机会报告

截至 2026-10-29（`source-compat` 分支，提交 `c153bf6`；工作区另有未提交改动，见“项目与分析范围”），已阅声明 **0 个 App Intents 动作**，没有声明 Shortcuts、App Shortcuts、Spotlight、Siri、小组件或控制中心入口，也没有采用任何 Apple Intelligence schema。

## 现有 App Intents 清单

| 业务动作 | Intent / Shortcut / Entity / Query 路径与符号 | 当前接线 | 缺失 / 证据限制 |
| --- | --- | --- | --- |
| 无 | 在 `YiYue/`、`YiYueTests/` 搜索 `AppIntent`、`AppShortcutsProvider`、`AppShortcut`、`AppEntity`、`EntityQuery`、`IndexedEntity`、`AppSchema`、`CSSearchableIndex`、`NSUserActivity`、`onAppIntentExecution`，结果均为 0 | 没有 App Intents 目标、provider、entity、query、schema 或 Spotlight 内容索引 | 这是源码搜索结论，不代表 Shortcuts/Siri 的系统可见性；当前没有可被系统发现的动作 |

搜索范围是 `YiYue/` 与 `YiYueTests/` 下全部 Swift 文件，并检查了 `YiYue/App/Info.plist`、`project.yml` 和已提交的 `YiYue.xcodeproj/project.pbxproj`。工程中没有 App Intents extension、widget extension 或 Siri entitlement，这符合“所有 App Intents 放在主 App target”的要求；但主 target 也还没有任何 Intent 声明。

## 项目与分析范围

- 项目：已阅（YiYue），现有 iOS 小说阅读器，SwiftUI + SwiftData；支持 Legado 书源、书源搜索、本地 txt/epub 导入、阅读器分页、章节缓存和换源。
- 分析日期：2026-10-29。
- 代码基线：分支 `source-compat`，提交 `c153bf63166fcc5b0d18636176c577f3b0d5d0b3`；分析开始时工作区干净，落盘前发现下述未提交改动。本报告以 `c153bf6` 加工作区快照评估；涉及目录刷新的结论以工作区为准。版本 `1.0.5`，构建号 `4`，bundle `com.mistyislet.yiyue`。
- 相关未提交改动（本报告没有修改这些文件）：`YiYue/Services/SourceEngine.swift` 新增 `TocMerger`；`YiYue/Views/Reader/ReaderView.swift` 新增 `refreshTableOfContents()`；`YiYue/Views/Reader/ReaderMenuOverlay.swift` 新增 `TocRefreshOutcome`、`onRefreshToc`、`updateToc()` 与目录搜索；`YiYue/Views/Reader/ChapterListView.swift` 被删除，目录列表合并进 `ReaderMenuOverlay`；`YiYue.xcodeproj/project.pbxproj` 增加 `TocMergerTests.swift`；新增未跟踪的 `YiYueTests/TocMergerTests.swift`。这些改动没有提交，也没有在本环境编译或运行。
- 分析原因：在实现 App Intents 前做产品机会评估和排序。仓库中没有上一版 `intent-opportunities.md`，这是首次分析。
- 需求与实际实现的对照：仓库只有阅读器设计/计划文档（`docs/superpowers/specs/2026-05-20-novel-reader-design.md`、`docs/superpowers/plans/`）和书源对接说明（`docs/novel-library-integration.md`），没有 App Intents 需求文档。本次以已提交代码和上述工作区改动为准，不把设计文档里的未实现内容当作现有能力；工作区改动单独标注，不混同为 `c153bf6` 的能力。
- 主要检查的代码：
  - 入口与书架：`YiYue/App/YiYueApp.swift`、`YiYue/Views/ContentView.swift`、`YiYue/Views/Bookshelf/BookshelfView.swift`、`BookshelfItem.swift`、`SeriesBookView.swift`、`BookManager.swift`。
  - 阅读器：`YiYue/Views/Reader/ReaderView.swift`、`ReaderMenuOverlay.swift`、`YiYue/Models/Chapter.swift`、`Book.swift`、`ReaderSettings.swift`；`c153bf6` 的 `ChapterListView.swift` 在工作区已删除并合并进 `ReaderMenuOverlay`。
  - 搜索与导入：`YiYue/Views/Search/SearchView.swift`、`SourceSelectView.swift`、`AddBookView.swift`、`YiYue/Services/SearchService.swift`、`ImportService.swift`、`SourceImportService.swift`、`SourceEngine.swift`。
  - 书源与缓存：`YiYue/Views/Sources/SourceListView.swift`、`YiYue/Views/Bookshelf/ChangeSourceView.swift`、`YiYue/Services/ChapterDownloadManager.swift`、`ChapterContentStore.swift`、`ChapterDownloadSystemTask.swift`。
- 未完整阅读的部分：`ReaderView.swift` 共 3,439 行，本次只阅读了与本报告相关的初始化、章节切换、进度保存、缓存入口和导航状态；没有逐行审计排版、手势和横向翻页实现。`CacheManageView.swift`（1,141 行）和 `ChangeSourceView.swift`（963 行）只阅读了入口与关键服务调用，没有逐行审计所有错误分支。
- 环境限制：本次分析所在环境没有 Xcode、iOS SDK、`xcodebuild` 或模拟器，无法编译、运行、查看 `Metadata.appintents`、验证 Shortcuts 磁贴、Spotlight 索引或 Siri。下面的 API 版本来自 2026-10-29 抓取的 Apple Developer Documentation；本地 SDK 声明未能核对，所有“可运行”结论都只到文档层。

| 目标 / 配置 | 相关源 | 部署目标 | SDK / 工具链证据 | 未知 |
| --- | --- | --- | --- | --- |
| `YiYue`（application） | `YiYue/**`；`project.yml`；`YiYue.xcodeproj/project.pbxproj` | iOS 17.0（`IPHONEOS_DEPLOYMENT_TARGET = 17.0`） | 本机无 Xcode/SDK；pbxproj 中 `SDKROOT = iphoneos`、`SWIFT_VERSION = 5.9`；`.airbuild/airbuild.yaml` 用 `airbuild-xcode archive` | 实际 Xcode 版本、iOS SDK 版本、App Intents 元数据生成、编译结果均未验证 |
| `YiYueTests`（unit-test bundle） | `YiYueTests/**` | 随项目，iOS 17.0 | `SWIFT_VERSION = 5.0`；测试代码构造独立 `ModelContainer` | 未运行测试 |

`YiYue/App/Info.plist` 声明了 `UIBackgroundModes = processing` 和两个 `BGTaskSchedulerPermittedIdentifiers`（章节缓存），但该后台能力只用于现有缓存队列，不等于任意 App Intent 都能后台执行。网络层允许 `NSAllowsArbitraryLoads = true`，书源是外部不可信内容；这一点会影响任何“让 Siri/Shortcuts 触发网络搜索或导入”的设计。

## 决策摘要

建议首批做 **3 个普通 App Intent**，按顺序：

1. **继续阅读**：无参数，打开最近在读的书，回到保存的章节和页内位置（E01、E02、E03、E08）。
2. **打开书籍**：按书名/作者选择一个书架里的 `Book`，回到该书保存的阅读位置（E04、E05、E06、E07、E08、E09）。
3. **搜索书籍**：把关键词带进现有书源搜索界面；Intent 本身不等待网络结果（E01、E02、E03、E08）。

理由：这三个动作覆盖“打开书 → 继续读 → 找下一本”的主循环，都是现有已实现能力；继续阅读和打开书籍只读本地 SwiftData，搜索只做导航和预填，不需要在 `perform()` 里跑 9 路并发网络请求；三者都不需要登录、支付或危险写入，适合先做小批次。首批的共同前置改造是共享 `ModelContainer`、前台路由和 `ReaderView`/`SearchView` 的初始参数，这部分比单个 Intent 的声明更花时间。

首批边界：

- **普通路径（建议实施）**：`AppIntent`、`AppShortcutsProvider`、`AppShortcut`、`AppEntity`、`EntityStringQuery`、`OpenIntent`、`openAppWhenRun` 都有 iOS 16 的文档可用；项目部署目标 17.0，普通路径可以覆盖。首批不使用 `supportedModes`、`TargetContentProvidingIntent`、`onAppIntentExecution`（它们从 iOS 26 开始），也不使用 `IndexedEntity` 或任何 schema。
- **可选增强（不在首批）**：`.system.search`（iOS 18，Siri + Shortcuts）、`.system.open`（iOS 27，Siri + Shortcuts）、`IndexedEntity`/`CSSearchableIndex.indexAppEntities`（iOS 18）以及 `books` 域 schema。它们都需要额外 SDK、运行时和真机验证；`books` 域的 `openBook`/`search` 在文档中只列 Shortcuts，不把它当作 Siri/Apple Intelligence 收益。
- **需要产品决策**：搜索动作是“打开搜索页并自动搜”还是“只预填、让用户点搜索”；是否接受把书名/作者索引进 Spotlight（已阅没有应用锁，Spotlight/Siri 可能暴露书名）；工作区里的“更新目录”是否转正并服务化，以及是否投入阅读统计。
- **尚未验证**：没有编译、没有 Shortcuts/Spotlight 磁贴检查、没有 Siri 真机、没有 iOS 27 新 Siri 运行。首批是“文档路径可用”的产品建议，不是“已验证可运行”的集成。
- **近期待定第 4 项**：工作区已出现“更新目录”实现（`ReaderView.refreshTableOfContents()`、`TocMerger`、`ReaderMenuOverlay.updateToc()`），但它未提交、未编译，逻辑仍在视图内。若它在提交前通过构建和 `TocMergerTests`，可把“检查更新”作为第 4 个候选；仍需先抽成服务，不能直接把私有视图方法当 Intent 业务层。

## 已评估动作

### 继续阅读 — 从上次停下的位置继续

- **业务状态**：已实现。
- **代码链**：
  - UI 入口：`YiYue/Views/Bookshelf/BookshelfView.swift` 的 `BookshelfView` 用 `@Query(sort: \Book.addedDate, order: .reverse)` 取书架，`groupedItems` 调用 `BookshelfItem.sortedByRecentRead`；点击封面设置 `selectedBook`，再由 `.fullScreenCover(item: $selectedBook)` 打开 `ReaderView(book:startChapterIndex: book.lastReadChapterIndex, startPosition: book.lastReadPosition)`。
  - 业务函数：`YiYue/Views/Reader/ReaderView.swift` 的 `init(book:startChapterIndex:startPosition:)` 把 `startChapterIndex` 写入 `currentChapterIndex`，把 `startPosition` 写入 `restorePositionFraction`；`loadChapters()` 读取 `book.chapters`；`persistReadingPosition()` 和 `chapterPositionFraction` 在翻页/退出时保存章节内比例。
  - 数据与持久化：`YiYue/Models/Book.swift` 的 `@Model final class Book` 有稳定的 `id: UUID`、`lastReadChapterIndex`、`lastReadPosition`、`lastReadDate`、`readingStatus`、`totalChapters`；`YiYue/Services/BookManager.swift` 的 `updateProgress(book:chapterIndex:position:)` 写入这些字段并设置 `lastReadDate`。
  - 现有 Intent：无。
- **判定**：**推荐**。这是阅读器最高频、最直接的“从系统入口回到内容”的动作，且不依赖网络。
- **方向**：
  - 提议类型 `ContinueReadingIntent: AppIntent`（名称是提案，不是现有代码），无参数；`title` 用“继续阅读”。
  - 选择规则建议：优先 `lastReadDate` 最新的 `Book`；没有阅读记录时按 `addedDate` 最新的书开始，与书架“最近优先”一致；并列时用 `addedDate` 再按 `title` 稳定排序。书架为空时返回用户句“书架里还没有书”，而不是静默失败。以上是新增的查找/兜底规则，需要作为提案实现。
  - 打开时使用该书保存的 `lastReadChapterIndex` 和 `lastReadPosition`；重复执行不改变阅读进度，除非 `ReaderView` 自身在退出/翻页时保存，这是现有行为。
  - 已读完的书仍打开最后位置，不自动跳到下一部；系列书按具体 `Book` 选择，不按 `seriesName` 聚合。是否推进到系列下一部需要产品另行决定。
  - 前台运行：Intent 需要把 App 带到前台并让 `BookshelfView` 呈现 `ReaderView`。可以只把“继续阅读”意图交给共享路由，书目选择在视图层完成，从而避免 Intent 直接查库；但 Siri 对话若想报出书名，就需要在 Intent 中读取共享容器。两种方案的成本差异见下。
- **访问与安全**：本地 SwiftData，无登录、无账号范围、无设备认证要求；只读选择加现有进度写入，不是破坏性动作。书名可能被 Siri 朗读或在 Spotlight 显示，已阅没有应用锁；如果书名本身敏感，对话应使用“继续上次阅读”而不报书名。书目可能在解析后被删除，执行时必须按 `id` 重取并给出“这本书已不在书架”的失败句。
- **普通路径**：`AppIntent`（iOS 16）+ `AppShortcut`（iOS 16）+ `openAppWhenRun`（iOS 16，iOS 26 起弃用但未移除）+ App 内共享路由。部署目标 17.0 下不能用 `supportedModes` 或 `TargetContentProvidingIntent`；`supportedModes` 只作为 iOS 26 以上的可选分支。证据见 E01、E02、E03、E08，E09、E20、E21 仅作 26+ 备注。
- **Schema 增强**：不适用。`.system.open` 需要 `target` 实体，而“继续阅读”没有用户选择的实体；`books.openBook` 同样需要 `BookEntity`。不要为了“继续阅读”硬造一个无意义的 target。
- **系统入口**：Shortcuts 动作和 Spotlight 快捷指令磁贴由 `AppShortcut` 提供；Siri 可用短语触发；Action button、锁定屏幕、控制中心由用户自行分配；内容级 Spotlight（在 Spotlight 里直接看到书名）不在本动作内，需要额外索引。
- **优先级与成本**：#1；**S–M**。如果书目选择和对话框都在 Intent 内完成，需要共享容器（M）；如果选择放到视图层，可做到 S，但 Siri 对话只能给通用回复。
- **验证与下一步**：已核对 Apple 文档的 `AppIntent`、`AppShortcutsProvider`、`AppShortcut`、`openAppWhenRun` 可用版本；未编译、未在 Shortcuts/Spotlight/Siri 运行。下一步是在 iOS 17.0 模拟器构建后，用 App 内 debug 入口直接调用 `perform()`，确认打开的是正确书籍和位置，再在真机验证 Siri 短语。

### 打开书籍 — 按书名打开指定书

- **业务状态**：已实现（书籍数据和阅读位置都已存在；缺的是按名称查找和系统入口）。
- **代码链**：
  - 数据：`YiYue/Models/Book.swift` 的 `Book` 有 `id`、`title`、`author`、`seriesName`、`seriesIndex`、`lastReadChapterIndex`、`lastReadPosition`；`Book.chapters` 与 `Chapter` 有 SwiftData 关系。
  - UI：`BookshelfView` 的封面点击和 `selectedBook` 已经能打开 `ReaderView`；`BookshelfItem.group` 与 `SeriesBookView` 只影响展示，不改变 `Book` 身份。
  - 现有查找：没有按书名查询书架的公开服务；`SearchService` 搜索的是启用的 `BookSource`，不是本地书架。`AddBookView` 的 `AddBookPersistenceWorker` 负责新增，不负责查找。
  - 现有 Intent：无。
- **判定**：**推荐**。比“继续阅读”更适合书名明确、书架里有多本书的场景；和继续阅读共享同一套路由和阅读位置逻辑。
- **方向**：
  - 提议 `BookEntity: AppEntity`，`id: UUID`（直接用 `Book.id`，跨重启稳定），`title`、`author`、`seriesTitle` 作为显示字段；`typeDisplayRepresentation` 用“书籍”，`displayRepresentation` 建议“书名 · 作者”，避免同名书只显示书名。
  - 提议 `BookEntityQuery: EntityStringQuery`：`entities(for:)` 按 UUID 取；`suggestedEntities()` 返回最近阅读/最近加入的 8 本，不能返回全部；`entities(matching:)` 对 `title` 和 `author` 做大小写/全半角/变音符不敏感匹配，返回有上限的候选（例如 20 本）。
  - 提议 `OpenBookIntent: OpenIntent`，`target: BookEntity`；`perform()` 按 `id` 重取 `Book`，打开该书的 `lastReadChapterIndex` / `lastReadPosition`。若书已被删除，返回“这本书已不在书架”，不要创建新书。
  - 歧义处理：同名/同作者多本时让系统从多个实体中选择，不能静默取第一本；`suggestedEntities()` 只给最近项，`entities(matching:)` 才做全量匹配。重复执行只打开，不新增、不修改书籍。
- **访问与安全**：本地数据；无登录、无账号范围、无设备认证；打开是只读导航，现有阅读器会更新 `lastReadDate` 和位置，这属于正常阅读行为。书名/作者会被 Siri 朗读，隐私考虑同“继续阅读”。如果后续支持删除/修改，必须另做确认，不要塞进 `OpenBookIntent`。
- **普通路径**：`AppEntity`（iOS 16）+ `EntityQuery`/`EntityStringQuery`（iOS 16）+ `OpenIntent`（iOS 16）+ `OpenIntent.target`（iOS 16）+ `openAppWhenRun`（iOS 16）。`OpenIntent` 的 `target` 是必需属性，正好对应本书。`AppShortcut` 的实体参数短语在书架增删后需要调用 `AppShortcuts.updateAppShortcutParameters()`（iOS 16），否则 Siri/Spotlight 的候选可能过期。证据见 E04、E05、E06、E07、E08、E09。
- **Schema 增强**：
  - `.system.open`（iOS 27，Siri + Shortcuts）是语义最接近的增强：`OpenIntent` + `target: any AppEntity`，可以让 iOS 27 新 Siri 按实体打开书。但它需要 iOS 27 SDK 和 `@available(iOS 27, *)`；项目目标 17.0，不能把它放进首批。
  - `.books.openBook`（iOS 18）也能映射 `BookEntity`，但文档的 system experiences 只列 Shortcuts，不列 Siri；对“让 Siri 打开书”没有额外收益，反而多一层 schema 约束。不建议首批采用。
  - `.books.book` 实体 schema 的字段（`title`、`author`、`seriesTitle`、`url`）与 `BookEntity` 基本吻合，但同样只服务 Shortcuts；可作为后续统一 schema 的选项，不作为首批。
- **系统入口**：Shortcuts 的“打开书籍”动作；Siri 通过带参数的 App Shortcut 短语询问书名；Spotlight 快捷指令磁贴；内容 Spotlight 和语义 Siri 需要额外的 `IndexedEntity`/索引，见“后续可选”。`OpenIntent` 本身是系统打开动作的协议，不等于已保证 Siri 会主动推荐。
- **优先级与成本**：#2；**M**。成本主要不在 Intent 声明，而在共享 `ModelContainer`、`BookEntityQuery`、路由，以及书架增删后的快捷指令参数更新。
- **验证与下一步**：文档核对通过；未编译。需要重点测试：同名书是否出现消歧、书名含中英文/空格/标点时 `entities(matching:)` 是否命中、删除书后执行是否给用户句、`updateAppShortcutParameters()` 是否在增删后调用。

### 打开章节 — 跳到指定章节

- **业务状态**：已实现（章节列表选择 + 阅读器章节状态）；缺的是按章节名/序号从系统入口打开。
- **代码链**：`YiYue/Models/Chapter.swift` 的 `@Model final class Chapter` 有 `id: UUID`、`book: Book?`、`index: Int`、`title`、`sourceURL`；`YiYue/Views/Reader/ReaderMenuOverlay.swift` 的 `chapterList` 点击章节时设置 `currentChapterIndex = chapter.index` 并关闭目录；`ReaderView` 的 `.onChange(of: currentChapterIndex)` 负责加载章节、更新进度并重置分页。工作区还新增了目录内章节搜索（`chapterSearch`/`filteredChapters`），但这是 App 内 UI，不是 Intent。
- **判定**：**不推荐首批**。对“直接跳到某一章”有中等价值，但章节序号/标题在不同书源和版本可能不一致；语音通常要同时指定书名和章节（两个参数），而一个 App Shortcut 短语只能自然承载一个参数，Siri 会多轮追问；Shortcuts 更合适，但优先级低于“打开书籍/继续阅读”。
- **方向（若以后做）**：提议 `ChapterEntity`（`bookID` + `index` + `title`，`id` 建议用 `Chapter.id` UUID）和 `OpenChapterIntent`，参数为 `BookEntity` + `ChapterEntity`；按 `index` 定位，标题作为显示和搜索；重复执行只跳转，不修改内容。若同名章节，按 `index` 消歧并在 UI 显示“第 N 章 · 标题”。
- **访问与安全**：本地只读导航；无登录；无破坏性；会触发阅读器保存阅读位置（现有行为）。不能按“章节序号”跨书源假设一致，换源后要重新解析。
- **普通路径**：`AppEntity`/`EntityStringQuery`（iOS 16）+ `AppIntent`（iOS 16）；不需要 `OpenIntent`，除非要把章节作为系统可打开实体；首批不做。
- **Schema 增强**：`books.navigatePage` 是翻页，不是章节跳转；没有匹配的章节 member，不要猜。
- **系统入口**：Shortcuts 动作最适合；Siri 需两个参数，体验不如“打开书籍”后手动点目录。
- **优先级与成本**：#5；**M**（新增章节实体/查询、两参数短语/预设、章节序号与标题歧义）。
- **验证与下一步**：先确认产品是否需要“按章节名”而非仅按序号；验证同名章节、超长目录、换源后的章节映射；本报告未实现。

### 搜索书籍 — 打开现有书源搜索

- **业务状态**：已实现（书源搜索和结果聚合都已存在；缺的是从系统入口带关键词进入）。
- **代码链**：
  - UI：`YiYue/Views/Search/SearchView.swift` 的 `SearchView` 有 `@State private var keyword`、`performSearch()`；`onAppear` 创建 `SearchService(modelContext:)`；结果列表点击进入 `SourceSelectView`，选择来源后进入 `AddBookView` 加入书架。
  - 业务：`YiYue/Services/SearchService.swift` 的 `@MainActor @Observable final class SearchService`；`search(keyword:)` 重置并启动 `prepareSearch(generation:)`；`SearchSourceSnapshotWorker.fetchEnabledSources` 读取启用的 `BookSource`；`performStage` 最多 9 个并发源，staged 模式 36 个源或 12 秒后暂停，单源 15 秒超时；`results` 由 UI 观察，没有 async 完成回调。
  - 数据：`BookSource`（`YiYue/Models/BookSource.swift`）的 `enabled`、`ruleJSON`、`sourceURL`；`SearchService` 只搜启用源，不搜本地书架。
  - 现有 Intent：无。
- **判定**：**推荐**（前台、预填/自动搜索；不在 Intent 内等待结果）。
- **方向**：
  - 提议 `SearchBooksIntent: AppIntent`，一个 `@Parameter(title: "关键词") var keyword: String`；`title` 用“搜索书籍”。参数必须有默认值，或出现在 `parameterSummary`，否则 Spotlight 可能隐藏该动作。
  - `perform()` 只做校验和路由：非空关键词 → 设置共享路由为“打开搜索页，关键词 X，自动执行一次搜索” → 返回“正在搜索《X》”或“已打开搜索”。不要在 `perform()` 里等待 `SearchService.results`；它没有 async 完成 API，网络又可能超过 30 秒。
  - `SearchView` 需要新增 `init(keyword:autoSearch:)` 或读取路由；`onAppear` 创建 service 后只触发一次搜索，避免重复 `onAppear` 造成二次请求。这是 App 内代码改动，不是 Intent API。
  - 重复执行：每次新关键词调用 `SearchService.search` 会先 `searchTask?.cancel()` 并重置结果；不会写书架。已有搜索会被取消，符合“新搜索覆盖旧搜索”。
  - 没有启用书源时，现有 `SearchView` 已显示“没有启用的书源”，Intent 不必自己编造结果。
- **访问与安全**：会触发对外部书源的网络请求；`NSAllowsArbitraryLoads = true`，书源 HTML/JSON 不可信，解析层已有 `SourceEngine`/`RuleExecutor` 边界，但 Intent 不应扩大其权限。无登录、无账号范围、无设备认证；搜索关键词可能被 Siri 朗读。无破坏性写入；加入书架仍由用户在选择来源后完成。
- **普通路径**：`AppIntent`（iOS 16）+ `AppShortcut`（iOS 16）+ `openAppWhenRun`（iOS 16）。如果希望系统把动作识别为“App 内搜索”，可在 iOS 17.2+ 采用 `ShowInAppSearchResultsIntent` + `StringSearchCriteria`，但项目最低 17.0，首批发普通 `AppIntent` 更稳；17.2 的 `ShowInAppSearchResultsIntent` 默认包含前台运行，和本设计一致。证据见 E01、E02、E03、E08、E10、E11。
- **Schema 增强**：
  - `.system.search`（iOS 18，Siri + Shortcuts）与“把搜索词交给 App 的搜索界面”高度匹配：`ShowInAppSearchResultsIntent` + `searchScopes = [.general]` + `criteria: StringSearchCriteria`。这是本报告中最值得考虑的可选 schema，但仍需 iOS 18 SDK/运行时；可作为后续增强，不进首批。
  - `.books.search`（iOS 18）只是 `ShowInAppSearchResultsIntent` 的 books 域版本，文档 surface 只列 Shortcuts；既然 `.system.search` 支持 Siri 且更通用，不需要选 `books.search`。
  - `.system.searchInApp`（iOS 27，Siri + Shortcuts）是更新的系统搜索 schema；如果未来统一到 iOS 27，可替代 18 的 `.system.search`，但不是当前目标。
- **系统入口**：Shortcuts 动作、Siri 短语、Spotlight 快捷指令磁贴；内容 Spotlight 不适用（搜索的是外部书源，不是本地索引）。Siri 的实际语音匹配、中文短语和 Spotlight 磁贴需要在真机验证。
- **优先级与成本**：#3；**S–M**。Intent 本身很小；成本在 `SearchView` 的初始参数/自动搜索和共享路由。
- **验证与下一步**：文档核对通过；未编译、未实际发起书源搜索。需要验证：空关键词、只有空白、没有启用书源、搜索中再次触发、从搜索结果加入书架后返回；以及 Siri 说中文书名时是否能匹配短语。

### 查询阅读进度 — 我现在读到哪了

- **业务状态**：已实现（有进度字段，但没有“阅读统计”）。
- **代码链**：`Book.progress` 用 `lastReadChapterIndex / totalChapters`；`ReaderView.readerFooter` 用 `currentChapterIndex + chapterFraction` 计算百分比；`BookManager.updateProgress` 写入 `lastReadChapterIndex`、`lastReadPosition`、`lastReadDate`、`readingStatus`。没有按天/按书统计阅读时长或次数的模型。
- **判定**：**不推荐首批**。这是只读查询，技术上容易（S，后台 `ReturnsValue` 或对话），但用户在阅读器页脚和书架已经能看到进度，从 Siri 再问一次的价值有限；在没有小组件/自动化需求前不值得占首批名额。
- **方向（若以后做）**：提议 `GetReadingProgressIntent`，可选 `BookEntity` 参数，缺省取最近阅读；返回书名、章节标题、约百分比，重复执行只读。需要共享容器。歧义规则同“打开书籍”，不要静默选同名书。
- **访问与安全**：本地只读；无登录/认证；书名和进度会被朗读。没有破坏性。
- **普通路径**：`AppIntent` + `ReturnsValue`/`ProvidesDialog`（iOS 16）；不需要 `OpenIntent`，因为不打开内容。
- **Schema 增强**：没有匹配的已验证 member；不要猜。
- **系统入口**：Shortcuts/Siri，若未来有小组件可作为数据源；本报告不把它放进首批。
- **优先级与成本**：#6 左右；**S**，但产品收益低。
- **验证与下一步**：先确认产品是否真的需要“语音问进度”；如果要，先修正下述状态问题。

**现有代码风险（影响“进度/统计”类动作）**：`BookManager.updateProgress` 只有在 `chapterIndex >= book.totalChapters` 时把 `readingStatus` 设为 `.finished`，但 `ReaderView` 传入的是 0-based 的 `currentChapterIndex`，最大为 `totalChapters - 1`；`Book.progress` 也用 0-based 索引除以 `totalChapters`。因此正常读到最后一章时，`readingStatus` 可能仍是 `.reading`，进度显示 99% 而不是 100%。`YiYueTests/BookManagerTests.swift` 的 `testMarkAsFinished` 直接传 `100`（`totalChapters = 100`）才会通过，和 UI 的传值不一致。任何“统计已读完/继续下一本”的 Intent 都应以实际章节位置判断，不能只信 `readingStatus`；是否修正该判定属于另一个产品/代码任务。

### 缓存章节 — 缓存接下来 N 章

- **业务状态**：已实现，但入口绑定在阅读器 UI 内。
- **代码链**：`YiYue/Views/Reader/ReaderView.swift` 的 `cacheChapters(count:)` 计算 `startingChapterIndex`，用 `chapterContentConfiguration()` 和 `makeChapterFetchJobs(from:)` 组装 `ChapterDownloadRequest`，再调用 `ChapterDownloadManager.shared.enqueue(_:preparationToken:)`；`YiYue/Services/ChapterDownloadManager.swift` 是 actor，带持久化队列、暂停/恢复/清理；`ChapterDownloadSystemTask` 提交 `BGContinuedProcessingTask`（iOS 26+）或 `BGProcessingTask`（旧系统）。
- **判定**：**不推荐首批，列后续可选**。用户已经在阅读器菜单里一键缓存；从 Siri 触发虽自然（“缓存接下来 100 章”），但需要把 `cacheChapters` 的私有组装逻辑提取成服务，处理书源规则、已缓存章节、当前章节、后台租约和取消，成本 L。`perform()` 只入队可以很快返回，但队列后续执行依赖系统后台调度，不能承诺“说完就缓存完”。
- **方向（若以后做）**：`CacheChaptersIntent`，`BookEntity` + `count`（例如“接下来 100 章”/“全部”）；确认大批量“缓存全部”；入队成功后返回“已加入缓存队列”，把进度留给现有 `ChapterDownloadManager` 和通知/阅读器状态。重复执行要由 `ChapterDownloadManager.enqueue` 的 job 去重保证，不要新建重复任务。
- **访问与安全**：写磁盘和网络请求；无登录；非破坏性但占存储；用户可在 App 内取消/清理。大批量缓存应确认，避免 Siri 误触发。
- **普通路径**：`AppIntent`（16）+ 现有 actor 入队；`BGContinuedProcessingTask` 仅 iOS 26+，17–25 的后续执行能力未验证；`LongRunningIntent`/`performBackgroundTask` 是 iOS 27，不应作为首批依赖。
- **Schema 增强**：`books` 域没有缓存 member；不适用。
- **系统入口**：Shortcuts 比 Siri 更合适（可配置书目和数量）；Siri 只适合固定“接下来 100 章”预设。
- **优先级与成本**：#7；**L**。
- **验证与下一步**：先做服务抽取和单元测试（不依赖 UI），再验证 iOS 17/26 的后台租约；本报告未执行。

### 导入书源（网址）— 从 URL 导入 Legado 书源

- **业务状态**：已实现。
- **代码链**：`YiYue/Views/Sources/SourceListView.swift` 的 `importFromURL()` 用 `NetworkClient.shared.fetchString` 拉取 JSON，再调用 `SourceImportService.importJSON(_:)`；`SourceImportService` 按 `bookSourceUrl` 去重，插入 `BookSource`；`SourceListView` 也支持 `DocumentPicker` 文件导入。`Info.plist` 允许任意 HTTP。
- **判定**：**不推荐首批，列后续可选**。这是面向高级用户的批量配置动作，Shortcuts 自动化比 Siri 更合适；它不直接产生阅读价值，且会写入外部规则。技术上 S–M：一个 `String`/URL 参数 + 网络 + 解析即可，但需要大小限制、错误句、重复源提示和“导入多少个”的返回值。
- **方向（若以后做）**：`ImportSourcesIntent`，参数为网址字符串；后台拉取并解析；返回“导入 N 个书源，跳过 M 个已存在”。执行前确认会写入书源；重复 URL 由现有 `fetchExistingURLs` 去重。不要自动启用所有导入源（现有 `BookSource.init` 默认 `enabled = true`，这是现有行为，若产品希望导入后默认关闭需另改）。
- **访问与安全**：外部不可信 JSON/HTML；ATS 允许 HTTP；写入 `BookSource`；无登录。建议限制响应大小、超时和错误信息，不把原始异常直接读给用户。
- **普通路径**：`AppIntent`（16）+ 网络；`URL` 参数类型未在本报告验证，建议先用 `String` 以降低 API 风险。
- **Schema 增强**：没有匹配的已验证 member；不适用。
- **系统入口**：Shortcuts；Siri 只在用户明确说“导入书源”时有意义。
- **优先级与成本**：#8；**S–M**。
- **验证与下一步**：先确认产品是否愿意让 Shortcuts 写书源；验证大 JSON、重复 URL、无效 JSON、HTTP 错误和导入后搜索可用性。

### 导入本地书 — 把 txt/epub 加入书架

- **业务状态**：已实现，但依赖文档选择器。
- **代码链**：`YiYue/Views/Bookshelf/BookshelfView.swift` 的 `showingFilePicker` + `DocumentPicker` 调用 `ImportService.importTXT(from:)` 或 `importEPUB(from:)`；`YiYue/Services/ImportService.swift` 读取 Data、`EncodingDetector`、`ChapterSplitter`（TXT）或 `EPUBParser`（EPUB），创建 `Book` 和 `Chapter` 并 `modelContext.save()`。没有重复导入检测。
- **判定**：**不推荐首批，列后续可选**。对自动化（例如 Shortcuts 下载文件后导入）有价值，但需要 `IntentFile`/安全作用域 URL、文件大小与编码、同步解析可能阻塞、重复导入的处理；成本 M–L。Siri 语音直接传文件不自然，Shortcuts 更合适。
- **方向（若以后做）**：`ImportLocalBookIntent`，文件参数 + 可选书名；在后台读取并在主上下文插入；返回书名/章节数。重复导入检测（同文件名/同内容）是新增业务规则，必须作为提案，不要假装现有能力。
- **访问与安全**：文件读取权限；本地；无登录；写书架；大文件可能超时/占内存。需要限制大小和取消。
- **普通路径**：`AppIntent`（16）+ 文件参数；具体 `IntentFile` 类型/可用版本本报告未核对，属于未验证 API。
- **Schema 增强**：`files` 域没有确认的匹配 member；不要猜。
- **系统入口**：Shortcuts（文件输入），不适合 Siri 语音。
- **优先级与成本**：#9；**M–L**。
- **验证与下一步**：先验证 `IntentFile`/安全作用域 URL 在目标 SDK 的声明和文件拷贝行为；再做大小/编码/重复导入测试。

### 检查更新 / 追更 — 检查书源有没有新章节

- **业务状态**：**部分实现（工作区未提交，未编译/未运行测试）**。`c153bf6` 中没有这个能力；落盘前工作区新增了手动“更新目录”的实现，但还没有自动/定时检查，也没有通知或每本书的更新记录。
- **代码链与证据**：
  - `YiYue/Views/Reader/ReaderView.swift` 新增 `refreshTableOfContents() async -> TocRefreshOutcome`：用 `book.sourceId` 查 `BookSource`，用 `LegadoSourceParser.parse` 解析规则，调用私有 `fetchChapters(source:bookURL:)` 拉目录；`fetchChapters` 支持 `nextTocUrl` 分页，最多 200 页，按标题+URL 去重，空目录抛 `ChapterSourceSwitchError.noChapters`。
  - 新增 `TocMerger.newChapters(existingTitles:existingURLs:incoming:)`（位于 `YiYue/Services/SourceEngine.swift`）：按 URL 或规范化标题过滤已存在章节，只返回新增项；`normalizedTitle` 去空白并转小写。现有实现只追加新章节，保留已有 `Chapter.index`，因此阅读位置和缓存索引不会被重排；它不处理删除、重命名或重排旧章节。
  - 追加逻辑在 `refreshTableOfContents()`：`nextIndex = (chapters.map(\.index).max() ?? -1) + 1`，逐个插入 `Chapter`、设置 `sourceURL` 和 `book`，`book.totalChapters = max(book.totalChapters, nextIndex)`，`try? modelContext.save()`，再 `loadChapters()`，返回 `.added(count)`。
  - UI 在 `YiYue/Views/Reader/ReaderMenuOverlay.swift`：`onRefreshToc` 回调、`TocRefreshOutcome`、`updateToc()`、`isUpdatingToc`、toast（新增/已最新/失败可重试/无书源）；只在 `book.sourceId != nil` 时显示刷新按钮。目录列表还新增了章节搜索。
  - 新测试 `YiYueTests/TocMergerTests.swift`（未跟踪）覆盖“只追加不存在章节”和“空格/大小写归一化”；尚未运行。
  - 仍然缺少：后台定时检查、通知、每本书的 `lastCheckedAt`/最新章节标记、失败重试的持久状态、与换源/缓存队列的互斥。
- **判定**：**需验证**，不进首批。它比“搜索书籍”更贴近连载读者的核心需求，但代码刚出现在未提交工作区，逻辑私有在 `ReaderView`，`try? modelContext.save()` 会吞掉保存失败却仍返回 `.added`，且没有构建/测试证据。适合在第 4 位、上述问题解决后再做 Intent。
- **方向（若转正）**：提议抽出 `TocRefreshService`（输入 `bookID`/`BookEntity`，输出 `.upToDate`/`.added(n)`/`.failed`），Intent 默认“只检查不写入”，返回“新增 N 章”；如果要直接追加，执行前确认。重复执行必须幂等，按 `sourceURL` + 规范化标题去重；分页最多 200 页，`perform()` 30 秒预算可能不够，需分块/后台或只检查第一页后的增量。
- **访问与安全**：外部网络 + 写 `Chapter`/`Book.totalChapters`；无登录、无账号范围、无设备认证；追加是增量写入，但不能在保存失败时报告成功；失败不能破坏已有章节。需要确认“只检查”与“写入”的边界。
- **普通路径**：`AppIntent`（iOS 16）+ `BookEntity` + 现有 `fetchChapters`/`TocMerger`（需先服务化）；不依赖 `LongRunningIntent`（iOS 27）。
- **Schema 增强**：没有匹配的已验证 member；不适用。
- **系统入口**：Shortcuts 定时自动化、Siri 查询“有没有更新”；Siri 只适合检查并报数，不适合直接写入。
- **优先级与成本**：产品价值高；**M–L**（服务抽取、幂等/失败语义、后台/超时、测试）。
- **验证与下一步**：先让工作区改动提交并通过构建/`TocMergerTests`；再把追加逻辑从 `ReaderView` 抽到服务，给保存失败返回错误；最后验证分页目录、多书源、断网、重复执行和“新增 N 章”不误报。

### 阅读统计 — 阅读时长/连续天数/读完多少

- **业务状态**：**未实现**。现有 `Book.readingStatus`、`lastReadDate`、`progress` 只能表达单本状态，没有阅读会话、时长、天数或统计页面；`ChapterCacheStatistics` 是缓存统计，不是阅读统计。上面提到的 `finished` 判定还可能不准。
- **判定**：**不推荐当前批次 / 计划功能**。需要新的数据模型和写入点（进入/退出阅读器、前后台切换、分页计时），成本 L；没有这些数据就不能诚实地生成“本周读了 3 小时”这类回答。
- **方向（若以后做）**：先做 App 内统计模型和聚合，再考虑 `GetReadingStatsIntent`；不要先做 Intent。
- **访问与安全**：本地阅读历史，敏感度高于书名；Siri 朗读/Spotlight 展示需要产品选择；无登录。
- **普通路径**：`AppIntent`（16）+ 只读查询，但依赖新业务模型。
- **Schema 增强**：无匹配 member。
- **系统入口**：Shortcuts/小组件比 Siri 更合适。
- **优先级与成本**：**L**；不在首批。

### 换源 — 把书切换到另一个书源

- **业务状态**：已实现，但流程复杂且会改动章节数据。
- **代码链**：`YiYue/Views/Bookshelf/ChangeSourceView.swift` 的 `startSwitch(to:)`、`switchSource(to:generation:)`、`switchToPinned(...)`、`fetchChapters(...)`、`applySwitch(...)`；`ChangeSourceError` 覆盖无目录规则、无章节、正文保存失败等。`Book.pinnedSources` / `blockedSourceIds` 保存用户选择。
- **判定**：**不推荐**（至少不做语音入口）。换源需要候选源搜索、章节匹配、正文验证和持久化；选错源可能把整本书的章节映射换掉，属于需要确认的破坏性/半破坏性操作。Siri 语音不适合处理这种多步选择；Shortcuts 也只能在用户明确选择源并确认后做。
- **方向（若以后做）**：`ChangeBookSourceIntent`，`BookEntity` + `SourceEntity`，执行前确认，失败回滚，返回“已切换/未改变”；重复执行要幂等。现有 `ChangeSourceView` 的逻辑需要先抽成服务，不能在 Intent 里复制视图代码。
- **访问与安全**：外部网络、写章节和 `Book` 元数据；无登录；必须确认并保留回滚路径；不能自动选择第一个源。
- **普通路径**：`AppIntent`（16）+ 确认；但业务就绪度低。
- **Schema 增强**：无匹配 member。
- **系统入口**：Shortcuts 仅在高级自动化中有价值；Siri 不推荐。
- **优先级与成本**：**L**；不推荐。

### 搜索并直接加入书架 — 一句话把书加进书架

- **业务状态**：链路上的能力都已实现，但没有“自动选择来源并加入”的安全业务规则。
- **代码链**：`SearchView.performSearch()` → `SearchService.search` → `SourceSelectView` 选择 `AggregatedSearchResult.SourceMatch` → `AddBookView.loadBookDetail()` 拉详情/目录 → `addToBookshelf()` → `AddBookPersistenceWorker.addBook(_:in:)` 创建 `Book`/`Chapter`。`AddBookPersistenceWorker` 每次都创建新 `Book`，没有按 `sourceId + sourceBookURL` 去重。
- **判定**：**不推荐**。搜索结果常有同名书、多个来源、多个版本；自动选第一个源可能加错书，且会产生重复书籍。用户必须看到来源和章节数再做选择。正确做法是“搜索书籍”打开现有结果页，而不是在 Siri 里替用户决定。
- **方向（若以后做）**：只能做“搜索并在 App 内展示候选”，或在用户明确指定 `sourceId` + `sourceBookURL` 且确认后加入；需要新增去重规则（同一来源同一 bookURL 已存在则拒绝/提示），这是新业务规则。
- **访问与安全**：网络 + 写书架；无登录；错误加入会污染书架，重复加入会占空间；需要确认和撤销路径。
- **普通路径**：`AppIntent`（16）+ `BookEntity` 结果展示；但业务规则未就绪。
- **Schema 增强**：无匹配 member。
- **系统入口**：不推荐 Siri；Shortcuts 也应先展示候选。
- **优先级与成本**：**L**；不推荐。

## 排除项

| 功能 / 用户任务 | 业务状态与证据 | 判定与排除原因 | 什么会改变决定 |
| --- | --- | --- | --- |
| 阅读设置（字号、行距、主题） | `YiYue/Models/ReaderSettings.swift` 的 `fontSize`、`lineSpacing`、`theme` 已实现；`books` schema 有 `updateFontSize`/`updateLineSpacing`/`updateSettings`（iOS 18，文档只列 Shortcuts） | 不推荐：偏好调整是 UI 内操作，不是阅读任务；schema 也不带来 Siri 收益 | 如果要做无障碍快捷指令，可单独评估，但不进首批 |
| 翻页 / 跳到某页 | `ReaderView` 的翻页手势和 `PageMode` 已实现；`books.navigatePage`（iOS 18，Shortcuts） | 不推荐：语音翻页是噱头，且需要阅读器当前页上下文；没有独立任务价值 | 出现明确的免手操作场景再评估 |
| 有声书 / 朗读 | 源码中无 `AVFoundation`、`AVAudio`、`Speech`；`books.playAudiobook` 不适用 | 不推荐：功能未实现，不能由 schema 伪造 | 先实现音频播放业务 |
| 删除书籍 / 清空缓存 | `BookManager.deleteBook`、`ChapterDownloadManager.clear/clearAll` 已实现 | 不推荐：破坏性操作，Siri 误触发风险高；应留在 App 内确认流程 | 若做 Shortcuts，需二次确认、撤销/回收站 |
| 修改封面 / 置顶 / 排序 | `BookshelfView` 的 contextMenu、`CoverPickerView`、`pinnedDate` 已实现 | 不推荐：装饰/整理型操作，不是核心任务 | 不做 |
| 关于/版本 | `AboutView` 只读展示版本 | 不推荐：无任务价值 | 不做 |

## 计划、未确定与被排除的功能

| 功能 / 用户任务 | 业务状态与证据 | 判定与排除/延后原因 | 改变决定的条件 |
| --- | --- | --- | --- |
| 检查更新 / 追更 | **工作区部分实现（未提交/未编译）**：`ReaderView.refreshTableOfContents()` + `TocMerger` + `ReaderMenuOverlay.updateToc()` 已能手动追加新章；仍无自动检查、通知、每书检查时间/最新章节记录 | 延后/需验证；先提交并通过构建/`TocMergerTests`，再把逻辑抽出 `ReaderView` 成服务；成本 M–L | 服务抽取、保存失败语义、分页/后台验证完成；可成为第 4 个候选 |
| 阅读统计 | **未实现**：无阅读会话/时长模型；`Book.progress`/`lastReadDate` 不是统计 | 延后；先做数据模型，不先做 Intent | 统计模型和页面落地后 |
| 缓存章节 | 已实现：`ReaderView.cacheChapters` → `ChapterDownloadManager.enqueue` → `ChapterDownloadSystemTask` | 延后；需抽取服务并验证后台租约，成本 L | 服务抽取 + iOS 17/26 后台验证完成 |
| 导入书源 URL | 已实现：`SourceListView.importFromURL` → `SourceImportService.importJSON` | 延后；高级用户/自动化场景，需写权限和输入限制 | 有明确自动化需求 |
| 导入本地 txt/epub | 已实现：`DocumentPicker` → `ImportService.importTXT/importEPUB` | 延后；文件参数/安全作用域/去重未就绪 | `IntentFile` 验证完成、去重规则确定 |
| 小组件 / 实时活动 | 无 WidgetKit 代码 | 不属于 App Intent 首批；可作为后续独立设计 | 产品要做桌面/锁屏入口时 |
| Apple Intelligence 章节摘要 | 没有 Foundation Models 代码；不是 App Intent 能力 | 不在本报告范围；是新 AI 功能，需要模型可用性、中文、长文本和隐私设计 | 单独功能评估 |
| `books` 域 schema（openBook/search/updateFontSize 等） | schema 存在，iOS 18；文档 system experiences 对 openBook/search 只列 Shortcuts | 延后；对 Siri/Apple Intelligence 没有额外收益，反而增加 schema 约束 | 若产品只需要更标准的 Shortcuts 表单，可评估 `books.openBook` |
| `.system.search` | iOS 18，Siri + Shortcuts，`ShowInAppSearchResultsIntent` + `StringSearchCriteria` | 可选增强，不进首批；需要 iOS 18 SDK/运行时 | 首批稳定后，用 iOS 18+ 设备验证 |
| `.system.open` | iOS 27，Siri + Shortcuts，`OpenIntent` + `target: any AppEntity` | 可选增强，不进首批；需要 iOS 27 SDK 和新 Siri 真机 | 项目决定支持 iOS 27 语义 Siri 时 |
| `.system.searchInApp` | iOS 27，Siri + Shortcuts，`ShowInAppSearchResultsIntent` | 可选增强；与 `.system.search` 重叠，等 27 生态成熟 | 统一到 iOS 27 后 |
| `IndexedEntity` / Spotlight 内容索引 | 无 CoreSpotlight 代码；`IndexedEntity`/`indexAppEntities` iOS 18 | 可选后续；能提升 Spotlight/Siri 实体发现，但会暴露书名/作者，且需要增删/更新时同步索引 | 产品接受隐私权衡并有索引维护方案 |

## API 与可用性证据

以下符号均在 2026-10-29 通过 Apple Developer Documentation 页面读取；“本地 SDK 声明”一列统一说明：本机没有 Xcode/iOS SDK，未能读取 `.swiftinterface` 或本地声明，因此“文档可用”不等于“当前项目的 SDK 能编译”。所有 URL 为 Apple 文档页面，不是项目内文件。

| ID | 精确符号 / 域名.成员 | 最低 OS | 所需 SDK/工具链与所选 SDK 证据 | 适用表面 / 条件 | 来源 URL 或 SDK 路径/声明 | 验证日期 / 快照 | 缺口与下一步 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| E01 | `AppIntent` 协议 | iOS 16.0 | 文档；本地 SDK 未验证 | 所有 App Intents 动作的基础 | https://developer.apple.com/documentation/appintents/appintent | 2026-10-29 | 需在项目 SDK 编译；确认 Swift 5.9 下 `static let` 元数据生成 |
| E02 | `AppShortcutsProvider` / `appShortcuts` | iOS 16.0 | 文档；本地 SDK 未验证 | Shortcuts、Spotlight 快捷指令、Siri App Shortcuts | https://developer.apple.com/documentation/appintents/appshortcutsprovider | 2026-10-29 | 每个 App 只能一个 provider，必须在主 target；未验证 |
| E03 | `AppShortcut.init(intent:phrases:shortTitle:systemImageName:)`（16.0 重载） | iOS 16.0 | 文档；本地 SDK 未验证 | App Shortcuts 磁贴和短语 | https://developer.apple.com/documentation/appintents/appshortcut | 2026-10-29 | 短语必须包含 `\(.applicationName)`；这是技能参考规则，需在真机验证匹配 |
| E04 | `AppEntity` | iOS 16.0 | 文档；本地 SDK 未验证 | 实体参数、Siri/Shortcuts 选择 | https://developer.apple.com/documentation/appintents/appentity | 2026-10-29 | 需要稳定 `id`；`Book.id` 是 UUID，满足 |
| E05 | `EntityQuery` | iOS 16.0 | 文档；本地 SDK 未验证 | 实体按 ID 解析 | https://developer.apple.com/documentation/appintents/entityquery | 2026-10-29 | 需要共享 ModelContainer 才能查 SwiftData |
| E06 | `EntityStringQuery` | iOS 16.0 | 文档；本地 SDK 未验证 | 按字符串搜实体、Siri 消歧 | https://developer.apple.com/documentation/appintents/entitystringquery | 2026-10-29 | `entities(matching:)` 要有上限；未验证中文/全半角匹配 |
| E07 | `OpenIntent` / `OpenIntent.target` | iOS 16.0 | 文档；本地 SDK 未验证 | 系统打开某个实体 | https://developer.apple.com/documentation/appintents/openintent | 2026-10-29 | `target` 是必需属性；需搭配前台模式 |
| E08 | `AppIntent.openAppWhenRun` | iOS 16.0（26.0 弃用） | 文档；本地 SDK 未验证 | 让 App 在前台运行 Intent | https://developer.apple.com/documentation/appintents/appintent/openappwhenrun | 2026-10-29 | 部署目标 17.0 用它；26+ 可换 `supportedModes` |
| E09 | `AppShortcuts.updateAppShortcutParameters()` | iOS 16.0 | 文档；本地 SDK 未验证 | 实体参数短语的数据变化后刷新 | https://developer.apple.com/documentation/appintents/appshortcutsprovider/updateappshortcutparameters() | 2026-10-29 | 增删书后调用；未验证刷新时机 |
| E10 | `ShowInAppSearchResultsIntent` | iOS 17.2 | 文档；本地 SDK 未验证 | 系统把搜索词路由到 App 搜索界面；默认含前台运行 | https://developer.apple.com/documentation/appintents/showinappsearchresultsintent | 2026-10-29 | 项目最低 17.0，需 `@available(iOS 17.2, *)`；首批可不使用 |
| E11 | `StringSearchCriteria` / `StringSearchScope` | iOS 17.2 | 文档；本地 SDK 未验证 | 搜索词和搜索范围 | https://developer.apple.com/documentation/appintents/stringsearchcriteria | 2026-10-29 | `searchScopes = [.general]`；未编译 |
| E12 | `AppSchema.SystemIntent.search`（`.system.search`） | iOS 18.0 | 文档；本地 SDK 未验证 | Siri、Shortcuts；`ShowInAppSearchResultsIntent` + `criteria` | https://developer.apple.com/documentation/appintents/appschema/systemintent/search | 2026-10-29 | 需 `@AppIntent(schema: .system.search)` 和 iOS 18 SDK；未验证 |
| E13 | `AppSchema.SystemIntent.open`（`.system.open`） | iOS 27.0 | 文档；本地 SDK 未验证 | Siri、Shortcuts；`OpenIntent` + `target: any AppEntity` | https://developer.apple.com/documentation/appintents/appschema/systemintent/open | 2026-10-29 | 需 iOS 27 SDK/运行时；不能为目标 17.0 直接采用 |
| E14 | `IndexedEntity` | iOS 18.0 | 文档；本地 SDK 未验证 | Spotlight 内容索引、Apple Intelligence 实体发现 | https://developer.apple.com/documentation/appintents/indexedentity | 2026-10-29 | 需在增删/更新时维护索引；隐私需产品确认 |
| E15 | `CSSearchableIndex.indexAppEntities(_:priority:)` | iOS 18.0 | 文档；本地 SDK 未验证 | 把 `IndexedEntity` 写入 Spotlight | https://developer.apple.com/documentation/corespotlight/cssearchableindex/indexappentities(_:priority:) | 2026-10-29 | 需要 CoreSpotlight import；未验证 |
| E16 | `@AppIntent(schema:)` 宏 | iOS 18.0 | 文档；本地 SDK 未验证 | schema 动作的编译期成员生成 | https://developer.apple.com/documentation/appintents/appintent(schema:) | 2026-10-29 | schema 错误会导致元数据导出失败；不首批采用 |
| E17 | `AppSchema.BooksIntent.openBook` | iOS 18.0 | 文档；本地 SDK 未验证 | 仅 Shortcuts（文档 system experiences 只列 Shortcuts） | https://developer.apple.com/documentation/appintents/appschema/booksintent/openbook | 2026-10-29 | 不带来 Siri/AI 收益；不首批 |
| E18 | `AppSchema.BooksIntent.search` | iOS 18.0 | 文档；本地 SDK 未验证 | 仅 Shortcuts；`ShowInAppSearchResultsIntent` + `StringSearchCriteria` | https://developer.apple.com/documentation/appintents/appschema/booksintent/search | 2026-10-29 | 与 `.system.search` 重叠；不选它 |
| E19 | `AppSchema.BooksEntity.book` | iOS 18.0 | 文档；本地 SDK 未验证 | Shortcuts 的 book 实体 schema；`title`/`author`/`seriesTitle`/`url` | https://developer.apple.com/documentation/appintents/appschema/booksentity/book | 2026-10-29 | schema entity 的 `@Property` 和初始化约束需另验 |
| E20 | `TargetContentProvidingIntent` | iOS 26.0 | 文档；本地 SDK 未验证 | 让视图处理 Intent 导航 | https://developer.apple.com/documentation/appintents/targetcontentprovidingintent | 2026-10-29 | 目标 17.0 不可用；首批用共享路由替代 |
| E21 | `View.onAppIntentExecution(_:perform:)` | iOS 26.0 | 文档；本地 SDK 未验证 | 在视图层接收 Intent | https://developer.apple.com/documentation/swiftui/view/onappintentexecution(_:perform:) | 2026-10-29 | 26+ 可选；首批不用 |
| E22 | `AppIntent.requestConfirmation(result:confirmationActionName:showPrompt:)` | iOS 16.0 | 文档；本地 SDK 未验证 | 破坏性/敏感动作确认 | https://developer.apple.com/documentation/appintents/appintent/requestconfirmation(result:confirmationactionname:showprompt:) | 2026-10-29 | 只用于后续缓存/换源/删除，不用于首批只读动作 |
| E23 | `AppIntent.supportedModes` | iOS 26.0 | 文档；本地 SDK 未验证 | 前台/后台模式 | https://developer.apple.com/documentation/appintents/appintent/supportedmodes | 2026-10-29 | 目标 17.0 不可用；首批用 `openAppWhenRun` |
| E24 | `AppSchema.SystemIntent.searchInApp`（`.system.searchInApp`） | iOS 27.0 | 文档；本地 SDK 未验证 | Siri、Shortcuts；`ShowInAppSearchResultsIntent` + `criteria` | https://developer.apple.com/documentation/appintents/appschema/systemintent/searchinapp | 2026-10-29 | iOS 27 可选增强；未验证 |

补充：`AppShortcut` 的 17.0 重载 `init(intent:phrases:shortTitle:systemImageName:)` 也存在，但 16.0 重载已足够首批；`@AppEntity(schema:)` 宏为 iOS 18.0，若采用 `books.book` 需遵守 schema entity 的 `@Property` 生成规则，现成 `BookEntity` 不能直接照搬 schema 初始化。以上都没有在本地 SDK 编译。

## 产品交接

- **建议首批（3 个）**：继续阅读、打开书籍、搜索书籍。三者都基于已实现的书架/阅读/搜索能力，不新增外部账号或危险写入；建议按此顺序实现。
- **共享前置改造**：
  1. 把 `YiYueApp` 的 `.modelContainer(for:)` 场景容器提升为 App 级共享 `ModelContainer`，供 Intents、`BookshelfView`、`ReaderView` 共用；当前没有共享容器，Intent 无法直接访问 SwiftData。
  2. 增加一个前台路由（例如 `AppRoute`/`ReadingRouter`），把“继续阅读/打开某书/搜索关键词”传给 `BookshelfView` 和 `SearchView`；iOS 26+ 可以用 `TargetContentProvidingIntent`/`onAppIntentExecution`，iOS 17–25 用同一路由的观察/回调实现。首批不要依赖 iOS 26 API。
  3. 给 `SearchView` 增加关键词初值和自动搜索标记；给 `BookshelfView` 增加按 `Book.id` 打开 `ReaderView` 的入口，避免从搜索/Intent 复制 `fullScreenCover` 逻辑。
  4. 增加 `BookEntity`/`BookEntityQuery`，并在加书/删书后调用 `AppShortcuts.updateAppShortcutParameters()`（iOS 16+）。
- **首批明确不做**：Spotlight 内容索引、任何 schema、iOS 26/27 专属模式、缓存/换源/导入/删除，以及工作区尚未验证的“更新目录”。
- **需要产品先决定**：
  - “继续阅读”在没有 `lastReadDate` 时是否打开最近加入的书，还是提示“还没有在读的书”；系列书是否要自动推进到下一部。
  - 搜索动作是自动执行搜索，还是只打开搜索页并预填关键词；自动搜索会立即发起多书源网络请求。
  - 是否接受把书名/作者索引进 Spotlight（已阅没有应用锁；Siri/Spotlight 可能暴露书名）。
  - 是否修正 `readingStatus`/`progress` 的 0-based 判定；这会直接影响后续“已读完/统计”类功能。
  - 工作区的“更新目录”是否转正：默认只检查还是直接追加；是否加通知/定时检查；是否接受它只追加、不处理旧章节重命名/重排。
- **可选后续**：`.system.search`（iOS 18）→ `IndexedEntity`/Spotlight → `.system.open`（iOS 27）；再往后才是工作区追更转正、统计、缓存、导入和换源。`books` 域 schema 只在需要标准 Shortcuts 表单时考虑，不应作为 Siri/Apple Intelligence 的主要理由。
- **未执行的验证**：本报告只创建了这份 markdown，没有由本报告修改任何 App 代码、工程配置或资源；工作区中列出的未提交改动并非本报告产生。没有编译、没有安装、没有运行 Shortcuts/Spotlight/Siri，也没有执行任何书籍、书源、缓存或删除操作。所有“可运行/可见”的判断都只是文档层分析，真机验证仍是后续任务。
