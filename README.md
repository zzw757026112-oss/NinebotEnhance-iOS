# NinebotEnhance iOS v0.1.5

给官方九号出行 App（`cn.ninebot.segway`）的注入插件：钩住投屏画面的
编码器入口，在 App 自己的导航画面上叠加一层 HUD，再交给 App 原来的
H.264/RTP/RTCP/UDP 链路发给仪表。思路来自安卓的 NinebotEnhance，
但代码是全新写的 iOS Theos 插件（安卓代码一行都搬不过来）。

## v0.1.5 改了什么

**车辆数据探测（Route B Phase 1，只读侦察）并进插件。** 直接走蓝牙读
M3（九号 M395C MAX）已经试过 9 帧 PRE_COMM，全无回应，此路不通。
改从九号 App 自己的蓝牙栈里找数据：App 内部有
`NBDynamicModule.DynamicTool`（相当于安卓的 DynamicDevice），手里有
每款车的指令表（`commandDict`），App 自己会跟车握手解密。本版只做
侦察，**不发任何蓝牙指令**：

1. **加载后 5 秒**，把 5 个候选类（`DynamicTool` / `DynamicDebugManager` /
   `BleCommandDebugManager` / `DebugTool` / `BleCommandDebugVC`）的存在性
   + 完整方法列表打到 os_log，找含 Response / receive / sendCommand /
   Command / Frame / handle 的选择器——那就是接收/发送方法；
2. **之后每 10 秒试一次（最多 12 次，2 分钟）**：按 cmddump 的 10 个单例
   选择器找实例，顺着 ivar 找到持有 `deviceCommands` / `commandDict` 的
   对象，序列化写 `Documents/BleCmdDump.json`，并查里面有没有 `rSpeed` /
   `rPower` / `rVrlaVoltage` / `rBattery` / `rTirePressureRealTimeInfo`；
   写出非空结果就停。

全部操作都有 nil / respondsToSelector / @try 保护，类不存在或单例拿不到
只记日志，绝不崩；HUD 和设置按钮不受影响。

**怎么用：** 车通电，打开九号出行（连上车），等 2 分钟；然后用 Filza
把 `Documents/BleCmdDump.json` 导出来发回，再把 os_log 里 `[PROBE]`
开头的日志发回（或截图）。如果 12 次都没拿到，日志里会写原因——
大概率是车没连上，或单例入口不在这 4 个类上。

日志例子：

```
[PROBE] _TtC15NBDynamicModule11DynamicTool 存在（父类 NSObject），实例方法 12 个，类方法 3 个，可作单例入口的选择器：shared
[PROBE] ⭐ _TtC15NBDynamicModule11DynamicTool 实例方法里值得注意的（可能含接收/发送）：
[PROBE]     ⭐ onResponse:
[PROBE] _TtC15NBDynamicModule11DynamicTool 单例拿到（入口 shared）
[PROBE]   指令表持有者：_TtC15NBDynamicModule11DynamicTool
[PROBE] 目标指令 rSpeed：有
[PROBE] 目标指令 rVrlaVoltage：有
[PROBE] ✅ 已写入 /var/mobile/Containers/Data/Application/…/Documents/BleCmdDump.json（48213 B，第 2 次尝试）
```

关掉探测：`defaults write cn.ninebot.segway NEProbeVehicle -bool NO`

## v0.1.4 改了什么

**1. HUD设置按钮不再盖住 App 自己的齿轮按钮。** 我的页右上角的齿轮约在安全区顶部 +8~+36，按钮原来放 +8 正好盖住它；本版下移到 +56，落在齿轮下方空白处。

**2. HUD设置按钮不再出现在自己的设置页里。** NEHUDSettingsVC 的类名里也有 setting，会被匹配规则命中；本版排除所有 NEHUD* 的页面。

## v0.1.3 改了什么

**1. HUD 翻转修好了。** v0.1.2 导航正了但 HUD 是倒的：原因是
RenderOverlay 在自己的 bitmap 里翻转了一次再画字，出来的叠加图
字就是倒的；v0.1.1 在合成时再翻一次，字正了但位置被镜像到上方
仪表表盘的遮挡区里，所以看不见。本版全程不翻转——画字直接用
y 朝上的 bitmap 坐标，和 Ninebot Pro+ 的 HUDOverlay.swift
完全同一套画法（那份代码已在同一块仪表上验证是正的）。

**2. HUD 改成小胶囊样式**（照 Ninebot Pro+ 1.0.8+ 的样子）：
仪表画面右下角一个圆角胶囊，黑底 45% + 白边 35% 1pt + 圆角 12。

- **上行**：时钟图标 + 日期时间（例如 `11月19日 周四 22:12`）
- **下行**：天气图标 + 温度、联网方式（WiFi 图标 / 5G / 4G / 3G）、
  音量、电量图标 + 百分比（低于 20% 变红）
- **有音乐在放时再加一行**：音符图标 + 歌名 - 歌手
- **来电提示**：有未接通/通话中的电话时，左下角出现红色 `来电`
  药丸。只显示“来电”两个字，不显示号码（CallKit 不向第三方
  App 暴露号码）。

天气是当前温度 + 天气（例如 `18° 晴`），定位一次后用 Open-Meteo
免费接口拉取（无 key），缓存 20 分钟，后台刷新，永不阻塞投屏帧回调。
没拿到天气之前那一项不画。

速度没有叠加——仪表自己就显示速度，不需要重复。

**3. 新增 HUD 设置。** 九号 App 的“我的/个人/设置”页右上角会
出现一个 **HUD设置** 按钮（插件按页面类名运行时匹配，没匹配到
就不出现，不会崩）。点开可以开关：日期时间、天气温度、信号、
电量、音乐、音量；还可以选位置（右下 / 左下 / 左上 / 右上）
和字号（小 / 中 / 大）。改完立即生效，下次投屏帧就用新设置。

如果按钮没出现，也可以用命令改（改完重开九号出行，或等下次
投屏帧）：

```sh
defaults write cn.ninebot.segway NEHUDShowDate -bool NO    # 关掉日期时间
defaults write cn.ninebot.segway NEHUDPosition -int 1      # 0 右下 1 左下 2 左上 3 右上
defaults write cn.ninebot.segway NEHUDFontSize -int 2       # 0 小 1 中 2 大
```

开关的键：`NEHUDShowDate` / `NEHUDShowWeather` / `NEHUDShowSignal` /
`NEHUDShowBattery` / `NEHUDShowMusic` / `NEHUDShowVolume`（都是 bool，
默认 YES）。

## 安装（巨魔注入器 TrollFools）

1. 从 GitHub Actions 产物下载 `NinebotEnhance.dylib`
  （artifact 名 `NinebotEnhance-iOS-0.1.4-dylib`；注意：网站上的 workflow
  文件目前还是 0.1.1 版，所以实际下载到的 artifact 名字仍是
  `NinebotEnhance-iOS-0.1.1-dylib`，但里面装的是 0.1.4，以加载日志为准）。
2. 打开巨魔注入器（TrollFools），选择九号出行 App，把
   `NinebotEnhance.dylib` 注入进去（注入器会把它放到 App 的
   `Frameworks/` 目录并加 load 命令；dylib 的 install_name 已按
   `@executable_path/Frameworks/NinebotEnhance.dylib` 设定好）。
3. 打开九号出行，正常连车、进投屏导航，仪表画面上就多了 HUD。
4. 不需要装 .deb，也不需要 Sileo/Zebra——这个版本就是给注入器用的，
   dylib 自带了 `MSHookMessageEx` 实现，不依赖 Substrate/ElleKit。

## 检查是否加载成功

手机上（需越狱环境下的终端，NewTerm / SSH）：

```sh
log stream --predicate 'subsystem == "com.user.ninebotenhance"'
```

打开九号出行后应看到：

```
NinebotEnhance iOS 0.1.4 已加载（小胶囊 HUD：日期/天气/信号/音量/电量/音乐/来电）
[HOOK] NBPixelBufferConverter 已找到，pixelBufferFromCGImage: YES
```

开始投屏后应看到 `[CAST] frame #1 size=848x480（投屏正在推流，HUD 已叠加）`
（尺寸随仪表型号变）。如果看到的是：

```
[HOOK] NBPixelBufferConverter 类未找到——插件不会起作用
```

说明 6.10.12 把钩的类/方法改名了，插件静默失效（不会崩，只是没效果）。
把这段日志发给我，我按新版本重新定位钩点。

可选：想确认实际发给车机的画面，可以在九号出行的设置里写
`POFrameDump = YES`（同上，`defaults write cn.ninebot.segway POFrameDump -bool YES`），
前 5 帧会存到 App 的 `Documents/POFrames/cast_*.png`。

## 关闭

不想用了不用卸载：

```sh
defaults write cn.ninebot.segway NBProjectionOverride -bool NO
```

再重开九号出行即恢复原生画面。改回 YES 重新启用。

## v0.1.4 不包含

- **其他 App 的通知**：从九号出行 App 进程里用公开 API 读不到别的
  App 的通知，那需要一个 SpringBoard 侧的组件，以后版本再做。
- **来电号码/姓名**：需要私有 CoreTelephony API，以后版本再做。
- **车辆实时数据（速度/功率/胎压/电压）**：iOS 侧九号 App 的蓝牙回包
  路径还没定位到，v0.1 只用手机端数据（电量/时间/天气/信号/音乐/
  音量/来电）。车辆数据的插件路线正在另外研究（先做一个探测
  dylib 定位 `NBDynamicModule.DynamicTool` 的收发方法）。
- **导航转向箭头**：需要先定位 iOS 侧的 TFT 113 号指令发送路径，
  以后版本再做。
- **虚拟显示器/把指定 App 投到仪表**：iOS 没有虚拟显示器 API，
  做不了安卓那套。整块手机屏幕镜像请用 Ninebot Pro+（ReplayKit 方案）。

## 诚实说明 / 风险

- 钩点来自对九号出行 **6.10.9** 的逆向（Xiaolangs/ninebot-cast-tweak，
  `NBPixelBufferConverter -pixelBufferFromCGImage:` 及 `_Mjpeg:` 变体）。
  本机是 **6.10.12**，钩子是按类名+方法名挂的，小版本升级一般能活，
  但如果 6.10.12 改了名，插件静默失效（见上“检查是否加载成功”）。
- HUD 翻转修复只在代码层面按 Ninebot Pro+ 已验证的画法改了，
  **必须在仪表上实测确认**（导航正 + 胶囊正 + 内容对）。
- HUD 设置按钮是按页面类名运行时匹配的（Mine/Profile/Setting/
  Me/User/Account），如果 6.10.12 的“我的”页类名不含这些词，
  按钮就不出现——设置仍可用上面的 `defaults` 命令改。
  如果按钮没出现，把日志里 `[HUD] 已在 ... 上加 HUD设置 按钮`
  那行（或“没出现”）告诉我，我再调匹配规则。
- 每帧都要把原画面和叠加层合成一张新图（25fps），比整帧替换多一次
  全帧拷贝；叠加层本身有 250ms 缓存，只在数据变化时重画。
- 天气依赖定位权限（九号出行本身已有）+ 联网；无网时天气项不显示，
  其他项不受影响。
- 本插件只改你自己手机上你自己车子的显示，不改车辆任何设置。

## 构建（开发者）

GitHub Actions（macOS runner）自动构建：装 Theos + ldid，`make`，
校验 dylib（arm64、install_name、`_MSHookMessageEx` 已定义且无
substrate 未定义符号），上传产物。本地有 Mac + Xcode 时也可
`export THEOS=/path/to/theos && make`。
