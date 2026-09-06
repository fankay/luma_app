# Luma

![Luma 应用图标](Assets/AppIcon-source.png)

一款原生 macOS 图片转换与压缩工具。Luma 在本机完成图片处理，支持拖放批量操作、HEIC 输出和严格无损优化。

## 下载与运行

在仓库的 [Releases](https://github.com/fankay/luma_app/releases) 页面下载最新的 `Luma-macOS.zip`，解压后将 `Luma.app` 拖到“应用程序”文件夹，再双击启动。

当前发布包使用临时签名，首次运行时 macOS 可能提示无法验证开发者：在 Finder 中按住 Control 点击 `Luma.app`，选择“打开”，并在随后弹窗中再次选择“打开”。后续正式发布会改用 Developer ID 签名和 Apple 公证。

系统要求：macOS 14 Sonoma 或更高版本，Apple Silicon Mac。

## 功能

- 批量拖放或选择图片，处理过程和结果一目了然。
- 输入支持 macOS ImageIO 可读取的静态图片；输出支持 HEIC、JPEG、PNG、TIFF。
- HEIC / JPEG 可调质量，默认 88%，在体积和画质之间取得平衡。
- 严格无损模式会逐像素验证重新编码结果；只有像素、色彩空间和位深保持一致且文件变小时才会采用优化结果，否则保留原文件字节。
- 自动保留原图，导出文件不会覆盖同名文件，并展示每张图片的处理状态与体积变化。
- 深色原生界面、启动动画和处理反馈动画，同时遵从 macOS“减少动态效果”辅助功能设置。

## 使用方法

1. 将一张或多张图片拖进窗口，或点击“添加图片”。
2. 选择处理方式：
   - **高质量压缩**：选择 HEIC、JPEG、PNG 或 TIFF；HEIC / JPEG 使用有损编码，质量可调。
   - **严格无损**：保持原格式；Luma 会校验输出像素，无法安全缩小时直接复制原文件。
3. 在高质量压缩模式下选择目标格式和画质偏好。
4. 点击“开始处理”，选择导出目录。
5. 完成后点击文件夹按钮查看结果。

### 格式与透明度

| 输出格式 | 特性 | 建议用途 |
| --- | --- | --- |
| HEIC | 高效有损编码，体积通常最小 | Apple 设备、日常照片 |
| JPEG | 广泛兼容的有损编码 | 网页、分享、旧设备 |
| PNG | 无损且支持透明通道 | 截图、图形、透明图片 |
| TIFF | 无损、保留更多专业图像信息 | 存档、专业工作流 |

含透明通道的图像不能导出为 JPEG，以避免透明背景在未提示的情况下被破坏；请使用 PNG 或 HEIC。

## 隐私与限制

所有图片在本机处理，Luma 不上传图片或收集图片内容。

为避免静默丢失内容，多帧动画图和多页图片目前会被拒绝。跨格式转换会尽可能携带源元数据，但不能保证完整保留厂商私有信息、HDR 辅助图及特殊色彩信息。需要存档时请选择“严格无损”。

## 从源码构建

项目使用 Swift Package Manager，无第三方运行时依赖。需要 Xcode 16 或更高版本。

```sh
git clone git@github.com:fankay/luma_app.git
cd luma_app
bash scripts/build-app.sh
open build/Luma.app
```

也可以直接用 Xcode 打开 `Package.swift`，选择 `Luma` scheme 后运行。

### 测试

```sh
swift test
```

测试覆盖 HEIC、JPEG、PNG、TIFF 编码、导出可解码性、无损模式不增大文件、同名导出防覆盖以及源文件保持不变。

### 构建产物与图标

`scripts/build-app.sh` 会生成 `build/Luma.app`，同时调用 `scripts/build-icon.sh` 生成完整的 macOS 图标尺寸集并写入应用包。`build/` 与 SwiftPM 的 `.build/` 均不会提交到仓库。

## 发布

发布流程会构建 `Luma.app`，压缩为 `Luma-macOS.zip` 并上传到 GitHub Release。发布版本应使用 Developer ID 签名和 Apple 公证后再向最终用户分发。

## 许可证

本项目采用 [Apache License 2.0](LICENSE) 许可证。
