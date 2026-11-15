# Manual discovery observations

Use the [version 1 query set](queries.v1.json) and [empty observation template](observation.template.json) to make small, comparable observations. These files contain no measured results. They do not run searches, schedule work or collect analytics.

## Repeatable method

1. Choose the provider, surface and inspection limit **before** looking at results. For a web search, a limit such as the first 10 result entries defines the inspected sample; it is not a ranking claim. For an AI answer, inspect that one answer and its displayed source links. Run only the selected queries, once per planned observation.
2. Copy the template outside tracked source and set `is_template` to `false`. Use one record per query, provider and time. Copy the exact query, ID, language and query-set version. Do not quietly rephrase a query or add prior conversation context to improve the result.
3. Record a timezone-aware ISO timestamp, the visible provider/product name and its version/model label if exposed. Use `unknown` for an undisclosed provider and `null` for an unexposed version. If a tool merges providers or batches without per-query attribution, retain that limitation; do not assign results or ranks to Google or Bing by guesswork.
4. Set `search_ran` from observed behavior: `true`, `false`, or `null` when unknown. An AI answer mentioning a source does not prove that a web search ran. Record the underlying `search_provider` only if exposed; it may differ from the AI product.
5. Record the outcome below and only the public page URLs actually observed. Keep failed and empty observations. A blocked page is not a negative result, and a successful page fetch is not indexing confirmation.
6. Repeat later using the same query-set version, provider, surface and inspection limit. Record each attempt separately, including failures and product/version changes. No cadence is automatic. Do not immediately repeat until a favorable answer appears or combine unlike providers into one score.
7. Compare observations as dated samples. Search appearance, confirmed indexing, AI citation, attribution quality and traffic are different measures. This template has no traffic, conversion, rank or causal-improvement fields.

The EN/ZH queries are paired research questions, not guaranteed equivalent result populations. Keep results by language. Preserve `queries.v1.json` unchanged once used: a changed query set gets a new versioned file and version; retain old files and IDs for comparison. Changing this template's field meanings requires a new `schema_version`.

## Fields and outcomes

For `web-search` and `ai-answer`, `query_set.query_id`, `query` and `language` must match one versioned query exactly. `inspection_limit` is a short description of what was inspected, not an observed rank. `target_page_urls` contains the public pages being assessed; `public_source_urls` contains the public result or citation destinations actually observed. Neither array contains search-session URLs.

`surface` is one of `web-search`, `ai-answer`, or `indexing-status`. Keep separate records for Google Search, Bing Search, an AI product, Google Search Console, and Bing Webmaster Tools; an AI product's backend provider is not necessarily known.

| Outcome | Surface | Meaning |
| --- | --- | --- |
| `search-unavailable` | Web search / AI answer | Search capability was unavailable. Set `search_ran` to `false`; do not label it no result. |
| `access-failure` | Any | The selected surface, or a source needed to check attribution, could not be inspected because of a login/access block, rate limit or other failure. Retain any already observed public links and a short reason without account details; search execution may be unknown. |
| `no-result` | Web search | No target page appeared within the declared inspected sample. Search must have run; this does not prove absence from the engine's index. |
| `search-result-observed` | Web search | A target page appeared as a result. Record its direct URL; do not infer Webmaster indexing status or a durable rank. |
| `no-citation` | AI answer | The inspected answer has no citation to a target page. It may contain other citations or an uncited mention. Record those distinctions in a short note. |
| `citation-observed` | AI answer | The answer explicitly cites a target page and the associated claim is supported by that page. Record the actual citation URL. |
| `attribution-error` | AI answer | An answer attributes a claim to a source incorrectly, or cites a page that does not support the associated claim. Briefly paraphrase the mismatch in `attribution_note`; do not publish the entire answer or conversation. |
| `indexed-page-observed` | Indexing status only | An authorized owner directly checked an explicit indexed status for the public target URL in the named webmaster product. Search results, HTTP 200, sitemap submission and IndexNow receipt do not qualify. |
| `not-indexed-observed` | Indexing status only | An authorized owner directly checked an explicit not-indexed status for the target URL. A missing search result or unavailable dashboard does not qualify. |

An indexing-status record is a separate observation, not a query run. Leave `query_set`, `query`, `language`, `search_provider` and `inspection_limit` as `null`, and set `search_ran` to `false`. Retain the named webmaster product, check time, public target URL and explicit outcome only. Its account-side evidence stays private. Do not add owner names, property IDs or dashboard URLs.

Use `notes` for short, factual limitations such as a stale extract, undisclosed provider version or an uncited mention. Leave `attribution_note` null except when explaining an attribution check. Empty template values are placeholders, not observations or zeros.

## Public-data boundary

Keep raw observations private by default. Publish a summary only after checking that it contains intentionally public query text, public source/target URLs, provider labels, timestamps, outcomes and short original notes. Preserve uncertainty and the inspected sample size.

Never publish account emails, dashboard/property identifiers, cookies, tokens, session URLs, private screenshots, private conversations, or copies of complete result/answer pages. Remove tracking/session parameters from evidence links while preserving the public page identity. A restricted URL is not public evidence just because it opens in the maintainer's browser.

No live observation is included here. These materials make no claim about traffic, rankings, citations, indexing success or improvement caused by a site change. See the [discovery guide](../search-discovery.md) for primary search-engine documentation and the distinction between deployment and indexing.

---

## 中文说明

使用[第 1 版查询集](queries.v1.json)与[空白观察模板](observation.template.json)记录少量、可比较的观察。这些文件没有实测结果，不会执行搜索、安排定时任务或收集分析数据。

### 可重复的方法

1. 查看结果前，先确定提供方、观察界面与检查范围。网页搜索可约定检查前 10 个结果项；这是样本范围，不是排名结论。AI 回答则检查该条回答及其显示的来源。每次计划内观察只执行选定查询一次。
2. 将模板复制到版本控制之外，把 `is_template` 改为 `false`。每个查询、提供方和时间分别建一条记录，原样保留查询、ID、语言和查询集版本。不要为了改善结果而悄悄改写查询或加入前文。
3. 记录带时区的 ISO 时间戳、实际显示的提供方/产品名称，以及公开显示的版本或模型标签。提供方未披露时写 `unknown`，版本未披露时写 `null`。工具若合并提供方或批量结果却未标注各查询归属，应保留此限制，不猜测 Google/Bing 归属或排名。
4. 根据可观察行为填写 `search_ran`：已执行为 `true`，未执行为 `false`，不清楚为 `null`。AI 提到来源不代表执行过搜索；底层 `search_provider` 只有在明确显示时才填写，它可能不同于 AI 产品。
5. 记录下表结果及实际观察到的公开页面 URL，保留失败与空结果。页面被阻止访问不是负面搜索结果，成功抓取页面也不是已被索引的证明。
6. 后续复查应保持查询集版本、提供方、界面与检查范围一致，每次单独记录，并保留失败、产品和版本变化。这里没有自动频率，不应持续重试直到出现满意答案，也不将不同提供方合成一个分数。
7. 只将观察视为带日期的样本。搜索出现、确认索引、AI 引用、归因质量与流量是不同指标；模板不包含流量、转化、排名或因果提升字段。

中英文查询是配对研究问题，不保证结果群体等价，应按语言分别记录。使用后保持 `queries.v1.json` 不变；修改查询集时建立新版本文件并更新版本，保留旧文件和 ID。模板字段含义变化时更新 `schema_version`。

### 字段与结果

网页搜索和 AI 回答的 `query_set.query_id`、`query`、`language` 必须与某条固定版本查询完全一致。`inspection_limit` 简述检查范围，不填观察到的排名。`target_page_urls` 是待评估公开页面，`public_source_urls` 是实际出现的结果或引用目标，两者都不保存搜索会话 URL。

`surface` 分为 `web-search`、`ai-answer`、`indexing-status`。Google 搜索、Bing 搜索、各 AI 产品、Google Search Console 与 Bing Webmaster Tools 分开记录，不假设 AI 产品的搜索后端已知。

| 结果值 | 适用界面 | 含义 |
| --- | --- | --- |
| `search-unavailable` | 网页搜索 / AI 回答 | 无搜索能力，`search_ran` 为 `false`，不能写成没有结果。 |
| `access-failure` | 任意 | 登录/访问限制、限流或其他故障使指定界面或归因核查所需来源无法检查。保留已观察到的公开链接并简述原因，不含账号信息；搜索是否执行可以未知。 |
| `no-result` | 网页搜索 | 已执行搜索，但约定样本内没有目标页面；不证明索引中不存在该页面。 |
| `search-result-observed` | 网页搜索 | 目标页面实际出现在结果中，记录直接 URL；不推断 Webmaster 索引状态或稳定排名。 |
| `no-citation` | AI 回答 | 回答未引用目标页面，仍可能引用其他页面或无引用地提及目标，应简述区别。 |
| `citation-observed` | AI 回答 | 回答明确引用目标页面，且相关说法得到该页面支持，记录实际引用 URL。 |
| `attribution-error` | AI 回答 | 错误归因，或所引页面不支持相关说法。用 `attribution_note` 简短转述不一致，不发布整篇回答或会话。 |
| `indexed-page-observed` | 仅索引状态 | 授权所有者在指定 Webmaster 产品中直接核查到目标公开 URL 明确处于已索引状态。搜索结果、HTTP 200、提交站点地图和 IndexNow 回执均不算。 |
| `not-indexed-observed` | 仅索引状态 | 授权所有者直接核查到目标 URL 明确处于未索引状态。搜索中没找到或无法访问控制台均不算。 |

索引状态是单独观察，不是查询运行：将 `query_set`、`query`、`language`、`search_provider`、`inspection_limit` 设为 `null`，`search_ran` 设为 `false`。只保留产品名称、核查时间、公开目标 URL 与明确结果；账号侧证据保持私密，不添加所有者姓名、属性 ID 或控制台 URL。

`notes` 只写简短事实限制，如摘要过时、提供方版本未披露或没有引用的提及。`attribution_note` 仅用于解释归因核查，其他时候为 null。模板的空值只是占位，不是实测结果或零。

### 公开边界

原始观察默认私密。发布摘要前，只保留有意公开的查询、来源/目标 URL、提供方标签、时间戳、结果及简短原创备注，并保留不确定性和检查范围。

禁止发布账号邮箱、控制台/属性标识、Cookie、令牌、会话 URL、私密截图、私密会话或整页结果/回答。证据链接应去除跟踪和会话参数，同时保留公开页面身份。维护者浏览器能打开的受限 URL 不因此成为公开证据。

这里没有实时观察，也不声称流量、排名、引用、索引成功或网站变更导致的提升。[发现指南](../search-discovery.md)提供搜索引擎一手文档，并区分部署与索引。
