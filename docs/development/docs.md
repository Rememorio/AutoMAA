# 文档站维护

文档站源码与 AutoMAA 位于同一仓库的 `docs/` 目录，使用 VitePress 构建，并通过 GitHub Actions 发布到 GitHub Pages。

## 本地预览

需要 Node.js 22 或更高版本：

```bash
npm ci
npm run docs:dev
```

生产构建：

```bash
npm run docs:build
npm run docs:preview
```

VitePress 构建会检查页面链接，`docs:build` 还会验证截图格式。提交前应检查标题锚点并打开关键页面，确认桌面和窄屏、深浅色、键盘焦点与中文搜索。

## 信息架构

从读者要完成的事情决定内容位置：

| 位置 | 回答的问题 |
| --- | --- |
| 根目录 `README.md` | 这是什么、适不适合我、怎样开始、去哪里求助或贡献？ |
| `guide/installation`、`guide/getting-started` | 需要准备什么，怎样跑通第一套方案？ |
| `guide/workflow`、`guide/scheduling`、`guide/updates` | 日常怎样运行、续跑、定时和维护？ |
| `tasks/` | 每项任务怎样选择，参数有什么影响？ |
| `troubleshooting/` | 这个现象是什么原因，下一步该做什么？ |
| `reference/` | 数据存在哪里，怎样备份，有哪些安全与隐私边界？ |
| `development/`、`CONTRIBUTING.md` | 如何构建、修改、验证并提交贡献？ |
| `about/`、`Assets/README.md` | 上游分工、致谢和资产授权是什么？ |
| `CHANGELOG.md`、`RELEASE.md` | 版本有哪些变化，维护者怎样发布？ |

每项用法保留一处完整说明，其他页面按需链接；不要因新增功能就在 README 末尾追加一节。首次配置只围绕完成首次运行，参数细节与维护机制留给专项指南。更新现有说明时有机改写，删除已经过时或重复的内容。

新增页面同步更新 `.vitepress/config.mts` 的统一目录；修改标题时检查入站锚点。界面术语、默认值和限制以当前实现为准，行为改变时同步对应指南与 App 内文案。

## 公开内容

README、文档站、更新日志和 GitHub Release 面向不了解维护过程的读者，内容应脱离协作背景独立成立：

- 说明产品能力、用户影响、升级步骤、兼容性和已知限制；
- 已知风险写清触发条件、结果和规避方法，不用本机测试经过代替产品结论；
- 不出现请求来源、批准过程、代理或工具名称、测试账号、私人路径及临时验收记录；
- 测试命令与维护证据留在 PR、CI 和发版检查中，不混入面向下载者的 Release Notes。

提交前运行 `./scripts/check-public-content.sh`；准备 Release Notes 时再把临时 Notes 文件传给同一脚本检查。

## 产品截图

产品截图保存在 `docs/assets/screenshots/`。更新截图时：

- 使用隔离的演示配置和通用账号名称，不得出现真实账号片段、日志或用户目录；
- 截取当前可发布版本的真实界面，不使用与实际功能不符的界面稿；
- 深色与浅色模式分别截图，并在页面中跟随文档主题切换；
- 保持 `1180 × 780 pt` 的窗口尺寸，直接取得 `2360 × 1560 px` 的 Retina 背板像素；不得将 1× 截图放大到目标尺寸；
- 使用 `screencapture -x -o -l <window-id>` 或等效的原生窗口捕获保留透明圆角，再转换为无损 WebP；不要留下与文档深浅色冲突的白角或黑角；
- 每张图片都提供准确的替代文本和一句说明；
- 界面结构或关键文案发生明显变化时，同步更新首页和首次配置指南中的截图；
- 提交前运行 `npm run docs:check-screenshots`，并在图片 100% 缩放和文档实际展示宽度下分别检查文字边缘；自动检查只能验证尺寸、编码和透明通道，不能替代视觉验收。

## 发布

对 `main` 的文档相关推送会触发 `Deploy documentation` 工作流。Pull Request 只执行构建，不部署线上站点。

不要提交 `node_modules/`、`.vitepress/cache/` 或 `.vitepress/dist/`。部署失败时先查看 GitHub Actions 日志，确认依赖锁文件、站内链接、Pages 权限和 `/AutoMAA/` 基础路径。
