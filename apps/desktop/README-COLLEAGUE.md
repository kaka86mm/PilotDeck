# PilotDeck 安装指南

## 一分钟搞定

### 1. 下载安装

打开浏览器访问：

> https://github.com/kaka86mm/PilotDeck/releases/latest

下载 `PilotDeck-0.0.11-win-x64.exe`，双击安装。

安装包约 500MB，已内置所有依赖（Node.js、Python、Git Bash、poppler、GitHub CLI），**无需额外安装任何东西**。

### 2. 获取 API Key

1. 打开 https://acccode.store 注册账号
2. 在控制台获取 API Key（`sk-` 开头的字符串）

### 3. 填入 Key

有两种方式，选其一即可：

**方式 A：界面填写（推荐）**
- 启动 PilotDeck → 左下角「设置」→ 填入 API Key → 保存

**方式 B：编辑配置文件**
- 用记事本打开 `C:\Users\你的用户名\.pilotdeck\pilotdeck.yaml`
- 找到 `apiKey:` 那一行，替换为你的 key：
  ```yaml
  apiKey: sk-你的密钥
  ```
- 保存，重启 PilotDeck

### 4. 开始使用

直接在对话框里输入你的需求即可，例如：

- "帮我做一个季度销售汇报 PPT"
- "搜索一下最近的 AI 行业新闻"
- "把这个 Word 文档转成 PDF"
- "创建一个 Excel 数据分析表"

---

## 内置技能

| 类别 | 技能 | 说明 |
|------|------|------|
| 文档 | docx | 创建/编辑 Word 文档 |
| 文档 | pptx | 创建/编辑 PowerPoint 演示文稿 |
| 文档 | pdf | 创建/编辑/合并 PDF |
| 文档 | spreadsheets | 创建/编辑 Excel 电子表格 |
| 搜索 | anysearch | 网络搜索（无需密钥） |
| 工具 | github | GitHub 操作（已内置 gh CLI） |
| 工具 | powershell | 执行 Windows 命令 |
| 工具 | diagram-maker | 生成图表/流程图 |
| 工具 | summarize | 总结网页/视频/文章 |
| 工具 | skill-creator | 创建自定义技能 |

---

## 自动更新

应用启动后会自动检查新版本。有更新时会弹窗提示，点击「前往下载」即可。

手动检查：按 `Alt` 显示菜单栏 → 帮助 → 检查更新。

---

## 常见问题

**Q: 安装后打开是空白/报错？**
A: 等 30 秒（首次启动需要解压内置资源）。如果超过 1 分钟仍有问题，删除 `C:\Users\你的用户名\AppData\Roaming\PilotDeck` 后重启。

**Q: 网络搜索不工作？**
A: 检查网络连接。anysearch 使用匿名模式（低速率），如需更高限额，到 https://anysearch.com/console/api-keys 申请免费 key，填入 `~/.pilotdeck/skills/anysearch/.env`。

**Q: 如何更新？**
A: 应用会自动提醒。也可以直接去 Release 页面下载新版 exe，双击安装即可覆盖更新（不会丢失你的配置和数据）。
