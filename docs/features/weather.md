# 天气（weather）

显示当前位置的天气。目前只搭好了骨架：**WeatherKit 尚未接入**，因为需要真实的
Apple Developer 账号启用该能力。当前拿到位置后返回的是一句占位摘要与坐标。

## 不变量

- **任何自动路径都不得申请定位权限。** 模块激活、后台刷新、定时任务都不允许调用
  `requestWhenInUseAuthorization()`，也不允许调用 `CLLocationUpdate.liveUpdates()`
  （它会在未决定时隐式申请）。
  **破坏它的后果是每次启动都弹系统权限框** —— 这正是这个模块曾经的问题。
  唯一的申请入口是 `WeatherService.requestAuthorization()`，它只应由用户的明确动作触发。
- **`refresh()` 是只读的。** 未授权时它只读取 `authorizationStatus` 并把原因记进
  `unavailableReason`，然后返回。它永远不改变授权状态。
- **申请权限前必须能解释用途。** `Quick/Resources/Info.plist` 里的
  `NSLocationUsageDescription` / `NSLocationWhenInUseUsageDescription` 是 macOS 的硬要求：
  缺了它申请会被系统直接拒绝。改动定位相关代码时不要删这两个键。
- **定位精度保持公里级**（`kCLLocationAccuracyKilometer`）。天气不需要精确位置，
  精度越高越费电，也越侵犯隐私。
- **定位超时必须有界。** 目前是 8 秒的竞速任务。不要退回「发起请求后固定 sleep 再读结果」
  的写法：那个写法既慢又不保证拿到值（这是它被替换掉的原因）。

## 内部结构

| 类型 | 职责 |
| --- | --- |
| `WeatherModule` | 模块入口；把「权限状态」翻译成一条**可操作**的搜索结果 |
| `WeatherService` | 授权状态检查、按需申请、取一次位置 |
| `WeatherView` | 模块主视图（**面板外壳尚未接入模块视图**） |

`searchItems` 只有在查询命中触发词（天气 / weather / 温度 / 预报）时才工作，
并且把三种「拿不到」翻译成三条不同的结果，而不是统一说「失败」：

| 状态 | 结果 | 用户的下一步 |
| --- | --- | --- |
| `.needsPermission` | 「授予定位权限以显示天气」 | 点一下 → 这时才弹系统权限框 |
| `.permissionDenied` | 「定位权限已被拒绝」 | 点一下 → 打开系统设置的定位服务面板 |
| `.locationUnavailable` | 「暂时拿不到位置」 | 稍后重试（已授权但系统没返回位置） |

## 持久化

无。天气数据不落盘，位置也不落盘 —— 每次都是现取。

## 已知限制

- **WeatherKit 未接入。** 拿到位置后返回的是占位内容（`"天气服务就绪"` + 坐标），
  不是真实天气。需要 Apple Developer 账号与 WeatherKit 能力。
- **`WeatherView` 不会随服务状态更新。** `WeatherService` 标了 `@Observable`，但
  `WeatherView` 用普通 `let` 持有它，没有建立观察关系，所以视图不会在
  `currentInfo` 变化时刷新。目前无影响（面板外壳还没渲染模块视图），
  接入模块视图时要一并修掉。
- **不缓存位置。** 每次查看天气都会重新取一次位置。
- **不提供手动输入城市**，只能依赖系统定位。
