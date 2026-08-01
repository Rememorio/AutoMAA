# 参与开发

AutoMAA 使用 Swift 6.2、SwiftUI 和 Swift Package Manager，最低支持 macOS 14。

## 获取源码

```bash
git clone https://github.com/Rememorio/AutoMAA.git
cd AutoMAA
swift test --parallel
./scripts/build-app.sh
open .build/AutoMAA.app --args --data-directory /tmp/automaa-development
```

项目分为：

- `AutoMAA`：SwiftUI 图形界面；
- `AutoMAAKit`：配置、任务生成、工作流和系统集成；
- `AutoMAARunner`：LaunchAgent 使用的无界面入口。

## 开始贡献

请依次阅读：

- [AGENTS.md](https://github.com/Rememorio/AutoMAA/blob/main/AGENTS.md)：架构、安全边界和编码代理规则；
- [CONTRIBUTING.md](https://github.com/Rememorio/AutoMAA/blob/main/CONTRIBUTING.md)：分支、Commit、PR 与测试规范；
- [RELEASE.md](https://github.com/Rememorio/AutoMAA/blob/main/RELEASE.md)：维护者发版流程。

外部贡献者必须通过 fork、分支和 Pull Request 合入 `main`。涉及账号切换、端口、断点、取消和 MAA 参数的改动需要相应回归测试。

## 测试隔离

测试不得连接真实游戏或用户数据：

- 使用临时 `AppDirectories(root:)`；
- 使用假 Bundle Identifier 与测试专用端口；
- 不使用默认 MaaTools 地址或端口；
- 不读取 `~/Library/Application Support/AutoMAA`；
- 不依赖网络、PlayCover 或已登录账号。

Debug 构建支持 `--data-directory <临时目录>`，它会同时隔离配置、日志和 LaunchAgent，并关闭系统 LaunchAgent 集成与自动更新检查。提交前至少运行 `swift test --parallel` 和 `git diff --check`；涉及发布结构时运行 `./scripts/verify-release.sh`。
