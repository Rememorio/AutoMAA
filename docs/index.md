---
layout: home

hero:
  name: AutoMAA
  text: 把 MAA 日常，组织成可复用自动化方案
  tagline: 配好客户端与账号，安排任务和时间。AutoMAA 依次完成每套日常，你可以随时查看结果、处理异常或安全停止。
  image:
    src: /automaa-hero-icon.webp
    alt: AutoMAA 应用图标
  actions:
    - theme: brand
      text: 下载与安装
      link: /guide/installation
    - theme: alt
      text: 首次配置
      link: /guide/getting-started
    - theme: alt
      text: GitHub
      link: https://github.com/Rememorio/AutoMAA

features:
  - icon: ⛓️
    title: 可复用方案
    details: 客户端和账号只配置一次，轻量收菜、完整日常和周末剿灭各用一套任务与参数。
  - icon: 🛡️
    title: 多客户端与账号
    details: 按顺序处理每个客户端与账号队列，确认当前客户端关闭、连接释放后，再启动下一个。
  - icon: ↩️
    title: 当日断点
    details: 成功步骤按方案与日期记录，失败后可以续跑，不同方案不会互相误跳过。
  - icon: ⚙️
    title: 熟悉的 MAA 任务
    details: 作战、公招、基建、信用购物与奖励领取，既可使用推荐参数，也能按方案精细调整。
  - icon: 📋
    title: 结果与异常
    details: 在活动记录中查看每次运行的结果、失败原因和日志，需要人工处理时接收系统通知。
  - icon: 🕗
    title: 每方案定时
    details: 每个方案分别选择星期和时间。在用户登录、Mac 唤醒时，主 App 退出后仍能按时运行。
---

<figure class="slogan-artwork">
  <img src="/automaa-slogan.webp" width="1836" height="856" loading="lazy" decoding="async" alt="直到日常变成一次运行。Till the Dailies Become One Run." />
</figure>

<section class="product-showcase" aria-labelledby="product-tour-title">
  <div class="showcase-heading">
    <span class="showcase-kicker">工作方式</span>
    <h2 id="product-tour-title">一眼看清每套日常怎样执行</h2>
    <p>从总览确认方案、目标账号和运行条件；需要调整时，再进入客户端或任务配置。</p>
  </div>

  <figure class="product-shot product-shot-wide">
    <img class="theme-shot theme-shot-light" src="./assets/screenshots/overview-light.webp" width="2360" height="1560" alt="AutoMAA 今日总览：展示简中服与日服两个客户端、三个演示账号和两套日常方案" />
    <img class="theme-shot theme-shot-dark" src="./assets/screenshots/overview-dark.webp" width="2360" height="1560" alt="AutoMAA 今日总览：展示简中服与日服两个客户端、三个演示账号和两套日常方案" />
    <figcaption><strong>今日总览</strong><span>先比较全部方案的状态摘要，再展开当前方案的路径与检查详情。</span></figcaption>
  </figure>

  <div class="product-shot-grid">
    <figure class="product-shot">
      <img class="theme-shot theme-shot-light" src="./assets/screenshots/client-settings-light.webp" width="2360" height="1560" loading="lazy" decoding="async" alt="AutoMAA 客户端配置：服务器、应用、MaaTools、独立 Profile、账号队列和生命周期保护" />
      <img class="theme-shot theme-shot-dark" src="./assets/screenshots/client-settings-dark.webp" width="2360" height="1560" loading="lazy" decoding="async" alt="AutoMAA 客户端配置：服务器、应用、MaaTools、独立 Profile、账号队列和生命周期保护" />
      <figcaption><strong>客户端与账号队列</strong><span>每个客户端独立配置，顺序、连接与关闭边界都清晰可见。</span></figcaption>
    </figure>
    <figure class="product-shot">
      <img class="theme-shot theme-shot-light" src="./assets/screenshots/task-settings-light.webp" width="2360" height="1560" loading="lazy" decoding="async" alt="AutoMAA 任务配置：理智作战、公开招募、基建收菜和领取奖励可排序，并可分别启用自定义参数" />
      <img class="theme-shot theme-shot-dark" src="./assets/screenshots/task-settings-dark.webp" width="2360" height="1560" loading="lazy" decoding="async" alt="AutoMAA 任务配置：理智作战、公开招募、基建收菜和领取奖励可排序，并可分别启用自定义参数" />
      <figcaption><strong>熟悉的 MAA 任务参数</strong><span>需要时精细配置，不需要时关闭开关使用 MAA 推荐值。</span></figcaption>
    </figure>
  </div>
</section>

<section class="home-note">
  <div>
    <h2>开始前准备</h2>
    <p>需要 Apple Silicon Mac、macOS 14，以及独立安装的 MAA 和 PlayCover + MaaTools 游戏环境。<a href="./guide/installation">安装指南</a>会带你完成准备，再从一个客户端、一套方案开始。</p>
  </div>
  <div>
    <h2>遇到问题或想参与改进？</h2>
    <p>先按现象查阅<a href="./troubleshooting/common">常见问题</a>。欢迎反馈使用体验、改进文档或<a href="./development/">参与开发</a>；AutoMAA 与上游的分工见<a href="./about/credits">项目关系与致谢</a>。</p>
  </div>
</section>
