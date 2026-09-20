# URL 编解码（url-codec）

URL 百分号编码与解码。参考 Fasty url-codec。

## 不变量

- **解码失败必须报告，不能回显输入**：原实现是 `removingPercentEncoding ?? input`，用户看到的是「什么都没发生」，分不清是没编码还是输入有问题。现在失败会清空输出并在状态栏给出错误。
- 编码走 `.urlQueryAllowed` 字符集，空格会变成 `%20` 而不是 `+`。

## 内部结构

`Model/URLCodecLogic.swift` 是纯逻辑（Foundation only，可独立测），`UI/` 里是视图与 `AppStorage` 绑定的选项。

## 已知限制

见上面不变量里标为「既有行为」的条目：它们是当前实现的取舍，改之前先确认是有意为之。
