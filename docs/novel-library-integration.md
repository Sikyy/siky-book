# NovelReader - 私人书库对接

## 关联项目

- **私人小说库 (novel-library)**: `/Users/siky/code/novel-library`
  - Python 项目，负责爬取小说并提供 API
  - 本项目 (NovelReader) 通过 Legado 书源格式消费其 API

## 联调方式

1. 启动 novel-library API 服务:
   ```bash
   cd /Users/siky/code/novel-library
   python run_api.py    # 默认端口 8900
   ```

2. 在 NovelReader 中导入书源 JSON (见 novel-library 的 docs/architecture.md)

3. API 地址:
   - 本机调试: `http://localhost:8900`
   - 同局域网 iPhone 调试: `http://<Mac的局域网IP>:8900`

## API 接口对应关系

| NovelReader 功能 | novel-library 接口 |
|-----------------|-------------------|
| 搜索书籍 | `GET /search?q=关键词` |
| 书籍详情/封面 | `GET /book/{id}` |
| 获取章节目录 | `GET /book/{id}/toc` |
| 获取章节正文 | `GET /book/{id}/chapter/{index}` |

## 注意事项

- 真机调试时需要用 Mac 局域网 IP，不能用 localhost
- 书源 JSON 中的 URL 需要相应修改
- novel-library 的 data/ 目录存储所有小说数据，不入 git
