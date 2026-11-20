// NinebotEnhance iOS v0.2.0 — 九号出行(cn.ninebot.segway) 投屏画面 HUD 叠加
//
// v0.2.0 改动：HUD 加骑行小人，AI 重画的插画分层动画版。
//  表盘区下面紧挨着一个带边框的小框（背景跟 HUD 胶囊一样：黑 45% +
//  白 35% 边框、圆角 12），里面是 AI 照着用户参考图重画的插画：大黄头盔
//  竹蜻蜓、圆脸腮红、白上衣灰裤子骑浅蓝小绵羊，朝左，跟原图同构图同配色。
//  框顶边在帧高 0.30，框高按日期天气胶囊之上的可用空间定，框宽 = 框高 ×
//  314/320，水平居中，不去碰底下日期天气那几行。车子行驶时小人跟着骑
//  （3 帧循环：轮子转 + 螺旋桨转 + 速度线尾气，骑得越快帧切换越快），车子
//  停下来小人也停在静止帧（轮子不转、不喷尾气）；速度用插件已有的 GPS
//  速度驱动（>2 km/h 开始骑，<1 km/h 停下，中间迟滞防抖）。设置页加
//  “骑行小人”开关（默认开）。不晃动、不上下位移、不摇摆（用户明确不要）。
//  画法是分层贴图（NEDrawRider）：底下先画手绘轮子（CG，胎/盘/放射线/毂，
//  绕轮心转），再画 RiderImage.h 的 main 图，再绕 hub 旋转画螺旋桨，行驶帧
//  再画 RiderMotion.h 的速度线 + 尾气层；三张图 base64 运行时解码一次缓存。
//  超速提醒、探针一律不动。
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
// 再把 HUD 叠加层（小胶囊：日期时间 / 天气 / 信号 / 音量 / 电量，
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
//     黑底 45% + 白边 35% 1pt + 圆角 12；上行时钟图标 + 日期时间；
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
//   NEHUDShowBattery / NEHUDShowVolume / NEHUDShowRider（bool，默认 YES）
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
#include "RiderImage.h"  // AI 重画插画贴图素材（base64，见 RiderImage.h）
#include "RiderMotion.h" // 速度线 + 尾气层素材（base64，见 RiderMotion.h）

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
// 像素骑行小人开关（v0.2.0，默认 YES）
static BOOL NEHUDShowRider(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDShowRider"];
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

static void FetchWeather(double lat, double lon) {
    NSString *urlStr = [NSString stringWithFormat:
        @"https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f"
         "&current=temperature_2m,weather_code&timezone=auto", lat, lon];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        [gDataLock lock]; gWeatherFetching = NO; [gDataLock unlock];
        return;
    }
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
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
            [gDataLock lock];
            gWeatherCode = [code intValue];
            gWeatherTemp = (int)lround([temp doubleValue]);
            gWeatherAt = CFAbsoluteTimeGetCurrent();
            gWeatherFetching = NO;
            [gDataLock unlock];
            os_log(gLog, "[WX] %d° code=%d", (int)lround([temp doubleValue]), [code intValue]);
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

// 超速提醒或骑行小人开 → 连续定位（best 精度）；都关 → 恢复单次定位
// （3km 精度，只够天气用）。主线程调（gLocMgr 在主队列创建，回调也在主队列）。
static void NEApplySpeedLocationMode(void) {
    if (!gLocMgr) return;
    if (NEHUDSpeedAlert() || NEHUDShowRider()) {
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
    fmt.dateFormat = @"M月d日 EEE HH:mm";
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
    BOOL showRider;  // 骑行小人开关（v0.2.0）
    BOOL speedAlert; // 超速提醒开关（v0.1.8）
    NSInteger position; // 0 右下 1 左下 2 左上 3 右上
    CGFloat fontRefPt;  // 16/20/24
} NEHUDSettings;

// ---------- 骑行小人（v0.2.0）：AI 重画的插画，分层动画 ----------
// 用户已认可 AI 照着参考图重画的插画（rider-redrawn.png，手绘风，同构图
// 同配色）。上一版用户原图贴图（commit 817d57e9）作废，不用交付。
// 素材：RiderImage.h：kRiderMainB64（314x320，主体，轮子、螺旋桨、速度线、
// 尾气已抠掉，轮子处是透明洞）、kRiderPropB64（314x320 全画布，螺旋桨叶片）；
// RiderMotion.h：kRiderMotionB64（314x320 全画布，速度线 + 尾气，只在行驶帧）。
// 运行时 base64 解码一次并缓存。绘制顺序（同一坐标系）：(1) 手绘轮子
// （CG，胎/盘/12 根放射线/毂，绕轮心转，画在 main 图底下，main 图的轮洞
// 露出它们，main 图里的前叉/挡泥板/后车罩/消声器自然盖住轮子上部）；
// (2) main 图；(3) 螺旋桨（绕中心旋转）；(4) motion 层（只在行驶帧）。
// 动画：frame 0 停车静止（轮子 0°、螺旋桨 0°、无 motion 层）；frame 1/2
// 行驶（轮子 40°/80°、螺旋桨 40°/80°、motion 层显示）。不晃动、不上下
// 位移、不摇摆（用户明确不要）。边框：顶边在帧高 0.30；高度按日期天气
// 胶囊之上的可用空间定（RenderOverlay 把胶囊顶边位置写进
// gNERiderLimitBottomFromTop），宽度 = 高度 × 314/320，水平居中；样式
// 跟 HUD 胶囊一样（黑 45% + 白 35% 边、圆角 12）。框高 = 图片高 + 内边距，
// 不去碰底下日期天气那几行。位置/尺寸全部是常量，方便按用户实测照片微调。
#define NE_RIDER_IMG_W 314.0
#define NE_RIDER_IMG_H 320.0
#define NE_RIDER_HUB_X 143.5      // 螺旋桨中心（main 图坐标，314x320）
#define NE_RIDER_HUB_Y 22.5
#define NE_RIDER_WHEEL_FX 46.0    // 前轮中心 x（图坐标）
#define NE_RIDER_WHEEL_FY 285.0   // 前轮中心 y（图坐标）
#define NE_RIDER_WHEEL_RX 189.0   // 后轮中心 x（图坐标）
#define NE_RIDER_WHEEL_RY 285.0   // 后轮中心 y（图坐标）
#define NE_RIDER_WHEEL_R 25.0     // 轮子半径（图坐标）
static const CGFloat NE_RIDER_BOX_TOP_FRAC = 0.30; // 边框顶边离顶 = 帧高 × 0.30（表盘区下方，待实测校准）
static const CGFloat NE_RIDER_PAD          = 8;    // 边框内边距（848x480 参考 px）
static const double  NE_RIDER_SPEED_START  = 2.0;  // >2 km/h 开始骑
static const double  NE_RIDER_SPEED_STOP   = 1.0;  // <1 km/h 停下（迟滞，防抖）

// RenderOverlay 每次重画时把日期天气胶囊的顶边（离顶距离）写到这里，
// 供 NEDrawRider 定边框高度：边框底边必须在胶囊上面，留 12*sy 空隙。
// 胶囊在顶部时（position 左上/右上）或没有胶囊时，值 = 帧高 - 12*sy。
static CGFloat gNERiderLimitBottomFromTop = 0;

// 当前该画第几帧（0/1/2）。速度用 GPS 速度（km/h），speedFresh 为 NO
// （5 秒内没新定位）就当停车。>2 开始骑，<1 停下，中间保持上次状态
// （迟滞，避免在 1–2 之间抖）。骑得越快帧切换越快（0.45s→0.12s 下限）。
// 叠加层最多 250ms 重画一次，所以实际动画帧率 ≤4fps，贴图够用。
static int NERiderFrameIndex(double speedKmh, BOOL speedFresh, CFAbsoluteTime now) {
    static BOOL moving = NO;
    double speed = speedFresh ? speedKmh : 0;
    if (speed > NE_RIDER_SPEED_START) moving = YES;
    else if (speed < NE_RIDER_SPEED_STOP) moving = NO;
    if (!moving) return 0;
    double dur = 0.45 - speed * 0.006;
    if (dur < 0.12) dur = 0.12;
    if (dur > 0.45) dur = 0.45;
    long long ticks = (long long)(now / dur);
    return (int)(ticks % 3);
}

// base64 解码成 CGImage（只解码一次，缓存）。都是 iOS 7/4 时代的老 API。
static CGImageRef NERiderImageFromB64(const char *b64) {
    if (!b64) return NULL;
    NSString *s = [NSString stringWithUTF8String:b64];
    if (!s) return NULL;
    NSData *data = [[NSData alloc] initWithBase64EncodedString:s
                                                        options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (!data) return NULL;
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!src) return NULL;
    CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    return img;
}

static CGImageRef NERiderMainImage(void) {
    static CGImageRef img = NULL;
    static dispatch_once_t once = 0;
    dispatch_once(&once, ^{ img = NERiderImageFromB64(kRiderMainB64); });
    return img;
}

static CGImageRef NERiderPropImage(void) {
    static CGImageRef img = NULL;
    static dispatch_once_t once = 0;
    dispatch_once(&once, ^{ img = NERiderImageFromB64(kRiderPropB64); });
    return img;
}

static CGImageRef NERiderMotionImage(void) {
    static CGImageRef img = NULL;
    static dispatch_once_t once = 0;
    dispatch_once(&once, ^{ img = NERiderImageFromB64(kRiderMotionB64); });
    return img;
}

// 画小人框：黑 45% + 白 35% 边、圆角 12（跟 HUD 胶囊一样的底板）。
// ctx 是 y 朝上的 bitmap（跟 RenderOverlay 同一套坐标）。
// 绘制顺序（都在翻转后的图坐标里，y 朝下，跟预览脚本一致）：
//   (1) 手绘轮子（CG，画在 main 图底下）；(2) main 图；
//   (3) 螺旋桨（绕中心旋转）；(4) motion 层（只在行驶帧）。
// 不晃动、不上下位移、不摇摆。图片按等比缩放进框里（不拉伸）。
static void NEDrawRider(CGContextRef ctx, CGFloat w, CGFloat h, int frame) {
    if (frame < 0 || frame > 2) frame = 0;
    CGImageRef mainImg = NERiderMainImage();
    CGImageRef propImg = NERiderPropImage();
    CGImageRef motionImg = NERiderMotionImage();
    if (!mainImg || !propImg || !motionImg) return;

    CGFloat sx = w / 848.0;
    CGFloat sy = h / 480.0;

    // 边框：顶边 0.30，底边在胶囊上面（留空隙）；宽 = 高 × 314/320，水平居中
    CGFloat boxTopFromTop = NE_RIDER_BOX_TOP_FRAC * h;
    CGFloat limitBottomFromTop = (gNERiderLimitBottomFromTop > 0)
        ? gNERiderLimitBottomFromTop : (h - 12 * sy);
    CGFloat boxH = limitBottomFromTop - boxTopFromTop;
    if (boxH < 80 * sy) boxH = 80 * sy; // 兜底：可用空间太小也别画崩
    CGFloat boxW = boxH * (NE_RIDER_IMG_W / NE_RIDER_IMG_H);
    CGFloat boxX = (w - boxW) / 2;
    CGFloat boxY = h - boxTopFromTop - boxH; // y 朝上坐标：底边离底的距离

    // 底板：跟 HUD 胶囊一样
    CGPathRef panel = CGPathCreateWithRoundedRect(
        CGRectMake(boxX, boxY, boxW, boxH), 12 * sx, 12 * sy, NULL);
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.45);
    CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.35);
    CGContextSetLineWidth(ctx, MAX(1, 1 * sx));
    CGContextAddPath(ctx, panel);
    CGContextDrawPath(ctx, kCGPathFillStroke);
    CGPathRelease(panel);

    // 图片等比放进框内（留内边距），居中
    CGFloat padX = NE_RIDER_PAD * sx;
    CGFloat padY = NE_RIDER_PAD * sy;
    CGFloat contentW = boxW - 2 * padX;
    CGFloat contentH = boxH - 2 * padY;
    CGFloat s = MIN(contentW / NE_RIDER_IMG_W, contentH / NE_RIDER_IMG_H);
    CGFloat imgW = NE_RIDER_IMG_W * s;
    CGFloat imgH = NE_RIDER_IMG_H * s;
    CGFloat imgX = boxX + padX + (contentW - imgW) / 2;
    CGFloat imgY = boxY + padY + (contentH - imgH) / 2; // y 朝上：图片底边

    // 翻转成图坐标（y 朝下，原点在图片左上角），跟预览脚本一致。
    // 下面所有坐标都是“图坐标 × s”。
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, imgX, imgY + imgH);
    CGContextScaleCTM(ctx, 1, -1);

    // (1) 手绘轮子（画在 main 图底下）。轮子位置/半径按 rider-gen-geo.json。
    // 画法跟预览脚本的 draw_wheel 一致：胎、盘、12 根放射线、毂。
    // 放射线角度 = frame×40° + k×30°，用 cos/sin 直接算端点（y 朝下坐标，
    // 跟 PIL 一样），不用 CTM 旋转。
    CGFloat spokeDeg = frame * 40.0; // frame 0: 0°，frame 1: +40°，frame 2: +80°
    CGFloat wheelCX[2] = { NE_RIDER_WHEEL_FX * s, NE_RIDER_WHEEL_RX * s };
    CGFloat wheelCY[2] = { NE_RIDER_WHEEL_FY * s, NE_RIDER_WHEEL_RY * s };
    CGFloat wheelR = NE_RIDER_WHEEL_R * s;
    for (int wi = 0; wi < 2; wi++) {
        CGFloat cx = wheelCX[wi], cy = wheelCY[wi];
        // 胎：深灰填 + 棕描边
        CGContextSetRGBFillColor(ctx, 75/255.0, 65/255.0, 65/255.0, 1);
        CGContextSetRGBStrokeColor(ctx, 150/255.0, 45/255.0, 25/255.0, 1);
        CGContextSetLineWidth(ctx, 3 * s);
        CGContextFillEllipseInRect(ctx, CGRectMake(cx - wheelR, cy - wheelR, wheelR * 2, wheelR * 2));
        CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - wheelR, cy - wheelR, wheelR * 2, wheelR * 2));
        // 内盘：暖灰
        CGFloat discR = wheelR * 0.77;
        CGContextSetRGBFillColor(ctx, 110/255.0, 100/255.0, 95/255.0, 1);
        CGContextFillEllipseInRect(ctx, CGRectMake(cx - discR, cy - discR, discR * 2, discR * 2));
        // 12 根短放射线（红棕），绕轮心转
        CGContextSetRGBStrokeColor(ctx, 150/255.0, 60/255.0, 35/255.0, 1);
        CGContextSetLineWidth(ctx, 4 * s);
        CGContextBeginPath(ctx);
        for (int k = 0; k < 12; k++) {
            double a = (spokeDeg + k * 30.0) * M_PI / 180.0;
            CGFloat x1 = cx + wheelR * 0.45 * cos(a);
            CGFloat y1 = cy + wheelR * 0.45 * sin(a);
            CGFloat x2 = cx + wheelR * 0.68 * cos(a);
            CGFloat y2 = cy + wheelR * 0.68 * sin(a);
            CGContextMoveToPoint(ctx, x1, y1);
            CGContextAddLineToPoint(ctx, x2, y2);
        }
        CGContextStrokePath(ctx);
        // 毂：浅灰填 + 棕描边
        CGFloat hubR = wheelR * 0.2;
        CGContextSetRGBFillColor(ctx, 200/255.0, 200/255.0, 200/255.0, 1);
        CGContextSetRGBStrokeColor(ctx, 150/255.0, 45/255.0, 25/255.0, 1);
        CGContextSetLineWidth(ctx, 2 * s);
        CGContextFillEllipseInRect(ctx, CGRectMake(cx - hubR, cy - hubR, hubR * 2, hubR * 2));
        CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - hubR, cy - hubR, hubR * 2, hubR * 2));
    }

    // (2) main 图
    CGContextDrawImage(ctx, CGRectMake(0, 0, imgW, imgH), mainImg);

    // (3) 螺旋桨：绕中心 (143.5, 22.5) 旋转。prop 层是全画布图，绕 hub
    // 旋转整张图（跟预览脚本的 prop.rotate(frame*40, center=hub) 一致）。
    // 预览里螺旋桨是逆时针转；y 翻转的 CTM 下取负角才与预览一致（跟上一版一样）。
    CGFloat hubX = NE_RIDER_HUB_X * s;
    CGFloat hubY = NE_RIDER_HUB_Y * s;
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, hubX, hubY);
    CGContextRotateCTM(ctx, -spokeDeg * M_PI / 180.0);
    CGContextTranslateCTM(ctx, -hubX, -hubY);
    CGContextDrawImage(ctx, CGRectMake(0, 0, imgW, imgH), propImg);
    CGContextRestoreGState(ctx);

    // (4) motion 层（速度线 + 尾气）：只在行驶帧画在最上面
    if (frame > 0) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, imgW, imgH), motionImg);
    }

    CGContextRestoreGState(ctx);
}

static CGImageRef RenderOverlay(size_t w, size_t h,
                                NSString *timeStr,
                                float battLevel, BOOL battCharging,
                                int wxCode, int wxTemp,
                                int netKind, NSString * __unsafe_unretained netLabel,
                                float volume, BOOL callActive,
                                int speedKmh, BOOL overspeed,
                                int riderFrame,
                                NEHUDSettings st) {
    if (w == 0 || h == 0) return NULL;
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

    // 骑行小人框的底边上限：默认到帧底；有底部胶囊时改成胶囊顶边之上（留空隙）
    gNERiderLimitBottomFromTop = H - 12 * sy;

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

    // ---- 组行 ----
    NESeg rows[NE_MAX_ROWS][NE_MAX_SEGS];
    int rowCounts[NE_MAX_ROWS] = { 0, 0, 0 };
    memset(rows, 0, sizeof(rows));

    // 上行：时钟图标 + 日期时间
    if (st.showDate && timeStr.length > 0) {
        NESeg *s = &rows[0][rowCounts[0]++];
        s->kind = 1; s->icon = 0;
        s = &rows[0][rowCounts[0]++];
        s->kind = 0; s->text = timeStr; s->color = white;
    }
    // 下行：天气图标 + 温度、联网方式、音量、电池图标 + 百分比
    if (st.showWeather && wxCode >= 0) {
        NESeg *s = &rows[1][rowCounts[1]++];
        s->kind = 1; s->icon = 2; s->wxCode = wxCode;
        s = &rows[1][rowCounts[1]++];
        s->kind = 0; s->text = [NSString stringWithFormat:@"%d°", wxTemp]; s->color = white;
    }
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
    // 第三行：超速（只在超速时画，红色文字，不用图标）
    if (st.speedAlert && overspeed) {
        NESeg *s = &rows[2][rowCounts[2]++];
        s->kind = 0;
        s->text = [NSString stringWithFormat:@"超速 %d km/h", speedKmh];
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
                s->line = NETextLine(s->text, font, s->color);
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
        CGFloat pillW = contentW + padX * 2;
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
            if (pillY < H / 2) gNERiderLimitBottomFromTop = pillTopFromTop - 12 * sy; // 胶囊在底部时，小人框底边在它上面
            for (int ri = 0; ri < nonEmptyRows; ri++) {
                int r = rowOrder[ri];
                CGFloat rowTop = pillTopFromTop + padY + ri * (rowHeight + rowGap);
                CGFloat baseline = H - rowTop - ascent;
                CGFloat textCenterY = baseline + (ascent - descent) / 2;
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

    // 骑行小人（v0.2.0）：跟 HUD 一起出现/消失；就算胶囊各行全关也照画
    if (st.showRider) {
        NEDrawRider(ctx, (CGFloat)w, (CGFloat)h, riderFrame);
    }

    out = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    CFRelease(font);
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
    if (cache && cw == w && ch == h && (now - at) <= 0.25) {
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
    st.showRider = NEHUDShowRider();
    st.speedAlert = NEHUDSpeedAlert();
    st.position = NEHUDPosition(); st.fontRefPt = NEHUDFontRefPt();

    // 骑行小人帧号（v0.2.0）：放进缓存 key，帧变了才重画
    int riderFrame = 0;
    if (st.showRider) riderFrame = NERiderFrameIndex(speedKmhD, speedFresh, now);

    NSString *key = [NSString stringWithFormat:@"%@|%.2f|%d|%d|%d|%d|%@|%.2f|%d|%d%d%d%d%d|%ld|%.0f|%d|%d|%d",
                     timeStr, battLevel, battCharging, wxCode, wxTemp, netKind,
                     netLabel ?: @"", volume, callActive,
                     st.showDate, st.showWeather, st.showSignal,
                     st.showBattery, st.showVolume,
                     (long)st.position, st.fontRefPt, speedKmh, overspeed, riderFrame];
    if (!cache || cw != w || ch != h || ![key isEqualToString:cacheKey]) {
        if (cache) { CGImageRelease(cache); cache = NULL; }
        cache = RenderOverlay(w, h, timeStr, battLevel, battCharging,
                              wxCode, wxTemp, netKind, netLabel,
                              volume, callActive,
                              speedKmh, overspeed, riderFrame, st);
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
// 九号 App 的“我的”页右上角会出现一个“HUD设置”按钮。
// 找页面的办法：每 3 秒看一次最上层 ViewController，只在“我的”页
// 显示（NEIsMineRootPage：当前 tab 是“我的”且是根页面；没有 tab
// bar 时退回类名含 mine）。没匹配到就不出现，设置仍可用 defaults
// 命令改。不硬编任何 App 的类名，所以 6.10.12 改了类名也不会崩，
// 只是不出按钮。

static const char NEHUDButtonKey = 0;
static const char NESpeedLimitValueKey = 0;

@interface NEHUDSettingsVC : UIViewController
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
    cfg.title = @"HUD设置";
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
    os_log(gLog, "[HUD] 已在 %{public}s 上加 HUD设置 按钮", NSStringFromClass([vc class]).UTF8String);
}

@implementation NEHUDSettingsVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"HUD 设置";
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

    [stack addArrangedSubview:[self switchRow:@"日期时间" key:@"NEHUDShowDate" on:NEHUDShowDate()]];
    [stack addArrangedSubview:[self switchRow:@"天气温度" key:@"NEHUDShowWeather" on:NEHUDShowWeather()]];
    [stack addArrangedSubview:[self switchRow:@"信号（WiFi/5G）" key:@"NEHUDShowSignal" on:NEHUDShowSignal()]];
    [stack addArrangedSubview:[self switchRow:@"电量" key:@"NEHUDShowBattery" on:NEHUDShowBattery()]];
    [stack addArrangedSubview:[self switchRow:@"音量" key:@"NEHUDShowVolume" on:NEHUDShowVolume()]];
    [stack addArrangedSubview:[self switchRow:@"骑行小人" key:@"NEHUDShowRider" on:NEHUDShowRider()]];

    [stack addArrangedSubview:[self sectionLabel:@"位置"]];
    UISegmentedControl *pos = [[UISegmentedControl alloc]
        initWithItems:@[ @"右下", @"左下", @"左上", @"右上" ]];
    pos.selectedSegmentIndex = NEHUDPosition();
    [pos addTarget:self action:@selector(positionChanged:)
        forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:pos];

    [stack addArrangedSubview:[self sectionLabel:@"字号"]];
    UISegmentedControl *fs = [[UISegmentedControl alloc]
        initWithItems:@[ @"小", @"中", @"大" ]];
    CGFloat refPt = NEHUDFontRefPt();
    fs.selectedSegmentIndex = (refPt == 16) ? 0 : ((refPt == 24) ? 2 : 1);
    [fs addTarget:self action:@selector(fontChanged:)
        forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:fs];

    [stack addArrangedSubview:[self switchRow:@"超速提醒" key:@"NEHUDSpeedAlert" on:NEHUDSpeedAlert()]];
    [stack addArrangedSubview:[self speedLimitRow]];

    UILabel *note = [UILabel new];
    note.text = @"提示：仪表右上角是车子自己的表盘区，HUD 放右上会被盖住一部分，一般用右下。";
    note.font = [UIFont systemFontOfSize:13];
    note.textColor = [UIColor secondaryLabelColor];
    note.numberOfLines = 0;
    [stack addArrangedSubview:note];
}

- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont boldSystemFontOfSize:15];
    return l;
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
    // 超速提醒或骑行小人开关变化时，立刻切换定位模式（连续定位开/关）
    if ([key isEqualToString:@"NEHUDSpeedAlert"] ||
        [key isEqualToString:@"NEHUDShowRider"]) NEApplySpeedLocationMode();
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

    os_log(gLog, "NinebotEnhance iOS 0.2.0 已加载（小胶囊 HUD：日期/天气/信号/音量/电量/来电/超速 + 像素骑行小人 + 车辆数据探测）");

    // 电量监听 + 定位 + 来电观察，全部在主队列 / 后台队列做，不阻塞加载
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        gLocDelegate = [NELocationDelegate new];
        gLocMgr = [CLLocationManager new];
        gLocMgr.delegate = gLocDelegate;
        NEApplySpeedLocationMode(); // 提醒开着 → 连续定位；关着 → 单次定位（只够天气用）

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
