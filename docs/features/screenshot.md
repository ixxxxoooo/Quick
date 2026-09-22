# 截图工具（screenshot）

对齐 `~/jietu` 的做法：冻结屏幕 → 自绘遮罩原地框选与标注 → 保存 / 复制 / 钉图。
**不再使用系统 `screencapture` 命令行** —— 原地标注需要拿到「按下那一刻」的完整画面。

## 不变量

- **抓屏走 ScreenCaptureKit**（`CaptureEngine`），不再起 `screencapture` 进程。因此需要
  「屏幕录制」权限，且授权只对授权之后启动的进程生效（授权后要重启 Quick）。
- **遮罩用 `NSPanel + .nonactivatingPanel`，级别 `.screenSaver`**：全局热键触发时前台是别的
  App，非激活面板不必把 Quick 拉到前台就能拿到 key 与键盘焦点，也不会打断用户当前操作。
  见 `OverlayWindow` 的说明。
- **坐标只有两套，换算只发生在烘焙那一刻**：画布局部坐标（point，原点左下，与 `Annotation`
  一致）与图像像素坐标（原点左上）。换算收敛在 `DisplaySnapshot.pixelRect(fromLocalRect:)`
  与 `Annotation.transformed(offset:scale:)`。
- **实时预览与最终烘焙共用同一份绘制逻辑**（`AnnotationRenderer`）。预览用的底图是「点尺度」
  的冻结帧，烘焙用的是全分辨率裁剪图 —— 两者坐标尺度不同，所以各自传对应的 `baseImage`。
- **多显示器：每块屏一个遮罩**，选区只在其中一块上成立，交付时按那块屏算屏幕矩形。
- 截图期间 `NSApp.activate` 打断前台 App，`finish()` 时把前台还给用户原来的 App。
- 钉图是常驻置顶窗口（`PinWindowController`）：可拖动、滚轮/捏合缩放、双击 / Esc / ⌘W 关闭、右键复制。

## 内部结构

| 文件 | 职责 |
| --- | --- |
| `Model/Annotation.swift` | 标注模型（工具、RGBA 颜色、几何量）+ 坐标变换。纯 CoreGraphics |
| `Model/AnnotationRenderer.swift` | 把标注画进 CG 位图上下文（形状、箭头、文字、马赛克、序号）。纯 CG + CoreText |
| `Model/CaptureOutput.swift` | 裁剪、烘焙、缩放、编码（ImageIO） |
| `Model/DisplaySnapshot.swift` | 一帧冻结画面 + point→pixel 换算 |
| `Model/ScreenshotNaming.swift` | 文件名 / 时间戳 / 格式（纯函数，可独立测） |
| `Service/CaptureEngine.swift` | ScreenCaptureKit 抓屏（全屏 / 按窗口） |
| `Service/WindowEnumerator.swift` | `CGWindowListCopyWindowInfo` 窗口枚举与命中（悬停高亮 / 单击选窗） |
| `Service/OverlayCoordinator.swift` | 遮罩总控：展开、交付、收尾 |
| `Service/PinWindowController.swift` | 钉图窗口 |
| `Service/ScreenshotDelivery.swift` | 保存到桌面 / 复制到剪贴板 / 快门音 |
| `UI/OverlayWindowController.swift` | 一块屏的遮罩窗 |
| `UI/OverlayCanvasView.swift` | 选区 + 标注的绘制与鼠标/键盘交互 |
| `UI/AnnotationToolbarView.swift` | 选区旁的就地工具栏（AppKit） |
| `UI/PinContentView.swift` | 钉图内容视图（拖动 / 缩放 / 关闭） |

## 交互

- 框选：拖拽出一块区域；单击（几乎不拖动）选中点下的窗口。
- 选区就绪后工具栏出现在选区下方（放不下则在上方）。
- 工具：矩形、椭圆、箭头、画笔、荧光笔、文字、马赛克、序号；颜色 7 档；线宽 3 档。
- 快捷键：Esc 取消，⏎ / ⌘S 保存，⌘C 复制，⌘D 钉图，⌘Z 撤销上一条标注。
- 保存去向由设置页的「保存到桌面」决定：开着则落盘 + 复制，关掉则只复制。

## 已知限制

- 窗口截图用「冻结帧里那块矩形」，不排除遮挡它的窗口；独立抓窗（`CaptureEngine.captureWindow`）
  已就绪但尚未接进遮罩，后续可切换。
- 马赛克以固定块大小（10px）像素化，没有粗细档位。
