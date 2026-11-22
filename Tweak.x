// NinebotEnhance iOS v0.3.9 — 九号出行(cn.ninebot.segway) 投屏画面 HUD 叠加
//
// v0.3.9 改动：三个只改显示、不改真数据的样子货（照搬安卓 ninebot-sign-lsp 的思路）：
//  1. 服务有效期自定义：hook -[UILabel setText:]，文本含“服务有效期”且带日期时，
//     只把日期部分换成用户在设置里填的值；没填（空）就不换，显示真实有效期。
//     设置里是开关 + 输入框，默认关（开关 key NEValidity9999，值 key NEValidityValue）。
//  2. 主页车辆图自定义：九号 App“设备”主页那张车图是远端加载的，hook 图片加载换成用户自选的图。
//     SDWebImage 存在就 hook UIImageView 的 sd_setImageWithURL:（+ 带 context 的全量变体），
//     按 URL 特征只拦车辆图；不存在就退回 hook -[UIImageView setImage:]，只在“设备”主页、
//     图片够大时换。用户选的图存沙盒 Documents/ne-vehicle.png（key NEVehicleImagePath），
//     没选图时不装钩子、不改动。
//  3. 主页背景图自定义：和车辆图同一套拦截；“设备”主页那张满屏背景图（车图下面那张）也能换，
//     存 Documents/ne-bg.png（key NEBackgroundImagePath）。背景/车辆只按满屏 view 的同级顺序分
//     （容器里最后一个满屏 UIImageView 是车辆层，之前的是背景层），不按名字/URL 关键字分
//     （关键字误伤卡片图和顶部背景，第六修已删）。设置里“更换车辆图 / 更换背景图”用 PHPicker 选图（不用相册权限，
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
// v0.3.9 再修（7d1117ef 构建实测：里程误换到续航/最近骑行，我的/服务页仍不变）：
//  ① 里程只换总里程：有 km 的数先排除附近含续航/最近骑行/骑行/剩余/续航里程/本次/单次，
//     再肯定附近（放宽范围）有“总里程”或“我的数据”，认不出就不换；相邻判定改双向
//     （续航在数字左侧、最近骑行在数字上方、总里程在数字左侧，原先只认下方/右侧，漏了）。
//  ② 页面显示时刷新：hook -[UIViewController viewDidAppear:]，每 VC 节流 1 秒，
//     设置页本身不刷；tab 懒加载，切过去才加载，显示时重算文字+图片。
//  ③ 等级/称号药丸可能是 UIButton 标题：再 hook -[UIButton setTitle:forState:]，
//     只换 Lv. 开头和“暂无称号”，刷新时按钮标题也重设。
// v0.3.9 第三修（d130e03e 构建实测：背景图启动闪主题、切 tab 回来就还原；
//  总里程 9999 仍在主页面、我的页 35624.6 还是真的；我的/服务页五项全不动）：
//  ① 背景图时序竞态的根因：图片钩子是“二选一”——有 SDWebImage 就只装 SD 钩子，
//     -[UIImageView setImage:] 永远不装。主题重载（SD 内部完成、imageNamed + setImage、
//     直接赋值）全走 setImage:，全绕过拦截；3 秒/切页刷新只改一次，App 随后一重载
//     就盖回去，所以“卡一下就还原”。改：setImage: 永远装（set-time 拦截的主力，
//     任何路径设图都在显示前被换掉），SD 钩子只做补充；tab 判定改走响应链找所属 VC
//     （NEIsDeviceTabSelected 跟 presented 链，设置 modal 盖着时永远 NO，是错的）。
//     另加 UIButton setBackgroundImage:forState: 钩子（主题若是按钮背景图）。
//  ② 里程只认我的页：“总里程”会命中主页面最近骑行卡片底下那行，肯定判定只留
//     “我的数据”（我的页卡片头），主页面不再换。
//  ③ 我的/服务页全不动的根因：刷新是“把同一文本重设一遍、指望 setText: 钩子
//     再算一次”。若该 label 的 setText: 没走 UILabel 的实现（子类重写、或文本
//     经别的路径设好），钩子根本不触发，刷新就是空转。改：刷新直接对每个 label
//     的当前文本跑一遍 NEFixedLabelString，算出就换，不依赖 setter 钩子；
//     相邻/放宽搜索从只看父/祖父两层改成沿祖先链上溯 4 层（卡片嵌套深也能找到
//     “我的数据”/“N币”）；再加一个 3 秒定时刷新（仅 App 在前台时），兜住布局
//     晚、数据晚到的情况。
// v0.3.9 诊断追加：匹配三轮靠猜层级都修不好，加界面诊断导出——
//  我的/服务/设备页每启动第一次显示时，把视图层级写到 Documents/ne-diag.txt
//  （每 label 记文本、窗口 frame、4 级祖先链，和匹配器会怎么换；每 imageView
//  记有没有图、图尺寸；每按钮记标题）。设置页“美化娱乐”组里加一行
//  “导出界面诊断”，点一下立刻导当前页。用户用 Filza 打开发回，照真实结构修。
//  只写界面文本，不写任何 token、密码、请求头；文件超 500KB 从头写。
// v0.3.9 第四修（诊断实测：车辆槽位显示背景图）：背景/车辆按 frame 尺寸分
//  是错的——诊断证明车辆图画在满屏透明画布上，frame 和背景图一模一样
//  （0,0,430,521），按尺寸分车辆永远被当成背景；而且用户自选背景是竖图，
//  按纵横比分也不稳。改：主信号是同级顺序——容器里最后一个 UIImageView
//  是车辆层（两个 UIViews 之后、UITableView 之前），之前的都是背景层；
//  顺序拿不到时才退到纵横比，且只认“近似正方形 → 背景”。setImage: 钩子、
//  SDWebImage URL 判定、图片强制刷新三处共用同一套分类（NEClassifyDeviceImage
//  / NEImageBySiblingOrder）；已是自定义图的放行，不来回换；换图后刷新
//  （缓存已清、当前图是旧自定义图）也能分对，因为顺序判定不依赖当前图片。
//  我的/服务页（React Native）的值仍不动，是另一回事，不在这次改动里。
// v0.3.9 第五修（用户视频实测：车辆图跑到仪表/骑行页背景上了）：
//  根因不是分类，是页面范围——NEViewIsOnDeviceTab 对“设备”tab 导航栈里
//  任何页面都返回 YES，仪表/骑行页是 push 出去的子页面，它的满屏背景
//  也被当成“车辆层”，自定义车辆图就错换到仪表页背景上；设备页自己的
//  车辆槽位反而没换上。改：图片替换只认“设备”tab 的根页面（导航栈第
//  一个 VC；嵌在根页面里的子 VC 也算），push 出去的子页面一律不换；
//  setImage: / SDWebImage / imageNamed / UIButton 背景图四处和强制刷新
//  全部走同一套根页面判定（NEViewIsOnDeviceRootPage）。另两处顺带加固：
//  存的绝对路径可能失效（App 重装/更新后沙盒 UUID 变了），读不到就回退
//  到当前 Documents 目录下的同名文件并把存的路径修好；刷新换图时把
//  layer.contents 也同步成自定义图（App 若绕开 setImage: 直接写了图层
//  内容，只换 iv.image 显示换不上）。
// v0.3.9 第六修（用户视频实测：主页往下滚，“新手任务”三个卡片全被换成
//  车辆图；连设备页顶部背景也显示车辆图而非背景图）：
//  根因不是页面范围（卡片就在根页面上），是分类根本没看 view 有多大——
//  ① NEClassifyDeviceImage 只按图片像素尺寸跳过小图（w<200 && h<200），
//     卡片缩略图的素材本身是高清图，根本拦不住；近似正方形 fallback
//     （ratio 0.98–1.02 → 背景）更是没有任何 view 尺寸 gate，任何小 view
//     上的近似正方形素材都会被换；② SDWebImage 按 URL 关键字分背景/车辆
//     （vehicle/car/bike…），新手任务卡片的图 URL 里就有这类词，直接换成
//     车辆图；③ +[UIImage imageNamed:] 按名字关键字换，且它根本没有 view
//     可查，只能靠“根页面正显示”这个全局条件放行——根页面显示时，任何
//     名字带 vehicle/car/bike 的素材（卡片图、甚至顶部背景图）全被换成
//     车辆图，这就是顶部背景显示车辆图的根因。改：换图只允许满屏大视图
//     （view 宽 ≥ 屏宽 0.9 且高 ≥ 屏高 0.5），这道 gate 放到分类器最前面，
//     setImage: / SDWebImage / 强制刷新三处共用；SDWebImage 不再按 URL
//     关键字分，一律走同级顺序；imageNamed 钩子整个删掉（它没有 view，
//     永远分不清卡片和背景；本地 asset 走 setImage: 时一样能被满屏 gate
//     拦住，不丢覆盖）；同级顺序只在满屏 view 之间找“最后一个”，且父容
//     器里满屏 view 不足 2 个时不判、等刷新时再判（图先设、view 后加的
//     竞态会把背景 view 暂时当成“最后一个”错换成车辆图）。
// v0.3.9 第七修（用户实测 cf438018：RN 数字、背景、卡片、仪表页全好了，
//  唯独车辆图一直没变化）：新诊断（ne-diag-34ae638d.txt，七次设备导出）
//  证明“最后一个是车辆”是错的——三张满屏图里只有中间那张是可见的
//  （750x908 是用户当时选的狗车辆图，当时误以为是狗+车画在一张图里的主题合成图，
//  第十一修已纠正），第一张和第三张一直是 hidden；
//  旧规则把车辆图换到隐藏的第三张（375x385）上，用户永远看不到，
//  而真正显示的中间那张永远换不上。改：主信号改成“可见”——同级满屏 view
//  里唯一可见的那张就是用户看到的车辆/主图 → 车辆图，其余（隐藏的背景层）
//  → 背景图；一张都不可见时不判（等它显示出来再判）。另三处加固：① key
//  为空但 Documents 里文件还在时直接用文件（key 可能丢了）并自愈 key，
//  启动时 gHas 标志也按文件存在性补；② 刷新时 iv.image 已是自定义图也
//  要重查 layer.contents（App 可能把它覆盖回主题图）；③ 新装 CALayer
//  setContents: 钩子（只对设备根页面满屏 UIImageView 的图层生效），
//  App 绕开 setImage: 直接写图层内容时在写入时就换掉。
// v0.3.9 第八修（用户实测 cf438018：主页自定义背景图位置不对，偏上了）：
//  根因是纵横比——用户背景图是竖图（2160x4790，纵横比 0.45），设备页满屏
//  view 是 430x521（纵横比 0.825）。插件只换 image 不碰 contentMode，
//  App 的背景 view 是 scaleAspectFill：原图按宽放大到 430 后高 953pt，
//  view 只有 521pt，上下各被居中裁掉 ~23%——绿块顶部的白边+圆角被切掉、
//  卡通底部（Woodstock/足球/脚）被切掉，用户看就是“偏上了”。实测对得上：
//  居中裁切时绿块底边应在 view y≈139pt，截图 IMG_3925 里正是 141pt。
//  改：背景图不直接设原图，按 view 纵横比从顶部裁一张显示版（只裁不拉伸，
//  CGImage 像素裁，不重采样）：绿块带白边+圆角完整留在画面顶部，狗头/主角
//  也在画面里，满宽显示；卡通最底部本来就放不进 430x521（图比 view 高太多，
//  填满宽度必然要裁掉一部分），优先保顶部。显示版按（原图对象 + view 尺寸）
//  缓存，换图时 NEClearImageCache 一起清；“已是自定义图”的放行判定三处
//  （setImage 分类、CALayer setContents、刷新同步）都认显示版。车辆图不动。
// v0.3.9 第九修（用户实测 c5731585：设置页两行都显示“战神”）：
//  根因不是行标题写错——源码里标题本来就是“等级”“连续签到天数”。
//  是 UILabel setText: 钩子把设置页自己的 label 也改了：称号的“分开 label”
//  规则（短文本 + 不含“称号” + 不是数字 + 附近有“称号” label 就换成称号值）
//  在设置页里误触发——“等级”“连续签到天数”两行紧挨着“称号”行（行高 32 +
//  间距 18 = 50px，在相邻判定 60px 内），开关一切换就触发强制刷新重算，
//  两行都被换成称号值“战神”。改：NEFixedLabelString 开头直接放行我们自己
//  设置页（NEHUDSettingsVC）的 label（响应链上溯找所属 VC）；同时按用户
//  要求把两行标题改成“等级（1-9）”（等级最高 9 级，超过 9 不显示）和
//  “签到天数”。只改标题 + 钩子放行，key/值/开关行为一律不动。
//  另：用户报“改车辆图却换了背景图”——静态核查：选图接线、图片加载缓存、
//  分类三处全对（kind 0 → ne-vehicle.png/NEVehicleImagePath，kind 1 →
//  ne-bg.png/NEBackgroundImagePath；分类 veh 给最后一个可见满屏 view，
//  其余给 bg），代码里没有车辆/背景写反的地方；应是运行时的三张 view
//  可见状态在选图瞬间与诊断快照不同，需用户选完车辆图后立刻导一份新
//  ne-diag.txt（看三张图的 hidden 状态和图尺寸）+ 设备页截图才能定。
// v0.3.9 第十修（用户实测 + 新诊断 ne-diag-807ae3b2.txt 十一次设备导出，
//  2026-11-22 17:52）：根因是运行时的三处，不是静态接线——
//  ① 分类误判：第七修按“可见”分，主题重载瞬间可见状态是过渡态，14:56
//  那次导出里可见的第二张（车辆主图）被当成背景换上了 2160x4790 背景图，
//  就是用户说的“改车辆图却换了背景图”。改：三张满屏图时直接认中间一张
//  是车辆（十一次导出顺序恒定：隐藏背景层 / 可见车辆主图 / 隐藏阴影层），
//  完全不看可见状态；不是三张时退回“最后一个可见是车辆”的老规则。
//  ② 选完图不刷新：NEForceRefreshImages 要求当前选中是设备 tab 才刷，
//  但设置页是从“我的”tab 弹出的 modal，选完图时选中是“我的”，
//  savePickedImage 里的“选完立刻刷新”直接 return、白跑了。改：不再
//  要求选中设备 tab，设备根页面 view 一旦加载就常驻层级，在哪个 tab
//  都能刷（仍只刷 rootPage.view，仪表/骑行子页面不受影响）。
//  ③ 没有持续重断言：车辆主图只在创建时设一次（那时 view 还没挂载/布局，
//  分类返回 nil、钩子拦不到），之后 App 再也不重设，所以旧规则下第二张换不上用户车辆图；而 App 会在主题重载时主动重写这些 view（第一张图的
//  尺寸每次导出都在变就是证据），一次性刷新拦不住事后重写。改：3 秒定时
//  器跑一次 NEForceRefreshImages（幂等，已是自定义图的不动），选完图后
//  1 秒再补刷一次。背景层（第一张，隐藏）仍换背景图，阴影层（第三张，
//  隐藏）不动逻辑；卡片/仪表页/标题/RN/有效期/HUD 开关一律不动。
// （第十一修纠正：第十修“中间一张是车辆”是错的，三张全是背景层；见下。）
// v0.3.9 第十一修（用户实测 f7e1e35b + 新诊断 ne-diag-11500666.txt，
// 2026-11-22 18:16）：第十修的模型是错的——三张满屏图全是主题/背景层，
// 中间可见那张是主题画层，不是车辆。证据：18:16:37 导出，中间那张被换成
// 用户车辆图（蜘蛛侠 1080x1927）后，用户看到的是蜘蛛侠铺满整块背景区、
// 踏板车本体根本没变；750x908 是用户自己上传的狗车辆图（不是默认主题图，
// 狗不见了是因为用户把它换成了蜘蛛侠，是预期的），1892x4088 是动漫女孩
// 车辆图。用户说的“车辆”就是踏板车本体那个小图，“背景”是它后面整块
// 主题画区。改：① 满屏 view 一律只换背景图（NEImageBySiblingOrder 不再
// 分车辆，NEIsViewEffectivelyVisible 删掉）；② 车辆图改换踏板车本体——
// 它是 UITableView 里（header 或首 cell）一个单独的非满屏 UIImageView，
// 按“view 够大 + 图片够大 + 落在顶部图区”识别（NEVehicleImageForScooterView），
// set-time 钩子、CALayer 钩子、3 秒定时刷新三处共用同一分类器；
// ③ 诊断递归深度 8 → 12 层（UITableView 本身已在第 8 层，
// 它的 header/cell 一直被截掉，踏板车视图从没出现在导出里）。
// 1290x1562（18:08:27 一三张）约是主题画 @3x（430x3=1290），
// 不是插件的背景裁切输出（ne-bg.png 裁后是 2160x2617pt）。
// 标题守卫、背景裁切、RN、有效期、HUD 开关、卡片/仪表页范围一律不动。
// v0.3.9 第十二修（用户实测 60a60261 + 视频，2026-11-22 19:57）：换车辆图
// 已修好（踏板车本体能换），但点“恢复原图”后设备页还显示自定义图，只有
// 划掉 App 重开才还原。根因：恢复只删文件/清 key/清缓存，从没把原图设回去；
// NEForceRefreshImages 还在“没自定义图”时直接 return，刷新只会贴自定义图，
// 不会贴回原图。改：① 换图时把 App 的原图按（车辆/背景）暂存到 view 上
// （associated object，@[原图, 当时换上去的自定义图]；SD 直下原 URL 的
// 改存原 URL）；② 恢复时 clearImageTapped 立刻刷一次 + 1 秒再刷一次，
// NEForceRefreshImages 不再因“没自定义图”跳过，刷新走过、当前图还是我们
// 那张旧自定义图时就把暂存的原图设回去（按种类 + 几何再验，防止 cell 复用
// 还错 view；App 已自己换了别的图时只清过期暂存、不动当前图）；③ 设置页
// “重启九号 App”的提示删掉，恢复现在是立即生效。UIButton 背景图那条路没
// 暂存（只见过 UIImageView 的满屏图），恢复不到它的话再补。
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
//   NEHUDShowBattery / NEHUDShowVolume / NEHUDShowSlot（bool，默认 NO；
//   NEHUDSpeedAlert 同样默认 NO。开过一次后存 NSUserDefaults，下次启动还保持）
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
static dispatch_source_t gRefreshTimer = nil; // v0.3.9 第三修：每 3 秒补刷一次文字+图片

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
    return v ? [v boolValue] : NO;
}
static BOOL NEHUDShowWeather(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDShowWeather"];
    return v ? [v boolValue] : NO;
}
static BOOL NEHUDShowSignal(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDShowSignal"];
    return v ? [v boolValue] : NO;
}
static BOOL NEHUDShowBattery(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDShowBattery"];
    return v ? [v boolValue] : NO;
}
static BOOL NEHUDShowVolume(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDShowVolume"];
    return v ? [v boolValue] : NO;
}
// 翻页时钟开关（v0.3.6，老虎机改成翻页时钟；默认 NO；内部 key NEHUDShowSlot 不变）
static BOOL NEHUDShowSlot(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDShowSlot"];
    return v ? [v boolValue] : NO;
}
static BOOL NEHUDSpeedAlert(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"NEHUDSpeedAlert"];
    return v ? [v boolValue] : NO;
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
static NSString *gValidityValue = nil; // 用户填的自定义有效期；空 = 显示真实有效期

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
    gValidityValue = [d stringForKey:@"NEValidityValue"];
}

// 服务有效期实际要显示的值：用户填的日期（去空白）；没填返回 nil，
// 调用处就不替换，App 显示真实有效期。9999.12.31 不再是默认值。
static NSString *NEValidityDisplayValue(void) {
    NSString *v = [gValidityValue stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return v.length ? v : nil;
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

// 描述在数字正下方或正上方相邻：上沿在数字下沿附近（-4~+60），或下沿在数字上沿附近；横向重叠过半。
// 双向：续航在数字左侧、最近骑行在数字上方、总里程在数字左侧，这些都要能认出来。
static BOOL NEFramesVerticallyAdjacent(CGRect lf, CGRect cf) {
    CGFloat top = CGRectGetMinY(cf), bottom = CGRectGetMaxY(lf);
    CGFloat topL = CGRectGetMinY(lf), bottomC = CGRectGetMaxY(cf);
    BOOL below = (top >= bottom - 4 && top <= bottom + 60);
    BOOL above = (bottomC >= topL - 60 && bottomC <= topL + 4);
    if (!below && !above) return NO;
    CGFloat ox = MIN(CGRectGetMaxX(cf), CGRectGetMaxX(lf))
               - MAX(CGRectGetMinX(cf), CGRectGetMinX(lf));
    CGFloat w = MIN(CGRectGetWidth(cf), CGRectGetWidth(lf));
    return w > 0 && ox > w * 0.5;
}

// 描述在数字右侧或左侧相邻：左沿在数字右沿附近（-4~+40），或右沿在数字左沿附近；纵向重叠过半
static BOOL NEFramesHorizontallyAdjacent(CGRect lf, CGRect cf) {
    CGFloat left = CGRectGetMinX(cf), right = CGRectGetMaxX(lf);
    CGFloat leftL = CGRectGetMinX(lf), rightC = CGRectGetMaxX(cf);
    BOOL rightSide = (left >= right - 4 && left <= right + 40);
    BOOL leftSide = (rightC >= leftL - 40 && rightC <= leftL + 4);
    if (!rightSide && !leftSide) return NO;
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

// 从 label 往上沿祖先链上溯（最多 4 层），收集每层祖先子树里的 label
// （排除 label 自己所在的子树）。卡片嵌套深时描述 label 可能不在父/祖父
// 层，只看两层会漏；几何判定（相邻/放宽窗口）本身已足够严格，
// 多搜几层不会误认，只会让深嵌套的卡片也能配对。
static void NECollectNearbyLabels(UILabel *label, NSMutableArray<UILabel *> *out) {
    UIView *child = label;
    UIView *anc = label.superview;
    int levels = 0;
    while (anc && levels < 4) {
        NECollectLabelsExcept(anc, child, out);
        child = anc;
        anc = anc.superview;
        levels++;
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
    NECollectNearbyLabels(label, cands);
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

// 在 label 附近（放宽范围）找含关键字的 label：同一容器内，候选框与 label 框
// 上下 120px / 左右 300px 内相交。用于里程的“总里程/我的数据”肯定判定——
// “我的数据”卡片头离数值可能比严格相邻远一点；“总里程”在数值左侧同一行。
static BOOL NENearbyLabelContainsWide(UILabel *label, NSString *keyword) {
    if (!label || !keyword.length) return NO;
    UIWindow *w = NEKeyWindow();
    if (!w) return NO;
    CGRect lf = NEFrameInWindow(label, w);
    if (CGRectIsEmpty(lf)) return NO;
    CGRect expanded = CGRectInset(lf, -300, -120);
    NSMutableArray<UILabel *> *cands = [NSMutableArray array];
    NECollectNearbyLabels(label, cands);
    for (UILabel *cand in cands) {
        CGRect cf = NEFrameInWindow(cand, w);
        if (CGRectIsEmpty(cf)) continue;
        if (!CGRectIntersectsRect(expanded, cf)) continue;
        NSString *t = NEPlainTextOfLabel(cand);
        if (t.length && [t rangeOfString:keyword].location != NSNotFound) return YES;
    }
    return NO;
}

// 这个 label 是不是我们自己的设置页（NEHUDSettingsVC）里的：
// 沿响应链上溯找所属 VC，类名含 NEHUDSettings 就是。设置页的 label
// 是插件自己写的文字，钩子不该改——设置页的自定义项 label（“等级（1-9）”
// “签到天数”等）就在“称号”行旁边，称号的“分开 label”规则会把它们
// 当成要换的称号值（战神），设置页两行都显示“战神”就是这么来的。
static BOOL NEIsLabelInOwnSettingsPage(UILabel *label) {
    if (!label) return NO;
    UIResponder *r = label.nextResponder;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) {
            NSString *cls = NSStringFromClass([r class]);
            return [cls rangeOfString:@"NEHUDSettings"].location != NSNotFound;
        }
        r = r.nextResponder;
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
    // 我们自己的设置页的 label 不碰（见上文 NEIsLabelInOwnSettingsPage）
    if (NEIsLabelInOwnSettingsPage(label)) return nil;
    // 1. 服务有效期（自定义值；没填就不换，显示真实有效期）
    NSString *validityValue = NEValidityDisplayValue();
    if (gValidity9999 && validityValue.length > 0) {
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
                    return [text stringByReplacingCharactersInRange:m withString:validityValue];
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
                return validityValue;
            }
        }
    }
    // 纯数字才走“分开 label”匹配；先算一次，后面复用
    BOOL isNum = NEIsPureNumberString(text);
    // 2. 总里程 — 只换我的页的总里程，绝不换续航/最近骑行、绝不换主页面。
    // 肯定判定只认“我的数据”（我的页卡片头）；“总里程”会命中主页面最近骑行
    // 卡片底下那行，不能当肯定依据。有 km 的数才可能是里程：先排除（文本自己
    // 或附近 label 含续航/最近骑行/骑行/剩余/续航里程/本次/单次），再肯定
    // （附近放宽范围有“我的数据”）。认不出是我的页总里程就不换。
    if (gMileage && gMileageValue.length > 0) {
        BOOL sameKm = NO;
        if ([text rangeOfString:@"km"].location != NSNotFound) {
            static NSRegularExpression *sMileRe = nil;
            static dispatch_once_t sMileOnce;
            dispatch_once(&sMileOnce, ^{
                sMileRe = [NSRegularExpression regularExpressionWithPattern:
                           @"^\\s*[\\d,]+(\\.\\d+)?\\s*km\\s*$"
                           options:0 error:nil];
            });
            sameKm = sMileRe &&
                [sMileRe numberOfMatchesInString:text options:0
                                           range:NSMakeRange(0, text.length)] > 0;
        }
        // 分开 label：纯数字 + 旁边有“km”（不是 km/h）；旁边有 % 就是电量，不换
        BOOL sepKm = NO;
        NSArray<UILabel *> *adj = nil;
        if (!sameKm && isNum && !NEHasAdjacentPercentLabel(label)) {
            adj = NEAdjacentLabels(label);
            for (UILabel *cand in adj) {
                NSString *kt = NEPlainTextOfLabel(cand);
                if (!kt.length || [kt rangeOfString:@"km"].location == NSNotFound) continue;
                if ([kt rangeOfString:@"km/h"].location != NSNotFound) continue;
                sepKm = YES;
                break;
            }
        }
        if (sameKm || sepKm) {
            static NSArray<NSString *> *sMileSkip = nil;
            static dispatch_once_t sMileSkipOnce;
            dispatch_once(&sMileSkipOnce, ^{
                sMileSkip = @[@"续航", @"最近骑行", @"骑行", @"剩余", @"续航里程", @"本次", @"单次"];
            });
            BOOL skip = NO;
            for (NSString *kw in sMileSkip) {
                if ([text rangeOfString:kw].location != NSNotFound) { skip = YES; break; }
            }
            if (!skip) {
                if (!adj) adj = NEAdjacentLabels(label);
                for (UILabel *cand in adj) {
                    NSString *kt = NEPlainTextOfLabel(cand);
                    if (!kt.length) continue;
                    for (NSString *kw in sMileSkip) {
                        if ([kt rangeOfString:kw].location != NSNotFound) { skip = YES; break; }
                    }
                    if (skip) break;
                }
            }
            BOOL isTotal = NO;
            if (!skip) {
                isTotal = NENearbyLabelContainsWide(label, @"我的数据");
            }
            if (!skip && isTotal) {
                if (fieldOut) *fieldOut = @"NEMileage";
                if (separateOut) *separateOut = sepKm;
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

// 按钮标题钩子：等级/称号那两个药丸可能是 UIButton 的标题（走 setTitle:forState:，
// 不是 UILabel setText:），label 钩子拦不到。只换 Lv. 开头和“暂无称号”这两个，
// 别的按钮标题一概不碰。
static NSString *NEFixedButtonTitleForField(NSString *title, NSString **fieldOut) {
    if (fieldOut) *fieldOut = nil;
    if (!title.length) return nil;
    if (gLevel && gLevelValue.length > 0 &&
        ([title hasPrefix:@"Lv."] || [title hasPrefix:@"lv."])) {
        if (fieldOut) *fieldOut = @"NELevel";
        return gLevelValue;
    }
    if (gTitle && gTitleValue.length > 0 &&
        [title isEqualToString:@"暂无称号"]) {
        if (fieldOut) *fieldOut = @"NETitle";
        return gTitleValue;
    }
    return nil;
}

static void (*orig_UIButton_setTitle)(id, SEL, NSString *, UIControlState);
static void NE_UIButton_setTitle(id self, SEL _cmd, NSString *title, UIControlState state) {
    if (title.length > 0 && [self isKindOfClass:[UIButton class]]) {
        NSString *field = nil;
        NSString *fixed = NEFixedButtonTitleForField(title, &field);
        if (fixed) {
            if (field.length)
                objc_setAssociatedObject(self, &NEAppliedFieldKey, field,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            orig_UIButton_setTitle(self, _cmd, fixed, state);
            return;
        }
    }
    orig_UIButton_setTitle(self, _cmd, title, state);
}

// 页面显示刷新钩子（viewDidAppear）的前置声明：定义在图片刷新函数之后，
// 那里 NEForceRefreshLabels/NEForceRefreshImages 才可见。
static void NEInstallAppearHookIfNeeded(void);
static void NEStartImageRefreshTimerIfNeeded(void);

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
    // 按钮标题钩子（等级/称号药丸可能是 UIButton）
    Class btnCls = objc_getClass("UIButton");
    if (btnCls && class_getInstanceMethod(btnCls, @selector(setTitle:forState:))) {
        MSHookMessageEx(btnCls, @selector(setTitle:forState:),
                        (IMP)NE_UIButton_setTitle, (IMP *)&orig_UIButton_setTitle);
        if (orig_UIButton_setTitle)
            os_log(gLog, "[LBL] UIButton setTitle:forState: 钩子已装");
        else
            os_log(gLog, "[LBL] UIButton setTitle:forState: 钩子安装失败（只用 label 钩子）");
    }
    gLabelHookInstalled = YES;
    os_log(gLog, "[LBL] UILabel setText 钩子已装");
    // 页面显示时也要刷新（tab 懒加载，切过去才加载）
    NEInstallAppearHookIfNeeded();
}

// ---------------- RN Fabric 文字覆盖（v0.3.9 RN 数字）----------------
// “我的”/“服务”页是 React Native（Fabric），文字不是 UILabel，setText 钩子
// 够不着。Fabric 段落 view（RCTParagraphComponentView；旧版自己画字，新版
// 画字移到子 view RCTParagraphTextView）有个纯 ObjC getter -attributedText
// （C++ 字符串转出来的；页面还在加载、_state 为 nil 时返回 nil）。没有
// setter，所以不改数据，只在 drawRect: 里拦下来：读到原文是目标值，就画
// 一份改过的 attributed string（属性原样保留）盖上去，不调原 draw；不是
// 目标值、或读不到原文，就走原实现。只改显示，不改真数据，不碰网络。
// 短字符串（"8"、"3"、"124"）只在“我的”/“服务” tab 里、且满足独立段落 /
// 复合句式 / 兄弟段落上下文时才换，宁可不换也不误伤。
// 前向声明：NEPageNameForVC、NEAppTabBarController 定义在后面。
static NSString *NEPageNameForVC(UIViewController *vc);
static UITabBarController *NEAppTabBarController(void);

// 编译器可见的 RN getter 声明（只有声明，没有实现，运行时无影响）。
// 注意：必须是类本身的 @interface 声明，不能写成分类 (NE)——分类要求
// 类的接口已先声明，否则报 cannot find interface declaration。
@interface RCTParagraphComponentView : UIView
- (NSAttributedString *)attributedText;
@end

// 这个 view 所在的 tab 页名（“我的”/“服务”/“设备”/…）。
// 沿响应链找到 VC，用 NEPageNameForVC 判；找不到 VC 时退回当前选中 tab 的标题。
static NSString *NEPageNameForView(UIView *v) {
    if (!v) return nil;
    UIResponder *r = v.nextResponder;
    UIViewController *vc = nil;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) { vc = (UIViewController *)r; break; }
        r = r.nextResponder;
    }
    if (vc) return NEPageNameForVC(vc);
    UITabBarController *tab = NEAppTabBarController();
    if (!tab) return nil;
    return tab.selectedViewController.tabBarItem.title;
}

// 收集兄弟段落的文本：同一父视图下的 RCTParagraphComponentView 的
// attributedText，再往上找一层父视图的兄弟段落。只读，不改。用于
// “分开 label”式匹配（N币旁边的数字、km 旁边的数字、Lv 旁边的数字、
// 连续签到旁边的数字、服务有效期旁边的日期）。最多两层、每层最多 40 条；
// drawRect 里只在需要上下文时才调，成本可控。
static NSArray<NSString *> *NERNSiblingParagraphTexts(UIView *view) {
    if (!view) return @[];
    Class paraCls = objc_getClass("RCTParagraphComponentView");
    if (!paraCls) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    UIView *cur = view;
    for (int level = 0; level < 2 && cur.superview && out.count < 40; level++) {
        UIView *parent = cur.superview;
        for (UIView *sub in parent.subviews) {
            if (sub == view) continue;
            if (![sub isKindOfClass:paraCls]) continue;
            @try {
                NSAttributedString *a = [(RCTParagraphComponentView *)sub attributedText];
                if (a.string.length) [out addObject:a.string];
            } @catch (...) {}
        }
        cur = parent;
    }
    return out;
}

static BOOL NERNSiblingContains(NSArray<NSString *> *sibs, NSString *kw) {
    if (!kw.length) return NO;
    for (NSString *s in sibs) {
        if (s.length && [s rangeOfString:kw].location != NSNotFound) return YES;
    }
    return NO;
}

// 值里可能带了单位（如用户填了 "9999 km"）：只换数字部分时先去掉值末尾的
// km 单位，避免画出 "9999 km km"。
static NSString *NERNDigitsOnlyValue(NSString *v) {
    if (!v.length) return v;
    NSString *t = [v stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([t.lowercaseString hasSuffix:@"km"]) {
        t = [t substringToIndex:t.length - 2];
        t = [t stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return t.length ? t : v;
}

// RN 段落文本替换：只按段落自己的文本 + 有限的兄弟段落上下文匹配。
// 返回替换后的完整字符串（nil = 不换；与原文相同也返回 nil）。
// 只在“我的”/“服务”页调用；开关关着、值为空时一律不换。
static NSString *NEFixedRNText(NSString *text, UIView *view, NSString *page, NSString **fieldOut) {
    if (fieldOut) *fieldOut = nil;
    if (!text.length || !view || !page.length) return nil;
    BOOL isMine = [page isEqualToString:@"我的"];
    BOOL isService = [page isEqualToString:@"服务"];
    if (!isMine && !isService) return nil;
    NSString *trim = [text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL isNum = NEIsPureNumberString(trim);
    NSArray<NSString *> *sibs = nil;
    BOOL sibsDone = NO;

    // 1. 服务有效期（自定义值；没填就不换，显示真实有效期；只在服务页）
    NSString *validityValue = NEValidityDisplayValue();
    if (gValidity9999 && isService && validityValue.length > 0) {
        static NSRegularExpression *sRNDateRe = nil;
        static dispatch_once_t sRNDateOnce;
        dispatch_once(&sRNDateOnce, ^{
            sRNDateRe = [NSRegularExpression regularExpressionWithPattern:
                         @"\\d{4}[.\\-/年]\\d{1,2}[.\\-/月]\\d{1,2}日?"
                         options:0 error:nil];
        });
        NSRange keyRange = [text rangeOfString:@"服务有效期"];
        if (keyRange.location != NSNotFound && sRNDateRe) {
            NSRange search = NSMakeRange(keyRange.location, text.length - keyRange.location);
            NSRange m = [sRNDateRe rangeOfFirstMatchInString:text options:0 range:search];
            if (m.location != NSNotFound) {
                if (fieldOut) *fieldOut = @"NEValidity9999";
                return [text stringByReplacingCharactersInRange:m withString:validityValue];
            }
        } else if (sRNDateRe) {
            // 分开段落：整段就是一个日期。只换已知的当前有效期，或兄弟段落
            // 里有“服务有效期”的日期（服务页上别的日期不碰）。
            NSRange m = [sRNDateRe rangeOfFirstMatchInString:trim options:0
                                                       range:NSMakeRange(0, trim.length)];
            if (m.location != NSNotFound && m.length == trim.length) {
                BOOL known = [trim isEqualToString:@"2027.01.07"];
                if (!known) {
                    if (!sibsDone) { sibs = NERNSiblingParagraphTexts(view); sibsDone = YES; }
                    known = NERNSiblingContains(sibs, @"服务有效期");
                }
                if (known) {
                    if (fieldOut) *fieldOut = @"NEValidity9999";
                    return validityValue;
                }
            }
        }
    }

    // 2. 总里程（只在我的页）
    if (gMileage && gMileageValue.length > 0 && isMine) {
        // 当前真值（distinctive）：只换数字部分，保留 " km" 等单位
        if ([text rangeOfString:@"35624.6"].location != NSNotFound) {
            if (fieldOut) *fieldOut = @"NEMileage";
            return [text stringByReplacingOccurrencesOfString:@"35624.6"
                                                   withString:NERNDigitsOnlyValue(gMileageValue)];
        }
        // 通用：整段就是“数字 km”，且数字够大（总里程，不是单次骑行）
        static NSRegularExpression *sRNKmRe = nil;
        static dispatch_once_t sRNKmOnce;
        dispatch_once(&sRNKmOnce, ^{
            sRNKmRe = [NSRegularExpression regularExpressionWithPattern:
                       @"^\\s*([\\d,]+(\\.\\d+)?)\\s*km\\s*$"
                       options:0 error:nil];
        });
        if (sRNKmRe) {
            NSTextCheckingResult *m = [sRNKmRe firstMatchInString:text options:0
                                                            range:NSMakeRange(0, text.length)];
            if (m && m.numberOfRanges > 1) {
                NSString *num = [text substringWithRange:[m rangeAtIndex:1]];
                double v = [[num stringByReplacingOccurrencesOfString:@"," withString:@""] doubleValue];
                if (v >= 1000) {
                    if (fieldOut) *fieldOut = @"NEMileage";
                    return [text stringByReplacingCharactersInRange:[m rangeAtIndex:1]
                                                         withString:NERNDigitsOnlyValue(gMileageValue)];
                }
            }
        }
        // 分开段落：纯数字 + 兄弟段落有 km（不是 km/h），数字够大，
        // 且自己/兄弟段落里没有续航/最近骑行等词（那是别的数）。
        if (isNum) {
            double v = [[trim stringByReplacingOccurrencesOfString:@"," withString:@""] doubleValue];
            if (v >= 1000) {
                if (!sibsDone) { sibs = NERNSiblingParagraphTexts(view); sibsDone = YES; }
                static NSArray<NSString *> *sRNMileSkip = nil;
                static dispatch_once_t sRNMileSkipOnce;
                dispatch_once(&sRNMileSkipOnce, ^{
                    sRNMileSkip = @[@"续航", @"最近骑行", @"骑行", @"剩余", @"续航里程", @"本次", @"单次", @"%"];
                });
                BOOL skip = NO;
                for (NSString *kw in sRNMileSkip) {
                    if ([text rangeOfString:kw].location != NSNotFound) { skip = YES; break; }
                }
                if (!skip) {
                    BOOL hasKm = NO, hasKmh = NO;
                    for (NSString *s in sibs) {
                        if (!s.length) continue;
                        if ([s rangeOfString:@"km/h"].location != NSNotFound) { hasKmh = YES; break; }
                        if ([s rangeOfString:@"km"].location != NSNotFound) hasKm = YES;
                        for (NSString *kw in sRNMileSkip) {
                            if ([s rangeOfString:kw].location != NSNotFound) { skip = YES; break; }
                        }
                        if (skip) break;
                    }
                    if (!skip && hasKm && !hasKmh) {
                        if (fieldOut) *fieldOut = @"NEMileage";
                        return gMileageValue;
                    }
                }
            }
        }
    }

    // 3. 等级：段落以 Lv. 开头，或短段落里含 Lv.<数字>
    if (gLevel && gLevelValue.length > 0) {
        NSString *lv = gLevelValue;
        if (![lv hasPrefix:@"Lv."] && ![lv hasPrefix:@"lv."])
            lv = [@"Lv." stringByAppendingString:lv];
        if ([text hasPrefix:@"Lv."] || [text hasPrefix:@"lv."]) {
            if (fieldOut) *fieldOut = @"NELevel";
            return lv;
        }
        if (text.length <= 12) {
            static NSRegularExpression *sRNLvRe = nil;
            static dispatch_once_t sRNLvOnce;
            dispatch_once(&sRNLvOnce, ^{
                sRNLvRe = [NSRegularExpression regularExpressionWithPattern:@"[Ll]v\\.\\d+"
                                                                    options:0 error:nil];
            });
            if (sRNLvRe) {
                NSRange m = [sRNLvRe rangeOfFirstMatchInString:text options:0
                                                       range:NSMakeRange(0, text.length)];
                if (m.location != NSNotFound) {
                    if (fieldOut) *fieldOut = @"NELevel";
                    return [text stringByReplacingCharactersInRange:m withString:lv];
                }
            }
        }
        // 分开段落：纯数字 + 兄弟段落有 Lv
        if (isNum) {
            if (!sibsDone) { sibs = NERNSiblingParagraphTexts(view); sibsDone = YES; }
            if (NERNSiblingContains(sibs, @"Lv") || NERNSiblingContains(sibs, @"lv")) {
                if (fieldOut) *fieldOut = @"NELevel";
                NSString *v = gLevelValue;
                if ([v hasPrefix:@"Lv."] || [v hasPrefix:@"lv."]) v = [v substringFromIndex:3];
                return v;
            }
        }
    }

    // 4. 称号
    if (gTitle && gTitleValue.length > 0 && [trim isEqualToString:@"暂无称号"]) {
        if (fieldOut) *fieldOut = @"NETitle";
        return gTitleValue;
    }

    // 5. 连续签到天数
    if (gSignDays && gSignDaysValue.length > 0) {
        if ([text rangeOfString:@"连续签到"].location != NSNotFound) {
            static NSRegularExpression *sRNDayRe = nil;
            static dispatch_once_t sRNDayOnce;
            dispatch_once(&sRNDayOnce, ^{
                sRNDayRe = [NSRegularExpression regularExpressionWithPattern:
                            @"连续签到\\D*(\\d+)\\D*天"
                            options:0 error:nil];
            });
            if (sRNDayRe) {
                NSTextCheckingResult *m = [sRNDayRe firstMatchInString:text options:0
                                                                range:NSMakeRange(0, text.length)];
                if (m && m.numberOfRanges > 1) {
                    if (fieldOut) *fieldOut = @"NESignDays";
                    return [text stringByReplacingCharactersInRange:[m rangeAtIndex:1]
                                                         withString:gSignDaysValue];
                }
            }
        }
        // 分开段落：纯数字 + 兄弟段落有“连续签到”
        if (isNum) {
            if (!sibsDone) { sibs = NERNSiblingParagraphTexts(view); sibsDone = YES; }
            if (NERNSiblingContains(sibs, @"连续签到")) {
                if (fieldOut) *fieldOut = @"NESignDays";
                return gSignDaysValue;
            }
        }
    }

    // 6. N币（只在我的页）：纯数字，且是已知的当前值，或兄弟段落有“N币”；
    // 兄弟段落有 % 就是电量，不换。认不出宁可不换。
    if (gNCoins && gNCoinsValue.length > 0 && isNum && isMine) {
        if (!sibsDone) { sibs = NERNSiblingParagraphTexts(view); sibsDone = YES; }
        BOOL hasPercent = NERNSiblingContains(sibs, @"%");
        if (!hasPercent &&
            ([trim isEqualToString:@"124"] || NERNSiblingContains(sibs, @"N币"))) {
            if (fieldOut) *fieldOut = @"NENCoins";
            return gNCoinsValue;
        }
    }
    return nil;
}

// drawRect 覆盖的共用逻辑：view 是正在画字的 view（段落 view 或其子文本 view）。
// 读原文，匹配到目标值就画改过的 string；否则返回 NO（调用方调原实现）。
// 段落 view 自己不画字时（新版 RN：画字在子文本 view 里）也返回 NO。
static BOOL NETryDrawRNTextOverride(UIView *view) {
    @try {
        if (!view) return NO;
        Class paraCls = objc_getClass("RCTParagraphComponentView");
        if (!paraCls) return NO;
        UIView *pv = view;
        if (![pv isKindOfClass:paraCls]) {
            while (pv && ![pv isKindOfClass:paraCls]) pv = pv.superview;
        }
        if (!pv) return NO;
        // 新版 RN：段落 view 有个 RCTParagraphTextView 子 view 负责画字，
        // 段落 view 自己不画——段落 view 的钩子直接放行，让子 view 的钩子处理，
        // 避免同一段文字画两次。
        Class textCls = objc_getClass("RCTParagraphTextView");
        if (textCls && pv == view) {
            for (UIView *sub in pv.subviews) {
                if ([sub isKindOfClass:textCls]) return NO;
            }
        }
        NSAttributedString *orig = nil;
        @try { orig = [(RCTParagraphComponentView *)pv attributedText]; } @catch (...) { orig = nil; }
        if (!orig || orig.length == 0) return NO;
        NSString *page = NEPageNameForView(view);
        if (!page) return NO;
        NSString *field = nil;
        NSString *fixed = NEFixedRNText(orig.string, pv, page, &field);
        if (!fixed || [fixed isEqualToString:orig.string]) return NO;
        NSAttributedString *m = NEAttributedStringByReplacing(orig, orig.string, fixed);
        if (!m) return NO;
        [m drawInRect:view.bounds];
        // 每字段只记一次命中日志（定位用，不刷屏）
        static NSMutableSet<NSString *> *sRNLogged = nil;
        static dispatch_once_t sRNLogOnce;
        dispatch_once(&sRNLogOnce, ^{ sRNLogged = [NSMutableSet set]; });
        if (field.length && ![sRNLogged containsObject:field]) {
            [sRNLogged addObject:field];
            os_log(gLog, "[RN] 段落文字已覆盖：%{public}@（%{public}@ 页）",
                   field, page);
        }
        return YES;
    } @catch (...) {
        return NO;
    }
}

static void (*orig_RCTParagraphComponentView_drawRect)(id, SEL, CGRect);
static void NE_RCTParagraphComponentView_drawRect(id self, SEL _cmd, CGRect rect) {
    if (!NETryDrawRNTextOverride((UIView *)self)) {
        if (orig_RCTParagraphComponentView_drawRect)
            orig_RCTParagraphComponentView_drawRect(self, _cmd, rect);
    }
}

static void (*orig_RCTParagraphTextView_drawRect)(id, SEL, CGRect);
static void NE_RCTParagraphTextView_drawRect(id self, SEL _cmd, CGRect rect) {
    if (!NETryDrawRNTextOverride((UIView *)self)) {
        if (orig_RCTParagraphTextView_drawRect)
            orig_RCTParagraphTextView_drawRect(self, _cmd, rect);
    }
}

// RN 段落 drawRect 钩子：两个类都可能存在时都装（各只对自己的类生效）；
// 段落 view 的钩子在新版 RN 里会自己让路给子文本 view，不会重画。
// 类/方法不存在只记日志绝不崩。
static BOOL gRNTextHookInstalled = NO;
static void NEInstallRNTextHookIfNeeded(void) {
    if (gRNTextHookInstalled) return;
    if (!gValidity9999 && !gNCoins && !gMileage && !gLevel && !gTitle && !gSignDays) return;
    BOOL any = NO;
    Class textCls = objc_getClass("RCTParagraphTextView");
    if (textCls && class_getInstanceMethod(textCls, @selector(drawRect:))) {
        MSHookMessageEx(textCls, @selector(drawRect:),
                        (IMP)NE_RCTParagraphTextView_drawRect,
                        (IMP *)&orig_RCTParagraphTextView_drawRect);
        if (orig_RCTParagraphTextView_drawRect) {
            any = YES;
            os_log(gLog, "[RN] RCTParagraphTextView drawRect: 钩子已装");
        } else {
            os_log(gLog, "[RN] RCTParagraphTextView drawRect: 钩子安装失败");
        }
    }
    Class paraCls = objc_getClass("RCTParagraphComponentView");
    if (paraCls && class_getInstanceMethod(paraCls, @selector(drawRect:))) {
        MSHookMessageEx(paraCls, @selector(drawRect:),
                        (IMP)NE_RCTParagraphComponentView_drawRect,
                        (IMP *)&orig_RCTParagraphComponentView_drawRect);
        if (orig_RCTParagraphComponentView_drawRect) {
            any = YES;
            os_log(gLog, "[RN] RCTParagraphComponentView drawRect: 钩子已装");
        } else {
            os_log(gLog, "[RN] RCTParagraphComponentView drawRect: 钩子安装失败");
        }
    }
    if (!textCls && !paraCls) os_log(gLog, "[RN] RCTParagraph* 类不存在，不装钩子");
    if (any) gRNTextHookInstalled = YES;
}

// 开关/值改了，已显示的 RN 段落不会自动重画，强制重画一次
// （原值/假值随开关走；没换的段落重画后还是原样）。
static void NEForceRedrawRNTextInView(UIView *view) {
    if (!view) return;
    Class paraCls = objc_getClass("RCTParagraphComponentView");
    Class textCls = objc_getClass("RCTParagraphTextView");
    for (UIView *sub in view.subviews) {
        if ((paraCls && [sub isKindOfClass:paraCls]) ||
            (textCls && [sub isKindOfClass:textCls])) {
            @try { [sub setNeedsDisplay]; } @catch (...) {}
        }
        NEForceRedrawRNTextInView(sub);
    }
}

static void NEForceRedrawRNText(void) {
    if (!gRNTextHookInstalled) return;
    UIWindow *w = NEKeyWindow();
    if (!w) return;
    NEForceRedrawRNTextInView(w);
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

// 强制刷新：把 view 子树里所有 UILabel 的当前文本直接算一遍匹配，算出就换。
// 之前是“把同一文本重设一遍、指望 setText: 钩子再算一次”——若该 label 的
// setText: 没走 UILabel 的实现（子类重写、或文本经别的路径设好），钩子根本
// 不触发，刷新就是空转，这就是我的/服务页全不动的根因。这里直接跑匹配，
// 不依赖 setter 钩子；算出的值用普通赋值写回去（子类重写 setText: 也会
// 显示算好的值，不影响）。
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
                NSString *cur = NEPlainTextOfLabel(label);
                if (cur.length) {
                    NSString *f2 = nil; BOOL sep2 = NO;
                    NSString *fixed = NEFixedLabelString(cur, label, &f2, &sep2);
                    if (fixed) {
                        if (f2.length) {
                            objc_setAssociatedObject(label, &NEAppliedFieldKey, f2,
                                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                            objc_setAssociatedObject(label, &NEAppliedSeparateKey, @(sep2),
                                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        }
                        NESetLabelPlainText(label, fixed);
                    }
                }
            } @catch (...) {}
        }
        // 按钮标题（等级/称号药丸可能是 UIButton）：按当前值重设，走 setTitle: 钩子
        if ([sub isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)sub;
            @try {
                NSString *field = objc_getAssociatedObject(btn, &NEAppliedFieldKey);
                NSString *val = field.length ? NEFieldCurrentValue(field, NO) : nil;
                if (!val) {
                    NSString *t = [btn titleForState:UIControlStateNormal];
                    if (t.length) val = NEFixedButtonTitleForField(t, NULL);
                }
                if (val) [btn setTitle:val forState:UIControlStateNormal];
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

// ---------------- 界面诊断（v0.3.9 诊断追加）----------------
// 匹配三轮靠猜层级都修不好：把当前页的视图层级写到 Documents/ne-diag.txt，
// 用户用 Filza 打开发回，照真实结构修匹配。只写 label 文本/frame/祖先链、
// imageView/按钮的基本信息，不写任何 token、密码、请求头。
// 前向声明：NEAppTabBarController 定义在后面（主页车辆图那节），这里先声明。
static UITabBarController *NEAppTabBarController(void);

static NSString *NEDiagFilePath(void) {
    NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                        NSUserDomainMask, YES).firstObject;
    if (!doc) return nil;
    return [doc stringByAppendingPathComponent:@"ne-diag.txt"];
}

// 追加写入；文件超过 500KB 就从头写，避免无限增长。
static void NEAppendDiagText(NSString *text) {
    if (!text.length) return;
    NSString *path = NEDiagFilePath();
    if (!path) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
    if (size > 500 * 1024) [fm removeItemAtPath:path error:nil];
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [data writeToFile:path atomically:YES];
    } else {
        @try {
            [fh seekToEndOfFile];
            [fh writeData:data];
            [fh closeFile];
        } @catch (...) {
            @try { [fh closeFile]; } @catch (...) {}
        }
    }
}

// 祖先链：最多 4 级父视图的类名（只看结构，不含任何隐私数据）
static NSString *NESuperviewChainString(UIView *v) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    UIView *p = v.superview;
    for (int i = 0; i < 4 && p; i++) {
        [parts addObject:NSStringFromClass([p class])];
        p = p.superview;
    }
    return [parts componentsJoinedByString:@" > "];
}

// 文本进文件前处理：换行转义、截断，避免一行爆掉
static NSString *NEDiagSanitize(NSString *s) {
    if (!s) return @"";
    NSString *t = [s stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    t = [t stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    if (t.length > 120) t = [[t substringToIndex:120] stringByAppendingString:@"…"];
    return t;
}

// 可见性标记：FailureView 常驻层级里、加载成功时只是 hidden，不记 hidden 就
// 会把它当成当前状态。self hidden 记 [hidden]，祖先 hidden 记 [hidden-by-ancestor]，
// alpha<1 也记出来。
static NSString *NEVisMarker(UIView *v) {
    NSMutableString *m = [NSMutableString string];
    if (v.hidden) {
        [m appendString:@" [hidden]"];
    } else {
        for (UIView *p = v.superview; p; p = p.superview) {
            if (p.hidden) { [m appendString:@" [hidden-by-ancestor]"]; break; }
        }
    }
    if (v.alpha < 0.99) [m appendFormat:@" [alpha=%.2f]", v.alpha];
    return m;
}

// 诊断里的 frame：相对被导出的根视图（页面自身坐标），不是窗口坐标。
// 自动导出时根视图就是全屏 tab 页，两者数值相同；手动导出时设置 modal 把
// 底下的 tab 页缩放到约 0.907，窗口坐标全是缩过的，页面自身坐标才是真实布局。
static CGRect NEDiagFrame(UIView *v, UIView *root) {
    if (!v || !root) return CGRectZero;
    @try { return [v convertRect:v.bounds toView:root]; } @catch (...) { return CGRectZero; }
}

// RN Fabric 文本（我的/服务页是 React Native，文字不是 UILabel）：
// 类名含 Paragraph/Text（如 RCTParagraphComponentView）。文字在组件的
// attributedString（KVC 可能读到 NSAttributedString）或 accessibilityLabel
// 里；读不到只记类名+frame，绝不崩。
static BOOL NEIsRNTextView(UIView *v) {
    NSString *cls = NSStringFromClass([v class]);
    return [cls rangeOfString:@"Paragraph"].location != NSNotFound ||
           [cls rangeOfString:@"Text"].location != NSNotFound;
}

static NSString *NERNTextOfView(UIView *v) {
    if (!v) return nil;
    @try {
        id as = [v valueForKey:@"attributedString"];
        if ([as isKindOfClass:[NSAttributedString class]]) return [(NSAttributedString *)as string];
        if ([as isKindOfClass:[NSString class]]) return (NSString *)as;
    } @catch (...) {}
    @try {
        id t = [v valueForKey:@"text"];
        if ([t isKindOfClass:[NSString class]]) return (NSString *)t;
        if ([t isKindOfClass:[NSAttributedString class]]) return [(NSAttributedString *)t string];
    } @catch (...) {}
    @try {
        id at = [v valueForKey:@"attributedText"];
        if ([at isKindOfClass:[NSAttributedString class]]) return [(NSAttributedString *)at string];
        if ([at isKindOfClass:[NSString class]]) return (NSString *)at;
    } @catch (...) {}
    @try {
        NSString *acc = v.accessibilityLabel;
        if (acc.length) return acc;
    } @catch (...) {}
    return nil;
}

// 递归走子树：深度最多 12 层、总视图数最多 2000，超了就停（文件别太大）。
// （第十一修：UITableView 本身已在第 8 层，8 层会把它的 header/cell 全截掉，
// 踏板车视图一直在表里，从没出现在导出里；提到 12 层。）
// 每个 label 多记一列“匹配器会怎么换”——直接跑 NEFixedLabelString（纯读，
// 无副作用），一眼看出哪个没认出来、为什么。RN 文本也跑同一匹配器
// （它只用 label.superview/frame 等 UIView 层面的东西，不调 UILabel 专有
// 方法，传 RN view 是安全的）；但分开 label 的描述在 RN 里也是 RN 文本、
// 不是 UILabel，所以 RN 的 verdict 只含同 label 规则，纯数字需看 frame 人工判断。
static void NEDumpDiagViewRec(UIView *v, UIView *root, NSMutableString *out,
                              int depth, int *count) {
    if (!v || depth > 12 || *count >= 2000) return;
    (*count)++;
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) [indent appendString:@"  "];
    CGRect f = NEDiagFrame(v, root);
    NSString *cls = NSStringFromClass([v class]);
    NSString *vis = NEVisMarker(v);
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)v;
        NSString *plain = NEPlainTextOfLabel(label);
        NSString *text = NEDiagSanitize(plain);
        NSString *field = nil; BOOL sep = NO;
        NSString *fixed = NEFixedLabelString(plain, label, &field, &sep);
        NSString *verdict;
        if (field.length) {
            NSString *fv = NEDiagSanitize(fixed);
            if (fv.length > 80) fv = [[fv substringToIndex:80] stringByAppendingString:@"…"];
            verdict = [NSString stringWithFormat:@"→ %@ = \"%@\"", field, fv];
        } else {
            verdict = @"(no change)";
        }
        [out appendFormat:@"%@%@ frame=(%.0f,%.0f,%.0f,%.0f)%@ text=\"%@\" %@\n",
            indent, cls, f.origin.x, f.origin.y, f.size.width, f.size.height, vis, text, verdict];
        NSString *chain = NESuperviewChainString(v);
        if (chain.length) [out appendFormat:@"%@  ancestors: %@\n", indent, chain];
    } else if (NEIsRNTextView(v)) {
        NSString *rnText = NERNTextOfView(v);
        if (rnText.length) {
            NSString *text = NEDiagSanitize(rnText);
            NSString *field = nil; BOOL sep = NO;
            NSString *fixed = NEFixedLabelString(rnText, (UILabel *)v, &field, &sep);
            NSString *verdict;
            if (field.length) {
                NSString *fv = NEDiagSanitize(fixed);
                if (fv.length > 80) fv = [[fv substringToIndex:80] stringByAppendingString:@"…"];
                verdict = [NSString stringWithFormat:@"→ %@ = \"%@\"", field, fv];
            } else {
                verdict = @"(no change)";
            }
            [out appendFormat:@"%@%@ [RN-text] frame=(%.0f,%.0f,%.0f,%.0f)%@ text=\"%@\" %@\n",
                indent, cls, f.origin.x, f.origin.y, f.size.width, f.size.height, vis, text, verdict];
        } else {
            [out appendFormat:@"%@%@ [RN-text] frame=(%.0f,%.0f,%.0f,%.0f)%@ (text unreadable)\n",
                indent, cls, f.origin.x, f.origin.y, f.size.width, f.size.height, vis];
        }
        NSString *chain = NESuperviewChainString(v);
        if (chain.length) [out appendFormat:@"%@  ancestors: %@\n", indent, chain];
    } else if ([v isKindOfClass:[UIImageView class]]) {
        UIImageView *iv = (UIImageView *)v;
        NSString *imgInfo = iv.image ?
            [NSString stringWithFormat:@"image %.0fx%.0f", iv.image.size.width, iv.image.size.height] :
            @"no image";
        [out appendFormat:@"%@%@ frame=(%.0f,%.0f,%.0f,%.0f)%@ %@\n",
            indent, cls, f.origin.x, f.origin.y, f.size.width, f.size.height, vis, imgInfo];
    } else if ([v isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)v;
        NSString *title = NEDiagSanitize([btn titleForState:UIControlStateNormal]);
        [out appendFormat:@"%@%@ frame=(%.0f,%.0f,%.0f,%.0f)%@ title=\"%@\"\n",
            indent, cls, f.origin.x, f.origin.y, f.size.width, f.size.height, vis, title];
    } else {
        [out appendFormat:@"%@%@ frame=(%.0f,%.0f,%.0f,%.0f)%@\n",
            indent, cls, f.origin.x, f.origin.y, f.size.width, f.size.height, vis];
    }
    for (UIView *sub in v.subviews) {
        NEDumpDiagViewRec(sub, root, out, depth + 1, count);
        if (*count >= 2000) return;
    }
}

static void NEDumpDiagForView(UIView *root, NSString *pageName) {
    if (!root) return;
    NSMutableString *out = [NSMutableString string];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    [out appendFormat:@"\n===== %@ %@ =====\n", pageName ?: @"?", [df stringFromDate:[NSDate date]]];
    [out appendString:@"(文本为当前显示值；→ 后面是匹配器会换成的字段/值，(no change) 表示不换；[hidden] 表示该视图被隐藏；[RN-text] 是 React Native 文本视图；RN 文本的 verdict 只含同 label 规则；frame 是页面自身坐标)\n"];
    int count = 0;
    @try {
        NEDumpDiagViewRec(root, root, out, 0, &count);
    } @catch (...) {
        [out appendString:@"(dump 中途异常，已截断)\n"];
    }
    [out appendFormat:@"----- 共 %d 个视图 -----\n", count];
    NEAppendDiagText(out);
    os_log(gLog, "[DIAG] 已导出 %{public}@，%d 个视图", pageName ?: @"?", count);
}

// 页面名：VC 所属的 tab 标题（设备/发现/商城/服务/我的）；不在 tab 里就用类名。
static NSString *NEPageNameForVC(UIViewController *vc) {
    if (!vc) return @"?";
    UITabBarController *tab = NEAppTabBarController();
    if (tab) {
        UIViewController *q = vc;
        while (q) {
            for (UIViewController *child in tab.viewControllers) {
                if (q == child) {
                    return child.tabBarItem.title.length ?
                        child.tabBarItem.title : NSStringFromClass([child class]);
                }
            }
            q = q.parentViewController;
        }
        UIViewController *r = vc.presentingViewController;
        while (r) {
            for (UIViewController *child in tab.viewControllers) {
                if (r == child) {
                    return child.tabBarItem.title.length ?
                        child.tabBarItem.title : NSStringFromClass([child class]);
                }
            }
            r = r.presentingViewController;
        }
    }
    return NSStringFromClass([vc class]);
}

// 每页每启动只导出一次（我的/服务/设备）。延迟 2 秒再导，等数据加载完；
// 导出时若页面已不在窗口就跳过（这次不记数，切回来会再导）。
static NSMutableSet<NSString *> *gDiagDumpedPages = nil;
static void NEDumpDiagIfNeededForVC(UIViewController *vc) {
    if (!vc || !vc.view) return;
    NSString *page = NEPageNameForVC(vc);
    if (![page isEqualToString:@"我的"] && ![page isEqualToString:@"服务"] &&
        ![page isEqualToString:@"设备"]) return;
    if (!gDiagDumpedPages) gDiagDumpedPages = [NSMutableSet set];
    if ([gDiagDumpedPages containsObject:page]) return;
    __weak UIViewController *weakVC = vc;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIViewController *strongVC = weakVC;
        if (!strongVC || !strongVC.view.window) return;
        if ([gDiagDumpedPages containsObject:page]) return;
        [gDiagDumpedPages addObject:page];
        NEDumpDiagForView(strongVC.view, page);
    });
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
// 背景图显示版缓存（第八修）：按 view 纵横比从顶部裁好的图 + 它是按哪张原图、
// 哪个 view 尺寸裁的。只裁不拉伸；换图时 NEClearImageCache 一起清。
static UIImage *gBgDisplayImage = nil;
static UIImage *gBgDisplaySource = nil;
static CGSize gBgDisplayForSize = {0, 0};

// 路径没变就用缓存；路径变了/文件没了就重读（失败返回 nil，不崩）
// 注意：cacheSlot/pathSlot 指向的是全局 strong 变量，形参必须标 __strong，
// 否则 ARC 默认 __autoreleasing 写回参数会报“passing address of non-local object”编译错。
// 存的绝对路径可能已失效（App 重装/更新后沙盒 UUID 变了）：读不到时回退到
// 当前 Documents 目录下的同名文件，找到就用它，并把存的路径修好。
static UIImage *NELoadCustomImage(NSString *path, NSString *defaultsKey, UIImage * __strong *cacheSlot, NSString * __strong *pathSlot) {
    if (!path.length) return nil;
    [gImageLock lock];
    UIImage *img = nil;
    if (*cacheSlot && [*pathSlot isEqualToString:path]) {
        img = *cacheSlot;
    } else {
        @try { img = [UIImage imageWithContentsOfFile:path]; } @catch (...) { img = nil; }
        if (!img) {
            NSString *name = path.lastPathComponent;
            NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                NSUserDomainMask, YES).firstObject;
            if (name.length && doc.length) {
                NSString *fb = [doc stringByAppendingPathComponent:name];
                if (![fb isEqualToString:path]) {
                    @try { img = [UIImage imageWithContentsOfFile:fb]; } @catch (...) { img = nil; }
                    if (img) {
                        path = fb;
                        if (defaultsKey.length)
                            [[NSUserDefaults standardUserDefaults] setObject:fb forKey:defaultsKey];
                    }
                }
            }
        }
        *cacheSlot = img;
        *pathSlot = img ? path : nil;
    }
    [gImageLock unlock];
    return img;
}
static UIImage *NECustomVehicleImage(void) {
    NSString *path = NEVehicleImagePath();
    if (!path.length) {
        // key 为空但文件可能还在（key 丢了/被清掉）：直接试 Documents/ne-vehicle.png，
        // 找到就用它并把 key 修好。恢复原图时会删文件，所以文件在 = 用户没恢复。
        NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                            NSUserDomainMask, YES).firstObject;
        if (doc.length) {
            NSString *fb = [doc stringByAppendingPathComponent:@"ne-vehicle.png"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:fb]) {
                path = fb;
                [[NSUserDefaults standardUserDefaults] setObject:fb forKey:@"NEVehicleImagePath"];
                gHasVehicleImage = YES;
            }
        }
    }
    return NELoadCustomImage(path, @"NEVehicleImagePath", &gVehicleImage, &gVehicleImageLoadedPath);
}
static UIImage *NECustomBackgroundImage(void) {
    NSString *path = NEBackgroundImagePath();
    if (!path.length) {
        // 同上：key 为空但文件还在时直接试 Documents/ne-bg.png。
        NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                            NSUserDomainMask, YES).firstObject;
        if (doc.length) {
            NSString *fb = [doc stringByAppendingPathComponent:@"ne-bg.png"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:fb]) {
                path = fb;
                [[NSUserDefaults standardUserDefaults] setObject:fb forKey:@"NEBackgroundImagePath"];
                gHasBgImage = YES;
            }
        }
    }
    return NELoadCustomImage(path, @"NEBackgroundImagePath", &gBgImage, &gBgImageLoadedPath);
}
static void NEClearImageCache(void) {
    [gImageLock lock];
    gVehicleImage = nil; gVehicleImageLoadedPath = nil;
    gBgImage = nil; gBgImageLoadedPath = nil;
    gBgDisplayImage = nil; gBgDisplaySource = nil; gBgDisplayForSize = CGSizeZero;
    [gImageLock unlock];
}

// v0.3.9 第十二修：恢复原图立即生效——还原用的原图暂存。换图时把 App 正在设
// 的那张原图按（车辆/背景）分别挂在 view 上（associated object，view 释放
// 时自动清），恢复原图时刷新走过就把原图设回去，不用等 App 重建 view /
// 重启。只在原图被换掉的那个 view 上暂存，卡片/图标不进。暂存的是
// @[原图, 当时换上去的自定义图] 这一对：恢复时只认“现在还显示着我们那张
// 自定义图”的 view，App 已经自己换了别的图时只清掉过期的暂存、不动当前图。
// SD 直下原 URL 的那条路没有原图可存，改存原 URL，恢复时重下一遍。
// 注意：暂存和图片缓存是两套东西——NEClearImageCache 只清 gVehicleImage /
// gBgImage，不清暂存（恢复正要用它）。
static const char NEVehicleOriginalImageKey = 0;
static const char NEBackgroundOriginalImageKey = 0;
static const char NEOriginalImageURLKey = 0;
static void NEStashOriginalImage(UIImageView *iv, UIImage *original, UIImage *custom, NSInteger kind) {
    if (!iv || !original || !custom) return;
    const char *key = (kind == 0) ? &NEVehicleOriginalImageKey : &NEBackgroundOriginalImageKey;
    objc_setAssociatedObject(iv, key, @[original, custom], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static NSArray *NEStashedOriginalPair(UIImageView *iv, NSInteger kind) {
    if (!iv) return nil;
    const char *key = (kind == 0) ? &NEVehicleOriginalImageKey : &NEBackgroundOriginalImageKey;
    id v = objc_getAssociatedObject(iv, key);
    return [v isKindOfClass:[NSArray class]] ? (NSArray *)v : nil;
}
static void NEClearStashedOriginalImage(UIImageView *iv, NSInteger kind) {
    if (!iv) return;
    const char *key = (kind == 0) ? &NEVehicleOriginalImageKey : &NEBackgroundOriginalImageKey;
    objc_setAssociatedObject(iv, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void NEStashOriginalURL(UIImageView *iv, NSURL *url) {
    if (!iv || !url) return;
    objc_setAssociatedObject(iv, &NEOriginalImageURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static NSURL *NEStashedOriginalURL(UIImageView *iv) {
    if (!iv) return nil;
    id v = objc_getAssociatedObject(iv, &NEOriginalImageURLKey);
    return [v isKindOfClass:[NSURL class]] ? (NSURL *)v : nil;
}
static void NEClearStashedOriginalURL(UIImageView *iv) {
    if (!iv) return;
    objc_setAssociatedObject(iv, &NEOriginalImageURLKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
// 换上自定义图之前，先把要被盖掉的那张图暂存为“原图”。currentImg 是 view
// 现在那张图（App 的图）；custom 是要换上的自定义图。例外：currentImg 如
// 果就是上一次换上去的旧自定义图（用户又选了张新图），那它不是原图——只
// 把暂存里的 applied 更新成新图，原图不动；如果这 view 的原图要靠 SD 重
// 下（暂存了原 URL），也不从 currentImg 里取。
static void NEStashOriginalBeforeReplace(UIImageView *iv, UIImage *currentImg, UIImage *custom, NSInteger kind) {
    if (!iv || !currentImg || !custom) return;
    NSArray *existing = NEStashedOriginalPair(iv, kind);
    if (existing.count == 2 && currentImg == existing[1]) {
        NEStashOriginalImage(iv, existing[0], custom, kind);
        return;
    }
    if (NEStashedOriginalURL(iv)) return;
    NEStashOriginalImage(iv, currentImg, custom, kind);
}

// 背景图显示版（第八修）：把用户竖图按目标 view 的纵横比从顶部裁成一张
// 显示版再设上去。只裁不拉伸（CGImage 像素裁，不重采样，不丢清晰度）。
// 原图比 view 更竖才裁（这时 aspectFill 会上下切）；纵横比已接近（±2%）
// 或原图更宽时直接返回原图。view 还没布局好（bounds 是 0）时也返回原图，
// 等刷新时 bounds 正常了再裁。按（原图对象 + view 尺寸）缓存，裁一次复用。
static UIImage *NEBackgroundDisplayImage(UIImage *rawBg, CGSize viewSize) {
    if (!rawBg || viewSize.width <= 0 || viewSize.height <= 0) return rawBg;
    CGFloat imgAspect = rawBg.size.width / rawBg.size.height;
    CGFloat viewAspect = viewSize.width / viewSize.height;
    if (imgAspect <= 0 || viewAspect <= 0) return rawBg;
    if (fabs(imgAspect - viewAspect) / viewAspect < 0.02 || imgAspect >= viewAspect) return rawBg;
    if (gBgDisplayImage && gBgDisplaySource == rawBg && CGSizeEqualToSize(gBgDisplayForSize, viewSize))
        return gBgDisplayImage;
    CGImageRef cg = rawBg.CGImage;
    if (!cg) return rawBg;
    size_t pxW = CGImageGetWidth(cg);
    size_t pxH = CGImageGetHeight(cg);
    if (pxW == 0 || pxH == 0) return rawBg;
    // 从顶部裁：裁后高度 = 宽 / viewAspect（像素）。绿块（原图顶部约 6%–37%）
    // 和狗头/主角留在画面里；卡通最底部放不进，必然被裁掉，优先保顶部。
    size_t cropH = (size_t)llround((double)pxW / (double)viewAspect);
    if (cropH == 0 || cropH >= pxH) return rawBg;
    CGImageRef sub = CGImageCreateWithImageInRect(cg, CGRectMake(0, 0, pxW, cropH));
    if (!sub) return rawBg;
    UIImage *out = [UIImage imageWithCGImage:sub scale:rawBg.scale orientation:rawBg.imageOrientation];
    CGImageRelease(sub);
    if (!out) return rawBg;
    gBgDisplayImage = out;
    gBgDisplaySource = rawBg;
    gBgDisplayForSize = viewSize;
    return out;
}

// 这个 view 是不是在“设备”tab 里（响应链上溯找所属 VC，再看它是不是设备 tab
// 的根页面或其子页面）。NEIsDeviceTabSelected 跟 presented 链，设置 modal 盖着
// 时永远返回 NO，用在 set-time 拦截里是错的——图正在被设的时候，modal 可能正
// 盖在上面。定义在 NEAppTabBarController 之后，这里先声明。
static BOOL NEViewIsOnDeviceTab(UIView *v);
// 只认“设备”tab 的根页面（不含 push 出去的子页面，如仪表/骑行页）：
// 换图管太宽会把自定义车辆图错换到仪表页背景上。定义在后面，这里先声明。
static BOOL NEViewIsOnDeviceRootPage(UIView *v);
// 踏板车识别要换算到根页面坐标，NEDeviceRootPageVC 定义在后面，这里先声明。
static UIViewController *NEDeviceRootPageVC(void);

// 背景 vs 车辆（第十一修，模型纠正）：设备页容器里三张满屏 UIImageView
// （0,0,430,521）全是主题/背景层，中间可见那张是主题画层——用户车辆图
// （狗 750x908、蜘蛛侠 1080x1927、动漫女孩 1892x4088）都曾落在这里，
// 用户看到的是它们铺满整块背景区、踏板车本体根本没变，这就是一直报的
// “改车辆图却换了背景图”。第十修“中间一张是车辆”是错的（750x908 不是
// 默认主题图，是用户自己上传的狗车辆图；狗不见了是因为用户把它换成了
// 蜘蛛侠，是预期的）。所以：满屏 view 一律只换背景图（按 view 纵横比裁
// 显示版，第八修），再也不分车辆；没有自定义背景时不换，主题画保持原样。
// 踏板车是 UITableView 里（header 或首 cell）一个单独的非满屏
// UIImageView，见 NEVehicleImageForScooterView；诊断递归深度上限 8 层、
// UITableView 本身已在第 8 层，所以它从没出现在导出里（第十一修把深度
// 提到 12）。返回要换成的自定义图；nil = 不换。

// 第十一修：踏板车视图识别。只认同时满足以下四条的非满屏 UIImageView：
// ① view 够大（宽 ≥150、高 ≥50，卡片缩略图/图标进不来）；
// ② 图片够大（宽 ≥150、高 ≥50）；③ 换算到设备根页面坐标后落在顶部图区
// （与 0..560pt 相交，卡片都在图区下面）；④ 有自定义车辆图。
// 未布局（bounds/换算 frame 为空）时不判，等 3 秒定时刷新布局好后再换。
// 只给车辆图（不裁剪，原图直设）；满屏三张仍走 NEImageBySiblingOrder
// 给背景图，两者不再交叉。
// 第十二修：踏板车视图的几何判定（不含“有没有自定义图”），供换图和恢复原图共用。
static BOOL NEIsScooterViewGeometry(UIImageView *iv, UIImage *image) {
    if (!iv || !image) return NO;
    if (![NSThread isMainThread]) return NO;
    CGSize bs = iv.bounds.size;
    if (bs.width < 150 || bs.height < 50) return NO;
    CGFloat w = image.size.width, h = image.size.height;
    if (w < 150 || h < 50) return NO;
    UIViewController *rootPage = NEDeviceRootPageVC();
    if (!rootPage || !rootPage.view) return NO;
    CGRect f = [iv convertRect:iv.bounds toView:rootPage.view];
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;
    if (f.origin.y >= 560 || f.origin.y + f.size.height <= 0) return NO;
    return YES;
}

static UIImage *NEVehicleImageForScooterView(UIImageView *iv, UIImage *image) {
    if (!iv || !image) return nil;
    if (![NSThread isMainThread]) return nil;
    UIImage *veh = NECustomVehicleImage();
    if (!veh) return nil;
    if (!NEIsScooterViewGeometry(iv, image)) return nil;
    return veh;
}

// 满屏大 view 只换背景图（第十一修）：不再按同级顺序/可见分车辆——
// 三张满屏图全是背景层，车辆（踏板车本体）不在其中，见上。
// veh 参数保留只为兼容调用点（NEClassifyDeviceImage / NEImageForSDURL）。
static UIImage *NEImageBySiblingOrder(UIImageView *iv, UIImage *bg, UIImage *veh) {
    (void)veh;
    // 只对满屏大 view：宽 >= 屏宽 0.9 且高 >= 屏高 0.5
    // （诊断里三张图都是 430x521）；小图走不到这里。
    CGSize bs = iv.bounds.size;
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    if (bs.width < sw * 0.9 || bs.height < sh * 0.5) return nil;
    if (!bg) return nil;
    // 背景图返回前按 view 纵横比裁好显示版（第八修）。
    return NEBackgroundDisplayImage(bg, iv.bounds.size);
}

static UIImage *NEClassifyDeviceImage(UIImageView *iv, UIImage *image) {
    if (!image || !iv) return nil;
    UIImage *bg = NECustomBackgroundImage();
    UIImage *veh = NECustomVehicleImage();
    if (!bg && !veh) return nil;
    // 已经是自定义图：放行。刷新/重设时再进钩子不会来回换。
    // 显示版（第八修裁过的背景图）也是自定义图，一样放行。
    if ((bg && (image == bg || image == gBgDisplayImage)) || (veh && image == veh)) return nil;
    CGFloat w = image.size.width, h = image.size.height;
    // 小图（图标/头像）一概不碰
    if (w < 200 && h < 200) return nil;
    CGSize bs = iv.bounds.size;
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    if (bs.width >= sw * 0.9 && bs.height >= sh * 0.5) {
        // 满屏大视图：三张主题/背景层（第十一修：全是背景层，中间可见那张
        // 是主题画层，车辆不在其中）→ 背景图；没有自定义背景时不换。
        return NEImageBySiblingOrder(iv, bg, veh);
    }
    // 非满屏：踏板车视图（第十一修）——见 NEVehicleImageForScooterView。
    // 卡片缩略图进不来：view 小（~100px）或在图区下面，都被那里的 gate 拦住。
    return NEVehicleImageForScooterView(iv, image);
}

// SDWebImage 的 URL 判定：满屏 view 只换背景图，不再按 URL 关键字分背景/车辆。
// 关键字误伤太多——新手任务卡片的图 URL 里就有 vehicle/car 这类词，
// 顶部背景图的 URL 也可能含 vehicle，都会被错换成车辆图。
// 小 view（卡片缩略图）直接放行；判定不出就返回 nil，等图片下完走
// setImage: 兜底再判。
static UIImage *NEImageForSDURL(UIImageView *iv, NSURL *url) {
    if (!NEViewIsOnDeviceRootPage(iv)) return nil;
    if (!iv || !url) return nil;
    // 只换满屏大视图：卡片缩略图再匹配什么也不换。
    CGSize bs = iv.bounds.size;
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    if (bs.width < sw * 0.9 || bs.height < sh * 0.5) return nil;
    return NEImageBySiblingOrder(iv, NECustomBackgroundImage(), NECustomVehicleImage());
}

static void (*orig_sd_setImageWithURL)(id, SEL, NSURL *);
static void NE_sd_setImageWithURL(id self, SEL _cmd, NSURL *url) {
    if (url && (gHasVehicleImage || gHasBgImage)) {
        UIImage *custom = NEImageForSDURL((UIImageView *)self, url);
        if (custom) {
            // 第十二修：这条路不走 setImage:（原图根本没下下来），改存原 URL，
            // 恢复原图时重下一遍。setImage: 兜底钩子与 SDWebImage 钩子互斥安装，
            // 这里直接调不会递归
            NEStashOriginalURL((UIImageView *)self, url);
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
            // 第十二修：同上，存原 URL 供恢复时重下。
            NEStashOriginalURL((UIImageView *)self, url);
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

// set-time 拦截的主力：任何路径设图（SDWebImage 内部完成、imageNamed + setImage、
// 直接赋值、主题重载）都会走这里，在显示前就把主题图/车图换掉——没有延迟、
// 没有竞态，切 tab 回来重载也一样被拦。背景/车辆按 NEClassifyDeviceImage
// 区分（主信号是同级顺序，不按 frame 尺寸——车辆画在满屏画布上，
// 按尺寸分永远错）。只在“设备”tab 换（响应链判定，不跟 presented 链）；
// 小图（图标/头像）不碰；已是自定义图的放行，不来回换。
static void (*orig_UIImageView_setImage)(id, SEL, UIImage *);
static void NE_UIImageView_setImage(id self, SEL _cmd, UIImage *image) {
    if (image && (gHasVehicleImage || gHasBgImage) && NEViewIsOnDeviceRootPage((UIImageView *)self)) {
        UIImage *custom = NEClassifyDeviceImage((UIImageView *)self, image);
        if (custom) {
            // 第十二修：先把 App 的原图暂存（恢复原图时设回去）；每次都覆盖，
            // App 重载主题后暂存的也是最新原图。custom 是车辆图就是 0，否则是背景图。
            UIImage *veh = NECustomVehicleImage();
            NSInteger kind = (veh && custom == veh) ? 0 : 1;
            NEStashOriginalBeforeReplace((UIImageView *)self, image, custom, kind);
            orig_UIImageView_setImage(self, _cmd, custom);
            return;
        }
    }
    orig_UIImageView_setImage(self, _cmd, image);
}

// 次要路径：主题若是 UIButton 的背景图（满屏大图），走 setBackgroundImage:forState:。
// 只换满屏尺寸的，按钮上的小图标一概不碰。
static void (*orig_UIButton_setBackgroundImage)(id, SEL, UIImage *, UIControlState);
static void NE_UIButton_setBackgroundImage(id self, SEL _cmd, UIImage *image, UIControlState state) {
    if (image && gHasBgImage) {
        CGSize sz = image.size;
        CGFloat sw = [UIScreen mainScreen].bounds.size.width;
        CGFloat sh = [UIScreen mainScreen].bounds.size.height;
        if (sz.width >= sw * 0.9 && sz.height >= sh * 0.5) {
            // 按钮本身也得是满屏大按钮：卡片按钮也可能配大图素材，只看图片尺寸不够。
            CGSize bs = ((UIView *)self).bounds.size;
            if (bs.width >= sw * 0.9 && bs.height >= sh * 0.5) {
                // 背景图一样按按钮尺寸裁显示版（第八修），别直接设原图。
                UIImage *custom = NEBackgroundDisplayImage(NECustomBackgroundImage(), bs);
                if (custom && NEViewIsOnDeviceRootPage((UIView *)self)) {
                    orig_UIButton_setBackgroundImage(self, _cmd, custom, state);
                    return;
                }
            }
        }
    }
    orig_UIButton_setBackgroundImage(self, _cmd, image, state);
}

// 注意：+[UIImage imageNamed:] 的钩子在第六修里整个删掉了——它没有 view 可查，
// 只能靠名字关键字 +“根页面正显示”这个全局条件放行，根本分不清卡片缩略图
// 和顶部背景图（新手任务卡片、甚至顶部背景图的名字/URL 里带 vehicle/car
// 这类词时，全被错换成车辆图）。本地 asset 走 setImage: 时一样能被满屏
// gate + 同级顺序拦住，不丢覆盖。

// App 若绕开 UIImageView.image 直接写 layer.contents，setImage: 钩子拦不到，
// 3 秒刷新又会被 App 的下一次写入盖掉——可见主图（750x908 主题合成图）
// 一直换不上的另一可能原因。直接拦 CALayer setContents:，只对设备根页面
// 满屏 UIImageView 的图层生效；其余图层直接放行，不碰。CALayer 很热，
// 快筛放最前面：没自定义图、内容不是 CGImage、不是主线程时直接放行。
static void (*orig_CALayer_setContents)(id, SEL, id);
static void NE_CALayer_setContents(id self, SEL _cmd, id contents) {
    if ((gHasVehicleImage || gHasBgImage) && contents &&
        [NSThread isMainThread] &&
        CFGetTypeID((CFTypeRef)contents) == CGImageGetTypeID()) {
        @autoreleasepool {
            @try {
                id delegate = [(CALayer *)self delegate];
                if ([delegate isKindOfClass:[UIImageView class]]) {
                    UIImageView *iv = (UIImageView *)delegate;
                    if (NEViewIsOnDeviceRootPage(iv)) {
                        CGSize bs = iv.bounds.size;
                        CGFloat sw = [UIScreen mainScreen].bounds.size.width;
                        CGFloat sh = [UIScreen mainScreen].bounds.size.height;
                        if (bs.width >= sw * 0.9 && bs.height >= sh * 0.5) {
                            // 自己写的自定义图直接放行（别重复处理）。
                            // 显示版（第八修裁过的背景图）也是自己写的，一样放行。
                            UIImage *bg = NECustomBackgroundImage();
                            UIImage *veh = NECustomVehicleImage();
                            if (!((bg && (contents == (__bridge id)bg.CGImage ||
                                          (gBgDisplayImage && contents == (__bridge id)gBgDisplayImage.CGImage))) ||
                                  (veh && contents == (__bridge id)veh.CGImage))) {
                                UIImage *incoming = [UIImage imageWithCGImage:(CGImageRef)contents];
                                UIImage *custom = incoming ? NEClassifyDeviceImage(iv, incoming) : nil;
                                if (custom && custom.CGImage) {
                                    // 第十二修：暂存 App 要写的原图（图层直写的满屏 view 都是背景层）。
                                    NEStashOriginalBeforeReplace(iv, incoming, custom, 1);
                                    orig_CALayer_setContents(self, _cmd, (__bridge id)custom.CGImage);
                                    return;
                                }
                            }
                        }
                    }
                }
            } @catch (...) {}
        }
    }
    orig_CALayer_setContents(self, _cmd, contents);
}

static BOOL gImageHooksInstalled = NO;
static void NEInstallImageHooksIfNeeded(void) {
    if (gImageHooksInstalled) return;
    Class iv = objc_getClass("UIImageView");
    if (!iv) {
        os_log(gLog, "[IMG] UIImageView 类未找到，不装图片钩子");
        return;
    }
    // setImage: 永远装（set-time 拦截的主力）：以前是“有 SD 就不装 setImage:”，
    // 结果所有不走 sd_setImageWithURL: 的设置路径（SD 内部完成、imageNamed +
    // setImage、直接赋值、主题重载）全绕过拦截——切 tab 回来就还原的根因。
    // SD 钩子只做补充（URL 层先拦一次）；SD 钩子调 setImage: 换图时会再进
    // 一次本钩子，算出来是同一张自定义图，不会循环。
    MSHookMessageEx(iv, @selector(setImage:),
                    (IMP)NE_UIImageView_setImage, (IMP *)&orig_UIImageView_setImage);
    if (!orig_UIImageView_setImage) {
        os_log(gLog, "[IMG] UIImageView setImage: 钩子安装失败");
    } else {
        os_log(gLog, "[IMG] UIImageView setImage: 钩子已装（set-time 拦截）");
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
    }
    // UIButton 背景图钩子（主题若是按钮背景图，走这里）
    Class btnCls = objc_getClass("UIButton");
    if (btnCls && class_getInstanceMethod(btnCls, @selector(setBackgroundImage:forState:))) {
        MSHookMessageEx(btnCls, @selector(setBackgroundImage:forState:),
                        (IMP)NE_UIButton_setBackgroundImage,
                        (IMP *)&orig_UIButton_setBackgroundImage);
        if (orig_UIButton_setBackgroundImage)
            os_log(gLog, "[IMG] UIButton setBackgroundImage:forState: 钩子已装");
    }
    // CALayer setContents: 兜底：App 若直接写图层内容绕开 setImage:，这里在写入时就换掉。
    Class layerCls = objc_getClass("CALayer");
    if (layerCls && class_getInstanceMethod(layerCls, @selector(setContents:))) {
        MSHookMessageEx(layerCls, @selector(setContents:),
                        (IMP)NE_CALayer_setContents,
                        (IMP *)&orig_CALayer_setContents);
        if (orig_CALayer_setContents)
            os_log(gLog, "[IMG] CALayer setContents: 钩子已装（图层直写兜底）");
    }
    gImageHooksInstalled = YES;
    // 页面显示时也要刷新图片（tab 懒加载，切过去才加载）
    NEInstallAppearHookIfNeeded();
    // 第十修：定时重断言（3 秒一次），App 事后重写主题图时能再换回来
    NEStartImageRefreshTimerIfNeeded();
}

// v0.3.9 修复：图片强制刷新——主题图/车图在 App 启动时已加载好，改设置后
// App 不再重设，钩子拦不到。选图后把设备 tab 里所有 UIImageView 按尺寸重算一次。
// 注意：不能用 NEIsDeviceTabSelected() 判定——设置页正以 modal 盖在上面，
// 它跟 presentedViewController 会走到设置页 nav，永远返回 NO；
// 这里直接从根控制器取 tab bar（不跟 presented 链），再看当前选中的是不是设备 tab。
// 主题图若不是 UIImageView 的 image（而是 view 背景色/图层内容），这招换不上，
// 那时再看诊断里的结构另想办法——先按 UIImageView 处理。
static UITabBarController *NEAppTabBarController(void) {
    UIWindow *w = NEKeyWindow();
    UIViewController *root = w.rootViewController;
    if ([root isKindOfClass:[UITabBarController class]]) return (UITabBarController *)root;
    return nil;
}

// 这个 view 是不是在“设备”tab 里：沿响应链上溯找所属 VC，再看它是不是
// 设备 tab 的根页面或其子页面（导航栈里的子页面、子 VC 都算；从设备 tab
// 弹出的 modal 也算）。不跟 presented 链、不看当前选中的 tab——图正在被
// 设的时候，设置 modal 可能正盖在上面，那时“当前选中”已经不准了。
// 响应链里找不到 VC（view 还没挂进任何页面）时，退回看当前选中的 tab。
static BOOL NEViewIsOnDeviceTab(UIView *v) {
    if (!v) return NO;
    UITabBarController *tab = NEAppTabBarController();
    if (!tab || tab.viewControllers.count == 0) return NO;
    UIViewController *deviceRoot = nil;
    for (UIViewController *child in tab.viewControllers) {
        if ([child.tabBarItem.title isEqualToString:@"设备"]) { deviceRoot = child; break; }
    }
    if (!deviceRoot) deviceRoot = tab.viewControllers.firstObject;
    if (!deviceRoot) return NO;
    UIResponder *r = v.nextResponder;
    UIViewController *vc = nil;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) { vc = (UIViewController *)r; break; }
        r = r.nextResponder;
    }
    if (vc) {
        UIViewController *p = vc;
        while (p) {
            if (p == deviceRoot) return YES;
            p = p.parentViewController;
        }
        p = vc.presentingViewController;
        while (p) {
            if (p == deviceRoot) return YES;
            p = p.presentingViewController;
        }
        return NO;
    }
    return tab.selectedIndex == 0 ||
           [tab.selectedViewController.tabBarItem.title isEqualToString:@"设备"];
}

// 设备 tab 在 tab bar 里的子 VC（通常是 UINavigationController）。
static UIViewController *NEDeviceTabRoot(void) {
    UITabBarController *tab = NEAppTabBarController();
    if (!tab || tab.viewControllers.count == 0) return nil;
    for (UIViewController *child in tab.viewControllers) {
        if ([child.tabBarItem.title isEqualToString:@"设备"]) return child;
    }
    return tab.viewControllers.firstObject;
}

// 设备 tab 的根页面 VC（导航栈第一个；若设备 tab 不是导航控制器，就是它自己）。
static UIViewController *NEDeviceRootPageVC(void) {
    UIViewController *deviceRoot = NEDeviceTabRoot();
    if (!deviceRoot) return nil;
    if ([deviceRoot isKindOfClass:[UINavigationController class]])
        return ((UINavigationController *)deviceRoot).viewControllers.firstObject;
    return deviceRoot;
}

// 这个 view 是不是在“设备”tab 的根页面上（不含 push 出去的子页面）。
// NEViewIsOnDeviceTab 对导航栈里任何页面都返回 YES，仪表/骑行页是 push
// 出去的子页面，它的满屏背景也被当成“车辆层”，自定义车辆图就错换到
// 仪表页背景上，设备页自己的车辆槽位反而没换上——这就是第五修的根因。
// 根页面的子 VC（parent 链通向根页面）也算；push 出去的 VC（导航栈下标
// > 0）及其子 VC 不算；modal 不算。
static BOOL NEViewIsOnDeviceRootPage(UIView *v) {
    if (!v) return NO;
    if (!NEViewIsOnDeviceTab(v)) return NO;
    UIViewController *rootPage = NEDeviceRootPageVC();
    if (!rootPage) return NO;
    UIResponder *r = v.nextResponder;
    UIViewController *vc = nil;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) { vc = (UIViewController *)r; break; }
        r = r.nextResponder;
    }
    if (vc) {
        // 沿 parent 链上溯到“直接挂在导航栈/ tab bar 里的那一级”，看它是不是根页面。
        UIViewController *p = vc;
        while (p.parentViewController &&
               ![p.parentViewController isKindOfClass:[UINavigationController class]] &&
               ![p.parentViewController isKindOfClass:[UITabBarController class]]) {
            p = p.parentViewController;
        }
        return p == rootPage;
    }
    // view 还没挂进任何 VC（如刚创建正设图）：只在设备根页面正显示在
    // 最上层时放行（导航栈顶就是根页面，且设备 tab 被选中）。
    UITabBarController *tab = NEAppTabBarController();
    if (!tab) return NO;
    UIViewController *deviceRoot = NEDeviceTabRoot();
    if (!deviceRoot) return NO;
    if (tab.selectedViewController != deviceRoot) return NO;
    if ([deviceRoot isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)deviceRoot;
        return nav.topViewController == rootPage;
    }
    return YES;
}

// 第十二修：把一个 view 恢复成暂存的原图。只在它现在还显示着我们换上去的
// 那张自定义图（iv.image 或 layer.contents 还是当时那张）时才还；App 已经
// 自己换了别的图时只清掉过期的暂存、不动当前图。按种类 + 几何再验一次，
// 防止 UITableView cell 复用后把原图还到别的 view 上。SD 直下的原图没有
// 图片暂存，改重下原 URL（SDWebImage 读缓存，不用等网）。
static void NERestoreOriginalImageIfNeeded(UIImageView *iv, UIImage *currentImg) {
    if (!iv || ![NSThread isMainThread]) return;
    BOOL hadImageStash = NO;
    // 车辆原图
    NSArray *pairV = NEStashedOriginalPair(iv, 0);
    if (pairV.count == 2) {
        hadImageStash = YES;
        UIImage *orig = pairV[0]; UIImage *applied = pairV[1];
        BOOL showingCustom = (currentImg == applied) ||
            (iv.layer.contents && applied.CGImage &&
             iv.layer.contents == (__bridge id)applied.CGImage);
        if (showingCustom) {
            if (NEIsScooterViewGeometry(iv, orig)) {
                iv.image = orig;
                @try { if (orig.CGImage) iv.layer.contents = (__bridge id)orig.CGImage; } @catch (...) {}
                NEClearStashedOriginalImage(iv, 0);
            }
            // 几何还没就绪（未布局）→ 暂存留着，下次刷新再试
        } else {
            NEClearStashedOriginalImage(iv, 0);
        }
    }
    // 背景原图
    NSArray *pairB = NEStashedOriginalPair(iv, 1);
    if (pairB.count == 2) {
        hadImageStash = YES;
        UIImage *orig = pairB[0]; UIImage *applied = pairB[1];
        BOOL showingCustom = (currentImg == applied) ||
            (iv.layer.contents && applied.CGImage &&
             iv.layer.contents == (__bridge id)applied.CGImage);
        if (showingCustom) {
            CGSize bs = iv.bounds.size;
            CGFloat sw = [UIScreen mainScreen].bounds.size.width;
            CGFloat sh = [UIScreen mainScreen].bounds.size.height;
            if (bs.width >= sw * 0.9 && bs.height >= sh * 0.5) {
                iv.image = orig;
                @try { if (orig.CGImage) iv.layer.contents = (__bridge id)orig.CGImage; } @catch (...) {}
                NEClearStashedOriginalImage(iv, 1);
            }
        } else {
            NEClearStashedOriginalImage(iv, 1);
        }
    }
    // SD 直下的原图：没有图片暂存时重下原 URL（读 SD 缓存，很快）。
    // 有图片暂存时不用它——原图已经从暂存还回去了。
    NSURL *origURL = NEStashedOriginalURL(iv);
    if (origURL && !hadImageStash) {
        NEClearStashedOriginalURL(iv);
        if (orig_sd_setImageWithURL) {
            @try { orig_sd_setImageWithURL(iv, @selector(sd_setImageWithURL:), origURL); } @catch (...) {}
        } else if (orig_sd_setImageWithURL_ctx) {
            @try { orig_sd_setImageWithURL_ctx(iv, @selector(sd_setImageWithURL:placeholderImage:options:context:progress:completed:), origURL, nil, 0, nil, nil, nil); } @catch (...) {}
        }
    }
}

static void NEForceRefreshImagesInView(UIView *view) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UIImageView class]]) {
            UIImageView *iv = (UIImageView *)sub;
            UIImage *img = iv.image;
            if (img) {
                @try {
                    // 背景/车辆按 NEClassifyDeviceImage 区分（第十一修：满屏三张
                    // 是背景层→背景图，踏板车本体（表头里非满屏 view）→车辆图）。
                    // 分类不依赖当前图片的纵横比，所以换图后刷新（缓存已清、
                    // 当前图是旧自定义图）也能分对；已是当前自定义图的直接放行。
                    // 直接赋值走 setImage: 钩子再算一次也是同一张图，不会循环。
                    UIImage *custom = NEClassifyDeviceImage(iv, img);
                    if (custom && custom != img) {
                        // 第十二修：先把 App 当前那张原图暂存（恢复原图时设回去），
                        // 再换自定义图。见 NEStashOriginalBeforeReplace。
                        UIImage *veh = NECustomVehicleImage();
                        NSInteger kind = (veh && custom == veh) ? 0 : 1;
                        NEStashOriginalBeforeReplace(iv, img, custom, kind);
                        iv.image = custom;
                        // 若 App 绕开 setImage: 直接写了 layer.contents（显示内容
                        // 会盖过 UIImageView.image），只换 iv.image 显示换不上；
                        // 把图层内容也同步成自定义图。CGImage 为 nil 时不碰。
                        @try { if (custom.CGImage) iv.layer.contents = (__bridge id)custom.CGImage; } @catch (...) {}
                    } else {
                        // 当前图已经是自定义图（custom 为 nil 是放行），但
                        // layer.contents 可能被 App 覆盖回主题图——图层内容会盖过
                        // image 显示，刷新时只看 iv.image 就发现不了。若图层内容
                        // 不是当前自定义图，重新同步一次。
                        UIImage *bgNow = NECustomBackgroundImage();
                        UIImage *vehNow = NECustomVehicleImage();
                        // 显示版也是自定义图：当前图是显示版时，按显示版同步图层。
                        BOOL imgIsActiveCustom = (bgNow && (img == bgNow || img == gBgDisplayImage)) ||
                                                 (vehNow && img == vehNow);
                        if (imgIsActiveCustom) {
                            if (img && img.CGImage) {
                                @try {
                                    if (iv.layer.contents != (__bridge id)img.CGImage)
                                        iv.layer.contents = (__bridge id)img.CGImage;
                                } @catch (...) {}
                            }
                        } else {
                            // 第十二修：没有自定义图再管这个 view，但它以前被换过
                            // （暂存了原图）——现在就是恢复原图的时机，把原图设回去。
                            NERestoreOriginalImageIfNeeded(iv, img);
                        }
                    }
                } @catch (...) {}
            }
        }
        NEForceRefreshImagesInView(sub);
    }
}

static void NEForceRefreshImages(void) {
    // 第十二修：不能再在“没自定义图”时直接 return——恢复原图后两个 flag 都
    // 是 NO，但设备页上还留着旧自定义图，正要靠这一遍把它换回暂存的原图。
    // 没自定义图也没暂存时这一遍只是空走（指针比较），开销可忽略。
    // 第十修：不再要求当前选中的是设备 tab——设置页是从“我的”tab 弹出的
    // modal，选完图那一刻 selectedViewController 是“我的”，旧的 isDevice
    // 判断直接 return，savePickedImage 里“选完图立刻刷新”等于没跑——这
    // 就是选图后设备页不变的另一半原因。设备根页面的 view 一旦加载就常驻
    // 层级（切 tab 也不卸载），在哪个 tab 都能刷；只刷 rootPage.view，不含
    // push 出去的子页面（仪表/骑行页），所以不会把车辆图刷到子页面上去。
    // 根页面 view 还没加载出来时没东西可刷，直接返回（不要退回刷 sel.view，
    // 那会把子页面也刷进去，正是车辆图跑到仪表页的另一条路）。
    UIViewController *rootPage = NEDeviceRootPageVC();
    if (!rootPage || !rootPage.isViewLoaded || !rootPage.view) return;
    NEForceRefreshImagesInView(rootPage.view);
}

// v0.3.9 第十修：图片定时重断言——App 会在主题重载/切 tab/回前台时把设备页
// 三张满屏图重设回主题图（诊断 ne-diag-807ae3b2.txt 里第一张图的尺寸每次
// 导出都在变：942x1672、2160x4790、1206x2674、375x454、750x908、1892x4088，
// 证明 App 在主动重写它们），而一次性刷新（选完图/切 tab 时）拦不住事后
// 重写；set-time 钩子又只在 view 已挂载且已布局时才分得清，创建时预设的
// 那一次拦不到——踏板车本体图和主题图只在创建时设一次，之后 App 会主动
// 重写，钩子永远没机会。3 秒跑一次强制刷新，幂等（已是
// 自定义图的不动，只是指针比较），把被 App 盖回去的图再换回来。
static NSTimer *gImageRefreshTimer = nil;
static void NEStartImageRefreshTimerIfNeeded(void) {
    if (gImageRefreshTimer) return;
    void (^start)(void) = ^{
        if (gImageRefreshTimer) return;
        gImageRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            (void)timer;
            @try { NEForceRefreshImages(); } @catch (...) {}
        }];
    };
    if ([NSThread isMainThread]) start();
    else dispatch_async(dispatch_get_main_queue(), start);
}

// v0.3.9 修复：页面显示时刷新——tab 懒加载，启动 +3 秒刷新时我的/服务页
// 还没加载，切过去时 label 已设好不再重设，钩子拦不到。viewDidAppear 时
// 把当前页的文字和图片重算一次（图片只在设备 tab 生效，内部已判断）。
// 每 VC 节流 1 秒；我们自己的设置页出现时不刷（它没有要换的 App 文字）。
static NSMutableDictionary<NSString *, NSNumber *> *gAppearThrottle = nil;
static void (*orig_UIViewController_viewDidAppear)(id, SEL, BOOL);
static void NE_UIViewController_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    orig_UIViewController_viewDidAppear(self, _cmd, animated);
    if (!gLabelHookInstalled && !gHasVehicleImage && !gHasBgImage) return;
    NSString *clsName = NSStringFromClass([self class]);
    if ([clsName rangeOfString:@"NEHUDSettings"].location != NSNotFound) return;
    // 诊断：我的/服务/设备页每启动只导出一次（见 NEDumpDiagIfNeededForVC）
    @try { NEDumpDiagIfNeededForVC((UIViewController *)self); } @catch (...) {}
    NSString *key = [NSString stringWithFormat:@"%p", self];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!gAppearThrottle) gAppearThrottle = [NSMutableDictionary dictionary];
    NSNumber *last = gAppearThrottle[key];
    if (last && now - last.doubleValue < 1.0) return;
    gAppearThrottle[key] = @(now);
    if (gAppearThrottle.count > 100) {
        NSMutableArray<NSString *> *stale = [NSMutableArray array];
        for (NSString *k in gAppearThrottle) {
            if (now - [gAppearThrottle[k] doubleValue] > 10.0) [stale addObject:k];
        }
        [gAppearThrottle removeObjectsForKeys:stale];
    }
    @try {
        NEForceRefreshLabels();
        NEForceRefreshImages();
        NEForceRedrawRNText(); // RN 段落：切回页面时强制重画，开关状态变化时生效
    } @catch (...) {}
}

static BOOL gAppearHookInstalled = NO;
static void NEInstallAppearHookIfNeeded(void) {
    if (gAppearHookInstalled) return;
    Class cls = objc_getClass("UIViewController");
    if (!cls || !class_getInstanceMethod(cls, @selector(viewDidAppear:))) {
        os_log(gLog, "[LBL] UIViewController/viewDidAppear: 不存在，不装钩子");
        return;
    }
    MSHookMessageEx(cls, @selector(viewDidAppear:),
                    (IMP)NE_UIViewController_viewDidAppear,
                    (IMP *)&orig_UIViewController_viewDidAppear);
    if (!orig_UIViewController_viewDidAppear) {
        os_log(gLog, "[LBL] UIViewController viewDidAppear: 钩子安装失败");
        return;
    }
    gAppearHookInstalled = YES;
    os_log(gLog, "[LBL] UIViewController viewDidAppear: 钩子已装");
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
    // v0.3.9 美化：分组表样式——浅灰底 + 白色圆角卡片（iOS 系统分组表观感）。
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
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
        [scroll.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor]
    ]];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    // 内容横向用 frameLayoutGuide 定宽（可见宽 - 32，左右各 16 边距），
    // 纵向用 contentLayoutGuide：这是 scroll view 的标准写法，内容宽
    // 严格等于可见宽减边距，开关/按钮离右边缘永远有 16pt，不会贴边。
    UILayoutGuide *frame = scroll.frameLayoutGuide;
    UILayoutGuide *content = scroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor constant:-16]
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
    beautyStack.spacing = 0; // 卡片内行与行直接贴合，中间用底部分隔线分开
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [beautyStack addArrangedSubview:[self customDisplayRow:@"服务有效期" toggleKey:@"NEValidity9999" valueKey:@"NEValidityValue" on:NEValidity9999() value:[defs stringForKey:@"NEValidityValue"] placeholder:@"留空显示真实日期"]];
    [beautyStack addArrangedSubview:[self sectionLabel:@"主页车辆图"]];
    [beautyStack addArrangedSubview:[self imagePickRow:@"更换车辆图" kind:0]];
    [beautyStack addArrangedSubview:[self imageClearRow:@"恢复原图" kind:0]];
    [beautyStack addArrangedSubview:[self sectionLabel:@"主页背景图"]];
    [beautyStack addArrangedSubview:[self imagePickRow:@"更换背景图" kind:1]];
    [beautyStack addArrangedSubview:[self imageClearRow:@"恢复原背景" kind:1]];
    UILabel *imgNote = [UILabel new];
    imgNote.text = @"换图只换“设备”主页上的显示，不改车辆数据。选完、恢复完回设备页马上就能看到。";
    imgNote.font = [UIFont systemFontOfSize:13];
    imgNote.textColor = [UIColor secondaryLabelColor];
    imgNote.numberOfLines = 0;
    [beautyStack addArrangedSubview:[self ne_footnoteView:imgNote]];
    // v0.3.9 追加：五个自定义显示项（开关 + 输入框，自己填想显示的值）
    [beautyStack addArrangedSubview:[self customDisplayRow:@"N币余额" toggleKey:@"NENCoins" valueKey:@"NENCoinsValue" on:NEBoolDefault(@"NENCoins") value:[defs stringForKey:@"NENCoinsValue"] placeholder:@"如 99999"]];
    [beautyStack addArrangedSubview:[self customDisplayRow:@"总里程" toggleKey:@"NEMileage" valueKey:@"NEMileageValue" on:NEBoolDefault(@"NEMileage") value:[defs stringForKey:@"NEMileageValue"] placeholder:@"如 99999.9 km"]];
    [beautyStack addArrangedSubview:[self customDisplayRow:@"等级（1-9）" toggleKey:@"NELevel" valueKey:@"NELevelValue" on:NEBoolDefault(@"NELevel") value:[defs stringForKey:@"NELevelValue"] placeholder:@"如 Lv.99"]];
    [beautyStack addArrangedSubview:[self customDisplayRow:@"称号" toggleKey:@"NETitle" valueKey:@"NETitleValue" on:NEBoolDefault(@"NETitle") value:[defs stringForKey:@"NETitleValue"] placeholder:@"如 车神"]];
    [beautyStack addArrangedSubview:[self customDisplayRow:@"签到天数" toggleKey:@"NESignDays" valueKey:@"NESignDaysValue" on:NEBoolDefault(@"NESignDays") value:[defs stringForKey:@"NESignDaysValue"] placeholder:@"如 365"]];
    // v0.3.9 诊断：手动导出当前页的界面结构（设置页底下的那个 tab 页面）
    [beautyStack addArrangedSubview:[self diagExportRow]];
    [self ne_styleSeparatorsInStack:beautyStack];
    UIView *beautyCard = [self ne_cardWrappingStack:beautyStack];
    beautyCard.hidden = YES; // 默认折叠，折叠状态存在卡片上
    objc_setAssociatedObject(self, &NEBeautyGroupKey, beautyCard,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [stack addArrangedSubview:[self groupHeader:@"美化娱乐" tag:0]];
    [stack addArrangedSubview:beautyCard];

    // ---- 导航增强组（默认折叠，以前的 HUD/翻页时钟/超速等功能）----
    UIStackView *navStack = [UIStackView new];
    navStack.axis = UILayoutConstraintAxisVertical;
    navStack.spacing = 0; // 卡片内行与行直接贴合，中间用底部分隔线分开
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
    [navStack addArrangedSubview:[self ne_footnoteView:note]];
    [self ne_styleSeparatorsInStack:navStack];
    UIView *navCard = [self ne_cardWrappingStack:navStack];
    navCard.hidden = YES; // 默认折叠，折叠状态存在卡片上
    objc_setAssociatedObject(self, &NENavGroupKey, navCard,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [stack addArrangedSubview:[self groupHeader:@"导航增强" tag:1]];
    [stack addArrangedSubview:navCard];
}

- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    l.textColor = [UIColor secondaryLabelColor];
    [l.heightAnchor constraintEqualToConstant:30].active = YES;
    return l;
}

// v0.3.9 美化：把一组行包进白色圆角卡片（iOS 分组表样式）。卡片内边距
// 上下 8、左右 16；行高 44 + 底部分隔线，开关/按钮离卡片右沿还有 16pt，
// 再也不会贴着屏幕右边缘。
- (UIView *)ne_cardWrappingStack:(UIStackView *)inner {
    UIView *card = [UIView new];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 12;
    card.clipsToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    inner.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:inner];
    [NSLayoutConstraint activateConstraints:@[
        [inner.topAnchor constraintEqualToAnchor:card.topAnchor constant:8],
        [inner.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-8],
        [inner.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [inner.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16]
    ]];
    return card;
}

// v0.3.9 美化：行底部的 1px 分隔线（tag 1002）。只有下一行也是行时才显示，
// 小标题/备注/分段控件前后不画线，卡片底那行也不画。
- (void)ne_addBottomHairlineToRow:(UIView *)row {
    UIView *line = [UIView new];
    line.backgroundColor = [UIColor separatorColor];
    line.tag = 1002;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [line.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [line.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [line.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [line.heightAnchor constraintEqualToConstant:(1.0 / [UIScreen mainScreen].scale)]
    ]];
}

// v0.3.9 美化：按“下一行也是行才显示分隔线”的规则，刷一遍组内所有行的底线。
// 行用 tag 1001 标记（见各行工厂方法），小标题/备注/分段控件不参与。
- (void)ne_styleSeparatorsInStack:(UIStackView *)stack {
    NSArray<UIView *> *views = [stack.arrangedSubviews copy];
    for (NSInteger i = 0; i < (NSInteger)views.count; i++) {
        UIView *v = views[i];
        if (v.tag != 1001) continue;
        UIView *line = [v viewWithTag:1002];
        BOOL nextIsRow = (i + 1 < (NSInteger)views.count) && (views[i + 1].tag == 1001);
        if (line) line.hidden = !nextIsRow;
    }
}

// v0.3.9 美化：备注文字包一层容器，上下留白（8/4），左右由卡片内边距管。
- (UIView *)ne_footnoteView:(UILabel *)label {
    UIView *wrap = [UIView new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-4],
        [label.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor]
    ]];
    return wrap;
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
    UIView *container = objc_getAssociatedObject(self, key); // 卡片（折叠状态存在卡片上）
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
        [row.heightAnchor constraintEqualToConstant:44]
    ]];
    row.tag = 1001; // 美化：行标记，分隔线只画在两行之间
    [self ne_addBottomHairlineToRow:row];
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
    NEInstallRNTextHookIfNeeded();
    NEForceRefreshLabels(); // v0.3.9 修复：值改了，已显示的 label 不会自动重设，强制刷新立刻生效
    NEForceRedrawRNText(); // RN 段落同理：值改了，已显示的段落强制重画
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
        [row.heightAnchor constraintEqualToConstant:44]
    ]];
    row.tag = 1001; // 美化：行标记，分隔线只画在两行之间
    [self ne_addBottomHairlineToRow:row];
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
        NESyncCustomDisplayCache(); // 值也同步一次（输入框改完已同步过，这里是兜底）
        if (sw.isOn) { NEInstallLabelHookIfNeeded(); NEInstallRNTextHookIfNeeded(); }
        NEForceRefreshLabels(); // v0.3.9 修复：开关变了，已显示的 label 不会自动重设，强制刷新
        NEForceRedrawRNText();
    }
    // v0.3.9 追加：五个自定义显示项开关——同步缓存并按需装钩子
    if ([key isEqualToString:@"NENCoins"] || [key isEqualToString:@"NEMileage"] ||
        [key isEqualToString:@"NELevel"] || [key isEqualToString:@"NETitle"] ||
        [key isEqualToString:@"NESignDays"]) {
        NESyncCustomDisplayCache();
        if (sw.isOn) { NEInstallLabelHookIfNeeded(); NEInstallRNTextHookIfNeeded(); }
        NEForceRefreshLabels(); // v0.3.9 修复：同上
        NEForceRedrawRNText();
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
        [row.heightAnchor constraintEqualToConstant:44]
    ]];
    row.tag = 1001; // 美化：行标记，分隔线只画在两行之间
    [self ne_addBottomHairlineToRow:row];
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
    btn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
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
        [row.heightAnchor constraintEqualToConstant:44]
    ]];
    const char *key = (kind == 0) ? &NEVehicleStatusKey : &NEBackgroundStatusKey;
    objc_setAssociatedObject(self, key, status, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self refreshImageStatus];
    row.tag = 1001; // 美化：行标记，分隔线只画在两行之间
    [self ne_addBottomHairlineToRow:row];
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
    btn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
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
        [row.heightAnchor constraintEqualToConstant:44]
    ]];
    row.tag = 1001; // 美化：行标记，分隔线只画在两行之间
    [self ne_addBottomHairlineToRow:row];
    return row;
}

- (void)refreshImageStatus {
    UILabel *v = objc_getAssociatedObject(self, &NEVehicleStatusKey);
    if (v) v.text = NEVehicleImagePath().length ? @"已自定义" : @"原图";
    UILabel *b = objc_getAssociatedObject(self, &NEBackgroundStatusKey);
    if (b) b.text = NEBackgroundImagePath().length ? @"已自定义" : @"原图";
}

// v0.3.9 诊断：手动导出当前页的界面结构（设置页底下的那个 tab 页面），
// 写到 Documents/ne-diag.txt，用户用 Filza 打开发回。
- (UIView *)diagExportRow {
    UIView *row = [UIView new];
    UILabel *label = [UILabel new];
    label.text = @"导出界面诊断";
    label.font = [UIFont systemFontOfSize:16];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:@"导出" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:self action:@selector(exportDiagTapped:)
        forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:label];
    [row addSubview:btn];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [btn.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [btn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintEqualToConstant:44]
    ]];
    row.tag = 1001; // 美化：行标记，分隔线只画在两行之间
    [self ne_addBottomHairlineToRow:row];
    return row;
}

- (void)exportDiagTapped:(UIButton *)sender {
    // 取设置 modal 底下的 tab 页面：选中的 tab 若是导航控制器，取它的根页面
    // （tab 页本身）；设置页若是 push 进来的，在栈顶，不取它。frame 用页面
    // 自身坐标（见 NEDiagFrame），modal 把底下页面缩放也不影响。
    UITabBarController *tab = NEAppTabBarController();
    UIViewController *sel = tab.selectedViewController;
    if ([sel isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)sel;
        if (nav.viewControllers.count > 0) sel = nav.viewControllers.firstObject;
    }
    NSString *page = NEPageNameForVC(sel);
    BOOL dumped = NO;
    if (sel.view) {
        NEDumpDiagForView(sel.view, [page stringByAppendingString:@"（手动）"]);
        dumped = YES;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:dumped ? @"已导出" : @"未导出"
        message:dumped ? @"诊断已保存到 Documents/ne-diag.txt，用 Filza 打开九号出行 Documents 文件夹查看。"
                       : @"没找到当前页面，稍后再试。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
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
    // 第十二修：立刻把设备页的图恢复成暂存的原图，不用等切 tab / 重启
    //（savePickedImage 同款：立刻刷一次 + 1 秒后再刷一次，防 App 异步重载）。
    NEForceRefreshImages();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try { NEForceRefreshImages(); } @catch (...) {}
    });
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
    // 第十修：1 秒后再刷一次——App 可能在选图后异步重载主题，把刚换上的
    // 自定义图盖回去；定时器 3 秒才跑一轮，1 秒补刷让结果更快稳定。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try { NEForceRefreshImages(); } @catch (...) {}
    });
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
    if (gValidity9999 || gNCoins || gMileage || gLevel || gTitle || gSignDays)
        NEInstallRNTextHookIfNeeded();
    gHasVehicleImage = NEVehicleImagePath().length > 0;
    gHasBgImage = NEBackgroundImagePath().length > 0;
    // key 为空但文件还在时也算有图（key 可能丢了），否则图片钩子不装、刷新不跑。
    {
        NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSFileManager *fm = [NSFileManager defaultManager];
        if (!gHasVehicleImage && doc.length && [fm fileExistsAtPath:[doc stringByAppendingPathComponent:@"ne-vehicle.png"]])
            gHasVehicleImage = YES;
        if (!gHasBgImage && doc.length && [fm fileExistsAtPath:[doc stringByAppendingPathComponent:@"ne-bg.png"]])
            gHasBgImage = YES;
    }
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
        // 或主题图在钩子装好前已设好，靠刷新再补一次。
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

        // v0.3.9 第三修：每 3 秒补刷一次文字+图片（仅 App 在前台、且任一自定义
        // 开关开着或已选自定义图时）。兜住布局晚、数据晚到、页面重渲染的情况；
        // 刷新直接跑匹配，不依赖 setter 钩子。我们自己的设置页在最上层时不刷
        //（别打扰输入框）。图片主要靠 set-time 的 setImage: 钩子，这里只是兜底。
        gRefreshTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                               dispatch_get_main_queue());
        dispatch_source_set_timer(gRefreshTimer, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                                  3 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(gRefreshTimer, ^{
            if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) return;
            if (!gLabelHookInstalled && !gHasVehicleImage && !gHasBgImage) return;
            UIViewController *top = NETopViewController();
            if (top && [[NSStringFromClass([top class]) lowercaseString] containsString:@"nehud"]) return;
            NEForceRefreshLabels();
            NEForceRefreshImages();
        });
        dispatch_resume(gRefreshTimer);
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

