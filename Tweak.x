// NinebotEnhance iOS v0.3.9 — 九号出行(cn.ninebot.segway) 投屏画面 HUD 叠加
//
// v0.3.9 改动：三个只改显示、不改真数据的样子货（照搬安卓 ninebot-sign-lsp 的思路）：
//  1. 服务有效期显示 9999：hook -[UILabel setText:]，文本含“服务有效期”且带日期时，
//     只把日期部分换成 9999.12.31，其他日期不动。设置里加开关，默认关（key NEValidity9999）。
//  2. 主页车辆图自定义：九号 App“设备”主页那张车图是远端加载的，hook 图片加载换成用户自选的图。
//     SDWebImage 存在就 hook UIImageView 的 sd_setImageWithURL:（+ 带 context 的全量变体），
//     按 URL 特征只拦车辆图；不存在就退回 hook -[UIImageView setImage:]，只在“设备”主页、
//     图片够大时换。用户选的图存沙盒 Documents/ne-vehicle.png（key NEVehicleImagePath），
//     没选图时不装钩子、不改动。
//  3. 主页背景图自定义：和车辆图同一套拦截；“设备”主页那张满屏背景图（车图下面那张）也能换，
//     存 Documents/ne-bg.png（key NEBackgroundImagePath）。背景若是本地 asset，
//     再 hook +[UIImage imageNamed:] 按名字匹配（bg/background/banner 等关键字，
//     匹配不上就不换）。设置里“更换车辆图 / 更换背景图”用 PHPicker 选图（不用相册权限，
//     不可用时回退 UIImagePickerController），另有“恢复原图 / 恢复原背景”清除。
//  三个钩子都用 MSHookMessageEx 在运行时装，类/方法不存在只记日志绝不崩；
//  UILabel setText 是高频调用，开关先走缓存 BOOL 再做字符串匹配，不拖性能。
//  不碰任何 BLE、车辆写入、签到相关东西。
// v0.3.9 追加：五个自定义显示项（N币余额 / 总里程 / 等级 / 称号 / 连续签到天数，
//  每项“开关 + 输入框”，用户自己填想显示的值，开关开就按填的值显示，关就恢复原样；
//  都走已有的 -[UILabel setText:] 钩子，不另装。N币是单独数字最难认，
//  用兄弟视图里有没有“N币”label + 位置确认，认不出宁可不换）
//  + 设置页分两组折叠（“美化娱乐”：9999/换图/五个自定义项；“导航增强”：以前的
//  HUD/翻页时钟/超速等；进设置页默认两组都折叠，折叠状态不持久化）
//  + 入口按钮“HUD设置”改叫“Ninebot pro+”（只改标题，位置和出现逻辑不动）。
// v0.3.9 修复（实测新功能全不生效后修）：只拦 setText: 且要求数字+单位在同一串文本里，
//  匹配不上（数字和单位分属不同 label，或走 setAttributedText: 富文本），且页面启动时
//  已设好文本、改设置后 App 不再重设，钩子拦不到。修：setText: + setAttributedText: 都拦，
//  共用同一套匹配；匹配不到时看附近 label（窗口坐标判定相邻）配对才换；开关/值/选图改完
//  强制把 key window 的 UILabel 和设备 tab 的 UIImageView 重设一遍，立刻生效；
//  裸数字必须有明确描述才换，旁边有 % 就是电量，绝不换（之前电量被误换成 9999%）。
//  图片刷新不用 NEIsDeviceTabSelected()（设置页 modal 盖着时它永远返回 NO），改直接取根 tab bar。
//  启动 3 秒后也强制刷新一次（页面可能在钩子装好前已加载）。
// v0.3.8 改动：超速红行改成“请勿超速行驶！”，字比普通行大但绝不超胶囊边框；
//  超速那一刻中文语音读一次“您已超速行驶，请注意安全”（跟着超速提醒开关走，不另设开关）。
// v0.3.7 改动：设置页“日期时间”改叫“日期”（时间只在翻页时钟里显示）；和 App 1.3.19 同款。
// v0.3.6 改动：老虎机换成翻页时钟（用户创意，和 App 1.3.18 同款）。显示当前时间 HH:MM:SS，六张灰卡片，
//  白数字纵向拉长 1.9 倍，数字变了就翻页（0.35s）；无黑色底板，卡片直接浮在地图上。面板 204x108，
//  顶边 265，右对齐 X=632，跟车子自带 P 表盘、底下胶囊严格同宽对齐（都是 204）。胶囊：时间删掉
//  （只留翻页时钟显示时间），第一排改成“日期 + 星期 + 天气情况 + 温度”（如 11月21日 周六 晴 6°），
//  第二排只剩信号/音量/电量（温度从第二排移走）。设置页开关改叫“翻页时钟”（默认开，内部 key
//  NEHUDShowSlot 不变，老开关状态照用）。跟 BMS 面板互斥的机制原样保留；BMS 面板位置不动。
//  v0.3.5 改动：老虎机往下移（顶边 222→265）+ 面板收窄（281→245）；v0.3.4：老虎机移到右边
//  （X=555，右对齐）；v0.3.3：老虎机三格不同转速（1.0 / 1.5 / 0.7），和 App 1.3.15 同款。
//  v0.2.0 的像素骑行小人（AI 重画插画分层动画）已删除，RiderImage.h /
//  RiderMotion.h 留在仓库里不再用。
//
// v0.1.9 改动：音乐拿掉 + 超速提醒标题去重。
//  音乐整个删了（九号 App 自己就显示音乐，插件不再重复画）：
//  设置页的音乐开关、HUD 的音乐行、读歌名的代码都没了，
//  只留音量。设置页“超速提醒”段的重复标题删了，只留开关行 +
//  限速步进器行（默认 60 km/h，30–120，每 5 一档）。其他一律不动。
//
// v0.1.8 改动：HUD 加超速提醒。
//  设置页新增“超速提醒”段：开关（默认开）+ 限速步进器（默认 60 km/h，
//  30–120，每 5 一档，改完立即生效）。超过限速时手机震动 + 系统提示音
//  （只在刚超速那一刻触发一次），HUD 胶囊里多一行红色“超速 N km/h”；
//  速度回落到限速内就清除，下次再超再触发。速度取自定位（连续定位只
//  在提醒开着时才开，关了就恢复原来的单次定位）。只在九号 App 开着时
//  有效，App 退后台/被杀就停。其他一律不动。
//
// v0.1.7 改动：探测失败也写文件。
//  v0.1.6 的问题：只有拿到指令表持有者才写 Documents/BleCmdDump.json；
//  12 次尝试都失败就不写文件。用户实测（车通电连上、打开九号出行等满
//  2 分钟、确认注入 0.1.6）Filza 里找不到文件——不是找错地方，是文件
//  根本没生成。本版改成每次尝试都写一份 JSON（成功/失败都写，
//  用户中途退出 App 文件也已经在）；第 12 次仍失败时写一份最终文件，
//  额外加 status:"failed" 和 reason（中文，说明可能原因），然后停表。
//  成功时行为不变（targets 照常判有/无，成功后停表）。
//  其他一律不动：HUD 胶囊、设置按钮只在“我的”页根页面、kill switch。
//
// v0.1.6 改动：HUD 设置按钮只在“我的”页显示。
//  之前按类名匹配（Mine/Profile/Setting/Me/User/Account），
//  按钮会出现在设置页、个人资料页等各种页面上。改成看 tab：
//  当前选中的 tab 必须是“我的”tab（标题是“我的”，或是最后一个
//  tab），而且当前页得是该 tab 的根页面（不是从“我的”点进去的
//  子页面，如 MineSettingVC 这类）。没有 tab bar 时退回类名
//  含 mine 才算。类名含 mine 但不在“我的”tab 上时记一次日志
//  （方便排错）；自己的设置页（NEHUD*）照旧排除。
//  车辆数据探测（v0.1.5）原样保留。
//
// 拦截点：+[NBPixelBufferConverter pixelBufferFromCGImage:]（类方法）
//         +[NBPixelBufferConverter pixelBufferFromCGImage_Mjpeg:]（MJPEG 备用路径）
//         以及对应的实例方法版本（与参考实现一致，四者都挂）。
// 做法：不在编码器输入端整帧替换，而是把 App 自己的画面画到底层，
// 再把 HUD 叠加层（小胶囊：日期 / 天气 / 信号 / 音量 / 电量，
// 超速时再加一行红色超速；来电提示）画在上面，
// 合成后交给原实现编码发送。App 自己的 H.264/RTP/RTCP/UDP 链路不动。
//
// v0.1.5 改动：车辆数据探测（Route B Phase 1，只读侦察）并进插件。
//  直接走蓝牙读 M3（九号 M395C MAX）已经试过 9 帧 PRE_COMM，全无回应，
//  此路不通。改从九号 App 自己的蓝牙栈里找数据：App 内部有
//  NBDynamicModule.DynamicTool（相当于 Android 的 DynamicDevice），
//  手里有每款车的指令表（commandDict），App 自己会跟车握手解密。
//  本版只做侦察，不发任何蓝牙指令：
//   1. 加载后 5 秒，把 5 个候选类的存在性 + 完整方法列表打到 os_log
//      （找含 Response / receive / sendCommand / Command / Frame /
//      handle 的选择器——那就是接收/发送方法）；
//   2. 之后每 10 秒试一次（最多 12 次，2 分钟）：按 cmddump 的 10 个
//      单例选择器找 DynamicTool 等类的实例，顺着 ivar 找到持有
//      deviceCommands / commandDict 的对象，序列化写
//      Documents/BleCmdDump.json，查里面有没有 rSpeed / rPower /
//      rVrlaVoltage / rBattery / rTirePressureRealTimeInfo；
//      写出非空结果就停。
//  全部操作都有 nil / respondsToSelector / @try 保护，类不存在或
//  单例拿不到只记日志，绝不崩；HUD 和设置按钮不受影响。
//  关：defaults write cn.ninebot.segway NEProbeVehicle -bool NO
//  产出：Documents/BleCmdDump.json + os_log（[PROBE] 前缀）。
//
// v0.1.4 改动：
//  1. HUD设置按钮不再盖住 App 自己的齿轮按钮：我的页右上角的齿轮
//     约在安全区顶部 +8~+36，按钮原来放 +8 正好盖住它；改成 +56，
//     落在齿轮下方空白处。
//  2. HUD设置按钮不再出现在自己的设置页里：NEHUDSettingsVC 的类名
//     里也有 setting，会被匹配规则命中；现在排除所有 NEHUD* 的页面。
//
// v0.1.3 改动：
//  1. HUD 翻转修复：v0.1.2 的 RenderOverlay 在自己的 bitmap 里做了
//     Translate+Scale 翻转再画字，出来的叠加图字是倒的（用户 22:18
//     实测：导航正了，HUD 是反的）。v0.1.1 在合成时再翻一次，字正了
//     但位置被镜像到上方的仪表表盘遮挡区里，所以看不见。正确做法是
//     全程不翻转——画字直接用 y 朝上的 bitmap 坐标，基线 =
//     高 - 离顶距离 - 上伸，和 Ninebot Pro+ 的 HUDOverlay.swift
//     完全一致（那份代码已在同一块仪表上验证是正的）。
//     所以本版：RenderOverlay 不再翻转，CompositeWithOverlay 也不翻转，
//     原图和叠加层都直接画。
//  2. HUD 改成小胶囊样式（照 Ninebot Pro+ 1.0.8+）：右下角两行胶囊，
//     黑底 45% + 白边 35% 1pt + 圆角 12；上行时钟图标 + 日期；
//     下行天气图标 + 温度、联网方式（WiFi 图标 / 5G/4G/3G）、
//     音量、电量图标 + 百分比（低于 20% 变红）；有音乐在放时再加
//     一行音符 + 歌名。来电还是左下角红色药丸，不变。
//  3. 新增联网方式（NWPathMonitor + CTTelephonyNetworkInfo）和
//     音乐/音量（MPNowPlayingInfoCenter + AVAudioSession），
//     都在本进程内读，帧回调里只读缓存，永不阻塞。
//  4. 新增 HUD 设置：九号 App 的“我的/个人/设置”页右上角会出现
//     一个“HUD设置”按钮（运行时按类名匹配，没匹配到就不出现，
//     设置仍可用 defaults 命令改）；也可以直接用
//     defaults write cn.ninebot.segway <键> 改，键见下文。
//
// HUD 数据全部来自本进程内可公开拿到的东西：UIDevice 电量、
// 系统时间、CoreLocation 定位 + Open-Meteo 天气（无 key，20 分钟缓存）、
// CallKit 来电状态、联网方式、音量。
// 网络和定位一律在后台做，帧回调里只读缓存，永不阻塞。
//
// 开关：NSUserDefaults 写 NBProjectionOverride = NO 立刻恢复原生画面。
// HUD 设置键（defaults write cn.ninebot.segway <键> <值>）：
//   NEHUDShowDate / NEHUDShowWeather / NEHUDShowSignal /
//   NEHUDShowBattery / NEHUDShowVolume / NEHUDShowSlot（bool，默认 YES）
//   NEHUDPosition（int，默认 0：0 右下 1 左下 2 左上 3 右上）
//   NEHUDFontSize（int，默认 1：0 小 1 中 2 大）
// 日志：os_log subsystem "com.user.ninebotenhance"，只打加载、钩点检查、
// 帧计数（#1 / 每 100 帧）、天气和来电状态变化、车辆探测结果（[PROBE]）。

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
#import <CoreLocation/CoreLocation.h>
#import <CallKit/CallKit.h>
#import <UIKit/UIKit.h>
#import <Network/Network.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioServices.h>
#import <os/log.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <PhotosUI/PhotosUI.h>
#import <dlfcn.h>
// 翻页时钟不依赖任何图片资源（卡片和数字全是运行时画的）。
// RiderImage.h / RiderMotion.h（v0.2.0 像素骑行小人）已不用，留在仓库里。

@interface NBPixelBufferConverter : NSObject
+ (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image;
+ (CVPixelBufferRef)pixelBufferFromCGImage_Mjpeg:(CGImageRef)image;
- (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image;
- (CVPixelBufferRef)pixelBufferFromCGImage_Mjpeg:(CGImageRef)image;
@end

static os_log_t gLog      = NULL;
static NSLock  *gLock     = nil;   // 叠加层缓存 + 帧计数
static NSLock  *gDataLock = nil;   // 天气 / 来电 / 联网 / 音量状态
static int      gFrames   = 0;
static int      gDumped   = 0;
// 定时器必须有强引用留着（局部变量出作用域就释放，定时器会停）
static dispatch_source_t gVolumeTimer = nil;
static dispatch_source_t gButtonTimer = nil;

@class NELocationDelegate;
static CLLocationManager *gLocMgr = nil;
static NELocationDelegate *gLocDelegate = nil;

// 超速提醒：最新 GPS 速度（km/h）+ 采样时间；gWasOverspeed 是越界沿状态
static double         gSpeedKmh     = 0;
static CFAbsoluteTime gSpeedAt      = 0;
static BOOL           gWasOverspeed = NO;

// 超速语音朗读（0.3.8）：合成器 static 持有，边沿触发时读一次；
//  局部变量说到一半会被释放、没声——所以必须长期持有。
static AVSpeechSynthesizer *gSpeechSynth = nil;

static BOOL OverlayEnabled(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NBProjectionOverride"];
    return v ? [v boolValue] : YES;          // 置 NO 即恢复原生画面
}

// ---------------- HUD 设置（NSUserDefaults，改完下次渲染即生效）----------------

static BOOL NEHUDShowDate(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDShowDate"];
    return v ? [v boolValue] : YES;
}
static BOOL NEHUDShowWeather(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDShowWeather"];
    return v ? [v boolValue] : YES;
}
static BOOL NEHUDShowSignal(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDShowSignal"];
    return v ? [v boolValue] : YES;
}
static BOOL NEHUDShowBattery(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDShowBattery"];
    return v ? [v boolValue] : YES;
}
static BOOL NEHUDShowVolume(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDShowVolume"];
    return v ? [v boolValue] : YES;
}
// 翻页时钟开关（v0.3.6，老虎机改成翻页时钟；默认 YES；内部 key NEHUDShowSlot 不变）
static BOOL NEHUDShowSlot(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDShowSlot"];
    return v ? [v boolValue] : YES;
}
static BOOL NEHUDSpeedAlert(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDSpeedAlert"];
    return v ? [v boolValue] : YES;
}
// 限速 km/h：默认 60，读出来 clamp 到 30–120
static NSInteger NEHUDSpeedLimit(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDSpeedLimit"];
    NSInteger s = v ? [v integerValue] : 60;
    if (s < 30) return 30;
    if (s > 120) return 120;
    return s;
}
// 0 右下 1 左下 2 左上 3 右上
static NSInteger NEHUDPosition(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDPosition"];
    NSInteger p = v ? [v integerValue] : 0;
    return (p >= 0 && p <= 3) ? p : 0;
}
// 0 小(16) 1 中(20) 2 大(24)，848x480 参考字号
static CGFloat NEHUDFontRefPt(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDFontSize"];
    NSInteger s = v ? [v integerValue] : 1;
    if (s == 0) return 16;
    if (s == 2) return 24;
    return 20;
}

// ---------------- v0.3.9：服务有效期 9999 + 主页车辆图/背景图自定义 ----------------
// 都只改显示，不改真数据。三个钩子都用 MSHookMessageEx 在运行时装：
// 类/方法不存在时 orig 为 NULL，只记日志绝不崩（shim 的行为，见 substrate_shim.m）。
// 前向声明：NEKeyWindow 定义在后面（设置按钮那节），这里先声明。
static UIWindow *NEKeyWindow(void);
static const char NEPickKindKey = 0;        // 设置页：当前选图是车辆图(0)/背景图(1)
static const char NEVehicleStatusKey = 0;   // 设置页：车辆图状态 label
static const char NEBackgroundStatusKey = 0;// 设置页：背景图状态 label

// --- 服务有效期 9999（默认关）---
static BOOL NEValidity9999(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEValidity9999"];
    return v ? [v boolValue] : NO;
}
// setText 高频调用：开关缓存一份，钩子里先查这个 BOOL 再做字符串匹配
static BOOL gValidity9999 = NO;

static void (*orig_UILabel_setText)(id, SEL, NSString *);

// --- v0.3.9 追加：五个自定义显示项（开关 + 输入框，用户自己填值）---
// 匹配先快后慢：每个开关先走缓存 BOOL，值为空时也不换。
static BOOL NEBoolDefault(NSString *key) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ? [v boolValue] : NO;
}
static BOOL gNCoins = NO, gMileage = NO, gLevel = NO, gTitle = NO, gSignDays = NO;
static NSString *gNCoinsValue = nil, *gMileageValue = nil, *gLevelValue = nil,
                *gTitleValue = nil, *gSignDaysValue = nil;
static void NESyncCustomDisplayCache(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    gNCoins = NEBoolDefault(@"NENCoins");
    gMileage = NEBoolDefault(@"NEMileage");
    gLevel = NEBoolDefault(@"NELevel");
    gTitle = NEBoolDefault(@"NETitle");
    gSignDays = NEBoolDefault(@"NESignDays");
    gNCoinsValue = [d stringForKey:@"NENCoinsValue"];
    gMileageValue = [d stringForKey:@"NEMileageValue"];
    gLevelValue = [d stringForKey:@"NELevelValue"];
    gTitleValue = [d stringForKey:@"NETitleValue"];
    gSignDaysValue = [d stringForKey:@"NESignDaysValue"];
}

// v0.3.9 修复：文字替换根因——App 的数字和单位/描述经常不在同一个 label 里
// （数字一个 label，单位“km”/“N币”/“服务有效期”在旁边另一个 label），
// 或者走 setAttributedText:（富文本，大数字+小单位），所以只拦 setText: 且
// 要求“同一串文本里既有数字又有单位”永远匹配不上。另外页面启动时已设好
// 文本，改设置后 App 不再重设，钩子也拦不到。因此：
//  ① setText: 和 setAttributedText: 都拦，共用同一套匹配；
//  ② 匹配不到时看附近 label（窗口坐标判定相邻），数字+描述配对才换；
//  ③ 开关/值改完强制把 key window 里所有 UILabel 重设一遍，立刻生效；
//  ④ 裸数字必须有明确的描述才换，旁边有 % 就是电量，绝不换（之前电量被误换成 9999%）。
// 替换过的 label 记一个 associatedObject（字段 key + 是不是分开 label），
// 刷新时按当前值直接重设——换过的文本里原来的匹配特征可能已消失
// （如里程 "35624.6 km" 换成 "9999" 后文本里就没了 km）。

static const char NEAppliedFieldKey = 0;    // 之前被替换过的 label：字段 key
static const char NEAppliedSeparateKey = 0; // 同上：是不是“分开 label”式替换

// label 的纯文本：有富文本就取富文本的字符串，否则取 text
static NSString *NEPlainTextOfLabel(UILabel *label) {
    if (!label) return nil;
    if (label.attributedText) return label.attributedText.string;
    return label.text;
}

// 纯数字（可带千分位逗号/小数），如 124、35624.6
static BOOL NEIsPureNumberString(NSString *t) {
    if (!t.length) return NO;
    static NSRegularExpression *sNumRe = nil;
    static dispatch_once_t sOnce;
    dispatch_once(&sOnce, ^{
        sNumRe = [NSRegularExpression regularExpressionWithPattern:@"^[\\d,]+(\\.\\d+)?$"
                                                           options:0 error:nil];
    });
    return sNumRe &&
        [sNumRe numberOfMatchesInString:t options:0 range:NSMakeRange(0, t.length)] > 0;
}

// 视图在窗口里的 frame（跨容器比较位置用；失败返回 CGRectZero）
static CGRect NEFrameInWindow(UIView *v, UIWindow *w) {
    if (!v || !w) return CGRectZero;
    @try { return [v convertRect:v.bounds toView:w]; } @catch (...) { return CGRectZero; }
}

// 描述在数字正下方相邻：上沿在数字下沿附近（-4~+60），横向重叠过半
static BOOL NEFramesVerticallyAdjacent(CGRect lf, CGRect cf) {
    CGFloat top = CGRectGetMinY(cf), bottom = CGRectGetMaxY(lf);
    if (top < bottom - 4 || top > bottom + 60) return NO;
    CGFloat ox = MIN(CGRectGetMaxX(cf), CGRectGetMaxX(lf))
               - MAX(CGRectGetMinX(cf), CGRectGetMinX(lf));
    CGFloat w = MIN(CGRectGetWidth(cf), CGRectGetWidth(lf));
    return w > 0 && ox > w * 0.5;
}

// 描述在数字右侧相邻：左沿在数字右沿附近（-4~+40），纵向重叠过半
static BOOL NEFramesHorizontallyAdjacent(CGRect lf, CGRect cf) {
    CGFloat left = CGRectGetMinX(cf), right = CGRectGetMaxX(lf);
    if (left < right - 4 || left > right + 40) return NO;
    CGFloat oy = MIN(CGRectGetMaxY(cf), CGRectGetMaxY(lf))
               - MAX(CGRectGetMinY(cf), CGRectGetMinY(lf));
    CGFloat h = MIN(CGRectGetHeight(cf), CGRectGetHeight(lf));
    return h > 0 && oy > h * 0.5;
}

// 收集 view 子树里的所有 UILabel（跳过 exclude 这棵子树）
static void NECollectLabelsExcept(UIView *view, UIView *exclude, NSMutableArray<UILabel *> *out) {
    for (UIView *sub in view.subviews) {
        if (sub == exclude) continue;
        if ([sub isKindOfClass:[UILabel class]]) [out addObject:(UILabel *)sub];
        NECollectLabelsExcept(sub, exclude, out);
    }
}

// label 附近（下方或右侧相邻）的所有 label。帧还没布局出来时返回空——
// 那时不认，宁可不换，等刷新时（已布局好）再认。
static NSArray<UILabel *> *NEAdjacentLabels(UILabel *label) {
    UIWindow *w = NEKeyWindow();
    NSMutableArray<UILabel *> *out = [NSMutableArray array];
    if (!w || !label) return out;
    CGRect lf = NEFrameInWindow(label, w);
    if (CGRectIsEmpty(lf)) return out;
    NSMutableArray<UILabel *> *cands = [NSMutableArray array];
    UIView *sup = label.superview;
    if (!sup) return out;
    NECollectLabelsExcept(sup, label, cands);
    UIView *sup2 = sup.superview;
    if (sup2) NECollectLabelsExcept(sup2, sup, cands);
    for (UILabel *cand in cands) {
        CGRect cf = NEFrameInWindow(cand, w);
        if (CGRectIsEmpty(cf)) continue;
        if (NEFramesVerticallyAdjacent(lf, cf) || NEFramesHorizontallyAdjacent(lf, cf))
            [out addObject:cand];
    }
    return out;
}

// 附近 label 里含关键字的那一个（找不到返回 nil）
static UILabel *NEAdjacentLabelContaining(UILabel *label, NSString *keyword) {
    if (!keyword.length) return nil;
    for (UILabel *cand in NEAdjacentLabels(label)) {
        NSString *t = NEPlainTextOfLabel(cand);
        if (t.length && [t rangeOfString:keyword].location != NSNotFound) return cand;
    }
    return nil;
}

// 数字旁边有个 "%" label → 这是百分比（电量），绝不能当 N币/里程换
static BOOL NEHasAdjacentPercentLabel(UILabel *label) {
    for (UILabel *cand in NEAdjacentLabels(label)) {
        NSString *t = [NEPlainTextOfLabel(cand) stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];
        if (t.length && [t rangeOfString:@"%"].location != NSNotFound) return YES;
    }
    return NO;
}

// 所有文字替换共用：输入 label 的纯文本（setText: 的 text 或 attributedText.string），
// 返回替换后的字符串；没有可换的返回 nil。
// fieldOut/separateOut（可为 NULL）返回命中的字段 key 和是不是“分开 label”式替换。
static NSString *NEFixedLabelString(NSString *text, UILabel *label,
                                    NSString **fieldOut, BOOL *separateOut) {
    if (fieldOut) *fieldOut = nil;
    if (separateOut) *separateOut = NO;
    if (!text.length || !label) return nil;
    // 按钮的标题 label（如我们自己的“Ninebot pro+”按钮）不碰
    if ([label.superview isKindOfClass:[UIButton class]]) return nil;
    // 1. 服务有效期 9999
    if (gValidity9999) {
        NSRange keyRange = [text rangeOfString:@"服务有效期"];
        static NSRegularExpression *sDateRe = nil;
        static dispatch_once_t sOnce;
        dispatch_once(&sOnce, ^{
            sDateRe = [NSRegularExpression regularExpressionWithPattern:
                       @"\\d{4}[.\\-/年]\\d{1,2}[.\\-/月]\\d{1,2}日?"
                       options:0 error:nil];
        });
        if (keyRange.location != NSNotFound) {
            // 同 label：日期在“服务有效期”后面找，只换它
            if (sDateRe) {
                NSRange search = NSMakeRange(keyRange.location, text.length - keyRange.location);
                NSRange m = [sDateRe rangeOfFirstMatchInString:text options:0 range:search];
                if (m.location != NSNotFound) {
                    if (fieldOut) *fieldOut = @"NEValidity9999";
                    return [text stringByReplacingCharactersInRange:m withString:@"9999.12.31"];
                }
            }
        } else {
            // 分开 label：纯日期 + 旁边有“服务有效期”
            static NSRegularExpression *sDateOnlyRe = nil;
            static dispatch_once_t sDateOnlyOnce;
            dispatch_once(&sDateOnlyOnce, ^{
                sDateOnlyRe = [NSRegularExpression regularExpressionWithPattern:
                               @"^\\s*\\d{4}[.\\-/年]\\d{1,2}[.\\-/月]\\d{1,2}日?\\s*$"
                               options:0 error:nil];
            });
            if (sDateOnlyRe &&
                [sDateOnlyRe numberOfMatchesInString:text options:0
                                               range:NSMakeRange(0, text.length)] > 0 &&
                NEAdjacentLabelContaining(label, @"服务有效期")) {
                if (fieldOut) *fieldOut = @"NEValidity9999";
                if (separateOut) *separateOut = YES;
                return @"9999.12.31";
            }
        }
    }
    // 纯数字才走“分开 label”匹配；先算一次，后面复用
    BOOL isNum = NEIsPureNumberString(text);
    // 2. 总里程
    if (gMileage && gMileageValue.length > 0) {
        // 同 label：整行就是数字+km（如 35624.6 km）→ 整行换成用户填的值。
        // “60 km/h”这种带 /h 的不匹配（正则要求行尾就是 km），不会误换。
        if ([text rangeOfString:@"km"].location != NSNotFound) {
            static NSRegularExpression *sMileRe = nil;
            static dispatch_once_t sMileOnce;
            dispatch_once(&sMileOnce, ^{
                sMileRe = [NSRegularExpression regularExpressionWithPattern:
                           @"^\\s*[\\d,]+(\\.\\d+)?\\s*km\\s*$"
                           options:0 error:nil];
            });
            if (sMileRe &&
                [sMileRe numberOfMatchesInString:text options:0
                                           range:NSMakeRange(0, text.length)] > 0) {
                if (fieldOut) *fieldOut = @"NEMileage";
                return gMileageValue;
            }
        }
        // 分开 label：纯数字 + 旁边有“km”（不是 km/h）；旁边有 % 就是电量，不换
        if (isNum && !NEHasAdjacentPercentLabel(label)) {
            for (UILabel *cand in NEAdjacentLabels(label)) {
                NSString *kt = NEPlainTextOfLabel(cand);
                if (!kt.length || [kt rangeOfString:@"km"].location == NSNotFound) continue;
                if ([kt rangeOfString:@"km/h"].location != NSNotFound) continue;
                if (fieldOut) *fieldOut = @"NEMileage";
                if (separateOut) *separateOut = YES;
                return gMileageValue;
            }
        }
    }
    // 3. 等级
    if (gLevel && gLevelValue.length > 0) {
        if ([text hasPrefix:@"Lv."] || [text hasPrefix:@"lv."]) {
            if (fieldOut) *fieldOut = @"NELevel";
            return gLevelValue;
        }
        // 分开 label：纯数字 + 旁边有“Lv”
        if (isNum) {
            for (UILabel *cand in NEAdjacentLabels(label)) {
                NSString *ct = NEPlainTextOfLabel(cand);
                if (ct.length && ([ct rangeOfString:@"Lv"].location != NSNotFound ||
                                  [ct rangeOfString:@"lv"].location != NSNotFound)) {
                    if (fieldOut) *fieldOut = @"NELevel";
                    if (separateOut) *separateOut = YES;
                    NSString *v = gLevelValue;
                    if ([v hasPrefix:@"Lv."] || [v hasPrefix:@"lv."])
                        v = [v substringFromIndex:3];
                    return v;
                }
            }
        }
    }
    // 4. 称号
    if (gTitle && gTitleValue.length > 0) {
        if ([text isEqualToString:@"暂无称号"]) {
            if (fieldOut) *fieldOut = @"NETitle";
            return gTitleValue;
        }
        // 分开 label：短文本 + 旁边有“称号”（且自己不含“称号”、不是数字）
        if (text.length <= 16 && [text rangeOfString:@"称号"].location == NSNotFound &&
            !isNum && NEAdjacentLabelContaining(label, @"称号")) {
            if (fieldOut) *fieldOut = @"NETitle";
            if (separateOut) *separateOut = YES;
            return gTitleValue;
        }
    }
    // 5. 连续签到天数
    if (gSignDays && gSignDaysValue.length > 0) {
        if ([text rangeOfString:@"连续签到"].location != NSNotFound) {
            static NSRegularExpression *sDayRe = nil;
            static dispatch_once_t sDayOnce;
            dispatch_once(&sDayOnce, ^{
                sDayRe = [NSRegularExpression regularExpressionWithPattern:
                          @"连续签到\\D*(\\d+)\\D*天"
                          options:0 error:nil];
            });
            if (sDayRe) {
                NSTextCheckingResult *m = [sDayRe firstMatchInString:text options:0
                                                                range:NSMakeRange(0, text.length)];
                if (m && m.numberOfRanges > 1) {
                    if (fieldOut) *fieldOut = @"NESignDays";
                    return [text stringByReplacingCharactersInRange:[m rangeAtIndex:1]
                                                         withString:gSignDaysValue];
                }
            }
        }
        // 分开 label：纯数字 + 旁边有“连续签到”
        if (isNum && NEAdjacentLabelContaining(label, @"连续签到")) {
            if (fieldOut) *fieldOut = @"NESignDays";
            if (separateOut) *separateOut = YES;
            return gSignDaysValue;
        }
    }
    // 6. N币余额：单独数字，旁边有“N币”label（窗口坐标相邻才认，帧没布局时不认）；
    // 旁边有 % 就是电量，不换。认不出宁可不换，绝不能把创作/关注/粉丝的数字换了。
    if (gNCoins && gNCoinsValue.length > 0 && isNum &&
        !NEHasAdjacentPercentLabel(label) &&
        NEAdjacentLabelContaining(label, @"N币")) {
        if (fieldOut) *fieldOut = @"NENCoins";
        if (separateOut) *separateOut = YES;
        return gNCoinsValue;
    }
    return nil;
}

// 富文本替换：只换 plain 和 fixed 不同的那一段，保留原属性；
// 整串都换时插入的文本取被换掉那段首字符的属性。算不准就整串重建（首字符属性），绝不崩。
static NSAttributedString *NEAttributedStringByReplacing(NSAttributedString *orig,
                                                         NSString *plain, NSString *fixed) {
    if (!orig || orig.length == 0)
        return [[NSAttributedString alloc] initWithString:fixed ?: @""];
    if (!plain) plain = orig.string;
    if (!fixed) fixed = plain;
    NSUInteger n = MIN(plain.length, fixed.length);
    NSUInteger start = 0;
    while (start < n && [plain characterAtIndex:start] == [fixed characterAtIndex:start]) start++;
    NSUInteger endP = plain.length, endF = fixed.length;
    while (endP > start && endF > start &&
           [plain characterAtIndex:endP - 1] == [fixed characterAtIndex:endF - 1]) { endP--; endF--; }
    NSMutableAttributedString *m = [[NSMutableAttributedString alloc] initWithAttributedString:orig];
    @try {
        [m replaceCharactersInRange:NSMakeRange(start, endP - start)
                         withString:[fixed substringWithRange:NSMakeRange(start, endF - start)]];
    } @catch (...) {
        NSDictionary *attrs = orig.length > 0 ?
            [orig attributesAtIndex:0 effectiveRange:NULL] : nil;
        m = [[NSMutableAttributedString alloc] initWithString:fixed attributes:attrs];
    }
    return m;
}

static void (*orig_UILabel_setAttributedText)(id, SEL, NSAttributedString *);

static void NE_UILabel_setText(id self, SEL _cmd, NSString *text) {
    if (text.length > 0 && [self isKindOfClass:[UILabel class]]) {
        NSString *field = nil; BOOL separate = NO;
        NSString *fixed = NEFixedLabelString(text, (UILabel *)self, &field, &separate);
        if (fixed) {
            if (field.length) {
                objc_setAssociatedObject(self, &NEAppliedFieldKey, field,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(self, &NEAppliedSeparateKey, @(separate),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            orig_UILabel_setText(self, _cmd, fixed);
            return;
        }
    }
    orig_UILabel_setText(self, _cmd, text);
}

static void NE_UILabel_setAttributedText(id self, SEL _cmd, NSAttributedString *attr) {
    if (attr.length > 0 && [self isKindOfClass:[UILabel class]]) {
        NSString *field = nil; BOOL separate = NO;
        NSString *fixed = NEFixedLabelString(attr.string, (UILabel *)self, &field, &separate);
        if (fixed) {
            if (field.length) {
                objc_setAssociatedObject(self, &NEAppliedFieldKey, field,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(self, &NEAppliedSeparateKey, @(separate),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            orig_UILabel_setAttributedText(self, _cmd,
                NEAttributedStringByReplacing(attr, attr.string, fixed));
            return;
        }
    }
    orig_UILabel_setAttributedText(self, _cmd, attr);
}

// UILabel 文字钩子（setText: + setAttributedText:）由 9999 有效期和五个自定义项共用，只装一次。
static BOOL gLabelHookInstalled = NO;
static void NEInstallLabelHookIfNeeded(void) {
    if (gLabelHookInstalled) return;
    if (!gValidity9999 && !gNCoins && !gMileage && !gLevel && !gTitle && !gSignDays) return;
    Class cls = objc_getClass("UILabel");
    if (!cls || !class_getInstanceMethod(cls, @selector(setText:))) {
        os_log(gLog, "[LBL] UILabel/setText: 不存在，不装钩子");
        return;
    }
    MSHookMessageEx(cls, @selector(setText:), (IMP)NE_UILabel_setText,
                    (IMP *)&orig_UILabel_setText);
    if (!orig_UILabel_setText) {
        os_log(gLog, "[LBL] UILabel setText 钩子安装失败");
        return;
    }
    if (class_getInstanceMethod(cls, @selector(setAttributedText:))) {
        MSHookMessageEx(cls, @selector(setAttributedText:),
                        (IMP)NE_UILabel_setAttributedText,
                        (IMP *)&orig_UILabel_setAttributedText);
        if (orig_UILabel_setAttributedText)
            os_log(gLog, "[LBL] UILabel setAttributedText: 钩子已装");
        else
            os_log(gLog, "[LBL] UILabel setAttributedText: 钩子安装失败（只用 setText:）");
    }
    gLabelHookInstalled = YES;
    os_log(gLog, "[LBL] UILabel setText 钩子已装");
}

// 之前被替换过的 label 按当前值重设（开关还开着且值非空才换）。
// 有效期/签到天数不走这里——它们换完还保留原句式，正常重设就能再匹配上。
static NSString *NEFieldCurrentValue(NSString *field, BOOL separate) {
    if ([field isEqualToString:@"NEMileage"])
        return (gMileage && gMileageValue.length > 0) ? gMileageValue : nil;
    if ([field isEqualToString:@"NENCoins"])
        return (gNCoins && gNCoinsValue.length > 0) ? gNCoinsValue : nil;
    if ([field isEqualToString:@"NETitle"])
        return (gTitle && gTitleValue.length > 0) ? gTitleValue : nil;
    if ([field isEqualToString:@"NELevel"]) {
        if (!gLevel || gLevelValue.length == 0) return nil;
        if (!separate) return gLevelValue;
        // 分开 label 时只换数字部分：用户填 "Lv.99" 就取 "99"
        NSString *v = gLevelValue;
        if ([v hasPrefix:@"Lv."] || [v hasPrefix:@"lv."]) return [v substringFromIndex:3];
        return v;
    }
    return nil;
}

// 按 label 当前的文本/富文本形式，把新文本写回去（富文本保留原属性）
static void NESetLabelPlainText(UILabel *label, NSString *newText) {
    if (!label || !newText) return;
    if (label.attributedText) {
        label.attributedText = NEAttributedStringByReplacing(label.attributedText,
                                                             label.attributedText.string, newText);
    } else {
        label.text = newText;
    }
}

// 强制刷新：把 view 子树里所有 UILabel 的当前文本重设一遍，让它们走一遍钩子。
// 解决“页面启动时已设好文本，改设置后 App 不再重设”的问题。
// 注意：开关关掉后换过的 label 恢复不了原值（原值已被换掉），只能等下次进 App——
// 钩子关了就不再换，App 自己重设时就显示真值。
static void NEForceRefreshLabelsInView(UIView *view) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)sub;
            // 按钮的标题 label（如我们自己的“Ninebot pro+”按钮）不碰
            if ([label.superview isKindOfClass:[UIButton class]]) continue;
            @try {
                NSString *field = objc_getAssociatedObject(label, &NEAppliedFieldKey);
                if (field.length) {
                    NSNumber *sep = objc_getAssociatedObject(label, &NEAppliedSeparateKey);
                    NSString *val = NEFieldCurrentValue(field, sep.boolValue);
                    if (val) { NESetLabelPlainText(label, val); continue; }
                }
                if (label.attributedText) {
                    NSAttributedString *a = label.attributedText;
                    if (a.length) label.attributedText = a;
                } else if (label.text.length) {
                    label.text = label.text;
                }
            } @catch (...) {}
        }
        NEForceRefreshLabelsInView(sub);
    }
}

static void NEForceRefreshLabels(void) {
    if (!gLabelHookInstalled) return;
    UIWindow *w = NEKeyWindow();
    if (!w) return;
    NEForceRefreshLabelsInView(w);
}

// --- 主页车辆图 / 背景图自定义 ---
static NSString *NEVehicleImagePath(void) {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"NEVehicleImagePath"];
}
static NSString *NEBackgroundImagePath(void) {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"NEBackgroundImagePath"];
}
// 高频钩子（setImage:）的快筛缓存：设置页改动时同步更新
static BOOL gHasVehicleImage = NO;
static BOOL gHasBgImage = NO;

static NSLock *gImageLock = nil; // %ctor 里建；图片缓存读写用
static UIImage *gVehicleImage = nil;
static NSString *gVehicleImageLoadedPath = nil;
static UIImage *gBgImage = nil;
static NSString *gBgImageLoadedPath = nil;

// 路径没变就用缓存；路径变了/文件没了就重读（失败返回 nil，不崩）
// 注意：cacheSlot/pathSlot 指向的是全局 strong 变量，形参必须标 __strong，
// 否则 ARC 默认 __autoreleasing 写回参数会报“passing address of non-local object”编译错。
static UIImage *NELoadCustomImage(NSString *path, UIImage * __strong *cacheSlot, NSString * __strong *pathSlot) {
    if (!path.length) return nil;
    [gImageLock lock];
    UIImage *img = nil;
    if (*cacheSlot && [*pathSlot isEqualToString:path]) {
        img = *cacheSlot;
    } else {
        @try { img = [UIImage imageWithContentsOfFile:path]; } @catch (...) { img = nil; }
        *cacheSlot = img;
        *pathSlot = img ? path : nil;
    }
    [gImageLock unlock];
    return img;
}
static UIImage *NECustomVehicleImage(void) {
    return NELoadCustomImage(NEVehicleImagePath(), &gVehicleImage, &gVehicleImageLoadedPath);
}
static UIImage *NECustomBackgroundImage(void) {
    return NELoadCustomImage(NEBackgroundImagePath(), &gBgImage, &gBgImageLoadedPath);
}
static void NEClearImageCache(void) {
    [gImageLock lock];
    gVehicleImage = nil; gVehicleImageLoadedPath = nil;
    gBgImage = nil; gBgImageLoadedPath = nil;
    [gImageLock unlock];
}

// 是不是“设备”tab（第一个 tab，标题“设备”）：图片只在设备主页换。
// 只看选中的 tab，不要求是根页面——车辆图/背景图所在的页面就是该 tab 的根页面，
// 而拦截发生时可能正有 modal（比如设置页）盖在上面。
static BOOL NEIsDeviceTabSelected(void) {
    UIWindow *keyWindow = NEKeyWindow();
    UIViewController *root = keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    if (![root isKindOfClass:[UITabBarController class]]) return NO;
    UITabBarController *tab = (UITabBarController *)root;
    UIViewController *sel = tab.selectedViewController;
    return [sel.tabBarItem.title isEqualToString:@"设备"] || tab.selectedIndex == 0;
}

static BOOL NEStringHasAny(NSString *s, NSArray<NSString *> *keys) {
    for (NSString *k in keys) {
        if ([s rangeOfString:k].location != NSNotFound) return YES;
    }
    return NO;
}

// SDWebImage 的 URL 判定：满屏大图位 → 背景；小图（图标）直接放行；
// 其余按 URL 关键字分车辆图 / 背景图。view 的 bounds 在自动布局完成前可能为 0，
// 那时只按 URL 关键字判定。
static UIImage *NEImageForSDURL(UIImageView *iv, NSURL *url) {
    if (!NEIsDeviceTabSelected()) return nil;
    NSString *u = [[url absoluteString] lowercaseString];
    if (!u.length) return nil;
    CGSize vs = iv.bounds.size;
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    if (vs.width >= sw * 0.9 && vs.height >= sh * 0.5)
        return NECustomBackgroundImage();
    if (vs.width > 0 && vs.width < 150) return nil; // 图标/头像不碰
    if (NEStringHasAny(u, @[@"vehicle", @"veh", @"car", @"bike", @"scooter",
                            @"motor", @"m395", @"model"]))
        return NECustomVehicleImage();
    if (NEStringHasAny(u, @[@"bg", @"background", @"banner", @"wallpaper", @"theme"]))
        return NECustomBackgroundImage();
    return nil;
}

static void (*orig_sd_setImageWithURL)(id, SEL, NSURL *);
static void NE_sd_setImageWithURL(id self, SEL _cmd, NSURL *url) {
    if (url && (gHasVehicleImage || gHasBgImage)) {
        UIImage *custom = NEImageForSDURL((UIImageView *)self, url);
        if (custom) {
            // setImage: 兜底钩子与 SDWebImage 钩子互斥安装，这里直接调不会递归
            [(UIImageView *)self setImage:custom];
            return;
        }
    }
    orig_sd_setImageWithURL(self, _cmd, url);
}

// SDWebImage 5.x 全量变体（带 context 的是核心入口，带 placeholder 的便捷方法最终也走它）
static void (*orig_sd_setImageWithURL_ctx)(id, SEL, NSURL *, id, NSUInteger, id, id, id);
static void NE_sd_setImageWithURL_ctx(id self, SEL _cmd, NSURL *url, id placeholder,
                                      NSUInteger options, id context, id progress, id completed) {
    if (url && (gHasVehicleImage || gHasBgImage)) {
        UIImage *custom = NEImageForSDURL((UIImageView *)self, url);
        if (custom) {
            [(UIImageView *)self setImage:custom];
            if (completed) {
                void (^cb)(id, id, NSInteger, id) = completed;
                @try { cb(custom, nil, 0, url); } @catch (...) {}
            }
            return;
        }
    }
    orig_sd_setImageWithURL_ctx(self, _cmd, url, placeholder, options, context, progress, completed);
}

// 兜底：无 SDWebImage 时 hook -[UIImageView setImage:]，按图片尺寸分车辆图/背景图
static void (*orig_UIImageView_setImage)(id, SEL, UIImage *);
static void NE_UIImageView_setImage(id self, SEL _cmd, UIImage *image) {
    if (image && (gHasVehicleImage || gHasBgImage)) {
        CGSize sz = image.size;
        CGFloat sw = [UIScreen mainScreen].bounds.size.width;
        CGFloat sh = [UIScreen mainScreen].bounds.size.height;
        UIImage *custom = nil;
        if (sz.width >= sw * 0.9 && sz.height >= sh * 0.5) {
            custom = NECustomBackgroundImage(); // 满屏大图 → 背景
        } else if (sz.width >= 200) {
            custom = NECustomVehicleImage();    // 大图 → 车辆图；小图不碰
        }
        if (custom && NEIsDeviceTabSelected()) {
            orig_UIImageView_setImage(self, _cmd, custom);
            return;
        }
    }
    orig_UIImageView_setImage(self, _cmd, image);
}

// 本地 asset 兜底：+[UIImage imageNamed:]，按名字关键字匹配。
// 名字是运行时实际看到的才准：命中关键字的名字只记一次日志，方便以后收紧。
static id (*orig_UIImage_imageNamed)(id, SEL, NSString *);
static id NE_UIImage_imageNamed(id self, SEL _cmd, NSString *name) {
    id img = orig_UIImage_imageNamed(self, _cmd, name);
    if (!name.length || (!gHasVehicleImage && !gHasBgImage)) return img;
    NSString *lower = [name lowercaseString];
    BOOL isBg = NEStringHasAny(lower, @[@"bg", @"background", @"banner"]);
    BOOL isVeh = !isBg && NEStringHasAny(lower, @[@"vehicle", @"car", @"bike",
                                                  @"scooter", @"motor", @"m3"]);
    if (!isBg && !isVeh) return img;
    // 只在设备 tab 换：imageNamed 可能在后台线程调，同步回主线程查 tab
    __block BOOL onDeviceTab = YES;
    if ([NSThread isMainThread]) {
        onDeviceTab = NEIsDeviceTabSelected();
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{ onDeviceTab = NEIsDeviceTabSelected(); });
    }
    if (!onDeviceTab) return img;
    UIImage *custom = isBg ? NECustomBackgroundImage() : NECustomVehicleImage();
    if (!custom) return img;
    static NSMutableSet *sLoggedNames = nil;
    static dispatch_once_t sOnce;
    dispatch_once(&sOnce, ^{ sLoggedNames = [NSMutableSet new]; });
    @synchronized (sLoggedNames) {
        if (![sLoggedNames containsObject:name]) {
            [sLoggedNames addObject:name];
            os_log(gLog, "[IMG] imageNamed 命中 %{public}@ → 换成自定义%{public}@",
                   name, isBg ? @"背景图" : @"车辆图");
        }
    }
    return custom;
}

static BOOL gImageHooksInstalled = NO;
static void NEInstallImageHooksIfNeeded(void) {
    if (gImageHooksInstalled) return;
    Class iv = objc_getClass("UIImageView");
    if (!iv) {
        os_log(gLog, "[IMG] UIImageView 类未找到，不装图片钩子");
        return;
    }
    if (class_getInstanceMethod(iv, @selector(sd_setImageWithURL:))) {
        MSHookMessageEx(iv, @selector(sd_setImageWithURL:),
                        (IMP)NE_sd_setImageWithURL, (IMP *)&orig_sd_setImageWithURL);
        if (!orig_sd_setImageWithURL) {
            os_log(gLog, "[IMG] sd_setImageWithURL: 钩子安装失败");
        } else {
            os_log(gLog, "[IMG] SDWebImage 钩子已装（sd_setImageWithURL:）");
        }
        SEL ctxSel = @selector(sd_setImageWithURL:placeholderImage:options:context:progress:completed:);
        if (class_getInstanceMethod(iv, ctxSel)) {
            MSHookMessageEx(iv, ctxSel, (IMP)NE_sd_setImageWithURL_ctx,
                            (IMP *)&orig_sd_setImageWithURL_ctx);
            if (orig_sd_setImageWithURL_ctx)
                os_log(gLog, "[IMG] SDWebImage 钩子已装（sd_setImageWithURL:…context:）");
        }
    } else {
        MSHookMessageEx(iv, @selector(setImage:),
                        (IMP)NE_UIImageView_setImage, (IMP *)&orig_UIImageView_setImage);
        if (!orig_UIImageView_setImage) {
            os_log(gLog, "[IMG] UIImageView setImage: 钩子安装失败");
        } else {
            os_log(gLog, "[IMG] 无 SDWebImage，改用 UIImageView setImage: 兜底钩子");
        }
    }
    Class ui = objc_getClass("UIImage");
    if (ui && class_getClassMethod(ui, @selector(imageNamed:))) {
        MSHookMessageEx(object_getClass(ui), @selector(imageNamed:),
                        (IMP)NE_UIImage_imageNamed, (IMP *)&orig_UIImage_imageNamed);
        if (orig_UIImage_imageNamed)
            os_log(gLog, "[IMG] UIImage imageNamed: 钩子已装（本地 asset 兜底）");
    }
    gImageHooksInstalled = YES;
}

// v0.3.9 修复：图片强制刷新——主题图/车图在 App 启动时已加载好，改设置后
// App 不再重设，钩子拦不到。选图后把设备 tab 里所有 UIImageView 按尺寸重算一次。
// 注意：不能用 NEIsDeviceTabSelected() 判定——设置页正以 modal 盖在上面，
// 它跟 presentedViewController 会走到设置页 nav，永远返回 NO；
// 这里直接从根控制器取 tab bar（不跟 presented 链），再看当前选中的是不是设备 tab。
// 主题图若不是 UIImageView 的 image（而是 view 背景色/图层内容），这招换不上，
// 那时只能看日志里的 imageNamed 名字再收紧——先按 UIImageView 处理。
static UITabBarController *NEAppTabBarController(void) {
    UIWindow *w = NEKeyWindow();
    UIViewController *root = w.rootViewController;
    if ([root isKindOfClass:[UITabBarController class]]) return (UITabBarController *)root;
    return nil;
}

static void NEForceRefreshImagesInView(UIView *view) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UIImageView class]]) {
            UIImageView *iv = (UIImageView *)sub;
            UIImage *img = iv.image;
            if (img) {
                @try {
                    CGSize sz = img.size;
                    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
                    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
                    UIImage *custom = nil;
                    if (sz.width >= sw * 0.9 && sz.height >= sh * 0.5)
                        custom = NECustomBackgroundImage(); // 满屏大图 → 背景
                    else if (sz.width >= 200)
                        custom = NECustomVehicleImage();    // 大图 → 车辆图；小图不碰
                    // 直接赋值：SDWebImage 路径下 setImage: 没钩子，赋值就是替换；
                    // setImage: 兜底钩子装着时，走钩子再算一次也是同一张图，不会循环。
                    if (custom && custom != img) iv.image = custom;
                } @catch (...) {}
            }
        }
        NEForceRefreshImagesInView(sub);
    }
}

static void NEForceRefreshImages(void) {
    if (!gHasVehicleImage && !gHasBgImage) return;
    UITabBarController *tab = NEAppTabBarController();
    if (!tab) return;
    UIViewController *sel = tab.selectedViewController;
    BOOL isDevice = [sel.tabBarItem.title isEqualToString:@"设备"] || tab.selectedIndex == 0;
    if (!isDevice || !sel.view) return;
    NEForceRefreshImagesInView(sel.view);
}

// ---------------- 天气（Open-Meteo，免费、无 key）----------------
// 定位一次 → 后台拉天气 → 缓存 20 分钟。帧回调里只读缓存。
// 存天气码 + 温度（画图标用），不只存拼好的字符串。

static int              gWeatherCode     = -1;  // Open-Meteo weather_code，-1 = 还没拿到
static int              gWeatherTemp     = 0;
static CFAbsoluteTime   gWeatherAt       = 0;
static BOOL             gWeatherFetching = NO;
static BOOL             gHaveCoords      = NO;
static double           gLat = 0, gLon = 0;
static CFAbsoluteTime   gLastLocAttempt  = 0;

// 天气请求专用的 session：10 秒超时，别让一次挂起的请求长时间占着 gWeatherFetching 挡住重试。
static NSURLSession *NEWeatherSession(void) {
    static NSURLSession *s = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 10;
        s = [NSURLSession sessionWithConfiguration:cfg];
    });
    return s;
}

static void FetchWeather(double lat, double lon) {
    NSString *urlStr = [NSString stringWithFormat:
        @"https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f"
         "&current=temperature_2m,weather_code&timezone=auto", lat, lon];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        [gDataLock lock]; gWeatherFetching = NO; [gDataLock unlock];
        return;
    }
    NSURLSessionDataTask *task = [NEWeatherSession() dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data) {
            os_log(gLog, "[WX] 拉取失败：%{public}s",
                   err ? err.localizedDescription.UTF8String : "no data");
            [gDataLock lock]; gWeatherFetching = NO; [gDataLock unlock];
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *cur = json[@"current"];
        NSNumber *temp = cur[@"temperature_2m"];
        NSNumber *code = cur[@"weather_code"];
        if (temp && code) {
            int newCode = [code intValue];
            int newTemp = (int)lround([temp doubleValue]);
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            [gDataLock lock];
            gWeatherCode = newCode;
            gWeatherTemp = newTemp;
            gWeatherAt = now;
            gWeatherFetching = NO;
            [gDataLock unlock];
            // 存一份，下次冷启动 2 小时内直接用，不用等定位+拉取
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            [d setInteger:newCode forKey:@"NEWeatherCode"];
            [d setInteger:newTemp forKey:@"NEWeatherTemp"];
            [d setDouble:now forKey:@"NEWeatherAt"];
            os_log(gLog, "[WX] %d° code=%d", newTemp, newCode);
        } else {
            [gDataLock lock]; gWeatherFetching = NO; [gDataLock unlock];
        }
    }];
    [task resume];
}

// 满足条件就触发一次后台拉取（不阻塞调用方）。20 分钟内有缓存不拉。
static void RefreshWeatherIfNeeded(void) {
    [gDataLock lock];
    BOOL haveData = (gWeatherCode >= 0);
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    BOOL fresh = haveData && (now - gWeatherAt) < 20 * 60;
    BOOL fetching = gWeatherFetching;
    BOOL haveCoords = gHaveCoords;
    double lat = gLat, lon = gLon;
    [gDataLock unlock];
    if (fresh || fetching) return;
    if (!haveCoords) {
        // 还没拿到定位：1 分钟最多再试一次（主线程调 requestLocation）
        if (now - gLastLocAttempt < 60) return;
        gLastLocAttempt = now;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gLocMgr) [gLocMgr requestLocation];
        });
        return;
    }
    [gDataLock lock]; gWeatherFetching = YES; [gDataLock unlock];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        FetchWeather(lat, lon);
    });
}

@interface NELocationDelegate : NSObject <CLLocationManagerDelegate>
@end

@implementation NELocationDelegate
- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = locations.lastObject;
    if (!loc) return;
    [gDataLock lock];
    gLat = loc.coordinate.latitude;
    gLon = loc.coordinate.longitude;
    gHaveCoords = YES;
    [gDataLock unlock];
    os_log(gLog, "[WX] 定位已拿到，开始拉天气");
    RefreshWeatherIfNeeded();
    // 超速提醒：过滤后算 km/h，越界沿触发一次震动+提示音。
    // RefreshWeatherIfNeeded 内部有 20 分钟缓存 + fetching 节流，
    // 连续定位每秒调它也不会多拉天气。
    // 速度一直记（超速提醒和骑行小人共用）；提醒的触发仍只在开关开着时做。
    NSTimeInterval age = -[loc.timestamp timeIntervalSinceNow];
    if (loc.speed >= 0 && loc.horizontalAccuracy <= 65 && age <= 10) {
        double kmh = loc.speed * 3.6;
        [gDataLock lock];
        gSpeedKmh = kmh;
        gSpeedAt = CFAbsoluteTimeGetCurrent();
        [gDataLock unlock];
        if (NEHUDSpeedAlert()) {
            NSInteger limit = NEHUDSpeedLimit();
            if (kmh > limit) {
                if (!gWasOverspeed) {
                    gWasOverspeed = YES;
                    UINotificationFeedbackGenerator *gen = [UINotificationFeedbackGenerator new];
                    [gen notificationOccurred:UINotificationFeedbackTypeWarning];
                    AudioServicesPlaySystemSound(1005);
                    os_log(gLog, "[SPD] 超速 %d km/h（限速 %d）", (int)kmh, (int)limit);
                    // 语音朗读（0.3.8）：超速那一刻中文读一次；正在读就截断重读，
                    //  不排队。跟着超速提醒开关走（这里本来就只在开关开着时进）。
                    if (!gSpeechSynth) gSpeechSynth = [AVSpeechSynthesizer new];
                    [gSpeechSynth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
                    AVSpeechUtterance *utt = [AVSpeechUtterance speechUtteranceWithString:@"您已超速行驶，请注意安全"];
                    utt.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"zh-CN"];
                    utt.rate = AVSpeechUtteranceDefaultSpeechRate;
                    [gSpeechSynth speakUtterance:utt];
                }
            } else {
                gWasOverspeed = NO;
            }
        }
    }
}
- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(NSError *)error {
    os_log(gLog, "[WX] 定位失败：%{public}s", error.localizedDescription.UTF8String);
}
@end

// 超速提醒或翻页时钟开 → 连续定位（best 精度）；都关 → 恢复单次定位
// （3km 精度，只够天气用）。主线程调（gLocMgr 在主队列创建，回调也在主队列）。
static void NEApplySpeedLocationMode(void) {
    if (!gLocMgr) return;
    if (NEHUDSpeedAlert() || NEHUDShowSlot()) {
        gLocMgr.desiredAccuracy = kCLLocationAccuracyBest;
        [gLocMgr startUpdatingLocation];
    } else {
        [gLocMgr stopUpdatingLocation];
        gLocMgr.desiredAccuracy = kCLLocationAccuracyThreeKilometers;
        [gLocMgr requestLocation];
    }
}

// ---------------- 联网方式（NWPathMonitor + 蜂窝制式）----------------
// 0 不显示（没网/未知） 1 WiFi 2 蜂窝（netLabel 是 5G/4G/3G/2G/蜂窝）

static int       gNetKind  = 0;
static NSString *gNetLabel = nil;
static nw_path_monitor_t gPathMonitor = nil;
static CTTelephonyNetworkInfo *gTelephonyInfo = nil;

static NSString *NERadioTechLabel(void) {
    if (!gTelephonyInfo) gTelephonyInfo = [CTTelephonyNetworkInfo new];
    NSDictionary *techs = gTelephonyInfo.serviceCurrentRadioAccessTechnology;
    NSString *tech = techs.allValues.firstObject;
    if (!tech) return @"蜂窝";
    if ([tech isEqualToString:CTRadioAccessTechnologyNR] ||
        [tech isEqualToString:CTRadioAccessTechnologyNRNSA]) return @"5G";
    if ([tech isEqualToString:CTRadioAccessTechnologyLTE]) return @"4G";
    if ([tech isEqualToString:CTRadioAccessTechnologyWCDMA] ||
        [tech isEqualToString:CTRadioAccessTechnologyHSDPA] ||
        [tech isEqualToString:CTRadioAccessTechnologyHSUPA] ||
        [tech isEqualToString:CTRadioAccessTechnologyeHRPD] ||
        [tech isEqualToString:CTRadioAccessTechnologyCDMAEVDORev0] ||
        [tech isEqualToString:CTRadioAccessTechnologyCDMAEVDORevA] ||
        [tech isEqualToString:CTRadioAccessTechnologyCDMAEVDORevB] ||
        [tech isEqualToString:CTRadioAccessTechnologyCDMA1x]) return @"3G";
    if ([tech isEqualToString:CTRadioAccessTechnologyGPRS] ||
        [tech isEqualToString:CTRadioAccessTechnologyEdge]) return @"2G";
    return @"蜂窝";
}

static void NEStartNetworkMonitor(void) {
    gPathMonitor = nw_path_monitor_create();
    if (!gPathMonitor) return;
    nw_path_monitor_set_queue(gPathMonitor,
        dispatch_queue_create("com.user.ninebotenhance.net", DISPATCH_QUEUE_SERIAL));
    nw_path_monitor_set_update_handler(gPathMonitor, ^(nw_path_t path) {
        int kind = 0;
        NSString *label = nil;
        if (nw_path_get_status(path) == nw_path_status_satisfied) {
            if (nw_path_uses_interface_type(path, nw_interface_type_wifi)) {
                kind = 1;
            } else if (nw_path_uses_interface_type(path, nw_interface_type_cellular)) {
                kind = 2;
                label = NERadioTechLabel();
            }
        }
        [gDataLock lock];
        gNetKind = kind;
        gNetLabel = label;
        [gDataLock unlock];
    });
    nw_path_monitor_start(gPathMonitor);
}

// ---------------- 音量（系统音量，1 秒一刷）----------------

static float gVolume = -1;  // 0...1，-1 = 未知

static void NERefreshVolume(void) {
    // 主线程调用。
    float vol = [AVAudioSession sharedInstance].outputVolume;
    [gDataLock lock];
    gVolume = vol;
    [gDataLock unlock];
}

// ---------------- 来电（CallKit，公开 API）----------------
// 只记“有没有未结束的通话”，不读号码（CallKit 不向第三方 App 暴露号码）。

static CXCallObserver *gCallObserver = nil;
static BOOL gCallActive = NO;

@interface NECallDelegate : NSObject <CXCallObserverDelegate>
@end

@implementation NECallDelegate
- (void)callObserver:(CXCallObserver *)callObserver callChanged:(CXCall *)call {
    BOOL active = NO;
    for (CXCall *c in callObserver.calls) {
        if (!c.hasEnded) { active = YES; break; }
    }
    [gDataLock lock]; gCallActive = active; [gDataLock unlock];
    os_log(gLog, "[CALL] 来电状态=%d", active);
}
@end

static NECallDelegate *gCallDelegate = nil;

// ---------------- HUD 数据（帧回调里只读这些）----------------

static NSString *HUDTimeString(void) {
    // 例：11月17日 周一 23:20
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];
    fmt.dateFormat = @"M月d日 EEE"; // 0.3.6：时间删掉，只留日期星期（时间只在翻页时钟里）
    return [fmt stringFromDate:[NSDate date]];
}

// ---------------- 叠加层绘制（小胶囊，照 Ninebot Pro+ 1.0.8+）----------------
//
// 坐标系：bitmap context 默认 y 朝上（y=0 在底边），全程不做任何
// Translate/Scale 翻转。文字基线按“离顶距离”换算：
//   baseline = 高 - 离顶距离 - 上伸
// 胶囊锚在底边（pillY = 离底边的距离），行从胶囊顶往下排。
// 这和 Ninebot Pro+ 的 HUDOverlay.swift 是同一套画法，那份代码
// 已在同一块仪表上验证是正的。
//
// v0.1.2 的教训：RenderOverlay 在自己的 bitmap 里先翻转
// （Translate+Scale）再画字，出来的叠加图字是倒的；v0.1.1 在
// 合成时再翻一次，字正了但位置被镜像到上方的仪表表盘遮挡区
// (640,44)-(842,254) 里，所以看不见。本版两边都不翻转。
//
// 参考坐标 848x480。胶囊默认右下角（右边距 12、下边距 12），
// 避开仪表自带表盘遮挡区。帧尺寸随仪表型号变，所以全部用相对坐标。

static CTFontRef HUDFont(CGFloat size) {
    CTFontRef f = CTFontCreateWithName(CFSTR("PingFangSC-Semibold"), size, NULL);
    if (!f) f = CTFontCreateWithName(CFSTR("Helvetica-Bold"), size, NULL);
    return f;
}

static CTLineRef NETextLine(NSString *text, CTFontRef font, CGColorRef color) {
    const void *keys[] = { kCTFontAttributeName, kCTForegroundColorAttributeName };
    const void *vals[] = { font, color };
    CFDictionaryRef attrs = CFDictionaryCreate(NULL, keys, vals, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFAttributedStringRef astr = CFAttributedStringCreate(NULL,
        (__bridge CFStringRef)text, attrs);
    CTLineRef line = CTLineCreateWithAttributedString(astr);
    CFRelease(astr); CFRelease(attrs);
    return line;
}

static CGFloat NETextWidth(CTLineRef line) {
    CGFloat ascent = 0, descent = 0, leading = 0;
    return (CGFloat)CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
}

// ---------- 图标（CoreGraphics 手画，白色，y 朝上坐标，直接照抄 HUDOverlay.swift）----------

static void NEDrawClock(CGContextRef ctx, CGRect rect) {
    CGPoint c = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    CGFloat r = rect.size.width * 0.38;
    CGContextAddArc(ctx, c.x, c.y, r, 0, 2 * M_PI, 0);
    CGContextStrokePath(ctx);
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, c.x, c.y);
    CGContextAddLineToPoint(ctx, c.x, c.y + r * 0.72);
    CGContextMoveToPoint(ctx, c.x, c.y);
    CGContextAddLineToPoint(ctx, c.x + r * 0.55, c.y - r * 0.35);
    CGContextStrokePath(ctx);
}

static void NEDrawWifi(CGContextRef ctx, CGRect rect) {
    CGPoint c = CGPointMake(CGRectGetMidX(rect), rect.origin.y + rect.size.height * 0.12);
    CGFloat f[3] = { 0.30, 0.52, 0.74 };
    for (int i = 0; i < 3; i++) {
        CGContextAddArc(ctx, c.x, c.y, rect.size.width * f[i],
                        M_PI * 0.25, M_PI * 0.75, 0);
        CGContextStrokePath(ctx);
    }
    CGContextAddArc(ctx, c.x, c.y, rect.size.width * 0.06, 0, 2 * M_PI, 0);
    CGContextFillPath(ctx);
}

static void NEDrawSun(CGContextRef ctx, CGRect rect) {
    CGPoint c = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    CGFloat r = rect.size.width * 0.20;
    CGContextAddArc(ctx, c.x, c.y, r, 0, 2 * M_PI, 0);
    CGContextFillPath(ctx);
    for (int i = 0; i < 8; i++) {
        CGFloat a = (CGFloat)i * M_PI / 4;
        CGPoint p1 = CGPointMake(c.x + cos(a) * r * 1.45, c.y + sin(a) * r * 1.45);
        CGPoint p2 = CGPointMake(c.x + cos(a) * r * 2.05, c.y + sin(a) * r * 2.05);
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, p1.x, p1.y);
        CGContextAddLineToPoint(ctx, p2.x, p2.y);
        CGContextStrokePath(ctx);
    }
}

static void NEDrawCloud(CGContextRef ctx, CGRect rect) {
    CGFloat s = rect.size.width;
    CGRect base = CGRectMake(rect.origin.x + s * 0.12, rect.origin.y + s * 0.18,
                             s * 0.76, s * 0.34);
    CGContextFillRect(ctx, base);
    CGFloat cx[3] = { 0.30, 0.55, 0.78 };
    CGFloat cy[3] = { 0.48, 0.60, 0.48 };
    CGFloat cr[3] = { 0.20, 0.24, 0.18 };
    for (int i = 0; i < 3; i++) {
        CGPoint c = CGPointMake(rect.origin.x + s * cx[i], rect.origin.y + s * cy[i]);
        CGContextAddArc(ctx, c.x, c.y, s * cr[i], 0, 2 * M_PI, 0);
        CGContextFillPath(ctx);
    }
}

static void NEDrawBolt(CGContextRef ctx, CGRect rect) {
    CGFloat s = rect.size.width;
    CGPoint pts[6] = {
        CGPointMake(rect.origin.x + s * 0.56, rect.origin.y + s * 0.20),
        CGPointMake(rect.origin.x + s * 0.42, rect.origin.y + s * 0.02),
        CGPointMake(rect.origin.x + s * 0.52, rect.origin.y + s * 0.02),
        CGPointMake(rect.origin.x + s * 0.44, rect.origin.y - s * 0.12),
        CGPointMake(rect.origin.x + s * 0.62, rect.origin.y + s * 0.04),
        CGPointMake(rect.origin.x + s * 0.52, rect.origin.y + s * 0.04)
    };
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, pts[0].x, pts[0].y);
    for (int i = 1; i < 6; i++) CGContextAddLineToPoint(ctx, pts[i].x, pts[i].y);
    CGContextClosePath(ctx);
    CGContextFillPath(ctx);
}

static void NEDrawWeather(CGContextRef ctx, int code, CGRect rect) {
    CGFloat s = rect.size.width;
    if (code == 0) { NEDrawSun(ctx, rect); return; }
    if (code == 1 || code == 2) {
        CGRect sunRect = CGRectMake(rect.origin.x, rect.origin.y + s * 0.45,
                                    s * 0.55, s * 0.55);
        NEDrawSun(ctx, sunRect);
        CGRect cloudRect = CGRectMake(rect.origin.x + s * 0.30, rect.origin.y,
                                      s * 0.70, s * 0.70);
        NEDrawCloud(ctx, cloudRect);
        return;
    }
    NEDrawCloud(ctx, rect);
    if (code == 45 || code == 48) {
        CGFloat fy[2] = { 0.12, 0.03 };
        for (int i = 0; i < 2; i++) {
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, rect.origin.x + s * 0.22, rect.origin.y + s * fy[i]);
            CGContextAddLineToPoint(ctx, rect.origin.x + s * 0.80, rect.origin.y + s * fy[i]);
            CGContextStrokePath(ctx);
        }
    } else if (code == 51 || code == 53 || code == 55 || code == 61 || code == 63 ||
               code == 65 || code == 80 || code == 81 || code == 82) {
        CGFloat fx[3] = { 0.30, 0.52, 0.74 };
        for (int i = 0; i < 3; i++) {
            CGFloat x = rect.origin.x + s * fx[i];
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, x + s * 0.04, rect.origin.y + s * 0.16);
            CGContextAddLineToPoint(ctx, x - s * 0.04, rect.origin.y + s * 0.02);
            CGContextStrokePath(ctx);
        }
    } else if (code == 71 || code == 73 || code == 75) {
        CGFloat fx[3] = { 0.32, 0.52, 0.72 };
        CGFloat fy[3] = { 0.10, 0.04, 0.10 };
        for (int i = 0; i < 3; i++) {
            CGPoint c = CGPointMake(rect.origin.x + s * fx[i], rect.origin.y + s * fy[i]);
            CGContextAddArc(ctx, c.x, c.y, s * 0.045, 0, 2 * M_PI, 0);
            CGContextFillPath(ctx);
        }
    } else if (code == 95) {
        NEDrawBolt(ctx, rect);
    }
}

static void NEDrawSpeaker(CGContextRef ctx, CGRect rect) {
    CGFloat bx = rect.origin.x + rect.size.width * 0.08;
    CGFloat bw = rect.size.width * 0.20;
    CGFloat bh = rect.size.height * 0.36;
    CGContextFillRect(ctx, CGRectMake(bx, CGRectGetMidY(rect) - bh / 2, bw, bh));
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, bx + bw, CGRectGetMidY(rect) - bh / 2);
    CGContextAddLineToPoint(ctx, bx + bw + rect.size.width * 0.34, rect.origin.y + rect.size.height * 0.10);
    CGContextAddLineToPoint(ctx, bx + bw + rect.size.width * 0.34, rect.origin.y + rect.size.height * 0.90);
    CGContextAddLineToPoint(ctx, bx + bw, CGRectGetMidY(rect) + bh / 2);
    CGContextClosePath(ctx);
    CGContextFillPath(ctx);
    CGPoint c = CGPointMake(bx + bw + rect.size.width * 0.34, CGRectGetMidY(rect));
    CGContextAddArc(ctx, c.x, c.y, rect.size.width * 0.12, -M_PI / 3, M_PI / 3, 0);
    CGContextStrokePath(ctx);
    CGContextAddArc(ctx, c.x, c.y, rect.size.width * 0.24, -M_PI / 3, M_PI / 3, 0);
    CGContextStrokePath(ctx);
}

// 电池图标：圆角外框 + 按电量填充 + 右边小凸起；充电中填充变绿
// 并在里面画一道深色闪电；低电量（<20%）轮廓和填充变红。
static void NEDrawBattery(CGContextRef ctx, float level, BOOL charging, BOOL low, CGRect rect) {
    CGColorRef tint = low ? CGColorCreateGenericRGB(1, 0.25, 0.25, 1)
                          : CGColorCreateGenericRGB(1, 1, 1, 1);
    CGContextSetStrokeColorWithColor(ctx, tint);
    CGContextSetFillColorWithColor(ctx, tint);
    CGFloat s = rect.size.width;
    CGFloat bodyW = s * 0.78, bodyH = s * 0.52;
    CGFloat bodyX = rect.origin.x + s * 0.02;
    CGFloat bodyY = CGRectGetMidY(rect) - bodyH / 2;
    CGRect body = CGRectMake(bodyX, bodyY, bodyW, bodyH);
    CGFloat lw = MAX(1, s * 0.06);
    CGContextSetLineWidth(ctx, lw);
    CGPathRef path = CGPathCreateWithRoundedRect(body, s * 0.08, s * 0.08, NULL);
    CGContextAddPath(ctx, path);
    CGContextStrokePath(ctx);
    CGPathRelease(path);
    CGRect nub = CGRectMake(bodyX + bodyW, CGRectGetMidY(rect) - bodyH * 0.22,
                            s * 0.07, bodyH * 0.44);
    CGContextFillRect(ctx, nub);
    float clamped = level < 0 ? 0 : (level > 1 ? 1 : level);
    if (clamped > 0) {
        CGFloat inset = lw + s * 0.03;
        CGFloat fillW = (bodyW - inset * 2) * (CGFloat)clamped;
        CGRect fillRect = CGRectMake(bodyX + inset, bodyY + inset, fillW, bodyH - inset * 2);
        if (charging) {
            CGContextSetRGBFillColor(ctx, 0.25, 0.85, 0.35, 1);
        } else if (low) {
            CGContextSetRGBFillColor(ctx, 1, 0.25, 0.25, 1);
        } else {
            CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
        }
        CGContextFillRect(ctx, fillRect);
        if (charging) {
            CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.75);
            CGFloat cx = bodyX + bodyW * 0.5, cy = CGRectGetMidY(rect);
            CGFloat bw2 = bodyW * 0.16, bh2 = bodyH * 0.38;
            CGPoint pts[6] = {
                CGPointMake(cx + bw2 * 0.4, cy + bh2),
                CGPointMake(cx - bw2 * 0.6, cy - bh2 * 0.1),
                CGPointMake(cx - bw2 * 0.05, cy - bh2 * 0.1),
                CGPointMake(cx - bw2 * 0.4, cy - bh2),
                CGPointMake(cx + bw2 * 0.6, cy + bh2 * 0.1),
                CGPointMake(cx + bw2 * 0.05, cy + bh2 * 0.1)
            };
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, pts[0].x, pts[0].y);
            for (int i = 1; i < 6; i++) CGContextAddLineToPoint(ctx, pts[i].x, pts[i].y);
            CGContextClosePath(ctx);
            CGContextFillPath(ctx);
        }
    }
    CGColorRelease(tint);
}

// ---------- 胶囊行段 ----------
// kind: 0 文字 1 图标 2 电池；icon: 0 时钟 1 WiFi 2 天气 3 喇叭
#define NE_MAX_ROWS 3
#define NE_MAX_SEGS 8

typedef struct {
    int kind;
    int icon;
    int wxCode;
    NSString * __unsafe_unretained text;
    CGColorRef color; // 不持有；调用方保证在绘制期间有效
    float battLevel;
    BOOL battCharging, battLow;
    CTLineRef line; // kind==0 时量宽度建的，用完释放
    CGFloat w;
} NESeg;

static BOOL NEIsIconSeg(NESeg *s) { return s->kind != 0; }

// ---------- 叠加层（全尺寸透明层，只画胶囊 + 来电条）----------

typedef struct {
    BOOL showDate, showWeather, showSignal, showBattery, showVolume;
    BOOL showSlot;  // 翻页时钟开关（v0.3.6，老虎机改成翻页时钟）
    BOOL speedAlert; // 超速提醒开关（v0.1.8）
    NSInteger position; // 0 右下 1 左下 2 左上 3 右上
    CGFloat fontRefPt;  // 16/20/24
} NEHUDSettings;

// ---------- 翻页时钟（v0.3.6）：替代老虎机，和 App 1.3.18 同款 ----------
// 显示当前时间 HH:MM:SS，六张灰卡片，白数字纵向拉长 1.9 倍；
// 数字变了就翻页（0.35s：上半页绕中线折下、再展开新数字，下半页在中点切换）。
// 无黑色底板，卡片直接浮在地图上。面板 204x108，顶边 265，右对齐 X=632，
// 跟车子自带 P 表盘、底下胶囊严格同宽对齐（都是 204）。
// 时钟只跟时间走，不再用速度；跟 BMS 面板互斥的机制原样保留。
static const CGFloat NE_FLIP_PANEL_W = 204.0; // 面板宽（参考点）
static const CGFloat NE_FLIP_PANEL_H = 108.0; // 面板高（参考点）
static const CGFloat NE_FLIP_TOP = 265.0;     // 顶边离顶（参考点）
static const CGFloat NE_FLIP_CARD_W = 26.0;   // 卡片宽
static const CGFloat NE_FLIP_CARD_H = 88.0;   // 卡片高
static const CGFloat NE_FLIP_GAP = 3.0;       // 卡片间隙
static const CGFloat NE_FLIP_COLON_W = 7.0;   // 冒号宽
static const double NE_FLIP_DURATION = 0.35;  // 翻页时长（秒）

static int gNEFlipDigits[6] = { -1, -1, -1, -1, -1, -1 }; // 当前显示的数字（-1=未初始化）
static int gNEFlipOld[6] = { 0, 0, 0, 0, 0, 0 };         // 翻页前的数字
static CFAbsoluteTime gNEFlipStart[6] = { 0, 0, 0, 0, 0, 0 }; // 每格翻页开始时刻（0=没在翻）
static BOOL gNEFlipMoving = NO; // 上次 tick 是否有卡片在翻（节流用）

// 从当前时间取 6 位数字 HHMMSS。
static void NEFlipDigitsFromDate(int d[6]) {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                                 fromDate:[NSDate date]];
    d[0] = (int)c.hour / 10; d[1] = (int)c.hour % 10;
    d[2] = (int)c.minute / 10; d[3] = (int)c.minute % 10;
    d[4] = (int)c.second / 10; d[5] = (int)c.second % 10;
}

// NEFlipTick 在 OverlayForSize 里调（过节流才调一次）。返回：是否有卡片在翻页。
static BOOL NEFlipTick(CFAbsoluteTime now, BOOL enabled) {
    if (!enabled) {
        for (int i = 0; i < 6; i++) { gNEFlipDigits[i] = -1; gNEFlipStart[i] = 0; }
        gNEFlipMoving = NO;
        return NO;
    }
    int d[6];
    NEFlipDigitsFromDate(d);
    BOOL moving = NO;
    for (int i = 0; i < 6; i++) {
        if (gNEFlipDigits[i] == -1) { gNEFlipDigits[i] = d[i]; gNEFlipStart[i] = 0; continue; }
        if (d[i] != gNEFlipDigits[i] && gNEFlipStart[i] == 0) {
            gNEFlipOld[i] = gNEFlipDigits[i];
            gNEFlipDigits[i] = d[i];
            gNEFlipStart[i] = now;
        }
        if (gNEFlipStart[i] != 0) {
            if (now - gNEFlipStart[i] >= NE_FLIP_DURATION) gNEFlipStart[i] = 0;
            else moving = YES;
        }
    }
    gNEFlipMoving = moving;
    return moving;
}

// 在卡片内画一个数字：绕卡片中心纵向拉长 stretchY；
// hasClip 时只画 clipRect 内的部分；squashY/squashAnchorY 用于翻页
// （上半页绕中线压缩/展开，1=正常，0=压成一条线）。
static void NEDrawFlipDigit(CGContextRef ctx, NSString *text, CTFontRef font, CGColorRef color,
                            CGPoint center, CGFloat stretchY,
                            CGRect clipRect, BOOL hasClip,
                            CGFloat squashY, CGFloat squashAnchorY) {
    CTLineRef line = NETextLine(text, font, color);
    CGFloat tw = NETextWidth(line);
    CGFloat ascent = (CGFloat)CTFontGetAscent(font);
    CGFloat descent = (CGFloat)CTFontGetDescent(font);
    CGFloat baseline = center.y - (ascent - descent) / 2;
    CGContextSaveGState(ctx);
    if (hasClip) CGContextClipToRect(ctx, clipRect);
    CGContextTranslateCTM(ctx, 0, squashAnchorY);
    CGContextScaleCTM(ctx, 1.0, squashY);
    CGContextTranslateCTM(ctx, 0, -squashAnchorY);
    CGContextTranslateCTM(ctx, center.x, center.y);
    CGContextScaleCTM(ctx, 1.0, stretchY);
    CGContextTranslateCTM(ctx, -center.x, -center.y);
    CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    CGContextSetTextPosition(ctx, center.x - tw / 2, baseline);
    CTLineDraw(line, ctx);
    CGContextRestoreGState(ctx);
    CFRelease(line);
}

// 画翻页时钟：面板 204x108（参考点），x 632–836，顶边 265。
// ctx 是 y 朝上的 bitmap，跟 RenderOverlay 同一套坐标，不翻转。
static void NEDrawFlipClock(CGContextRef ctx, CGFloat w, CGFloat h) {
    CGFloat sx = w / 848.0;
    CGFloat sy = h / 480.0;
    CGFloat H = h;
    CGFloat flipW = NE_FLIP_PANEL_W;
    CGFloat flipH = NE_FLIP_PANEL_H;
    CGFloat flipTopFromTop = NE_FLIP_TOP * sy;
    CGFloat flipX = (848 - 12 - flipW) * sx; // 右对齐，X=632
    CGFloat flipY = H - flipTopFromTop - flipH * sy; // y 朝上：面板底边离底
    CGFloat cw = NE_FLIP_CARD_W, ch = NE_FLIP_CARD_H;
    CGFloat gap = NE_FLIP_GAP, colonW = NE_FLIP_COLON_W;
    CGFloat total = 6 * cw + 2 * colonW + 7 * gap; // 191
    CGFloat x0 = flipX + (flipW * sx - total * sx) / 2; // 面板内居中
    CGFloat cardBottom = flipY + (flipH - 10 - ch) * sy; // 卡片顶边离面板顶 10
    CGFloat midY = cardBottom + ch * sy / 2;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    CTFontRef digitFont = CTFontCreateWithName(CFSTR("Helvetica-Bold"), 30 * sy, NULL);
    if (!digitFont) digitFont = HUDFont(30 * sy);
    CGColorRef white = CGColorCreateGenericRGB(1, 1, 1, 1);
    CGFloat x = x0;
    for (int i = 0; i < 6; i++) {
        CGRect cardRect = CGRectMake(x, cardBottom, cw * sx, ch * sy);
        CGPathRef cardPath = CGPathCreateWithRoundedRect(cardRect, 6 * sx, 6 * sy, NULL);
        CGContextSetRGBFillColor(ctx, 0.5, 0.5, 0.5, 1); // 灰卡片 RGB 128
        CGContextAddPath(ctx, cardPath);
        CGContextDrawPath(ctx, kCGPathFill);
        CGPathRelease(cardPath);
        // 中线（深灰）
        CGContextSetRGBStrokeColor(ctx, 0.27, 0.27, 0.27, 1);
        CGContextSetLineWidth(ctx, MAX(1, 2 * sy));
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, x + 2, midY);
        CGContextAddLineToPoint(ctx, x + cw * sx - 2, midY);
        CGContextStrokePath(ctx);
        // 数字
        CGPoint center = CGPointMake(x + cw * sx / 2, cardBottom + ch * sy / 2);
        int cur = gNEFlipDigits[i];
        if (cur < 0) cur = 0;
        if (gNEFlipStart[i] == 0) {
            NEDrawFlipDigit(ctx, [NSString stringWithFormat:@"%d", cur], digitFont, white,
                            center, 1.9, CGRectZero, NO, 1.0, midY);
        } else {
            double p = (now - gNEFlipStart[i]) / NE_FLIP_DURATION;
            if (p < 0) p = 0; if (p > 1) p = 1;
            int oldD = gNEFlipOld[i];
            CGRect botRect = CGRectMake(x, cardBottom, cw * sx, ch * sy / 2);
            CGRect topRect = CGRectMake(x, midY, cw * sx, ch * sy / 2);
            if (p < 0.5) {
                NEDrawFlipDigit(ctx, [NSString stringWithFormat:@"%d", oldD], digitFont, white,
                                center, 1.9, botRect, YES, 1.0, midY);
                NEDrawFlipDigit(ctx, [NSString stringWithFormat:@"%d", oldD], digitFont, white,
                                center, 1.9, topRect, YES, 1.0 - p * 2, midY);
            } else {
                NEDrawFlipDigit(ctx, [NSString stringWithFormat:@"%d", cur], digitFont, white,
                                center, 1.9, botRect, YES, 1.0, midY);
                NEDrawFlipDigit(ctx, [NSString stringWithFormat:@"%d", cur], digitFont, white,
                                center, 1.9, topRect, YES, (p - 0.5) * 2, midY);
            }
        }
        x += cw * sx + gap * sx;
        if (i == 1 || i == 3) {
            // 冒号：两个深灰圆点
            CGContextSetRGBFillColor(ctx, 0.35, 0.35, 0.35, 1);
            CGFloat dotR = MAX(1.5, 3 * sx);
            CGFloat dotCX = x + colonW * sx / 2;
            CGContextFillEllipseInRect(ctx, CGRectMake(dotCX - dotR, cardBottom + ch * sy * 0.65 - dotR, dotR * 2, dotR * 2));
            CGContextFillEllipseInRect(ctx, CGRectMake(dotCX - dotR, cardBottom + ch * sy * 0.35 - dotR, dotR * 2, dotR * 2));
            x += colonW * sx + gap * sx;
        }
    }
    CFRelease(digitFont);
    CGColorRelease(white);
}

// Open-Meteo weather_code → 天气情况中文（胶囊第一行用，不带温度数字）。
static NSString *NEWeatherText(int code) {
    switch (code) {
        case 0: return @"晴";
        case 1: case 2: return @"多云";
        case 3: return @"阴";
        case 45: case 48: return @"雾";
        case 51: case 53: case 55: return @"毛毛雨";
        case 56: case 57: return @"冻毛毛雨";
        case 61: return @"小雨";
        case 63: return @"中雨";
        case 65: return @"大雨";
        case 66: case 67: return @"冻雨";
        case 71: return @"小雪";
        case 73: return @"中雪";
        case 75: return @"大雪";
        case 77: return @"雪粒";
        case 80: case 81: return @"阵雨";
        case 82: return @"暴雨";
        case 85: case 86: return @"阵雪";
        case 95: return @"雷阵雨";
        case 96: case 99: return @"雷阵雨伴冰雹";
        default: return @"—";
    }
}

static CGImageRef RenderOverlay(size_t w, size_t h,
                                NSString *timeStr,
                                float battLevel, BOOL battCharging,
                                int wxCode, int wxTemp,
                                int netKind, NSString * __unsafe_unretained netLabel,
                                float volume, BOOL callActive,
                                int speedKmh, BOOL overspeed,
                                NEHUDSettings st) {
    if (w == 0 || h == 0) return NULL;
    (void)speedKmh; // 0.3.8：红行文案不再显示速度数字；参数保留（签名/调用方不动，速度仍进缓存 key）
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (!ctx) return NULL;

    // 注意：这里故意不翻转 context。bitmap 默认 y 朝上，文字基线
    // 按“离顶距离”换算（baseline = 高 - 离顶距离 - 上伸），画出来
    // 在仪表上就是正的——和 Ninebot Pro+ HUDOverlay.swift 同一套画法。
    // v0.1.2 在这里翻转过一次，结果字是倒的；不要再加翻转。

    CGFloat sx = (CGFloat)w / 848.0;
    CGFloat sy = (CGFloat)h / 480.0;
    CGFloat H = (CGFloat)h;

    CGFloat fontSize = MAX(12, st.fontRefPt * sy);
    CTFontRef font = HUDFont(fontSize);
    CGColorRef white = CGColorCreateGenericRGB(1, 1, 1, 1);
    CGColorRef red = CGColorCreateGenericRGB(1, 0.25, 0.25, 1);
    CGFloat iconSize = fontSize;
    CGFloat iconTextGap = 4 * sx;
    CGFloat groupGap = 14 * sx;
    CGFloat rowGap = 8 * sy;
    CGFloat padX = 12 * sx;
    CGFloat padY = 10 * sy;
    CGFloat ascent = (CGFloat)CTFontGetAscent(font);
    CGFloat descent = (CGFloat)CTFontGetDescent(font);
    CGFloat rowHeight = ascent + descent;

    BOOL lowBatt = battLevel >= 0 && battLevel < 0.2;

    // 胶囊强制 204 宽（跟翻页时钟 / P 表盘对齐）。先估第一行宽度，太宽就把字号缩小
    // （字跟着缩，图标也跟着缩），保证不溢出面板。
    if (st.showDate && timeStr.length > 0 && st.showWeather && wxCode >= 0) {
        NSString *wxText = NEWeatherText(wxCode);
        NSString *tempStr = [NSString stringWithFormat:@"%d°", wxTemp];
        CTLineRef ld = NETextLine(timeStr, font, white);
        CTLineRef lw = NETextLine(wxText, font, white);
        CTLineRef lt = NETextLine(tempStr, font, white);
        CGFloat w1 = NETextWidth(ld) + NETextWidth(lw) + NETextWidth(lt) + 2 * groupGap;
        CFRelease(ld); CFRelease(lw); CFRelease(lt);
        CGFloat avail = 204 * sx - padX * 2;
        if (w1 > avail && w1 > 0) {
            CGFloat scale = avail / w1;
            fontSize = MAX(10, fontSize * scale);
            CFRelease(font);
            font = HUDFont(fontSize);
            iconSize = fontSize;
            ascent = (CGFloat)CTFontGetAscent(font);
            descent = (CGFloat)CTFontGetDescent(font);
            rowHeight = ascent + descent;
        }
    }

    // 超速红行（0.3.8）：字比普通行大，但绝不超胶囊边框。
    //  从 1.5 倍起步，量“请勿超速行驶！”的宽度，超了就往下缩到正好塞进
    //  胶囊内宽（204 - 左右 padX）；缩完仍比普通字号大（7 个全角字，
    //  1.5 倍在中/大字号下会缩到约 25.7，小字号下直接 24，都比普通字大）。
    //  行高跟着抬：超速行字更大，行高不够会上下裁字。
    CTFontRef overFont = NULL;
    CGFloat overAscent = 0, overDescent = 0;
    if (st.speedAlert && overspeed) {
        CGFloat overSize = fontSize * 1.5;
        CTFontRef f = HUDFont(overSize);
        CTLineRef l = NETextLine(@"请勿超速行驶！", f, red);
        CGFloat w = NETextWidth(l);
        CGFloat avail = 204 * sx - padX * 2;
        if (w > avail && w > 0) {
            CGFloat scale = avail / w;
            CGFloat newSize = overSize * scale;
            if (newSize < fontSize) newSize = fontSize; // 兜底：绝不比普通字小
            CFRelease(l); CFRelease(f);
            f = HUDFont(newSize);
            l = NETextLine(@"请勿超速行驶！", f, red);
        }
        overFont = f;
        overAscent = (CGFloat)CTFontGetAscent(f);
        overDescent = (CGFloat)CTFontGetDescent(f);
        CFRelease(l);
        if (overAscent + overDescent > rowHeight) rowHeight = overAscent + overDescent;
    }

    // ---- 组行 ----
    NESeg rows[NE_MAX_ROWS][NE_MAX_SEGS];
    int rowCounts[NE_MAX_ROWS] = { 0, 0, 0 };
    memset(rows, 0, sizeof(rows));

    // 上行：日期（无时间，时间只在翻页时钟里）+ 天气情况 + 温度
    if (st.showDate && timeStr.length > 0) {
        NESeg *s = &rows[0][rowCounts[0]++];
        s->kind = 0; s->text = timeStr; s->color = white;
    }
    if (st.showWeather && wxCode >= 0) {
        NESeg *s = &rows[0][rowCounts[0]++];
        s->kind = 0; s->text = NEWeatherText(wxCode); s->color = white;
        s = &rows[0][rowCounts[0]++];
        s->kind = 0; s->text = [NSString stringWithFormat:@"%d°", wxTemp]; s->color = white;
    }
    // 下行：联网方式、音量、电池图标 + 百分比（天气已移到上行，不再画天气图标 + 温度）
    if (st.showSignal && netKind == 1) {
        NESeg *s = &rows[1][rowCounts[1]++];
        s->kind = 1; s->icon = 1;
    } else if (st.showSignal && netKind == 2 && netLabel.length > 0) {
        NESeg *s = &rows[1][rowCounts[1]++];
        s->kind = 0; s->text = netLabel; s->color = white;
    }
    if (st.showVolume && volume >= 0) {
        NESeg *s = &rows[1][rowCounts[1]++];
        s->kind = 1; s->icon = 3;
        s = &rows[1][rowCounts[1]++];
        s->kind = 0; s->text = [NSString stringWithFormat:@"%d%%", (int)(volume * 100)]; s->color = white;
    }
    if (st.showBattery) {
        NESeg *s = &rows[1][rowCounts[1]++];
        s->kind = 2; s->battLevel = battLevel; s->battCharging = battCharging; s->battLow = lowBatt;
        s = &rows[1][rowCounts[1]++];
        s->kind = 0;
        s->text = battLevel < 0 ? @"--%" : [NSString stringWithFormat:@"%d%%", (int)(battLevel * 100)];
        s->color = lowBatt ? red : white;
    }
    // 第三行：超速（只在超速时画，红色文字，不用图标；0.3.8：文案改成
    //  “请勿超速行驶！”，不带速度数字；字号见上面的 overFont）
    if (st.speedAlert && overspeed) {
        NESeg *s = &rows[2][rowCounts[2]++];
        s->kind = 0;
        s->text = @"请勿超速行驶！";
        s->color = red;
    }

    // ---- 量每行宽度 ----
    CGFloat rowWidths[NE_MAX_ROWS] = { 0, 0, 0 };
    int nonEmptyRows = 0;
    int rowOrder[NE_MAX_ROWS];
    for (int r = 0; r < NE_MAX_ROWS; r++) {
        CGFloat total = 0;
        for (int i = 0; i < rowCounts[r]; i++) {
            NESeg *s = &rows[r][i];
            if (i > 0) {
                total += (NEIsIconSeg(&rows[r][i - 1]) && !NEIsIconSeg(s)) ? iconTextGap : groupGap;
            }
            if (s->kind == 0) {
                // 超速行（rows[2]）用自己的大字号，其余行用普通字号
                CTFontRef segFont = (r == 2 && overFont) ? overFont : font;
                s->line = NETextLine(s->text, segFont, s->color);
                s->w = NETextWidth(s->line);
            } else {
                s->w = iconSize;
            }
            total += s->w;
        }
        rowWidths[r] = total;
        if (rowCounts[r] > 0) rowOrder[nonEmptyRows++] = r;
    }

    CGImageRef out = NULL;
    if (nonEmptyRows > 0 || callActive) {
        CGFloat contentW = 0;
        for (int i = 0; i < nonEmptyRows; i++)
            if (rowWidths[rowOrder[i]] > contentW) contentW = rowWidths[rowOrder[i]];
        CGFloat pillW = 204 * sx; // 0.3.6：强制跟翻页时钟 / P 表盘同宽 204，严格对齐
        (void)contentW; // 内容宽度已由前面的缩字逻辑保证 fit；pillW 强制 204，不再由内容决定
        CGFloat pillH = padY * 2 + rowHeight * nonEmptyRows + rowGap * MAX(0, nonEmptyRows - 1);

        // 胶囊锚点（y 朝上坐标，pillY 是底边离底的距离）
        CGFloat pillX = 0, pillY = 0;
        switch (st.position) {
            case 1: // 左下
                pillX = 12 * sx; pillY = 12 * sy; break;
            case 2: // 左上
                pillX = 12 * sx; pillY = H - 12 * sy - pillH; break;
            case 3: // 右上
                pillX = (848 - 12) * sx - pillW; pillY = H - 12 * sy - pillH; break;
            default: // 右下
                pillX = (848 - 12) * sx - pillW; pillY = 12 * sy; break;
        }

        if (nonEmptyRows > 0) {
            // 胶囊底板：黑 45% + 白 35% 边，圆角 12
            CGPathRef panel = CGPathCreateWithRoundedRect(
                CGRectMake(pillX, pillY, pillW, pillH), 12 * sx, 12 * sy, NULL);
            CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.45);
            CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.35);
            CGContextSetLineWidth(ctx, MAX(1, 1 * sx));
            CGContextAddPath(ctx, panel);
            CGContextDrawPath(ctx, kCGPathFillStroke);
            CGPathRelease(panel);

            CGContextSaveGState(ctx);
            CGColorRef shadow = CGColorCreateGenericRGB(0, 0, 0, 0.85);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0, -2), 3, shadow);
            CGColorRelease(shadow);

            // 画各行（左对齐，图标与文字垂直居中对齐）
            CGFloat pillTopFromTop = H - (pillY + pillH);
            for (int ri = 0; ri < nonEmptyRows; ri++) {
                int r = rowOrder[ri];
                CGFloat rowTop = pillTopFromTop + padY + ri * (rowHeight + rowGap);
                // 超速行用自己的上伸/下伸算基线，字在行里垂直居中，不裁字
                CGFloat rowAscent = (r == 2 && overFont) ? overAscent : ascent;
                CGFloat rowDescent = (r == 2 && overFont) ? overDescent : descent;
                CGFloat baseline = H - rowTop - rowAscent;
                CGFloat textCenterY = baseline + (rowAscent - rowDescent) / 2;
                CGFloat x = pillX + padX;
                for (int i = 0; i < rowCounts[r]; i++) {
                    NESeg *s = &rows[r][i];
                    if (s->kind == 0) {
                        CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
                        CGContextSetTextPosition(ctx, x, baseline);
                        CTLineDraw(s->line, ctx);
                    } else if (s->kind == 1) {
                        CGRect rect = CGRectMake(x, textCenterY - iconSize / 2,
                                                 iconSize, iconSize);
                        CGContextSetFillColorWithColor(ctx, white);
                        CGContextSetStrokeColorWithColor(ctx, white);
                        CGContextSetLineWidth(ctx, MAX(1, iconSize * 0.07));
                        CGContextSetLineCap(ctx, kCGLineCapRound);
                        switch (s->icon) {
                            case 0: NEDrawClock(ctx, rect); break;
                            case 1: NEDrawWifi(ctx, rect); break;
                            case 2: NEDrawWeather(ctx, s->wxCode, rect); break;
                            case 3: NEDrawSpeaker(ctx, rect); break;
                            default: break;
                        }
                    } else if (s->kind == 2) {
                        CGRect rect = CGRectMake(x, textCenterY - iconSize / 2,
                                                 iconSize, iconSize);
                        NEDrawBattery(ctx, s->battLevel, s->battCharging, s->battLow, rect);
                    }
                    x += s->w;
                    if (i + 1 < rowCounts[r]) {
                        x += (NEIsIconSeg(s) && !NEIsIconSeg(&rows[r][i + 1])) ? iconTextGap : groupGap;
                    }
                }
            }
            CGContextRestoreGState(ctx); // 关掉文字阴影，来电条不用
        }

        // 来电：左下角红色圆角条（不动）
        if (callActive) {
            CTFontRef cfont = font;
            CTLineRef line = NETextLine(@"来电", cfont, white);
            CGFloat tw = NETextWidth(line);
            CGFloat pillW2 = tw + 24 * sx;
            CGFloat pillH2 = 34 * sy;
            CGRect pillRect = CGRectMake(16 * sx, 16 * sy, pillW2, pillH2);
            CGPathRef pill = CGPathCreateWithRoundedRect(pillRect, 8 * sx, 8 * sy, NULL);
            CGContextSetRGBFillColor(ctx, 0.9, 0.1, 0.1, 0.55);
            CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.35);
            CGContextSetLineWidth(ctx, MAX(1, 1 * sx));
            CGContextAddPath(ctx, pill);
            CGContextDrawPath(ctx, kCGPathFillStroke);
            CGPathRelease(pill);
            CGFloat callBaseline = pillRect.origin.y + (pillH2 - ascent - descent) / 2 + descent;
            CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
            CGContextSetTextPosition(ctx, pillRect.origin.x + 12 * sx, callBaseline);
            CTLineDraw(line, ctx);
            CFRelease(line);
        }
    }

    // 释放本行建的 CTLine
    for (int r = 0; r < NE_MAX_ROWS; r++)
        for (int i = 0; i < rowCounts[r]; i++)
            if (rows[r][i].line) CFRelease(rows[r][i].line);

    // 翻页时钟（v0.3.6，替代老虎机）：跟 HUD 一起出现/消失；就算胶囊各行全关也照画
    if (st.showSlot) {
        NEDrawFlipClock(ctx, (CGFloat)w, (CGFloat)h);
    }

    out = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    CFRelease(font);
    if (overFont) CFRelease(overFont);
    CGColorRelease(white);
    CGColorRelease(red);
    return out;
}

// 叠加层缓存：数据没变且 250ms 内，直接复用。
// 注意：缓存的是叠加层，不是整帧——App 自己的画面每帧都在变，必须每帧重新合成。
static CGImageRef OverlayForSize(size_t w, size_t h) {
    [gLock lock];
    static CGImageRef cache = NULL;
    static size_t cw = 0, ch = 0;
    static NSString *cacheKey = nil;
    static CFAbsoluteTime at = 0;

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    // 翻页时钟在翻时 150ms 档重画（翻页动画才跟得上），静止时 250ms。
    // gNEFlipMoving 是上次 tick 的状态（tick 在下面过节流时才跑一次）。
    double throttle = gNEFlipMoving ? 0.15 : 0.25;
    if (cache && cw == w && ch == h && (now - at) <= throttle) {
        CGImageRef out = CGImageRetain(cache);
        [gLock unlock];
        return out;
    }

    NSString *timeStr = HUDTimeString();
    UIDevice *dev = [UIDevice currentDevice];
    float battLevel = dev.batteryLevel;
    BOOL battCharging = (dev.batteryState == UIDeviceBatteryStateCharging ||
                         dev.batteryState == UIDeviceBatteryStateFull);
    [gDataLock lock];
    int wxCode = gWeatherCode, wxTemp = gWeatherTemp;
    int netKind = gNetKind;
    NSString *netLabel = gNetLabel;
    float volume = gVolume;
    BOOL callActive = gCallActive;
    double speedKmhD = gSpeedKmh;
    CFAbsoluteTime speedAt = gSpeedAt;
    [gDataLock unlock];

    // 超速行：5 秒内的速度才算新鲜；开关关着或速度没超限速就不画
    BOOL speedFresh = (now - speedAt) <= 5.0;
    BOOL overspeed = speedFresh && NEHUDSpeedAlert() && speedKmhD > NEHUDSpeedLimit();
    int speedKmh = (int)speedKmhD;

    NEHUDSettings st;
    st.showDate = NEHUDShowDate(); st.showWeather = NEHUDShowWeather();
    st.showSignal = NEHUDShowSignal(); st.showBattery = NEHUDShowBattery();
    st.showVolume = NEHUDShowVolume();
    st.showSlot = NEHUDShowSlot();
    st.speedAlert = NEHUDSpeedAlert();
    st.position = NEHUDPosition(); st.fontRefPt = NEHUDFontRefPt();

    // 翻页时钟状态机（v0.3.6）：秒变了就翻页；翻的时候缓存 key 里加一个
    // 150ms 档位，逼重画跟上动画；静止时每秒一个档位（秒针要走）。
    BOOL flipMoving = NEFlipTick(now, st.showSlot);
    long flipBucket = flipMoving ? (long)(now / 0.15) : (long)(now / 1.0);

    NSString *key = [NSString stringWithFormat:@"%@|%.2f|%d|%d|%d|%d|%@|%.2f|%d|%d%d%d%d%d|%ld|%.0f|%d|%d|%ld",
                     timeStr, battLevel, battCharging, wxCode, wxTemp, netKind,
                     netLabel ?: @"", volume, callActive,
                     st.showDate, st.showWeather, st.showSignal,
                     st.showBattery, st.showVolume,
                     (long)st.position, st.fontRefPt, speedKmh, overspeed, flipBucket];
    if (!cache || cw != w || ch != h || ![key isEqualToString:cacheKey]) {
        if (cache) { CGImageRelease(cache); cache = NULL; }
        cache = RenderOverlay(w, h, timeStr, battLevel, battCharging,
                              wxCode, wxTemp, netKind, netLabel,
                              volume, callActive,
                              speedKmh, overspeed, st);
        cacheKey = [key copy];
        cw = w; ch = h;
    }
    at = now;
    CGImageRef out = cache ? CGImageRetain(cache) : NULL;
    [gLock unlock];
    return out;
}

// 原画面 + 叠加层合成一张新图。全程不翻转：
// 原图直接画（v0.1.1/0.1.2 已证明这样导航是正的），叠加层也是
// 直接画——RenderOverlay 本版已不再翻转，出来的就是正向图。
// v0.1.0 在这里全局翻转，结果导航是反的；v0.1.1 只翻叠加层，
// 结果 HUD 被镜像到上方的仪表表盘遮挡区里看不见；v0.1.2 两边
// 都不翻但 RenderOverlay 内部翻了，结果 HUD 字是倒的。
// 本版：两边都不翻，RenderOverlay 内部也不翻，导航和 HUD 都正。
static CGImageRef CompositeWithOverlay(CGImageRef original) {
    size_t w = CGImageGetWidth(original), h = CGImageGetHeight(original);
    if (w == 0 || h == 0) return NULL;
    CGImageRef overlay = OverlayForSize(w, h);
    if (!overlay) return NULL;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (!ctx) { CGImageRelease(overlay); return NULL; }

    // 原图直接画，不翻转：行顺序原样通过，钩子对原图透明。
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), original);
    // 叠加层直接画，不翻转：RenderOverlay 本版已是正向图。
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), overlay);
    CGImageRelease(overlay);

    CGImageRef out = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return out;
}

// 可选：把真正要发给车机的画面导出（POFrameDump=YES 时前 5 帧）
static void MaybeDump(CGImageRef img, int idx) {
    if (gDumped >= 5) return;
    id flag = [[NSUserDefaults standardUserDefaults] objectForKey:@"POFrameDump"];
    if (!flag || ![flag boolValue]) return;
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (!docs.count) return;
    NSString *dir = [docs[0] stringByAppendingPathComponent:@"POFrames"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                             withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [dir stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"cast_%03d.png", idx]];
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL(
        (__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.png"), 1, NULL);
    if (!dst) return;
    CGImageDestinationAddImage(dst, img, NULL);
    CGImageDestinationFinalize(dst);
    CFRelease(dst);
    gDumped++;
    os_log(gLog, "[CAST] 已导出 %{public}s", path.UTF8String);
}

static void NoteFrame(size_t w, size_t h) {
    gFrames++;
    if (gFrames == 1 || gFrames % 100 == 0) {
        os_log(gLog, "[CAST] frame #%d size=%zux%zu（投屏正在推流，HUD 已叠加）",
               gFrames, w, h);
    }
    // 天气过期了就触发一次后台刷新（不阻塞）
    RefreshWeatherIfNeeded();
}

// ---------------- HUD 设置界面 ----------------
// 九号 App 的“我的”页右上角会出现一个“Ninebot pro+”按钮。
// 找页面的办法：每 3 秒看一次最上层 ViewController，只在“我的”页
// 显示（NEIsMineRootPage：当前 tab 是“我的”且是根页面；没有 tab
// bar 时退回类名含 mine）。没匹配到就不出现，设置仍可用 defaults
// 命令改。不硬编任何 App 的类名，所以 6.10.12 改了类名也不会崩，
// 只是不出按钮。

static const char NEHUDButtonKey = 0;
static const char NEBeautyGroupKey = 0; // 设置页：“美化娱乐”折叠容器
static const char NENavGroupKey = 0;    // 设置页：“导航增强”折叠容器
static const char NESpeedLimitValueKey = 0;

@interface NEHUDSettingsVC : UIViewController
    <PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end

@interface NEHUDButtonHandler : NSObject
+ (instancetype)shared;
- (void)openSettings:(UIButton *)sender;
@end

// 取 key window。UIApplication.windows 在 iOS 15 已废弃（-Werror 下会编译失败），改走 connectedScenes → UIWindowScene.windows。
static UIWindow *NEKeyWindow(void) {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
        }
        if (keyWindow) break;
    }
    if (!keyWindow) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            keyWindow = ((UIWindowScene *)scene).windows.firstObject;
            if (keyWindow) break;
        }
    }
    return keyWindow;
}

static UIViewController *NETopViewController(void) {
    UIWindow *keyWindow = NEKeyWindow();
    UIViewController *vc = keyWindow.rootViewController;
    while (vc) {
        if (vc.presentedViewController) { vc = vc.presentedViewController; continue; }
        if ([vc isKindOfClass:[UITabBarController class]]) {
            vc = ((UITabBarController *)vc).selectedViewController; continue;
        }
        if ([vc isKindOfClass:[UINavigationController class]]) {
            vc = ((UINavigationController *)vc).topViewController; continue;
        }
        break;
    }
    return vc;
}

@implementation NEHUDButtonHandler
+ (instancetype)shared {
    static NEHUDButtonHandler *s = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [NEHUDButtonHandler new]; });
    return s;
}
- (void)openSettings:(UIButton *)sender {
    UIViewController *top = NETopViewController();
    if (!top) return;
    NEHUDSettingsVC *vc = [NEHUDSettingsVC new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [top presentViewController:nav animated:YES completion:nil];
}
@end

// 是不是“我的”页的根页面：当前选中的 tab 是“我的”tab，且当前页是该 tab 的根页面。
// “我的”tab 的判定：tab 标题是“我的”，或是最后一个 tab（中文 App 里“我的”通常在最后）。
// 根页面的判定：tab 里是导航栈时，当前页得是栈底；不是导航栈时，当前页得是 tab 本身。
// 没有 tab bar 时退回类名判断（类名含 mine 才算）。
static BOOL NEIsMineRootPage(UIViewController *topVC) {
    UIWindow *keyWindow = NEKeyWindow();
    UIViewController *root = keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    if (![root isKindOfClass:[UITabBarController class]]) {
        return [[NSStringFromClass([topVC class]) lowercaseString] containsString:@"mine"];
    }
    UITabBarController *tab = (UITabBarController *)root;
    UIViewController *sel = tab.selectedViewController;
    BOOL isMineTab = [sel.tabBarItem.title isEqualToString:@"我的"] ||
                     tab.selectedIndex == tab.viewControllers.count - 1;
    if (!isMineTab) {
        // 诊断：类名含 mine 但不在“我的”tab 上（旧规则会放行）——只在类名变时记一次，
        // 万一按钮不出来了，拿这条日志就知道 tab 结构长什么样。
        static NSString *sLastDiag = nil;
        NSString *cls = NSStringFromClass([topVC class]);
        if ([[cls lowercaseString] containsString:@"mine"] && ![cls isEqualToString:sLastDiag]) {
            sLastDiag = cls;
            os_log(gLog, "[HUD] 类名含 mine 但不在我的 tab（tab %ld/%ld，标题 %{public}@，当前页 %{public}@），不放按钮",
                   (long)tab.selectedIndex, (long)tab.viewControllers.count,
                   sel.tabBarItem.title ?: @"(无)", cls);
        }
        return NO;
    }
    if ([sel isKindOfClass:[UINavigationController class]]) {
        return topVC == ((UINavigationController *)sel).viewControllers.firstObject;
    }
    return topVC == sel;
}

static void NECheckSettingsButton(void) {
    // 只在主线程调（定时器就是主队列）。
    UIViewController *vc = NETopViewController();
    if (!vc || !vc.view) return;
    NSString *lower = [NSStringFromClass([vc class]) lowercaseString];
    // 排除我们自己的设置页：NEHUDSettingsVC 的类名里也有 setting，
    // 不排除的话按钮会出现在自己的设置页右上角（还挡住第一个开关）。
    if ([lower containsString:@"nehud"]) return;
    // 只在“我的”页显示（根页面，不是从“我的”点进去的子页面）。
    if (!NEIsMineRootPage(vc)) return;
    if (objc_getAssociatedObject(vc, &NEHUDButtonKey)) return;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    // contentEdgeInsets 在 iOS 15 已废弃（-Werror 下会编译失败），改用 UIButtonConfiguration（iOS 15+，本工程最低 16.0）。
    UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
    cfg.title = @"Ninebot pro+";
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(6, 10, 6, 10);
    cfg.background.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.12];
    cfg.background.cornerRadius = 8;
    cfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> * _Nonnull(NSDictionary<NSAttributedStringKey, id> * _Nonnull incoming) {
        NSMutableDictionary *out = [incoming mutableCopy];
        out[NSFontAttributeName] = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        return out;
    };
    btn.configuration = cfg;
    [btn addTarget:[NEHUDButtonHandler shared] action:@selector(openSettings:)
        forControlEvents:UIControlEventTouchUpInside];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:btn];
    UILayoutGuide *guide = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [btn.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-12],
        // 我的页右上角有 App 自己的齿轮按钮（约在安全区顶部 +8~+36），
        // 按钮放 +8 会正好盖住它；下移到 +56，落在齿轮下方空白处。
        [btn.topAnchor constraintEqualToAnchor:guide.topAnchor constant:56]
    ]];
    objc_setAssociatedObject(vc, &NEHUDButtonKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    os_log(gLog, "[HUD] 已在 %{public}s 上加 Ninebot pro+ 按钮", NSStringFromClass([vc class]).UTF8String);
}

@implementation NEHUDSettingsVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"Ninebot pro+";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStyleDone
                                         target:self action:@selector(closeTapped)];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16]
    ]];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor]
    ]];

    UILabel *hint = [UILabel new];
    hint.text = @"改完立即生效，下次投屏帧就用新设置。";
    hint.font = [UIFont systemFontOfSize:13];
    hint.textColor = [UIColor secondaryLabelColor];
    hint.numberOfLines = 0;
    [stack addArrangedSubview:hint];

    // 点空白处收起输入框键盘（不拦截其他控件的点击）
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];

    // ---- 美化娱乐组（默认折叠，只改显示不改真数据）----
    UIStackView *beautyStack = [UIStackView new];
    beautyStack.axis = UILayoutConstraintAxisVertical;
    beautyStack.spacing = 18;
    beautyStack.hidden = YES;
    objc_setAssociatedObject(self, &NEBeautyGroupKey, beautyStack,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [beautyStack addArrangedSubview:[self switchRow:@"服务有效期 9999" key:@"NEValidity9999" on:NEValidity9999()]];
    [beautyStack addArrangedSubview:[self sectionLabel:@"主页车辆图"]];
    [beautyStack addArrangedSubview:[self imagePickRow:@"更换车辆图" kind:0]];
    [beautyStack addArrangedSubview:[self imageClearRow:@"恢复原图" kind:0]];
    [beautyStack addArrangedSubview:[self sectionLabel:@"主页背景图"]];
    [beautyStack addArrangedSubview:[self imagePickRow:@"更换背景图" kind:1]];
    [beautyStack addArrangedSubview:[self imageClearRow:@"恢复原背景" kind:1]];
    UILabel *imgNote = [UILabel new];
    imgNote.text = @"换图只换“设备”主页上的显示，不改车辆数据。选完回设备页就能看到；如果还是原图，切换一下 tab 或重启九号 App（图片可能已被缓存）。";
    imgNote.font = [UIFont systemFontOfSize:13];
    imgNote.textColor = [UIColor secondaryLabelColor];
    imgNote.numberOfLines = 0;
    [beautyStack addArrangedSubview:imgNote];
    // v0.3.9 追加：五个自定义显示项（开关 + 输入框，自己填想显示的值）
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [beautyStack addArrangedSubview:[self customDisplayRow:@"N币余额" toggleKey:@"NENCoins" valueKey:@"NENCoinsValue" on:NEBoolDefault(@"NENCoins") value:[defs stringForKey:@"NENCoinsValue"] placeholder:@"如 99999"]];
    [beautyStack addArrangedSubview:[self customDisplayRow:@"总里程" toggleKey:@"NEMileage" valueKey:@"NEMileageValue" on:NEBoolDefault(@"NEMileage") value:[defs stringForKey:@"NEMileageValue"] placeholder:@"如 99999.9 km"]];
    [beautyStack addArrangedSubview:[self customDisplayRow:@"等级" toggleKey:@"NELevel" valueKey:@"NELevelValue" on:NEBoolDefault(@"NELevel") value:[defs stringForKey:@"NELevelValue"] placeholder:@"如 Lv.99"]];
    [beautyStack addArrangedSubview:[self customDisplayRow:@"称号" toggleKey:@"NETitle" valueKey:@"NETitleValue" on:NEBoolDefault(@"NETitle") value:[defs stringForKey:@"NETitleValue"] placeholder:@"如 车神"]];
    [beautyStack addArrangedSubview:[self customDisplayRow:@"连续签到天数" toggleKey:@"NESignDays" valueKey:@"NESignDaysValue" on:NEBoolDefault(@"NESignDays") value:[defs stringForKey:@"NESignDaysValue"] placeholder:@"如 365"]];
    [stack addArrangedSubview:[self groupHeader:@"美化娱乐" tag:0]];
    [stack addArrangedSubview:beautyStack];

    // ---- 导航增强组（默认折叠，以前的 HUD/翻页时钟/超速等功能）----
    UIStackView *navStack = [UIStackView new];
    navStack.axis = UILayoutConstraintAxisVertical;
    navStack.spacing = 18;
    navStack.hidden = YES;
    objc_setAssociatedObject(self, &NENavGroupKey, navStack,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [navStack addArrangedSubview:[self switchRow:@"日期" key:@"NEHUDShowDate" on:NEHUDShowDate()]];
    [navStack addArrangedSubview:[self switchRow:@"天气温度" key:@"NEHUDShowWeather" on:NEHUDShowWeather()]];
    [navStack addArrangedSubview:[self switchRow:@"信号（WiFi/5G）" key:@"NEHUDShowSignal" on:NEHUDShowSignal()]];
    [navStack addArrangedSubview:[self switchRow:@"电量" key:@"NEHUDShowBattery" on:NEHUDShowBattery()]];
    [navStack addArrangedSubview:[self switchRow:@"音量" key:@"NEHUDShowVolume" on:NEHUDShowVolume()]];
    [navStack addArrangedSubview:[self switchRow:@"翻页时钟" key:@"NEHUDShowSlot" on:NEHUDShowSlot()]];

    [navStack addArrangedSubview:[self sectionLabel:@"位置"]];
    UISegmentedControl *pos = [[UISegmentedControl alloc]
        initWithItems:@[ @"右下", @"左下", @"左上", @"右上" ]];
    pos.selectedSegmentIndex = NEHUDPosition();
    [pos addTarget:self action:@selector(positionChanged:)
        forControlEvents:UIControlEventValueChanged];
    [navStack addArrangedSubview:pos];

    [navStack addArrangedSubview:[self sectionLabel:@"字号"]];
    UISegmentedControl *fs = [[UISegmentedControl alloc]
        initWithItems:@[ @"小", @"中", @"大" ]];
    CGFloat refPt = NEHUDFontRefPt();
    fs.selectedSegmentIndex = (refPt == 16) ? 0 : ((refPt == 24) ? 2 : 1);
    [fs addTarget:self action:@selector(fontChanged:)
        forControlEvents:UIControlEventValueChanged];
    [navStack addArrangedSubview:fs];

    [navStack addArrangedSubview:[self switchRow:@"超速提醒" key:@"NEHUDSpeedAlert" on:NEHUDSpeedAlert()]];
    [navStack addArrangedSubview:[self speedLimitRow]];

    UILabel *note = [UILabel new];
    note.text = @"提示：仪表右上角是车子自己的表盘区，HUD 放右上会被盖住一部分，一般用右下。";
    note.font = [UIFont systemFontOfSize:13];
    note.textColor = [UIColor secondaryLabelColor];
    note.numberOfLines = 0;
    [navStack addArrangedSubview:note];
    [stack addArrangedSubview:[self groupHeader:@"导航增强" tag:1]];
    [stack addArrangedSubview:navStack];
}

- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont boldSystemFontOfSize:15];
    return l;
}

// v0.3.9 追加：折叠分组头（标题 + ▸/▾ 箭头），点一下展开/收起。
// tag：0 美化娱乐，1 导航增强。折叠状态不持久化，每次进设置页默认都折叠。
- (UIButton *)groupHeader:(NSString *)title tag:(NSInteger)tag {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:[NSString stringWithFormat:@"▸ %@", title] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    btn.tag = tag;
    [btn addTarget:self action:@selector(groupHeaderTapped:)
        forControlEvents:UIControlEventTouchUpInside];
    [btn.heightAnchor constraintEqualToConstant:32].active = YES;
    return btn;
}

- (void)groupHeaderTapped:(UIButton *)sender {
    const char *key = (sender.tag == 0) ? &NEBeautyGroupKey : &NENavGroupKey;
    UIStackView *container = objc_getAssociatedObject(self, key);
    if (!container) return;
    container.hidden = !container.hidden;
    NSString *title = (sender.tag == 0) ? @"美化娱乐" : @"导航增强";
    [sender setTitle:[NSString stringWithFormat:@"%@ %@", container.hidden ? @"▸" : @"▾", title]
            forState:UIControlStateNormal];
}

// v0.3.9 追加：自定义显示项行——左边标题 + 中间输入框 + 右边开关。
// 输入框失焦即存 NSUserDefaults；开关走通用的 switchChanged:。
- (UIView *)customDisplayRow:(NSString *)title toggleKey:(NSString *)toggleKey
                    valueKey:(NSString *)valueKey on:(BOOL)on value:(NSString *)value
                 placeholder:(NSString *)placeholder {
    UIView *row = [UIView new];
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = [UIFont systemFontOfSize:16];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UITextField *field = [UITextField new];
    field.text = value;
    field.placeholder = placeholder;
    field.font = [UIFont systemFontOfSize:15];
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.accessibilityIdentifier = valueKey;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field addTarget:self action:@selector(customValueChanged:)
        forControlEvents:UIControlEventEditingDidEnd];
    UISwitch *sw = [UISwitch new];
    sw.on = on;
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    sw.accessibilityIdentifier = toggleKey;
    [sw addTarget:self action:@selector(switchChanged:)
        forControlEvents:UIControlEventValueChanged];
    [row addSubview:label];
    [row addSubview:field];
    [row addSubview:sw];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.widthAnchor constraintEqualToConstant:116],
        [sw.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [sw.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [field.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:8],
        [field.trailingAnchor constraintEqualToAnchor:sw.leadingAnchor constant:-8],
        [field.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintEqualToConstant:32]
    ]];
    return row;
}

- (void)customValueChanged:(UITextField *)field {
    NSString *key = field.accessibilityIdentifier;
    if (key.length == 0) return;
    NSString *v = field.text ?: @"";
    if (v.length > 0)
        [[NSUserDefaults standardUserDefaults] setObject:v forKey:key];
    else
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    // 空值时开关开也不换（避免显示空白），所以值改完同步一次缓存
    NESyncCustomDisplayCache();
    NEInstallLabelHookIfNeeded();
    NEForceRefreshLabels(); // v0.3.9 修复：值改了，已显示的 label 不会自动重设，强制刷新立刻生效
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (UIView *)switchRow:(NSString *)title key:(NSString *)key on:(BOOL)on {
    UIView *row = [UIView new];
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = [UIFont systemFontOfSize:16];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UISwitch *sw = [UISwitch new];
    sw.on = on;
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    // 把 key 存在 switch 的 accessibilityIdentifier 里，回调时读出来
    sw.accessibilityIdentifier = key;
    [sw addTarget:self action:@selector(switchChanged:)
        forControlEvents:UIControlEventValueChanged];
    [row addSubview:label];
    [row addSubview:sw];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [sw.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [sw.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintEqualToConstant:32]
    ]];
    return row;
}

- (void)switchChanged:(UISwitch *)sw {
    NSString *key = sw.accessibilityIdentifier;
    if (key.length > 0)
        [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:key];
    // 超速提醒或翻页时钟开关变化时，立刻切换定位模式（连续定位开/关）
    if ([key isEqualToString:@"NEHUDSpeedAlert"] ||
        [key isEqualToString:@"NEHUDShowSlot"]) NEApplySpeedLocationMode();
    // v0.3.9：有效期 9999 开关——同步缓存并按需装钩子（关掉后钩子留着但直接走原实现）
    if ([key isEqualToString:@"NEValidity9999"]) {
        gValidity9999 = sw.isOn;
        if (sw.isOn) NEInstallLabelHookIfNeeded();
        NEForceRefreshLabels(); // v0.3.9 修复：开关变了，已显示的 label 不会自动重设，强制刷新
    }
    // v0.3.9 追加：五个自定义显示项开关——同步缓存并按需装钩子
    if ([key isEqualToString:@"NENCoins"] || [key isEqualToString:@"NEMileage"] ||
        [key isEqualToString:@"NELevel"] || [key isEqualToString:@"NETitle"] ||
        [key isEqualToString:@"NESignDays"]) {
        NESyncCustomDisplayCache();
        if (sw.isOn) NEInstallLabelHookIfNeeded();
        NEForceRefreshLabels(); // v0.3.9 修复：同上
    }
}

// 限速行：左边“限速”+ 中间值 + 右边步进器（30–120，每 5 一档）
- (UIView *)speedLimitRow {
    UIView *row = [UIView new];
    UILabel *label = [UILabel new];
    label.text = @"限速";
    label.font = [UIFont systemFontOfSize:16];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *value = [UILabel new];
    value.text = [NSString stringWithFormat:@"%d km/h", (int)NEHUDSpeedLimit()];
    value.font = [UIFont systemFontOfSize:16];
    value.translatesAutoresizingMaskIntoConstraints = NO;
    UIStepper *step = [UIStepper new];
    step.minimumValue = 30;
    step.maximumValue = 120;
    step.stepValue = 5;
    step.value = NEHUDSpeedLimit();
    step.translatesAutoresizingMaskIntoConstraints = NO;
    // 值 label 挂在 stepper 上，回调时直接改，不用再找
    objc_setAssociatedObject(step, &NESpeedLimitValueKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [step addTarget:self action:@selector(limitChanged:)
        forControlEvents:UIControlEventValueChanged];
    [row addSubview:label];
    [row addSubview:value];
    [row addSubview:step];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [step.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [step.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [value.trailingAnchor constraintEqualToAnchor:step.leadingAnchor constant:-12],
        [value.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintEqualToConstant:32]
    ]];
    return row;
}

- (void)limitChanged:(UIStepper *)step {
    NSInteger v = (NSInteger)step.value;
    [[NSUserDefaults standardUserDefaults] setInteger:v forKey:@"NEHUDSpeedLimit"];
    UILabel *value = objc_getAssociatedObject(step, &NESpeedLimitValueKey);
    if (value) value.text = [NSString stringWithFormat:@"%ld km/h", (long)v];
}

- (void)positionChanged:(UISegmentedControl *)seg {
    [[NSUserDefaults standardUserDefaults] setInteger:seg.selectedSegmentIndex forKey:@"NEHUDPosition"];
}

- (void)fontChanged:(UISegmentedControl *)seg {
    [[NSUserDefaults standardUserDefaults] setInteger:seg.selectedSegmentIndex forKey:@"NEHUDFontSize"];
}

// ---------------- v0.3.9：主页车辆图 / 背景图自定义 ----------------
// kind：0 车辆图，1 背景图。选图用 PHPicker（iOS 14+，不用相册权限）；
// 拿不到 PHPicker 类时回退 UIImagePickerController（走系统常规相册授权）。
- (UIView *)imagePickRow:(NSString *)title kind:(NSInteger)kind {
    UIView *row = [UIView new];
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = [UIFont systemFontOfSize:16];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *status = [UILabel new];
    status.font = [UIFont systemFontOfSize:13];
    status.textColor = [UIColor secondaryLabelColor];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:@"选择" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16];
    btn.tag = kind;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:self action:@selector(pickImageTapped:)
        forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:label];
    [row addSubview:status];
    [row addSubview:btn];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [btn.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [btn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [status.trailingAnchor constraintEqualToAnchor:btn.leadingAnchor constant:-12],
        [status.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintEqualToConstant:32]
    ]];
    const char *key = (kind == 0) ? &NEVehicleStatusKey : &NEBackgroundStatusKey;
    objc_setAssociatedObject(self, key, status, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self refreshImageStatus];
    return row;
}

- (UIView *)imageClearRow:(NSString *)title kind:(NSInteger)kind {
    UIView *row = [UIView new];
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = [UIFont systemFontOfSize:16];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:@"恢复" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16];
    btn.tag = kind;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:self action:@selector(clearImageTapped:)
        forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:label];
    [row addSubview:btn];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [btn.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [btn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintEqualToConstant:32]
    ]];
    return row;
}

- (void)refreshImageStatus {
    UILabel *v = objc_getAssociatedObject(self, &NEVehicleStatusKey);
    if (v) v.text = NEVehicleImagePath().length ? @"已自定义" : @"原图";
    UILabel *b = objc_getAssociatedObject(self, &NEBackgroundStatusKey);
    if (b) b.text = NEBackgroundImagePath().length ? @"已自定义" : @"原图";
}

- (void)pickImageTapped:(UIButton *)sender {
    NSInteger kind = sender.tag;
    objc_setAssociatedObject(self, &NEPickKindKey, @(kind),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    Class pickerCls = NSClassFromString(@"PHPickerViewController");
    if (pickerCls) {
        PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
        config.selectionLimit = 1;
        config.filter = [PHPickerFilter imagesFilter];
        PHPickerViewController *picker =
            [[PHPickerViewController alloc] initWithConfiguration:config];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    } else {
        // 回退：UIImagePickerController（系统常规相册授权流程）
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)clearImageTapped:(UIButton *)sender {
    NSInteger kind = sender.tag;
    NSString *key = (kind == 0) ? @"NEVehicleImagePath" : @"NEBackgroundImagePath";
    NSString *path = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    if (path.length) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    }
    if (kind == 0) gHasVehicleImage = NO; else gHasBgImage = NO;
    NEClearImageCache();
    [self refreshImageStatus];
    os_log(gLog, "[IMG] 已恢复原%{public}@", kind == 0 ? @"车辆图" : @"背景图");
}

- (void)savePickedImage:(UIImage *)img kind:(NSInteger)kind {
    if (!img) return;
    NSString *name = (kind == 0) ? @"ne-vehicle.png" : @"ne-bg.png";
    NSString *key = (kind == 0) ? @"NEVehicleImagePath" : @"NEBackgroundImagePath";
    NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                        NSUserDomainMask, YES).firstObject;
    if (!doc) return;
    NSString *path = [doc stringByAppendingPathComponent:name];
    // 注意：-[UIImage pngData] 在 Theos 构建的 SDK 头文件里不可见（编译报 no visible @interface），
    // 改用 UIImagePNGRepresentation；它在新 SDK 已废弃，用 pragma 压掉废弃警告（构建是 -Werror）。
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSData *data = UIImagePNGRepresentation(img);
#pragma clang diagnostic pop
    if (!data) {
        os_log(gLog, "[IMG] 选图转 PNG 失败");
        return;
    }
    NSError *err = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&err]) {
        os_log(gLog, "[IMG] 选图保存失败 %{public}@",
               err.localizedDescription ?: @"(未知)");
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:path forKey:key];
    if (kind == 0) gHasVehicleImage = YES; else gHasBgImage = YES;
    NEClearImageCache();
    NEInstallImageHooksIfNeeded();
    [self refreshImageStatus];
    NEForceRefreshImages(); // v0.3.9 修复：选完图立刻把设备 tab 的图重算一遍，不用等切 tab/重启
    os_log(gLog, "[IMG] 已保存自定义%{public}@（%ldx%ld），已应用到设备页",
           kind == 0 ? @"车辆图" : @"背景图",
           (long)img.size.width, (long)img.size.height);
}

// PHPicker 回调（主线程）
- (void)picker:(PHPickerViewController *)picker
    didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *r = results.firstObject;
    if (!r) return;
    NSNumber *kindNum = objc_getAssociatedObject(self, &NEPickKindKey);
    NSInteger kind = kindNum ? kindNum.integerValue : 0;
    NSItemProvider *provider = r.itemProvider;
    if (![provider canLoadObjectOfClass:[UIImage class]]) return;
    __weak typeof(self) weakSelf = self;
    [provider loadObjectOfClass:[UIImage class]
              completionHandler:^(__kindof id<NSItemProviderReading> _Nullable obj,
                                  NSError * _Nullable error) {
        if (![obj isKindOfClass:[UIImage class]]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf savePickedImage:(UIImage *)obj kind:kind];
        });
    }];
}

// UIImagePickerController 回调（回退路径）
- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    NSNumber *kindNum = objc_getAssociatedObject(self, &NEPickKindKey);
    NSInteger kind = kindNum ? kindNum.integerValue : 0;
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (img) [self savePickedImage:img kind:kind];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

// ---------------- 车辆数据探测（v0.1.5，Route B Phase 1：只读侦察）----------------
//
// 目标：找出九号 App 里相当于 Android DynamicDevice 的接收/发送路径，
// 以及 M3（九号 M395C MAX）自己的指令表里有没有需要的指令。
// 做法照 Xiaolangs tweak-cmddump（单例试探 + ivar 递归 + JSON 写盘）
// 和 tweak-theos DumpSelectors（class_copyMethodList 打方法列表）。
//
// 只读：本节代码永远不发蓝牙指令、不调任何发送方法、不写任何特征值，
// 只读类/方法信息和 App 内存里已有的指令表。
// 防御：每一步都有 nil / respondsToSelector / @try 保护；
// 类不存在、单例拿不到、指令表为空都只记日志，绝不崩。
// 触发：加载后 5 秒打一次方法列表；之后每 10 秒试取一次指令表，
// 最多 12 次（2 分钟）。每次尝试都写一份 Documents/BleCmdDump.json
//（成功/失败都写，第 12 次失败写最终文件，带 status:failed + reason）；
// 写出非空结果就停。车没连上时拿不到是正常的。
// 开关：defaults write cn.ninebot.segway NEProbeVehicle -bool NO
// 产出：Documents/BleCmdDump.json + os_log（[PROBE] 前缀）。

static dispatch_source_t gProbeTimer   = nil;
static dispatch_queue_t  gProbeQueue   = nil;
static int               gProbeAttempts = 0;
static BOOL              gProbeDone     = NO;
static NSMutableDictionary *gProbeClassInfo = nil;

static NSString *NEProbeCN(id o) { return o ? NSStringFromClass(object_getClass(o)) : @""; }

static NSString *NEProbeDocPath(NSString *name) {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return dir ? [dir stringByAppendingPathComponent:name] : name;
}

static NSArray<NSString *> *NEProbeTargetCommands(void) {
    return @[@"rSpeed", @"rPower", @"rVrlaVoltage", @"rBattery",
             @"rTirePressureRealTimeInfo",
             @"rVoltage", @"rVoltage2", @"rVoltage3", @"rBool", @"rBmsCycleCount"];
}

static NSArray<NSString *> *NEProbeCandidateClasses(void) {
    return @[@"_TtC15NBDynamicModule11DynamicTool",
             @"_TtC15NBDynamicModule19DynamicDebugManager",
             @"_TtC7Vehicle22BleCommandDebugManager",
             @"_TtC17NBBluetoothModule9DebugTool",
             @"_TtC7Vehicle17BleCommandDebugVC"];
}

// ---- 读一个 ivar（对象直接取，标量按类型编码读；cmddump 同款）----

static id NEProbeReadIvar(id obj, Ivar iv) {
    const char *t = ivar_getTypeEncoding(iv);
    if (!t) return nil;
    if (t[0] == '@') { @try { return object_getIvar(obj, iv); } @catch (__unused NSException *e) { return nil; } }
    ptrdiff_t off = ivar_getOffset(iv);
    char *base = (char *)(__bridge void *)obj;
    switch (t[0]) {
        case 'c': return @(*(char *)(base+off));
        case 'B': return @(*(BOOL *)(base+off));
        case 's': return @(*(short *)(base+off));
        case 'i': return @(*(int *)(base+off));
        case 'l': return @(*(long *)(base+off));
        case 'q': return @(*(long long *)(base+off));
        case 'f': return @(*(float *)(base+off));
        case 'd': return @(*(double *)(base+off));
        default:  return nil;
    }
}

// ---- 递归序列化任意对象（限深 4、防环、数组/字典各限 300 条）----

static id NEProbeSer(id obj, int depth, NSMutableSet *seen) {
    if (!obj || depth > 4) return nil;
    if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]]) return obj;
    if ([obj isKindOfClass:[NSNull class]]) return [NSNull null];
    if ([seen containsObject:[NSValue valueWithNonretainedObject:obj]]) return @"(cycle)";
    [seen addObject:[NSValue valueWithNonretainedObject:obj]];

    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [NSMutableArray array];
        int i = 0;
        for (id e in (NSArray *)obj) {
            if (i++ >= 300) { [a addObject:@"…（已截断，只取前 300 条）"]; break; }
            [a addObject:NEProbeSer(e, depth+1, seen) ?: [NSNull null]];
        }
        return a;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        __block int i = 0;
        [(NSDictionary *)obj enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            if (i++ >= 300) { d[@"…truncated"] = @"只取前 300 条"; *stop = YES; return; }
            d[[k description]] = NEProbeSer(v, depth+1, seen) ?: [NSNull null];
        }];
        return d;
    }
    if ([obj isKindOfClass:[NSData class]]) {
        return [NSString stringWithFormat:@"<NSData %luB>", (unsigned long)[(NSData *)obj length]];
    }
    // 自定义对象：读它的 ivar
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"_class"] = NEProbeCN(obj);
    unsigned int n = 0;
    Ivar *ivs = class_copyIvarList(object_getClass(obj), &n);
    for (unsigned int i = 0; i < n; i++) {
        NSString *nm = [NSString stringWithUTF8String:ivar_getName(ivs[i])] ?: @"?";
        id v = NEProbeReadIvar(obj, ivs[i]);
        if (!v) continue;
        id s = NEProbeSer(v, depth+1, seen);
        if (s) d[nm] = s;
    }
    free(ivs);
    return d;
}

// ---- 从序列化结果里收集所有字典键 + 字符串值（用来查目标指令在不在）----

static void NEProbeCollectKeys(id obj, int depth, NSMutableSet *seen, NSMutableSet *out) {
    if (!obj || depth > 4 || out.count > 2000) return;
    if ([obj isKindOfClass:[NSString class]]) {
        if (((NSString *)obj).length <= 64) [out addObject:obj];
        return;
    }
    if ([obj isKindOfClass:[NSNumber class]] || [obj isKindOfClass:[NSNull class]]) return;
    if ([seen containsObject:[NSValue valueWithNonretainedObject:obj]]) return;
    [seen addObject:[NSValue valueWithNonretainedObject:obj]];
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) NEProbeCollectKeys(e, depth+1, seen, out);
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        [(NSDictionary *)obj enumerateKeysAndObjectsUsingBlock:^(id k, id v, __unused BOOL *s) {
            if ([k isKindOfClass:[NSString class]] && ((NSString *)k).length <= 64) [out addObject:k];
            NEProbeCollectKeys(v, depth+1, seen, out);
        }];
    }
}

// ---- 单例试探（cmddump 的 10 个入口）----

static NSArray<NSString *> *NEProbeSingletonSelectors(void) {
    return @[@"shared", @"sharedInstance", @"defaultManager", @"standard", @"instance",
             @"manager", @"current", @"default", @"sharedManager", @"singleton"];
}

static id NEProbeTrySingleton(Class cls, NSString **outSel) {
    if (!cls) return nil;
    for (NSString *selName in NEProbeSingletonSelectors()) {
        SEL s = NSSelectorFromString(selName);
        if (![cls respondsToSelector:s]) continue;
        @try {
            id o = ((id (*)(id, SEL))objc_msgSend)(cls, s);
            if (o) { if (outSel) *outSel = selName; return o; }
        } @catch (__unused NSException *e) {}
    }
    return nil;
}

// ---- 在对象 ivar 里递归找持有 deviceCommands / commandDict 的对象 ----

static id NEProbeFindCommandsHolder(id obj, int depth, NSMutableSet *seen) {
    if (!obj || depth > 3) return nil;
    if ([seen containsObject:[NSValue valueWithNonretainedObject:obj]]) return nil;
    [seen addObject:[NSValue valueWithNonretainedObject:obj]];

    NSArray *want = @[@"deviceCommands", @"commandDict", @"commands"];
    unsigned int n = 0;
    Ivar *ivs = class_copyIvarList(object_getClass(obj), &n);
    for (unsigned int i = 0; i < n; i++) {
        NSString *nm = [NSString stringWithUTF8String:ivar_getName(ivs[i])] ?: @"";
        if ([want containsObject:nm]) {
            id v = NEProbeReadIvar(obj, ivs[i]);
            if (v) { free(ivs); return obj; }
        }
    }
    // 再往下钻一层
    for (unsigned int i = 0; i < n; i++) {
        const char *t = ivar_getTypeEncoding(ivs[i]);
        if (!t || t[0] != '@') continue;
        id v = NEProbeReadIvar(obj, ivs[i]);
        if (!v) continue;
        id hit = NEProbeFindCommandsHolder(v, depth+1, seen);
        if (hit) { free(ivs); return hit; }
    }
    free(ivs);
    return nil;
}

// ---- 方法列表：只看名字里有没有接收/发送的线索 ----

static BOOL NEProbeIsInteresting(NSString *selName) {
    static NSArray<NSString *> *kws = nil;
    static dispatch_once_t once = 0;
    dispatch_once(&once, ^{
        kws = @[@"Response", @"receive", @"didReceive", @"sendCommand", @"send",
                @"Command", @"Frame", @"handle", @"onResponse", @"intercept",
                @"hasCommand", @"getSn", @"createCommand"];
    });
    for (NSString *k in kws) {
        if ([selName rangeOfString:k options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static void NEProbeLogMethodList(Method *ms, unsigned int n, const char *kind, const char *clsName) {
    if (n == 0) return;
    const unsigned int kMaxLog = 200;
    NSMutableArray<NSString *> *interesting = [NSMutableArray array];
    for (unsigned int i = 0; i < n; i++) {
        const char *s = sel_getName(method_getName(ms[i]));
        if (!s) continue;
        NSString *name = [NSString stringWithUTF8String:s];
        if (name.length && NEProbeIsInteresting(name)) [interesting addObject:name];
        if (i < kMaxLog)
            os_log(gLog, "[PROBE]   %{public}s %{public}s -%{public}s", clsName, kind, s);
    }
    if (n > kMaxLog)
        os_log(gLog, "[PROBE]   %{public}s %{public}s方法共 %u 个，只打了前 %u 个", clsName, kind, n, kMaxLog);
    if (interesting.count) {
        os_log(gLog, "[PROBE] ⭐ %{public}s %{public}s方法里值得注意的（可能含接收/发送）：", clsName, kind);
        for (NSString *name in interesting)
            os_log(gLog, "[PROBE]     ⭐ %{public}s", name.UTF8String);
    } else {
        os_log(gLog, "[PROBE]   %{public}s %{public}s方法里没有含 Response/receive/send/Command/Frame/handle 的选择器", clsName, kind);
    }
}

static void NEProbeDumpMethods(const char *clsName) {
    Class c = objc_getClass(clsName);
    if (!gProbeClassInfo) gProbeClassInfo = [NSMutableDictionary dictionary];
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    if (!c) {
        entry[@"exists"] = @NO;
        gProbeClassInfo[@(clsName)] = entry;
        os_log(gLog, "[PROBE] %{public}s 不存在（6.10.12 相对 6.10.9 改名了？）", clsName);
        return;
    }
    entry[@"exists"] = @YES;
    Class superCls = class_getSuperclass(c);
    if (superCls) entry[@"superclass"] = NSStringFromClass(superCls);

    unsigned int nInst = 0;
    Method *inst = class_copyMethodList(c, &nInst);
    entry[@"instanceMethods"] = @(nInst);
    unsigned int nCls = 0;
    Method *clsMethods = class_copyMethodList(object_getClass(c), &nCls);
    entry[@"classMethods"] = @(nCls);

    NSMutableArray *sels = [NSMutableArray array];
    for (NSString *name in NEProbeSingletonSelectors()) {
        if ([c respondsToSelector:NSSelectorFromString(name)]) [sels addObject:name];
    }
    entry[@"singletonSelectors"] = sels;

    os_log(gLog, "[PROBE] %{public}s 存在（父类 %{public}s），实例方法 %u 个，类方法 %u 个，可作单例入口的选择器：%{public}s",
           clsName, superCls ? class_getName(superCls) : "(无)", nInst, nCls,
           sels.count ? [sels componentsJoinedByString:@", "].UTF8String : "(无)");
    if (nInst == 0 && nCls == 0)
        os_log(gLog, "[PROBE] ⚠️ %{public}s 没有任何 ObjC 可见方法——可能是 Swift-only 类，ObjC hook 挂不上（研究 §3 gap 7）", clsName);

    NEProbeLogMethodList(inst, nInst, "实例", clsName);
    NEProbeLogMethodList(clsMethods, nCls, "类", clsName);
    free(inst);
    free(clsMethods);
    gProbeClassInfo[@(clsName)] = entry;
}

static void NEProbeDumpClassesOnce(void) {
    os_log(gLog, "[PROBE] ---- 类 + 方法列表（一次）----");
    for (NSString *cn in NEProbeCandidateClasses()) NEProbeDumpMethods(cn.UTF8String);
    os_log(gLog, "[PROBE] ---- 类 + 方法列表结束 ----");
}

// ---- 一次取指令表尝试：单例 → 找持有者 → 序列化 → 查目标指令 → 写 JSON ----

static BOOL NEProbeAttempt(int attempt) {
    os_log(gLog, "[PROBE] 第 %d 次尝试取指令表（共 12 次）", attempt);
    NSArray<NSString *> *candClasses = @[@"_TtC15NBDynamicModule11DynamicTool",
                                         @"_TtC15NBDynamicModule19DynamicDebugManager",
                                         @"_TtC7Vehicle22BleCommandDebugManager",
                                         @"_TtC17NBBluetoothModule9DebugTool"];
    NSMutableDictionary *report = [NSMutableDictionary dictionary];
    report[@"probe"] = @"NinebotEnhance iOS 0.2.0";
    report[@"attempt"] = @(attempt);
    report[@"date"] = [[NSDate date] description];
    if (gProbeClassInfo) report[@"classes"] = gProbeClassInfo;
    NSMutableDictionary *singletons = [NSMutableDictionary dictionary];
    NSMutableDictionary *holders = [NSMutableDictionary dictionary];
    NSMutableSet *foundKeys = [NSMutableSet set];

    @try {
        for (NSString *cn in candClasses) {
            Class c = objc_getClass(cn.UTF8String);
            if (!c) continue;
            NSString *usedSel = nil;
            id inst = NEProbeTrySingleton(c, &usedSel);
            if (!inst) {
                os_log(gLog, "[PROBE] %{public}s 单例：10 个入口都拿不到", cn.UTF8String);
                continue;
            }
            os_log(gLog, "[PROBE] %{public}s 单例拿到（入口 %@）", cn.UTF8String, usedSel);
            id holder = NEProbeFindCommandsHolder(inst, 0, [NSMutableSet set]);
            if (!holder) {
                os_log(gLog, "[PROBE]   顺着 ivar 没找到含 deviceCommands/commandDict 的对象");
                continue;
            }
            NSString *holderCls = NSStringFromClass(object_getClass(holder));
            singletons[cn] = @{@"accessor": usedSel ?: @"?", @"holderClass": holderCls};
            os_log(gLog, "[PROBE]   指令表持有者：%{public}s", holderCls.UTF8String);
            id ser = NEProbeSer(holder, 0, [NSMutableSet set]);
            if (!ser) {
                os_log(gLog, "[PROBE]   持有者序列化为空");
                continue;
            }
            holders[cn] = ser;
            NSMutableSet *keys = [NSMutableSet set];
            NEProbeCollectKeys(ser, 0, [NSMutableSet set], keys);
            for (NSString *t in NEProbeTargetCommands()) {
                if ([keys containsObject:t]) [foundKeys addObject:t];
            }
        }
    } @catch (NSException *e) {
        os_log(gLog, "[PROBE] 尝试过程异常：%{public}s", e.reason.UTF8String ?: "?");
    }

    // v0.1.7：无论拿到没拿到，都写一份 JSON（每次尝试都写，用户
    // 中途退出 App 文件也已经在）。成功时 targets 照常判有/无；
    // 失败时 singletons/holders/targets 为空、status 为 failed；
    // 第 12 次仍失败时再加 reason，说明可能原因。
    report[@"singletons"] = singletons;
    report[@"holders"] = holders;
    NSMutableDictionary *targets = [NSMutableDictionary dictionary];
    for (NSString *t in NEProbeTargetCommands()) targets[t] = @([foundKeys containsObject:t]);
    report[@"targets"] = targets;
    BOOL ok = (holders.count > 0);
    report[@"status"] = ok ? @"success" : @"failed";
    if (!ok) {
        os_log(gLog, "[PROBE] 第 %d 次尝试：没拿到指令表", attempt);
        if (attempt >= 12) {
            report[@"reason"] = @"12 次尝试都没拿到指令表，可能原因：车没连上，或单例入口不在这 4 个候选类上，或顺着 ivar 没找到含 deviceCommands/commandDict 的对象。";
        }
    } else {
        for (NSString *t in NEProbeTargetCommands())
            os_log(gLog, "[PROBE] 目标指令 %{public}s：%{public}s", t.UTF8String,
                   [foundKeys containsObject:t] ? "有" : "无");
    }

    NSError *err = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:report
                    options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&err];
    if (!json) {
        os_log(gLog, "[PROBE] ❌ JSON 序列化失败：%{public}s", err.localizedDescription.UTF8String ?: "?");
        return NO;
    }
    NSString *path = NEProbeDocPath(@"BleCmdDump.json");
    if (![json writeToFile:path atomically:YES]) {
        os_log(gLog, "[PROBE] ❌ 写文件失败：%{public}s", path.UTF8String);
        return NO;
    }
    os_log(gLog, "[PROBE] ✅ 已写入 %{public}s（%lu B，第 %d 次尝试）", path.UTF8String,
           (unsigned long)json.length, attempt);
    return ok;
}

// ---- 启动：5 秒后打方法列表，之后每 10 秒试取指令表，最多 12 次 ----

static void NEProbeStart(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEProbeVehicle"];
    if (v && ![v boolValue]) {
        os_log(gLog, "[PROBE] 已关（NEProbeVehicle=NO）");
        return;
    }
    gProbeQueue = dispatch_queue_create("com.user.ninebotenhance.probe", DISPATCH_QUEUE_SERIAL);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), gProbeQueue, ^{
        NEProbeDumpClassesOnce();
    });
    gProbeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gProbeQueue);
    dispatch_source_set_timer(gProbeTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)),
                              10 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(gProbeTimer, ^{
        if (gProbeDone) { dispatch_source_cancel(gProbeTimer); return; }
        gProbeAttempts++;
        if (gProbeAttempts > 12) {
            os_log(gLog, "[PROBE] 12 次尝试都没拿到指令表，停止重试（可能车没连上，或单例入口不在这 4 个类上）；最终结果已写入 BleCmdDump.json，请把文件发回");
            gProbeDone = YES;
            dispatch_source_cancel(gProbeTimer);
            return;
        }
        if (NEProbeAttempt(gProbeAttempts)) {
            gProbeDone = YES;
            dispatch_source_cancel(gProbeTimer);
            os_log(gLog, "[PROBE] 探测完成：BleCmdDump.json 已写好，请把文件发回");
        } else if (gProbeAttempts >= 12) {
            // 第 12 次已写过一份带 status:failed + reason 的最终文件，
            // 不用再等第 13 次 tick，直接停表。
            gProbeDone = YES;
            dispatch_source_cancel(gProbeTimer);
            os_log(gLog, "[PROBE] 12 次尝试都没拿到指令表，停止重试（可能车没连上，或单例入口不在这 4 个类上）；最终结果已写入 BleCmdDump.json，请把文件发回");
        }
    });
    dispatch_resume(gProbeTimer);
    os_log(gLog, "[PROBE] 车辆数据探测已启动（只读）：5 秒后打方法列表，之后每 10 秒试取指令表，最多 12 次");
}

// ---------------- Hooks ----------------
%hook NBPixelBufferConverter

+ (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image {
    NoteFrame(CGImageGetWidth(image), CGImageGetHeight(image));
    if (!image || !OverlayEnabled()) return %orig;
    CGImageRef composited = CompositeWithOverlay(image);
    if (!composited) return %orig;
    MaybeDump(composited, gFrames);
    CVPixelBufferRef buf = %orig(composited);
    CGImageRelease(composited);
    return buf;
}

+ (CVPixelBufferRef)pixelBufferFromCGImage_Mjpeg:(CGImageRef)image {
    NoteFrame(CGImageGetWidth(image), CGImageGetHeight(image));
    if (!image || !OverlayEnabled()) return %orig;
    CGImageRef composited = CompositeWithOverlay(image);
    if (!composited) return %orig;
    MaybeDump(composited, gFrames);
    CVPixelBufferRef buf = %orig(composited);
    CGImageRelease(composited);
    return buf;
}

- (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image {
    NoteFrame(CGImageGetWidth(image), CGImageGetHeight(image));
    if (!image || !OverlayEnabled()) return %orig;
    CGImageRef composited = CompositeWithOverlay(image);
    if (!composited) return %orig;
    MaybeDump(composited, gFrames);
    CVPixelBufferRef buf = %orig(composited);
    CGImageRelease(composited);
    return buf;
}

- (CVPixelBufferRef)pixelBufferFromCGImage_Mjpeg:(CGImageRef)image {
    NoteFrame(CGImageGetWidth(image), CGImageGetHeight(image));
    if (!image || !OverlayEnabled()) return %orig;
    CGImageRef composited = CompositeWithOverlay(image);
    if (!composited) return %orig;
    MaybeDump(composited, gFrames);
    CVPixelBufferRef buf = %orig(composited);
    CGImageRelease(composited);
    return buf;
}

%end

%ctor {
    gLog      = os_log_create("com.user.ninebotenhance", "general");
    gLock     = [NSLock new];
    gDataLock = [NSLock new];
    gImageLock = [NSLock new];

    // v0.3.9：有效期 9999 / 五个自定义显示项——开关开着就装 UILabel 钩子；主页已选自定义图就装图片钩子
    gValidity9999 = NEValidity9999();
    NESyncCustomDisplayCache();
    if (gValidity9999 || gNCoins || gMileage || gLevel || gTitle || gSignDays)
        NEInstallLabelHookIfNeeded();
    gHasVehicleImage = NEVehicleImagePath().length > 0;
    gHasBgImage = NEBackgroundImagePath().length > 0;
    if (gHasVehicleImage || gHasBgImage) NEInstallImageHooksIfNeeded();
    // PHPicker（PhotosUI）运行时加载：dlopen 失败也不影响，回退 UIImagePickerController
    dlopen("/System/Library/Frameworks/PhotosUI.framework/PhotosUI", RTLD_NOW | RTLD_LOCAL);

    // 天气：恢复上次拉到的结果（2 小时内直接用，冷启动不用等定位+拉取；
    // 超过 20 分钟的照常在后台刷新，见 RefreshWeatherIfNeeded）
    {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        double savedAt = [d doubleForKey:@"NEWeatherAt"];
        int savedCode = (int)[d integerForKey:@"NEWeatherCode"];
        if (savedCode >= 0 && savedAt > 0 &&
            (CFAbsoluteTimeGetCurrent() - savedAt) < 2 * 3600) {
            int savedTemp = (int)[d integerForKey:@"NEWeatherTemp"];
            [gDataLock lock];
            gWeatherCode = savedCode;
            gWeatherTemp = savedTemp;
            gWeatherAt = savedAt;
            [gDataLock unlock];
            os_log(gLog, "[WX] 恢复缓存天气：%d° code=%d", savedTemp, savedCode);
        }
    }

    // 钩点存在性检查：6.10.12 相对 6.10.9 可能改名，改了就静默失效，这里先记下来
    Class conv = objc_getClass("NBPixelBufferConverter");
    if (!conv) {
        os_log(gLog, "[HOOK] NBPixelBufferConverter 类未找到——插件不会起作用"
               "（App 版本漂移？逆向针对 6.10.9，本机是 6.10.12）");
    } else {
        BOOL hasSel = class_getClassMethod(conv, @selector(pixelBufferFromCGImage:)) != NULL ||
                      class_getInstanceMethod(conv, @selector(pixelBufferFromCGImage:)) != NULL;
        os_log(gLog, "[HOOK] NBPixelBufferConverter 已找到，pixelBufferFromCGImage: %s",
               hasSel ? "YES" : "NO");
    }

    os_log(gLog, "NinebotEnhance iOS 0.3.9 已加载（小胶囊 HUD：日期/天气/信号/音量/电量/来电/超速 + 翻页时钟 + 车辆数据探测 + 有效期9999/主页换图/自定义显示）");

    // 电量监听 + 定位 + 来电观察，全部在主队列 / 后台队列做，不阻塞加载
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        gLocDelegate = [NELocationDelegate new];
        gLocMgr = [CLLocationManager new];
        gLocMgr.delegate = gLocDelegate;
        NEApplySpeedLocationMode(); // 提醒开着 → 连续定位；关着 → 单次定位（只够天气用）

        // v0.3.9 修复：启动 3 秒后强制刷新一次文字+图片——页面可能在钩子装好前已加载，
        // 或主题图走 imageNamed 时名字没命中关键字，靠尺寸启发式再补一次。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NEForceRefreshLabels();
            NEForceRefreshImages();
        });

        // 音量：每秒一刷（主线程）
        NERefreshVolume();
        gVolumeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                              dispatch_get_main_queue());
        dispatch_source_set_timer(gVolumeTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                                  NSEC_PER_SEC, NSEC_PER_SEC / 2);
        dispatch_source_set_event_handler(gVolumeTimer, ^{ NERefreshVolume(); });
        dispatch_resume(gVolumeTimer);

        // HUD 设置按钮：每 3 秒看一次最上层页面，只在“我的”页加按钮
        gButtonTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                              dispatch_get_main_queue());
        dispatch_source_set_timer(gButtonTimer, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                                  3 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(gButtonTimer, ^{ NECheckSettingsButton(); });
        dispatch_resume(gButtonTimer);
    });

    // 联网方式监听（后台队列）
    NEStartNetworkMonitor();

    gCallDelegate = [NECallDelegate new];
    gCallObserver = [CXCallObserver new];
    [gCallObserver setDelegate:gCallDelegate
                         queue:dispatch_queue_create("com.user.ninebotenhance.calls",
                                                     DISPATCH_QUEUE_SERIAL)];

    // 车辆数据探测（只读侦察，见上文 NEProbeStart）
    NEProbeStart();
}

