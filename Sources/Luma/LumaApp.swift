import SwiftUI
import UniformTypeIdentifiers

@main struct LumaApp: App {
    @StateObject private var model = Workspace()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model).preferredColorScheme(.dark)
                .frame(minWidth: 1000, minHeight: 680)
        }.windowStyle(.hiddenTitleBar).defaultSize(width: 1220, height: 800)
            .commands { CommandGroup(replacing: .newItem) { Button("添加图片…") { model.chooseImages() }.keyboardShortcut("o").disabled(model.running) } }
    }
}
private let lime = Color(red: 0.78, green: 0.96, blue: 0.43)
private let base = Color(red: 0.065, green: 0.075, blue: 0.07)
struct ContentView: View {
    @EnvironmentObject var model: Workspace
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var appeared = false
    @State private var targeted = false
    @State private var showOriginal = false
    @State private var previewZoom: CGFloat = 1
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 218)
            Divider().overlay(.white.opacity(0.06))
            VStack(alignment: .leading, spacing: 24) {
                header
                HStack(alignment: .top, spacing: 22) {
                    VStack(spacing: 16) { preview; fileList }.frame(maxWidth: .infinity)
                    settings.frame(width: 264)
                }
                footer
            }.padding(30)
        }
        .background(base)
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 12)
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.65)) { appeared = true } }
        .onChange(of: model.mode) { _, _ in showOriginal = false; model.prepareBackgrounds() }
        .onChange(of: model.current?.id) { _, _ in previewZoom = 1; showOriginal = false }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard !model.running else { return false }
            for provider in providers { _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in model.add([url]) } } } }
            return true
        }
        .overlay { if targeted { RoundedRectangle(cornerRadius: 18).stroke(lime, lineWidth: 3).padding(8).allowsHitTesting(false) } }
        .alert("图片处理提示", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) { Button("好") { model.alert = nil } } message: { Text(model.alert ?? "") }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 34) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 27)).foregroundStyle(lime)
                Text("luma").font(.system(size: 30, weight: .bold, design: .rounded))
            }.padding(.top, 28)
            VStack(alignment: .leading, spacing: 12) {
                Text("工作空间").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.gray)
                Label("图片工作台", systemImage: "slider.horizontal.3").font(.system(size: 13, weight: .medium)).foregroundStyle(lime).padding(13).frame(maxWidth: .infinity, alignment: .leading).background(lime.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "leaf").font(.system(size: 22)).foregroundStyle(lime)
                Text("更轻盈，也更出色。") .font(.system(size: 14, weight: .medium))
                Text("为每一个像素，\n保留值得珍藏的细节。") .font(.system(size: 12)).foregroundStyle(.gray).lineSpacing(5)
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            Label("本地处理 · 隐私安心", systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(.gray)
        }.padding(22).background(.black.opacity(0.15))
    }
    var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 9) {
                Text("LESS SIZE. MORE POSSIBILITIES.").font(.system(size: 9, weight: .medium)).tracking(2.5).foregroundStyle(lime)
                Text("让图片，轻装上阵。") .font(.system(size: 29, weight: .semibold))
                Text("转换格式，精简体积，一键移除背景。") .font(.system(size: 12)).foregroundStyle(.gray)
            }
            Spacer()
            Button { model.chooseImages() } label: { Label("添加图片", systemImage: "plus").padding(.horizontal, 10).padding(.vertical, 7) }.buttonStyle(.bordered).disabled(model.running)
        }
    }
    var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.035))
            if let item = model.current, item.thumbnail != nil {
                let isCutout = model.mode == .removeBackground && item.cutoutPreview != nil && !showOriginal
                if isCutout { TransparencyGrid().clipShape(RoundedRectangle(cornerRadius: 18)) }
                ZoomablePreview(itemID: item.id, url: item.url, cutout: isCutout ? item.cutout : nil, zoom: $previewZoom)
                VStack {
                    HStack {
                        badge(isCutout ? "透明预览" : "原图预览")
                        Spacer()
                        if model.mode == .removeBackground, item.cutoutPreview != nil {
                            Button(showOriginal ? "查看抠图" : "查看原图") { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showOriginal.toggle() } }.buttonStyle(.bordered).font(.system(size: 11))
                        }
                        badge(isCutout ? "PNG · 透明" : item.url.pathExtension.uppercased())
                    }
                    Spacer()
                    HStack {
                        badge(item.dimensions)
                        Spacer()
                        HStack(spacing: 10) {
                            Button { previewZoom = max(PreviewViewport.zoomRange.lowerBound, previewZoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                                .help("缩小").accessibilityLabel("缩小图片").disabled(previewZoom <= PreviewViewport.zoomRange.lowerBound)
                            Text("\(Int((previewZoom * 100).rounded()))%")
                                .font(.system(size: 10, design: .monospaced)).frame(minWidth: 40)
                                .accessibilityLabel("相对适应窗口缩放 \(Int((previewZoom * 100).rounded()))%")
                            Button { previewZoom = min(PreviewViewport.zoomRange.upperBound, previewZoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                                .help("放大").accessibilityLabel("放大图片").disabled(previewZoom >= PreviewViewport.zoomRange.upperBound)
                            Divider().frame(height: 12)
                            Button { previewZoom = 1 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                                .help("重置为适应窗口").accessibilityLabel("重置图片缩放")
                        }
                        .buttonStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.black.opacity(0.7), in: Capsule())
                    }
                }.padding(16)
            } else {
                VStack(spacing: 17) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 19).fill(lime.opacity(0.05)).frame(width: 100, height: 100).rotationEffect(.degrees(-12))
                        RoundedRectangle(cornerRadius: 16).stroke(lime.opacity(0.3), lineWidth: 1).frame(width: 78, height: 78).rotationEffect(.degrees(8))
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 34, weight: .light)).foregroundStyle(lime)
                    }
                    Text("把好照片，放进来。") .font(.system(size: 19, weight: .medium))
                    Text("拖放图片到此处，或点击添加图片") .font(.system(size: 12)).foregroundStyle(.gray)
                    Text("HEIC  /  JPG  /  PNG  /  TIFF  /  更多") .font(.system(size: 9, design: .monospaced)).tracking(1).foregroundStyle(.gray.opacity(0.7))
                    Button("选择图片") { model.chooseImages() }.buttonStyle(.bordered).tint(lime)
                }
            }
            if model.running {
                RoundedRectangle(cornerRadius: 18).fill(.black.opacity(0.4))
                VStack(spacing: 14) { ProgressView().controlSize(.large); Text(model.removingBackground ? "正在识别主体，细致分离背景…" : "正在精心处理每一个像素…").font(.system(size: 12)) }.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }.frame(maxWidth: .infinity).frame(height: 310)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.07), lineWidth: 1))
    }
    var fileList: some View {
        VStack(spacing: 12) {
            HStack { Text("处理队列").font(.system(size: 12, weight: .medium)); Text(String(format: "%02d", model.items.count)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.gray); Spacer(); Button("清空") { model.items.removeAll(); model.selected = nil; model.completed = 0 }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.gray).disabled(model.running || model.items.isEmpty) }
            if model.items.isEmpty {
                HStack { Image(systemName: "square.stack"); Text("支持批量处理，灵感无需等待") }.font(.system(size: 12)).foregroundStyle(.gray).frame(maxWidth: .infinity).frame(height: 84).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.items) { item in
                            Button { model.selected = item.id } label: {
                                HStack(spacing: 10) {
                                    if let image = item.thumbnail { Image(nsImage: image).resizable().scaledToFill().frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 7)) }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.url.lastPathComponent).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                        Text(item.error ?? (model.mode == .removeBackground && item.cutout != nil ? "背景已移除 · 可导出透明 PNG" : item.result?.note ?? item.dimensions)).font(.system(size: 10)).foregroundStyle(item.error == nil ? Color.gray : .orange).lineLimit(2)
                                    }
                                    Spacer()
                                    Text(item.result.map { Workspace.bytes($0.outputBytes) } ?? Workspace.bytes(item.bytes)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.gray)
                                    if item.working { ProgressView().controlSize(.small) } else if item.result != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(lime) }
                                }.padding(9).background(model.selected == item.id ? .white.opacity(0.07) : .white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(minHeight: 90, maxHeight: .infinity)
            }
        }
    }
    var settings: some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack { Image(systemName: "dial.low").foregroundStyle(lime); Text("导出设置").font(.system(size: 14, weight: .semibold)) }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                caption("01", "处理方式")
                VStack(spacing: 7) {
                    ForEach(ProcessingMode.allCases) { mode in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { model.mode = mode }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: mode == .removeBackground ? "person.crop.rectangle" : mode == .lossless ? "checkmark.shield" : "arrow.down.right.and.arrow.up.left")
                                    .frame(width: 18)
                                Text(mode.rawValue)
                                Spacer()
                                if model.mode == mode { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 11)
                            .foregroundStyle(model.mode == mode ? lime : Color.white.opacity(0.7))
                            .background(model.mode == mode ? lime.opacity(0.1) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(model.mode == mode ? lime.opacity(0.4) : .clear, lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                caption("02", "目标格式")
                if model.mode == .removeBackground {
                    Label("PNG · 透明背景", systemImage: "checkerboard.rectangle").font(.system(size: 13, weight: .semibold)).foregroundStyle(lime).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(lime.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(OutputFormat.allCases) { format in
                        Button { model.format = format } label: {
                            Text(format.rawValue).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12).background(model.format == format ? lime : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(model.format == format ? base : .gray)
                        }.buttonStyle(.plain)
                    }
                }.disabled(model.mode == .lossless).opacity(model.mode == .lossless ? 0.35 : 1)
                }
            }
            if model.mode != .removeBackground {
            VStack(alignment: .leading, spacing: 12) {
                HStack { caption("03", "画质偏好"); Spacer(); Text("\(Int(model.quality * 100))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(lime) }
                Slider(value: $model.quality, in: 0.5...1).tint(lime).disabled(model.mode == .lossless || model.format == .png || model.format == .tiff)
                HStack { Text("更小体积"); Spacer(); Text("更高画质") }.font(.system(size: 10)).foregroundStyle(.gray)
            }
            } else if model.items.contains(where: { $0.cutout == nil && $0.error != nil }) {
                Button("重新识别未成功的图片") { model.prepareBackgrounds() }
                    .buttonStyle(.bordered).font(.system(size: 10))
            }
        }.padding(20).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16)).disabled(model.running)
    }
    var footer: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.running ? "正在处理 \(model.completed + 1) / \(model.items.count)" : model.completed > 0 ? "处理完成 · \(model.items.compactMap(\.result).count) 张已导出" : "为你的下一张好照片，准备就绪。") .font(.system(size: 12, weight: .medium))
                if model.completed > 0 { Text(model.saved >= 0 ? "共节省 \(Workspace.bytes(model.saved))" : "输出增加 \(Workspace.bytes(-model.saved))").font(.system(size: 10)).foregroundStyle(lime) }
                else { Text("原文件始终保留，所有操作均在本机完成") .font(.system(size: 10)).foregroundStyle(.gray) }
            }
            Spacer()
            if let folder = model.outputFolder, !model.running { Button { NSWorkspace.shared.open(folder) } label: { Image(systemName: "folder") }.buttonStyle(.bordered).help("打开导出文件夹") }
            Button { model.export() } label: { HStack(spacing: 12) { Text(model.running ? "正在处理…" : model.mode == .removeBackground ? "导出透明 PNG" : "开始处理"); Image(systemName: "arrow.up.right") }.font(.system(size: 13, weight: .semibold)).foregroundStyle(base).padding(.horizontal, 26).padding(.vertical, 14).background(lime, in: RoundedRectangle(cornerRadius: 11)) }.buttonStyle(.plain).disabled(model.running || model.items.isEmpty).opacity(model.items.isEmpty ? 0.5 : 1)
        }.padding(.top, 10)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.running)
    }
    func caption(_ number: String, _ title: String) -> some View { HStack(spacing: 8) { Text(number).font(.system(size: 9, design: .monospaced)).foregroundStyle(.gray); Text(title).font(.system(size: 11, weight: .medium)) } }
    func badge(_ text: String) -> some View { Text(text).font(.system(size: 10, design: .monospaced)).padding(.horizontal, 10).padding(.vertical, 6).background(.black.opacity(0.55), in: Capsule()) }
}

private struct TransparencyGrid: View {
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 14
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.17)))
            for row in 0...Int(size.height / side) {
                for column in 0...Int(size.width / side) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)), with: .color(Color(white: 0.22)))
                }
            }
        }.accessibilityHidden(true)
    }
}
