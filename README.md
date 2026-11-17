# NinebotEnhance iOS v0.1

给官方九号出行 App（`cn.ninebot.segway`）的注入插件：钩住投屏画面的
编码器入口，在 App 自己的导航画面上叠加一层 HUD，再交给 App 原来的
H.264/RTP/RTCP/UDP 链路发给仪表。思路来自安卓的 NinebotEnhance，
但代码是全新写的 iOS Theos 插件（安卓代码一行都搬不过来）。

## v0.1 叠加内容

仪表画面右下角（避开仪表自带表盘的遮挡区）：

- **电量**：手机电量百分比，充电时带 ⚡
- **日期时间**：例如 `11月17日 周一 23:20`
- **天气**：当前温度 + 天气（例如 `18° 晴`），定位一次后用 Open-Meteo
  免费接口拉取（无 key），缓存 20 分钟，后台刷新，永不阻塞投屏帧回调。
  没拿到天气之前那一行不画。
- **来电提示**：有未接通/通话中的电话时，左下角出现红色 `来电` 药丸。
  只显示“来电”两个字，不显示号码（CallKit 不向第三方 App 暴露号码）。

速度没有叠加——仪表自己就显示速度，不需要重复。

## 安装（巨魔注入器 TrollFools）

1. 从 GitHub Actions 产物下载 `NinebotEnhance.dylib`
  （artifact 名 `NinebotEnhance-iOS-0.1.0-dylib`）。
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
NinebotEnhance iOS 0.1.0 已加载（电量/日期时间/天气/来电叠加）
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

## v0.1 不包含

- **其他 App 的通知**：从九号出行 App 进程里用公开 API 读不到别的
  App 的通知，那需要一个 SpringBoard 侧的组件，以后版本再做。
- **来电号码/姓名**：需要私有 CoreTelephony API，以后版本再做。
- **车辆实时数据（速度/功率/胎压/电压）**：iOS 侧九号 App 的蓝牙回包
  路径还没定位到，v0.1 只用手机端数据（电量/时间/天气/来电）。
- **导航转向箭头**：需要先定位 iOS 侧的 TFT 113 号指令发送路径，
  以后版本再做。
- **虚拟显示器/把指定 App 投到仪表**：iOS 没有虚拟显示器 API，
  做不了安卓那套。整块手机屏幕镜像请用 Ninebot Pro+（ReplayKit 方案）。

## 诚实说明 / 风险

- 钩点来自对九号出行 **6.10.9** 的逆向（Xiaolangs/ninebot-cast-tweak，
  `NBPixelBufferConverter -pixelBufferFromCGImage:` 及 `_Mjpeg:` 变体）。
  本机是 **6.10.12**，钩子是按类名+方法名挂的，小版本升级一般能活，
  但如果 6.10.12 改了名，插件静默失效（见上“检查是否加载成功”）。
- 每帧都要把原画面和叠加层合成一张新图（25fps），比整帧替换多一次
  全帧拷贝；叠加层本身有 250ms 缓存，只在数据变化时重画。
- 天气依赖定位权限（九号出行本身已有）+ 联网；无网时天气行不显示，
  其他行不受影响。
- 本插件只改你自己手机上你自己车子的显示，不改车辆任何设置。

## 构建（开发者）

GitHub Actions（macOS runner）自动构建：装 Theos + ldid，`make`，
校验 dylib（arm64、install_name、`_MSHookMessageEx` 已定义且无
substrate 未定义符号），上传产物。本地有 Mac + Xcode 时也可
`export THEOS=/path/to/theos && make`。
