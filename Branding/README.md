# TaskEase 图标

## 图形与颜色

标识由两片错位、收拢的叶片组成。弧形间隙表达应用前后台之间的切换，双叶组成一个紧凑轮廓。

- 后叶采用青绿色，目标色值 `#30BBA9`。
- 前叶采用浅绿色，目标色值 `#B9F37B`。
- 应用图标采用深青绿色背景，由 Icon Composer 应用渐变、光照和材质。
- 菜单栏使用双叶轮廓的 template image，颜色随系统外观变化。

## 资源

| 文件 | 用途 |
| --- | --- |
| `TaskEaseMark.png` | 带透明通道的图形源文件 |
| `../TaskEase/Resources/AppIcon.icon/` | 可在 Icon Composer 中打开的原生图标文件 |
| `../TaskEase/Resources/Assets.xcassets/TaskEaseMark.imageset/` | 窗口和菜单面板的彩色标识 |
| `../TaskEase/Resources/Assets.xcassets/TaskEaseMenu.imageset/` | 菜单栏单色标识 |
| `AppIcon-preview.png` | 从 Xcode 编译产物导出的图标预览 |

图形源文件通过内置 imagegen 生成。资源制作脚本保留源文件，将前景归一为 1024 像素图层，并为界面资源调整透明边距和尺寸。在项目根目录执行：

```sh
xcrun swift -module-cache-path /tmp/taskease-branding-module-cache Scripts/prepare-branding.swift
```

然后在 Xcode 中构建。图标采用简单正视轮廓、充足留白、分层透明前景和系统材质，依据 [Apple 图标设计说明](https://developer.apple.com/videos/play/wwdc2025/220/) 与 [Icon Composer 文档](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)。

## 生成规格

使用内置 imagegen，生成透明 PNG 前景。最终前景规格为两片宽而平滑的叶片，保留弧形间隙，表面采用青绿与浅绿，居中约占画布宽高的 65%。轮廓用于 16 像素以上的标识；图标材质由 Icon Composer 处理。

最终修整提示词：

> Refine this two-leaf TaskEase logo into production-ready flat vector-like artwork. Keep the exact two-piece composition, diagonal flow and broad curved seam. Rebuild both contours as perfectly smooth, simple Bezier shapes, removing every stray colored pixel, spike, speck, little notch and rough fringe. Give each exposed tip a softly rounded cap. The leaf surfaces must be perfectly uniform opaque solid colors: turquoise #30BBA9 above, mint #B9F37B below, no gradients or texture. Center the mark optically in a square canvas with equal transparent margins and about 65 percent coverage. True transparent alpha everywhere outside the two shapes and through the seam. No additional symbol, text, tile, outline, stem, shadows, reflections or material effects. This is the source layer for Apple Icon Composer; precision silhouettes are essential.
