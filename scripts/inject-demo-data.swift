import Foundation
import AppKit

let fileManager = FileManager.default
let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("SunMemo")
let memosDir = appSupport.appendingPathComponent("Memos")
let shotsDir = appSupport.appendingPathComponent("Screenshots")

try? fileManager.createDirectory(at: memosDir, withIntermediateDirectories: true)
try? fileManager.createDirectory(at: shotsDir, withIntermediateDirectories: true)

// 1. Create a beautiful sample photograph
let photoURL = shotsDir.appendingPathComponent("Sunset_Lake_Sample.png")
if !fileManager.fileExists(atPath: photoURL.path) {
    let size = NSSize(width: 800, height: 500)
    let img = NSImage(size: size)
    img.lockFocus()
    // Beautiful gradient sunset over mountain lake
    let skyGrad = NSGradient(colors: [
        NSColor(red: 0.98, green: 0.58, blue: 0.42, alpha: 1.0),
        NSColor(red: 0.95, green: 0.78, blue: 0.52, alpha: 1.0),
        NSColor(red: 0.56, green: 0.72, blue: 0.88, alpha: 1.0)
    ])!
    skyGrad.draw(in: NSRect(origin: .zero, size: size), angle: 90)

    // Distant mountain
    let mountainPath = NSBezierPath()
    mountainPath.move(to: NSPoint(x: 0, y: 180))
    mountainPath.line(to: NSPoint(x: 220, y: 320))
    mountainPath.line(to: NSPoint(x: 480, y: 220))
    mountainPath.line(to: NSPoint(x: 640, y: 340))
    mountainPath.line(to: NSPoint(x: 800, y: 200))
    mountainPath.line(to: NSPoint(x: 800, y: 0))
    mountainPath.line(to: NSPoint(x: 0, y: 0))
    mountainPath.close()
    NSColor(red: 0.28, green: 0.32, blue: 0.45, alpha: 0.85).setFill()
    mountainPath.fill()

    // Sun reflection on water
    let lakeRect = NSRect(x: 0, y: 0, width: 800, height: 160)
    let waterGrad = NSGradient(colors: [
        NSColor(red: 0.32, green: 0.44, blue: 0.58, alpha: 0.95),
        NSColor(red: 0.18, green: 0.24, blue: 0.36, alpha: 1.0)
    ])!
    waterGrad.draw(in: lakeRect, angle: -90)

    // Sun
    let sunRect = NSRect(x: 350, y: 250, width: 100, height: 100)
    let sunPath = NSBezierPath(ovalIn: sunRect)
    NSColor(red: 1.0, green: 0.92, blue: 0.75, alpha: 0.95).setFill()
    sunPath.fill()

    img.unlockFocus()
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: photoURL)
    }
}

// 2. Create Memo 1 (Wide 16:10 / Yellow)
let memo1Id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
let memo1Text = """
## ☀️ SunMemo v1.1 发布准备
- [x] 完成手拨扑克牌扇面推开动效测试
- [x] 重构 1.3pt 亚麻灰高光悬链拉绳
- [ ] 录制演示视频与生成动图
- [ ] 上传 GitHub Release v1.1.0

> 把未完成的想法，晾在桌面的阳光下。
"""
let memo1Data: [String: Any] = [
    "id": memo1Id.uuidString,
    "text": memo1Text,
    "color": "yellow",
    "isDone": false,
    "createdAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)),
    "aspectRatio": "wide"
]
let memo1URL = memosDir.appendingPathComponent("memo_\(memo1Id.uuidString).json")
if let data1 = try? JSONSerialization.data(withJSONObject: memo1Data, options: .prettyPrinted) {
    try? data1.write(to: memo1URL)
}

// 3. Create Memo 2 (Square 1:1 / Green)
let memo2Id = UUID(uuidString: "22222222-3333-4444-5555-666666666666")!
let memo2Text = """
## 💡 灵感闪念
尝试把自然的物候隐喻带入数字生活：
• 晾衣绳随微风自然摇摆
• 扑克牌般手拨扇形推开
• 撕下便签时的从容沉淀
"""
let memo2Data: [String: Any] = [
    "id": memo2Id.uuidString,
    "text": memo2Text,
    "color": "green",
    "isDone": false,
    "createdAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7200)),
    "aspectRatio": "square"
]
let memo2URL = memosDir.appendingPathComponent("memo_\(memo2Id.uuidString).json")
if let data2 = try? JSONSerialization.data(withJSONObject: memo2Data, options: .prettyPrinted) {
    try? data2.write(to: memo2URL)
}

// 4. Create Memo 3 (Tall 3:4 / Pink)
let memo3Id = UUID(uuidString: "33333333-4444-5555-6666-777777777777")!
let memo3Text = """
## 📋 周末清单
- [x] 早起手冲咖啡 ☕️
- [x] 整理摄影胶卷与快照
- [ ] 沿海滨公路骑行放空
- [ ] 读完设计书籍后半章
- [ ] 给阳台绿植浇透水
"""
let memo3Data: [String: Any] = [
    "id": memo3Id.uuidString,
    "text": memo3Text,
    "color": "pink",
    "isDone": false,
    "createdAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-10800)),
    "aspectRatio": "tall"
]
let memo3URL = memosDir.appendingPathComponent("memo_\(memo3Id.uuidString).json")
if let data3 = try? JSONSerialization.data(withJSONObject: memo3Data, options: .prettyPrinted) {
    try? data3.write(to: memo3URL)
}

// 5. Update UserDefaults pegged array
let paths = [
    photoURL.path,
    memo1URL.path,
    memo2URL.path,
    memo3URL.path
]
UserDefaults(suiteName: "com.zhangkaiming.SunMemo")?.set(paths, forKey: "pegged")
print("Injected demo data successfully! Paths:")
for p in paths { print("  - \(p)") }
