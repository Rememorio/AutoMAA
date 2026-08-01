---
layout: home

hero:
  name: AutoMAA
  text: 把多个 MAA 日常，串成一条可靠工作流
  tagline: 原生 macOS、多客户端、多账号、顺序可配置；安全切换、失败可恢复、每天只需要按一次开始。
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
    title: 通用工作流
    details: 自由添加和排序客户端、账号与任务，不预置任何开发者账号或本机路径。
  - icon: 🛡️
    title: 安全切换
    details: 当前客户端关闭并确认 MaaTools 连接释放后，才会启动下一项。
  - icon: ↩️
    title: 当日断点
    details: 成功步骤按日期记录，失败后可以续跑，不重复消耗已经完成的任务。
  - icon: ⚙️
    title: MAA 参数
    details: 每项任务可选择 MAA 默认参数，或启用 AutoMAA 的清晰可视化配置。
  - icon: 🏭
    title: 不换班收菜
    details: 基建支持只收制造、贸易、会客室产物，并可配置无人机用途。
  - icon: 🕗
    title: 每日自动运行
    details: 验证流程稳定后，可交给 macOS LaunchAgent 在用户登录状态下定时执行。
---

<section class="product-showcase" aria-labelledby="product-tour-title">
  <div class="showcase-heading">
    <span class="showcase-kicker">PRODUCT TOUR</span>
    <h2 id="product-tour-title">一眼看清今天会怎样执行</h2>
    <p>客户端、账号、任务数量和执行顺序集中呈现；运行前检查通过后，再交给 AutoMAA 串行完成。</p>
  </div>

  <figure class="product-shot product-shot-wide">
    <img src="./assets/screenshots/overview.jpg" width="1162" height="768" alt="AutoMAA 今日总览：展示国服与日服两个客户端、三个演示账号、十二个日常步骤和每天八点自动运行" />
    <figcaption><strong>今日总览</strong><span>先确认顺序与安全检查，再开始完整工作流。</span></figcaption>
  </figure>

  <div class="product-shot-grid">
    <figure class="product-shot">
      <img src="./assets/screenshots/client-settings.jpg" width="1162" height="768" loading="lazy" alt="AutoMAA 客户端配置：服务器、应用、MaaTools、独立 Profile、账号队列和生命周期保护" />
      <figcaption><strong>客户端与账号队列</strong><span>每个客户端独立配置，顺序、连接与关闭边界都清晰可见。</span></figcaption>
    </figure>
    <figure class="product-shot">
      <img src="./assets/screenshots/task-settings.jpg" width="1162" height="768" loading="lazy" alt="AutoMAA 任务配置：理智作战、公开招募、基建收菜和领取奖励可排序，并可分别启用自定义参数" />
      <figcaption><strong>熟悉的 MAA 任务参数</strong><span>需要时精细配置，不需要时关闭开关沿用 MAA 默认值。</span></figcaption>
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
