import { defineConfig } from "vitepress"

export default defineConfig({
  lang: "zh-CN",
  title: "AutoMAA",
  titleTemplate: ":title · AutoMAA 文档",
  description: "AutoMAA 安装、配置、任务编排与故障排查文档",
  base: "/AutoMAA/",
  cleanUrls: true,
  lastUpdated: true,
  sitemap: {
    hostname: "https://rememorio.github.io/AutoMAA/",
  },
  head: [
    ["meta", { name: "theme-color", content: "#12aead" }],
    ["meta", { property: "og:type", content: "website" }],
    ["meta", { property: "og:title", content: "AutoMAA 文档" }],
    ["meta", { property: "og:url", content: "https://rememorio.github.io/AutoMAA/" }],
    ["meta", { property: "og:image", content: "https://rememorio.github.io/AutoMAA/og.png" }],
    [
      "meta",
      {
        property: "og:description",
        content: "可靠、可配置、可恢复的 macOS MAA 多客户端工作流",
      },
    ],
    ["meta", { name: "twitter:card", content: "summary_large_image" }],
    ["meta", { name: "twitter:title", content: "AutoMAA 文档" }],
    [
      "meta",
      {
        name: "twitter:description",
        content: "可靠、可配置、可恢复的 macOS MAA 多客户端工作流",
      },
    ],
    ["meta", { name: "twitter:image", content: "https://rememorio.github.io/AutoMAA/og.png" }],
  ],
  themeConfig: {
    siteTitle: "AutoMAA 文档",
    nav: [
      { text: "首页", link: "/" },
      { text: "开始使用", link: "/guide/installation" },
      { text: "任务配置", link: "/tasks/fight" },
      { text: "常见问题", link: "/troubleshooting/common" },
      {
        text: "项目",
        items: [
          { text: "GitHub", link: "https://github.com/Rememorio/AutoMAA" },
          { text: "下载最新版", link: "https://github.com/Rememorio/AutoMAA/releases/latest" },
          { text: "更新日志", link: "https://github.com/Rememorio/AutoMAA/blob/main/CHANGELOG.md" },
          { text: "MAA 文档", link: "https://docs.maa.plus/zh-cn/" },
        ],
      },
    ],
    sidebar: {
      "/guide/": [
        {
          text: "开始使用",
          items: [
            { text: "下载与安装", link: "/guide/installation" },
            { text: "首次配置", link: "/guide/getting-started" },
            { text: "理解执行流程", link: "/guide/workflow" },
            { text: "每日自动运行", link: "/guide/scheduling" },
          ],
        },
      ],
      "/tasks/": [
        {
          text: "任务配置",
          items: [
            { text: "配置模式", link: "/tasks/" },
            { text: "理智作战", link: "/tasks/fight" },
            { text: "公开招募", link: "/tasks/recruit" },
            { text: "基建收菜", link: "/tasks/infrast" },
            { text: "领取奖励", link: "/tasks/award" },
          ],
        },
      ],
      "/troubleshooting/": [
        {
          text: "故障排查",
          items: [
            { text: "常见问题", link: "/troubleshooting/common" },
            { text: "游戏更新与人工处理", link: "/troubleshooting/game-update" },
          ],
        },
      ],
      "/reference/": [
        {
          text: "参考",
          items: [
            { text: "数据与配置", link: "/reference/configuration" },
            { text: "安全与隐私边界", link: "/reference/safety" },
          ],
        },
      ],
      "/development/": [
        {
          text: "开发",
          items: [
            { text: "参与开发", link: "/development/" },
            { text: "文档站维护", link: "/development/docs" },
          ],
        },
      ],
      "/about/": [
        {
          text: "关于",
          items: [{ text: "项目关系与致谢", link: "/about/credits" }],
        },
      ],
    },
    socialLinks: [
      { icon: "github", link: "https://github.com/Rememorio/AutoMAA" },
    ],
    search: {
      provider: "local",
      options: {
        translations: {
          button: { buttonText: "搜索文档", buttonAriaLabel: "搜索文档" },
          modal: {
            noResultsText: "没有找到相关内容",
            resetButtonTitle: "清除查询",
            footer: {
              selectText: "选择",
              navigateText: "切换",
              closeText: "关闭",
            },
          },
        },
      },
    },
    outline: { level: [2, 3], label: "本页内容" },
    lastUpdated: { text: "最后更新" },
    docFooter: { prev: "上一篇", next: "下一篇" },
    editLink: {
      pattern: "https://github.com/Rememorio/AutoMAA/edit/main/docs/:path",
      text: "在 GitHub 上编辑此页",
    },
    footer: {
      message: "AutoMAA 是独立社区项目，自动化能力由 MAA / MaaCore 提供。",
      copyright: "源代码与文档采用 MIT License；视觉资产另见仓库声明。",
    },
    returnToTopLabel: "返回顶部",
    sidebarMenuLabel: "文档目录",
    darkModeSwitchLabel: "切换深浅色",
    langMenuLabel: "切换语言",
    externalLinkIcon: true,
  },
})
