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

VitePress 构建会检查站内链接。提交前应打开关键页面，确认桌面和移动宽度、深浅色、键盘焦点与中文搜索。

## 信息架构

- `guide/`：安装、首次配置、工作流和定时；
- `tasks/`：用户可配置的任务；
- `troubleshooting/`：常见问题和游戏更新；
- `reference/`：配置、安全与隐私；
- `development/`：开发和文档维护；
- `about/`：项目关系、致谢和声明。

新增页面后同步更新 `.vitepress/config.mts` 中的导航或侧边栏。用户行为改变时同时检查 README 和 App 内文案。

## 产品截图

产品截图保存在 `docs/assets/screenshots/`。更新截图时：

- 使用隔离的演示配置和通用账号名称，不得出现真实账号片段、日志或用户目录；
- 截取当前可发布版本的真实界面，不使用与实际功能不符的界面稿；
- 深色与浅色模式分别截图，并在页面中跟随文档主题切换；
- 使用 2× Retina 分辨率的无损 WebP，保留统一窗口比例，并裁掉窗口外围的透明像素；
- 每张图片都提供准确的替代文本和一句说明；
- 界面结构或关键文案发生明显变化时，同步更新首页和首次配置指南中的截图。

## 发布

对 `main` 的文档相关推送会触发 `Deploy documentation` 工作流。Pull Request 只执行构建，不部署线上站点。

不要提交 `node_modules/`、`.vitepress/cache/` 或 `.vitepress/dist/`。部署失败时先查看 GitHub Actions 日志，确认依赖锁文件、站内链接、Pages 权限和 `/AutoMAA/` 基础路径。
