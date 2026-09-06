# Luma 应用图标

使用内置 imagegen 生成。源图保留透明背景；build-icon.sh 通过系统 sips 生成 16–1024 像素的标准 iconset，再由 iconutil 生成 AppIcon.icns。build-app.sh 将图标复制到应用 Resources，并通过 CFBundleIconFile 配置 Finder 与 Dock 图标。

生成提示词：

Use case: logo-brand. Create one production-ready macOS application icon for Luma, a native image converter and compressor. Square 1024x1024 PNG with genuine transparent background outside the icon. Centered macOS rounded-square charcoal tile occupying about 84% of canvas width, with subtle bevel and refined soft shadow. Inside: two beautifully layered rounded photo cards, the front card in luminous lime green (#C7F56E), a simple dark mountain silhouette and circular sun cut into the front card; rear card dark sage slightly rotated, suggesting batch image conversion and compactness. Premium restrained three-dimensional macOS icon craftsmanship, crisp bold silhouette legible at 32px, mostly front view, subtle lighting from upper left, elegant minimal geometry. Match a charcoal and lime productivity app. No letters, no text, no watermark, no extra objects, no mockup, no surrounding scenery. Actual transparent alpha outside rounded tile, not checkerboard.
