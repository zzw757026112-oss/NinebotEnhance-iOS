// NinebotEnhance iOS v0.1.1 — 九号出行(cn.ninebot.segway) 投屏画面 HUD 叠加
//
// 拦截点：+[NBPixelBufferConverter pixelBufferFromCGImage:]（类方法）
//         +[NBPixelBufferConverter pixelBufferFromCGImage_Mjpeg:]（MJPEG 备用路径）
//         以及对应的实例方法版本（与参考实现一致，四者都挂）。
// 做法：不在编码器输入端整帧替换，而是把 App 自己的画面画到底层，
// 再把 HUD 叠加层（电量 / 日期时间 / 天气 / 来电提示）画在上面，
// 合成后交给原实现编码发送。App 自己的 H.264/RTP/RTCP/UDP 链路不动。
//
// HUD 数据全部来自本进程内可公开拿到的东西：UIDevice 电量、
// 系统时间、CoreLocation 定位 + Open-Meteo 天气（无 key，20 分钟缓存）、
// CallKit 来电状态。网络和定位一律在后台做，帧回调里只读缓存，永不阻塞。
//
// 开关：NSUserDefaults 写 NBProjectionOverride = NO 立刻恢复原生画面。
// 日志：os_log subsystem "com.user.ninebotenhance"，只打加载、钩点检查、
// 帧计数（#1 / 每 100 帧）、天气和来电状态变化。

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
#import <CoreLocation/CoreLocation.h>
#import <CallKit/CallKit.h>
#import <UIKit/UIKit.h>
#import <os/log.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

@interface NBPixelBufferConverter : NSObject
+ (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image;
+ (CVPixelBufferRef)pixelBufferFromCGImage_Mjpeg:(CGImageRef)image;
- (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image;
- (CVPixelBufferRef)pixelBufferFromCGImage_Mjpeg:(CGImageRef)image;
@end

static os_log_t gLog      = NULL;
static NSLock  *gLock     = nil;   // 叠加层缓存 + 帧计数
static NSLock  *gDataLock = nil;   // 天气 / 来电状态
static int      gFrames   = 0;
static int      gDumped   = 0;

@class NELocationDelegate;
static CLLocationManager *gLocMgr = nil;
static NELocationDelegate *gLocDelegate = nil;

static BOOL OverlayEnabled(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NBProjectionOverride"];
    return v ? [v boolValue] : YES;          // 置 NO 即恢复原生画面
}

// ---------------- 天气（Open-Meteo，免费、无 key）----------------
// 定位一次 → 后台拉天气 → 缓存 20 分钟。帧回调里只读缓存。

static NSString        *gWeatherString  = nil;   // 例如 @"18° 晴"，nil = 还没拿到
static CFAbsoluteTime   gWeatherAt      = 0;
static BOOL             gWeatherFetching = NO;
static BOOL             gHaveCoords     = NO;
static double           gLat = 0, gLon = 0;
static CFAbsoluteTime   gLastLocAttempt = 0;

static NSString *WeatherConditionForCode(int code) {
    switch (code) {
        case 0:             return @"晴";
        case 1: case 2:     return @"多云";
        case 3:             return @"阴";
        case 45: case 48:   return @"雾";
        case 51: case 53: case 55: return @"毛毛雨";
        case 61: case 63: case 65: return @"雨";
        case 71: case 73: case 75: return @"雪";
        case 80: case 81: case 82: return @"阵雨";
        case 95:            return @"雷雨";
        default:            return @"多云";
    }
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
            NSString *wx = [NSString stringWithFormat:@"%.0f° %@",
                            [temp doubleValue], WeatherConditionForCode([code intValue])];
            [gDataLock lock];
            gWeatherString = wx;
            gWeatherAt = CFAbsoluteTimeGetCurrent();
            gWeatherFetching = NO;
            [gDataLock unlock];
            os_log(gLog, "[WX] %{public}s", wx.UTF8String);
        } else {
            [gDataLock lock]; gWeatherFetching = NO; [gDataLock unlock];
        }
    }];
    [task resume];
}

// 满足条件就触发一次后台拉取（不阻塞调用方）。20 分钟内有缓存不拉。
static void RefreshWeatherIfNeeded(void) {
    [gDataLock lock];
    BOOL haveData = (gWeatherString != nil);
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
}
- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(NSError *)error {
    os_log(gLog, "[WX] 定位失败：%{public}s", error.localizedDescription.UTF8String);
}
@end

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

static NSString *HUDBatteryString(BOOL *chargingOut) {
    UIDevice *dev = [UIDevice currentDevice];
    float level = dev.batteryLevel;   // -1 表示未知
    if (level < 0) return nil;
    BOOL charging = (dev.batteryState == UIDeviceBatteryStateCharging ||
                     dev.batteryState == UIDeviceBatteryStateFull);
    if (chargingOut) *chargingOut = charging;
    // 充电时加闪电符号（系统字体回退渲染）
    return charging ? [NSString stringWithFormat:@"电量 %.0f%% ⚡", level * 100]
                    : [NSString stringWithFormat:@"电量 %.0f%%", level * 100];
}

// ---------------- 叠加层绘制 ----------------
// 参考坐标 848x480（右列 x 648–838，避开仪表自带表盘遮挡区 (640,44)–(842,254)）。
// 实际按输入帧尺寸换算：右列 x∈[0.76w, 0.99w]，三行文字在 y∈[0.58h, 0.80h]，
// 来电药丸在左下角。帧尺寸随仪表型号变（240x320 / 848x480），所以全部用相对坐标。

static CTFontRef HUDFont(CGFloat size, BOOL bold) {
    CTFontRef f = CTFontCreateWithName(
        CFSTR("PingFangSC-Semibold"), size, NULL);
    if (!f) f = CTFontCreateWithName(
        bold ? CFSTR("Helvetica-Bold") : CFSTR("Helvetica"), size, NULL);
    return f;
}

static CGFloat DrawRightLine(CGContextRef ctx, NSString *text, CGFloat yTop,
                             CGFloat fontSize, CGFloat xRight, CGFloat scale) {
    if (!text || text.length == 0) return 0;
    CTFontRef font = HUDFont(fontSize, YES);
    CGColorRef white = CGColorCreateGenericRGB(1, 1, 1, 1);
    const void *keys[] = { kCTFontAttributeName, kCTForegroundColorAttributeName };
    const void *vals[] = { font, white };
    CFDictionaryRef attrs = CFDictionaryCreate(NULL, keys, vals, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFAttributedStringRef astr = CFAttributedStringCreate(NULL,
        (__bridge CFStringRef)text, attrs);
    CTLineRef line = CTLineCreateWithAttributedString(astr);
    double ascent, descent, leading;
    double width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);

    CGFloat pad = 8 * scale;
    CGFloat bgX = xRight - (CGFloat)width - pad * 2;
    CGFloat bgY = yTop - pad * 0.5;
    CGFloat bgW = (CGFloat)width + pad * 2;
    CGFloat bgH = fontSize + pad;
    CGPathRef bg = CGPathCreateWithRoundedRect(
        CGRectMake(bgX, bgY, bgW, bgH), 6 * scale, 6 * scale, NULL);
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.55);
    CGContextAddPath(ctx, bg);
    CGContextFillPath(ctx);
    CGPathRelease(bg);

    CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    CGContextSetTextPosition(ctx, xRight - (CGFloat)width, yTop + fontSize);
    CTLineDraw(line, ctx);

    CFRelease(line); CFRelease(astr); CFRelease(attrs);
    CGColorRelease(white); CFRelease(font);
    return (CGFloat)width;
}

static CGImageRef RenderOverlay(size_t w, size_t h,
                                NSString *timeStr, NSString *battStr,
                                NSString *wxStr, BOOL callActive) {
    if (w == 0 || h == 0) return NULL;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (!ctx) return NULL;

    // 左上原点（文字才能正着画），与参考实现一致
    CGContextTranslateCTM(ctx, 0, (CGFloat)h);
    CGContextScaleCTM(ctx, 1, -1);

    CGFloat scale = (CGFloat)h / 480.0;              // 相对 848x480 的缩放
    CGFloat fontSize = MAX(14.0, h * 0.055);
    CGFloat xRight = w * 0.985;

    // 三行信息：时间 / 电量 / 天气，右对齐，y 在遮挡区下方
    DrawRightLine(ctx, timeStr, h * 0.585, fontSize, xRight, scale);
    DrawRightLine(ctx, battStr, h * 0.670, fontSize, xRight, scale);
    if (wxStr) DrawRightLine(ctx, wxStr, h * 0.755, fontSize, xRight, scale);

    // 来电：左下角红色药丸，白字“来电”
    if (callActive) {
        CGFloat pillW = w * 0.28, pillH = h * 0.10;
        CGFloat pillX = w * 0.02, pillY = h * 0.86;
        CGPathRef pill = CGPathCreateWithRoundedRect(
            CGRectMake(pillX, pillY, pillW, pillH), pillH / 2, pillH / 2, NULL);
        CGContextSetRGBFillColor(ctx, 0.85, 0.15, 0.15, 0.92);
        CGContextAddPath(ctx, pill);
        CGContextFillPath(ctx);
        CGPathRelease(pill);

        CTFontRef font = HUDFont(fontSize, YES);
        CGColorRef white = CGColorCreateGenericRGB(1, 1, 1, 1);
        const void *keys[] = { kCTFontAttributeName, kCTForegroundColorAttributeName };
        const void *vals[] = { font, white };
        CFDictionaryRef attrs = CFDictionaryCreate(NULL, keys, vals, 2,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFAttributedStringRef astr = CFAttributedStringCreate(NULL, CFSTR("来电"), attrs);
        CTLineRef line = CTLineCreateWithAttributedString(astr);
        double ascent, descent, leading;
        double tw = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
        CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
        CGContextSetTextPosition(ctx,
            pillX + (pillW - (CGFloat)tw) / 2,
            pillY + (pillH + fontSize) / 2 - fontSize * 0.15);
        CTLineDraw(line, ctx);
        CFRelease(line); CFRelease(astr); CFRelease(attrs);
        CGColorRelease(white); CFRelease(font);
    }

    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return img;
}

// 叠加层缓存：数据没变且 250ms 内，直接复用（与参考实现的帧缓存同款逻辑）。
// 注意：缓存的是叠加层，不是整帧——App 自己的画面每帧都在变，必须每帧重新合成。
// 快路径先看 250ms：没过期直接返回，避免每帧都建 NSDateFormatter。
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
    BOOL charging = NO;
    NSString *battStr = HUDBatteryString(&charging);
    [gDataLock lock];
    NSString *wxStr = gWeatherString;
    BOOL callActive = gCallActive;
    [gDataLock unlock];

    NSString *key = [NSString stringWithFormat:@"%@|%@|%@|%d",
                     timeStr, battStr ?: @"", wxStr ?: @"", callActive];
    if (!cache || cw != w || ch != h || ![key isEqualToString:cacheKey]) {
        if (cache) { CGImageRelease(cache); cache = NULL; }
        cache = RenderOverlay(w, h, timeStr, battStr, wxStr, callActive);
        cacheKey = key;
        cw = w; ch = h;
    }
    at = now;
    CGImageRef out = cache ? CGImageRetain(cache) : NULL;
    [gLock unlock];
    return out;
}

// 原画面 + 叠加层合成一张新图。原图必须原样通过（不加任何变换），
// 否则整帧在仪表上是颠倒的；只有叠加层在局部翻转里画。
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
    // 叠加层（RenderOverlay 返回的正向图）只在局部翻转里画，
    // 画完恢复，不影响原图。
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, 0, (CGFloat)h);
    CGContextScaleCTM(ctx, 1, -1);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), overlay);
    CGContextRestoreGState(ctx);
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

    os_log(gLog, "NinebotEnhance iOS 0.1.1 已加载（电量/日期时间/天气/来电叠加）");

    // 电量监听 + 定位 + 来电观察，全部在主队列 / 后台队列做，不阻塞加载
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        gLocDelegate = [NELocationDelegate new];
        gLocMgr = [CLLocationManager new];
        gLocMgr.delegate = gLocDelegate;
        gLocMgr.desiredAccuracy = kCLLocationAccuracyThreeKilometers;
        [gLocMgr requestLocation];
    });

    gCallDelegate = [NECallDelegate new];
    gCallObserver = [CXCallObserver new];
    [gCallObserver setDelegate:gCallDelegate
                         queue:dispatch_queue_create("com.user.ninebotenhance.calls",
                                                     DISPATCH_QUEUE_SERIAL)];
}
