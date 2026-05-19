# NovelReader iOS App 设计文档

## 概述

一个纯粹的小说阅读 iOS App，专注于两件事：舒适的阅读体验和低成本的书籍获取。灵感来源于微信读书的阅读界面和 Apple Books 的书架设计。

- 平台：iOS (SwiftUI)
- 分发：个人侧载（TestFlight / AltStore）
- 主要用途：中文网络小说阅读
- 技术栈：SwiftUI + JavaScriptCore + SwiftData

## 架构

四层分离：

```
┌─────────────────────────────────────────────┐
│             UI 层 — SwiftUI                  │
│  书架视图 │ 阅读器视图 │ 搜索视图 │ 设置视图  │
├─────────────────────────────────────────────┤
│           业务逻辑层 — Swift                  │
│  BookManager │ SourceManager │               │
│  SearchCoordinator │ ImportService           │
├──────────────────────┬──────────────────────┤
│  书源引擎             │  文件解析器           │
│  JavaScriptCore      │  Swift               │
│  Legado 规则解析      │  EPUB / TXT 解析     │
│  网页抓取 / HTML 解析  │  编码检测 / 章节分割  │
├──────────────────────┴──────────────────────┤
│            数据层 — SwiftData                │
│  Book │ Chapter │ BookSource                 │
└─────────────────────────────────────────────┘
```

JavaScriptCore（iOS 内置框架）负责书源引擎，Swift 负责 UI、业务逻辑和本地文件解析。所有书籍无论来源，统一为 Book → Chapter 结构。

## 数据模型

### Book

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 主键 |
| title | String | 书名 |
| author | String | 作者 |
| coverURL | String? | 封面地址（本地路径或远程 URL） |
| sourceType | Enum | .bookSource / .localFile |
| sourceId | UUID? | 关联的 BookSource（仅在线书籍） |
| sourceBookURL | String? | 该书在源站的地址 |
| readingStatus | Enum | .unread / .reading / .finished |
| lastReadChapterIndex | Int | 上次读到第几章 |
| lastReadPosition | Double | 章内阅读进度（0.0 ~ 1.0） |
| totalChapters | Int | 总章节数 |
| addedDate | Date | 加入书架时间 |
| lastReadDate | Date? | 最后阅读时间 |
| seriesName | String? | 系列名（nil 表示独立书籍） |
| seriesIndex | Int? | 系列中的序号 |
| progress | Computed | lastReadChapterIndex / totalChapters |

### Chapter

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 主键 |
| book | Book | 关联的 Book（多对一） |
| index | Int | 章节序号 |
| title | String | 章节标题 |
| content | String? | 正文内容（可为空，未缓存时） |
| isCached | Bool | 是否已缓存到本地 |
| sourceURL | String? | 章节来源地址（仅在线书籍） |

### BookSource

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 主键 |
| name | String | 书源名称 |
| sourceURL | String | 书源站点地址 |
| sourceGroup | String? | 分组标签 |
| enabled | Bool | 是否启用 |
| ruleJSON | String | Legado 原始 JSON 规则 |
| lastUpdateDate | Date | 最后更新时间 |
| qualityScore | Double? | 综合质量评分（0~100，nil 未检测） |
| lastTestDate | Date? | 最后质量检测时间 |
| avgResponseTime | Double? | 平均响应时间（毫秒） |
| contentValidRate | Double? | 内容有效率（0.0~1.0） |
| encodingScore | Double? | 编码质量分（0.0~1.0） |
| catalogSize | Int? | 可用书籍数量 |
| isQualityVerified | Bool | 是否通过质量检测 |

### 关系

- Book ↔ Chapter：一对多，Chapter 按 index 排序
- Book → BookSource：多对一（仅在线书籍）
- 在线书籍的 chapter.content 支持懒加载（阅读时抓取并缓存）
- 本地导入书籍导入时即写入全部章节内容

## 书架 UI

### 布局

- 高密度封面网格：每行 4 本书
- 纯黑背景，封面为视觉焦点
- 书名显示在封面下方，用灰色小字

### 状态指示

| 状态 | 视觉表现 |
|------|---------|
| 未读 | 右上角蓝色「新」标签，无进度条 |
| 在读 | 封面底部蓝色进度条 + 百分比数字 |
| 已读完 | 右上角绿色 ✓ 标签 |

### 系列书展示

- 堆叠封面效果（3层叠放），一眼可识别为系列
- 右上角橙色角标显示总册数（如「8部」）
- 底部文字显示当前阅读进度（如「第3部 33%」）
- 系列进度条用橙色，与单本的蓝色区分
- 系列全部读完时显示绿色

## 搜索与导入

### 三步流程

**第 1 步 — 搜索：**
- 输入书名，聚合所有启用的书源并行搜索
- 结果按「书名 + 作者」去重合并，显示每本书匹配到几个来源
- 展示封面、书名、作者、来源数

**第 2 步 — 选来源：**
- 点进一本书后，展示所有提供该书的书源
- 每个来源显示：质量评分（颜色编码）、响应速度、章节数
- 顶部「仅显示优质书源」开关，开启后低分书源变灰淡出（仍可手动查看）
- 来源按质量评分降序排列

**第 3 步 — 确认添加：**
- 显示书籍详情：封面、书名、作者
- 显示来源信息：书源名、章节数、质量评分、完结状态
- 缓存策略选择：阅读时缓存（默认） / 缓存全部章节
- 「加入书架」按钮

### 本地文件导入

- 入口：iOS Share Sheet 或 Files app
- 支持格式：.epub、.txt
- TXT 文件：自动检测编码（UTF-8 / GBK / GB2312），按章节标题正则分割
- EPUB 文件：解析目录结构，保留原有章节划分
- 导入后自动进入书架，无需额外操作

## 书源引擎

### Legado 兼容

- 解析 Legado JSON 格式的书源规则
- 支持导入社区现有书源文件
- 规则语法支持：JSONPath、XPath、CSS 选择器、正则表达式
- 通过 JavaScriptCore 执行规则中的 JS 表达式

### 书源质量检测

运行质量检测时，对每个书源自动测试：

1. 响应速度：发送请求计时
2. 内容有效性：随机抽查几本热门书名，验证能否正常获取章节内容
3. 编码质量：检测返回内容的乱码率
4. 目录丰富度：搜索热门书名，统计结果数量

检测完成后计算 0~100 综合评分。用户可一键开启「仅优质书源」过滤。

## 阅读器

### 沉浸模式（默认）

- 纯黑背景 #121212，文字 #d4d4d4
- 默认字体：PingFang SC（苹方）
- 默认字号：17px，行距 2.0，首行缩进 2em
- 章节标题用浅灰小字，不抢注意力
- 底部仅显示书名和当前章节内的阅读位置（如 3818 / 7090，表示当前章节已读/总字符数）

### 菜单（轻触屏幕中央呼出）

单层菜单设计，不堆叠多排控件：

**顶栏：**
- 左：返回书架
- 中：当前章节名
- 右：目录入口

**底栏：**
- 章节滑块：左右显示上/下一章章节号
- 4 个图标按钮：目录、亮度、字号、设置

**子选项以浮层弹出：**
- 字号：圆角浮层，A 滑块 A + 当前数值
- 亮度：同样浮层，亮度滑块
- 点击浮层外区域自动收起

**设置页面（独立页面，低频操作）：**
- 字体选择：苹方（默认）/ 宋体 / 楷体
- 行距调节：1.5x ~ 2.5x
- 页边距调节
- 翻页模式：上下滑动（默认）/ 左右翻页 / 点击翻页
- 主题：纯黑 #121212 / 暖黑 #1a1814 / 浅白 #f5f5f0 / 护眼绿 / 跟随系统

### 翻页交互（点击翻页模式）

屏幕 3x3 九宫格划分：
- 中央格：呼出菜单
- 左侧列 + 上方格：上一页
- 右侧列 + 下方格：下一页

## App 视图结构

```
App
├── 书架 (BookshelfView) — 主页，封面网格
├── 搜索 (SearchView) — 统一搜索入口
├── 书源管理 (SourceManagerView) — 导入/启用/质量检测
└── 设置 (SettingsView) — 全局偏好
     └── 阅读器 (ReaderView) — 从书架点击书籍进入
          └── 阅读器菜单 (ReaderMenuOverlay)
```
