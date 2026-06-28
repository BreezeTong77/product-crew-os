# 知识图谱实体定义

## 核心实体类型

### 1. Product（产品）

**定义**：正在设计或评审的AI硬件产品

**属性**：
- name: 产品名称
- category: 产品类别（AI玩具/机器人/其他）
- stage: 当前阶段（创意/原型/工程化/量产）
- target_price: 目标售价
- target_users: 目标用户群体
- status: 状态（进行中/已暂停/已终止）

**关系**：
- targets → UserPersona（目标用户）
- competes_with → Competitor（竞品）
- uses → TechSolution（技术方案）
- has_decision → Decision（相关决策）

### 2. UserPersona（用户画像）

**定义**：产品的目标用户群体描述

**属性**：
- name: 画像名称/代号
- age_range: 年龄段
- city_tier: 城市级别
- income: 收入水平
- pain_points: 核心痛点
- use_cases: 使用场景
- verified: 是否已验证（true/false）

**关系**：
- targeted_by → Product（被哪些产品目标）
- compared_in → Decision（参与哪些决策）

### 3. Competitor（竞品）

**定义**：市场上的竞争产品或解决方案

**属性**：
- name: 竞品名称
- company: 所属公司
- price: 价格
- strengths: 优势
- weaknesses: 劣势
- threat_level: 威胁等级（高/中/低）

**关系**：
- competes_with → Product（与哪些产品竞争）
- referenced_in → Decision（被哪些决策引用）

### 4. TechSolution（技术方案）

**定义**：产品采用的技术实现方案

**属性**：
- name: 方案名称
- category: 类别（硬件/软件/算法）
- cost_estimate: 成本估算
- performance_metrics: 性能指标
- risks: 风险点
- status: 状态（评估中/已选定/已废弃）

**关系**：
- used_by → Product（被哪些产品使用）
- alternative_to → TechSolution（替代方案）
- decided_in → Decision（在哪些决策中确定）

### 5. Decision（决策）

**定义**：产品开发过程中的关键决策

**属性**：
- title: 决策标题
- date: 决策日期
- content: 决策内容
- reasoning: 决策理由
- assumptions: 前提假设
- expected_outcome: 预期结果
- status: 状态（已确认/已变更/已废弃）

**关系**：
- belongs_to → Product（属于哪个产品）
- impacts → TechSolution（影响哪些技术方案）
- based_on → UserPersona（基于哪些用户画像）
- considers → Competitor（考虑了哪些竞品）

## 实体创建时机

### 自动创建

以下情况自动创建实体：
- 用户首次描述产品想法 → 创建 Product
- 用户定义目标用户 → 创建 UserPersona
- 用户提及竞品 → 创建 Competitor
- 用户描述技术方案 → 创建 TechSolution
- 用户做出重要决策 → 创建 Decision

### 手动创建

拷打过程中，主动询问并创建：
```markdown
我将在知识图谱中记录这个产品，方便后续追踪。

- 产品名称：[从用户输入提取]
- 当前阶段：创意萌芽期
- 是否需要创建相关实体？
  - [ ] 目标用户画像
  - [ ] 主要竞品
  - [ ] 技术方案选型
```

## 关系建立规则

### 产品-用户关系
```
Product --targets--> UserPersona
```
**触发条件**：用户明确说明目标用户时

### 产品-竞品关系
```
Product --competes_with--> Competitor
```
**触发条件**：用户提及竞品或进行竞品分析时

### 产品-技术关系
```
Product --uses--> TechSolution
```
**触发条件**：用户描述技术方案选型时

### 产品-决策关系
```
Product --has_decision--> Decision
```
**触发条件**：用户做出重要决策时

### 决策-假设关系
```
Decision --based_on--> UserPersona
Decision --considers--> Competitor
Decision --selects--> TechSolution
```
**触发条件**：创建决策时，关联相关实体

## 知识检索规则

### 自动检索时机

每次拷打会话开始时，自动检索：
1. 当前产品的所有相关实体
2. 历史决策及其前提假设
3. 已确认的技术方案
4. 已定义的用户画像

### 检索查询示例

```
# 检索产品相关信息
search_nodes("Product:AIMANBO")

# 检索未验证的用户假设
search_nodes("UserPersona verified:false")

# 检索待确认的决策
search_nodes("Decision status:进行中")

# 检索被弃用的技术方案
search_nodes("TechSolution status:已废弃")
```

### 检索结果应用

```markdown
根据知识图谱记录，我注意到：

1. **已确认的用户画像**：[画像名称] - [关键特征]
2. **历史决策**：你之前决定 [决策内容]，基于假设 [假设]
3. **当前技术方案**：[方案名称] - [状态]

这些信息是否与当前讨论相关？有变化需要更新吗？
```

## 实体更新规则

### 状态变更

| 原状态 | 新状态 | 触发条件 |
|-------|-------|---------|
| 评估中 | 已选定 | 用户明确确认选择 |
| 已选定 | 已变更 | 用户改变方案 |
| 已确认 | 已废弃 | 决策前提假设失效 |
| 未验证 | 已验证 | 用户提供验证数据 |

### 属性更新

重要属性变更时，记录变更历史：
```markdown
**属性变更记录**
- [字段名]：[原值] → [新值]
- 变更原因：[用户说明]
- 变更时间：[日期]
```

## 知识沉淀检查清单

每次拷打结束时，检查并更新：

- [ ] 产品实体信息是否完整
- [ ] 新识别的用户画像是否创建
- [ ] 新提及的竞品是否记录
- [ ] 技术方案选型是否更新
- [ ] 重要决策是否记录
- [ ] 实体间关系是否建立
- [ ] decisions.md 是否同步更新
