> 历史参考：此文档来自 Trae v0.1，不能作为候选版安装／验证状态说明。当前步骤见项目根目录 README.md。

# 测试说明

## 1. 主机侧测试

### 单元测试

```sh
luajit tests/run.lua
```

当前结果（2026-11-11，Windows + LuaJIT 2.1）：

```text
39 passed, 0 failed
```

覆盖：

- JSON 编解码：Unicode、代理对、null、空数组/对象、错误输入
- 时间：civil date、ISO8601 偏移、日期型倒计时、时刻型倒计时、过期、星期/日期标签
- 调度器：到期、分钟对齐、合并、失败退避、强制与移除
- 配置：默认值深合并、用户覆盖、数组替换、持久化、secrets 独立
- 布局：权重、最小高度、双列、禁用模块过滤
- Dida 视图：今日/逾期/即将到期、完成数、进度、优先级排序
- 天气：Open-Meteo payload 解析、URL、错误 payload
- 触摸：16 字节 evdev 解码、单点/协议 B、tap/swipe
- 注册表：新增模块无需改核心、初始化、未知 API 隔离
- HTTP：脚本 shebang/续行/完成标记、成功回调、HTTP 错误状态
- 显示后端：`Display.new` 返回实例、FBInk OTF 参数、失败降级
- 启动集成：用真实 `App` + FBInk 后端 + 假 runner 完成 setup 与首屏渲染（覆盖 `display` 依赖注入）

### 页面 smoke test

```sh
python scripts/smoke_test.py
```

结果：

```text
home: 24 text elements, max_y=1346.4
tasks: 21 text elements, max_y=1346.4
system: 45 text elements, max_y=1346.4
settings: 29 text elements, max_y=1346.4
PASS: all pages rendered
```

检查：SVG 可生成、页脚四个导航项存在、没有 `nil`/`MODULE ERROR`/`KDASH FATAL`、文本基线不越过 1400px。

### 包构建检查

```sh
python scripts/build_package.py
```

它验证包内必需文件：

```text
manifest.json
install.sh / launch.sh / uninstall.sh
launcher/kdash-launch.sh
runtime/luajit / runtime/fbink
app/main.lua
app/config/default.json
app/assets/fonts/DroidSansFallbackFull.ttf
```

输出 SHA-256 与文件数。

## 2. 测试的边界

这些测试**不能**证明：

- FBInk 在 KPW3 上的实际输出、字体渲染、刷新波形
- KPM/scriptlet 在该固件上的安装与启动
- `/dev/input/event1` 的坐标方向
- `curl` 的 TLS/CA 能力
- 框架停止/恢复时序
- 休眠/唤醒行为
- KPM 升级路径

因此文档只写“主机侧通过”，不写“实机通过”。

## 3. 添加测试

在 `tests/` 新建 `test_<name>.lua`：

```lua
return function(T)
    T.test("my module parses data", function()
        local M = require("services.api.myapi")
        local view = M.parse(fixture)
        T.eq(view.value, 42)
    end)
end
```

把文件名加入 `tests/run.lua` 的 `files` 列表。

要求：

- 数据处理与 UI/网络解耦，才能单测。
- 网络适配器用 fixture JSON；不要测试真实网络。
- 模块注册路径用临时目录（参考 `tests/test_registry.lua`）。

## 4. 实机验收清单

见 `docs/DEVICE_DIAGNOSTICS.md` 第 4 节。至少需要：

1. 诊断报告
2. 启动/退出视频或照片
3. 日志
4. 触摸坐标验证
5. KOReader 仍可启动
6. 升级/卸载验证
7. 休眠/唤醒记录

## 5. 已知未跑的命令

- 没有在 ARM 设备上运行 `luajit`/`fbink`。
- 没有运行 KPM 安装。
- 没有运行 OAuth 真实授权（工具是标准 OAuth2 流程，但未用真实 client 验证）。
- 没有运行真实 Open-Meteo/Dida 请求（解析用 fixture）。
