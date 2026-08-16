---
layout: home

hero:
  name: AutoMAA
  text: 把 MAA 日常，组织成可复用自动化方案
  tagline: 原生 macOS、多客户端、多账号；轻量收菜与完整日常独立配置、手动或定时运行。
  image:
    src: /automaa-hero-icon.webp
    alt: AutoMAA 应用图标
  actions:
    - theme: brand
      text: 下载与安装
      link: /guide/installation
    - theme: alt
      text: 5 分钟完成配置
      link: /guide/getting-started
    - theme: alt
      text: GitHub
      link: https://github.com/Rememorio/AutoMAA

features:
  - icon: ⛓️
    title: 可复用方案
    details: 客户端和账号只配置一次，任意创建轻量、完整、周末或临时方案，不预置开发者数据。
  - icon: 🛡️
    title: 安全切换
    details: 当前客户端关闭并确认 MaaTools 连接释放后，才会启动下一项。
  - icon: ↩️
    title: 当日断点
    details: 成功步骤按方案与日期记录，失败后可以续跑，不同方案不会互相误跳过。
  - icon: ⚙️
    title: MAA 参数
    details: 每项任务可选择对齐当前 MAA 的推荐参数，或启用 AutoMAA 的清晰可视化配置。
  - icon: 🏭
    title: 三种基建模式
    details: 轻量方案可仅收菜，完整方案可换班，也可读取 MAA 自定义排班文件。
  - icon: 🕗
    title: 每方案定时
    details: 每个方案都有独立的 macOS LaunchAgent，也可以随时手动运行或安全停止。
---

<figure class="slogan-artwork">
  <img src="/automaa-slogan.webp" width="1836" height="856" loading="lazy" decoding="async" alt="直到日常变成一次运行。Till the Dailies Become One Run." />
</figure>

<section class="product-showcase" aria-labelledby="product-tour-title">
  <div class="showcase-heading">
    <span class="showcase-kicker">PRODUCT TOUR</span>
    <h2 id="product-tour-title">一眼看清每套日常怎样执行</h2>
    <p>方案、目标账号、任务组合、定时时间和各自的运行检查状态集中呈现；确认后，再交给 AutoMAA 串行完成。</p>
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
    <h2>第一次打开被 macOS 拦截？</h2>
    <p>当前公开版本采用临时代码签名、尚未完成 Apple 公证。请先确认下载来源与校验值，再通过系统提供的“仍要打开”流程授权这一个 App。</p>
    <span class="security-path">系统设置 → 隐私与安全性 → 仍要打开</span>
  </div>
  <div>
    <h2>AutoMAA 与 MAA</h2>
    <p>AutoMAA 负责编排；<a href="https://github.com/MaaAssistantArknights/MaaAssistantArknights">MAA / MaaCore</a> 负责识别与操作。两者各司其职。</p>
  </div>
</section>
