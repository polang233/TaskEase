# TaskEase 图标

叠层双叶通过错位轮廓与弧形留白表达前后台任务。后台叶片使用青色 `#43CDD2`，前台叶片使用浅绿 `#B1F293`；应用图标采用深青色背景，由 Icon Composer 渲染两层独立材质、光照和阴影。

<img src="AppIcon-preview.png" width="160" alt="默认应用图标"> <img src="AppIcon-dark-preview.png" width="160" alt="深色应用图标">

菜单栏采用相同轮廓的单色模板，逻辑尺寸为 18pt，分别提供 18px 和 36px 资源。系统按菜单栏背景处理颜色；窗口和菜单面板使用彩色标识。

## 资源

| 文件 | 用途 |
| --- | --- |
| `TaskEaseMark.svg` | 统一矢量源，包含前后台两个命名轮廓 |
| `TaskEaseMark.png` | 矢量源的透明 PNG 导出 |
| `../TaskEase/Resources/AppIcon.icon/` | 原生图标文档，两片叶片分别使用 SVG 图层 |
| `../TaskEase/Resources/Assets.xcassets/TaskEaseMark.imageset/` | 窗口和菜单面板的彩色标识 |
| `../TaskEase/Resources/Assets.xcassets/TaskEaseMenu.imageset/` | 18pt 菜单栏模板，包含 1x 与 2x 资源 |
| `AppIcon-preview.png`、`AppIcon-dark-preview.png` | Apple 渲染器导出的默认和深色外观 |
| `Concepts/` | 设计概念及菜单栏效果示意 |

## 制作与构建

概念预览使用内置 imagegen 生成，提示词保存在 [概念说明](Concepts/README.md) 与 [菜单栏说明](Concepts/TaskEase-A-menubar-preview.md)。正式轮廓整理为 SVG，全部资源从同一矢量源生成。

在仓库根目录执行：

```sh
xcrun swift -module-cache-path /private/tmp/taskease-layered-icon-cache Scripts/prepare-branding.swift
sh Scripts/build-app.sh
```

脚本按后叶、前叶的顺序导出两个 1024px 画布的 SVG 图层，并直接栅格化彩色标识与菜单栏模板。菜单栏两层各向外调整 0.3pt，保证 1x 与 2x 轮廓间的留白；图层保持一致的坐标，圆角遮罩、材质与阴影由 Icon Composer 处理。

应用目标的 App Icon 名称为 `AppIcon`，对应 `Resources/AppIcon.icon`。Xcode 自动生成不同尺寸、外观和较早系统使用的静态图标。传统尺寸槽位的 16pt / 2x 表示 32px；本工程的尺寸由原生图标文档统一生成。流程依据 [Apple Icon Composer 文档](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)。

使用 Xcode 随附的渲染器更新文档预览：

```sh
icon_tool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
"$icon_tool" "$PWD/TaskEase/Resources/AppIcon.icon" --export-image --output-file "$PWD/Branding/AppIcon-preview.png" --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
"$icon_tool" "$PWD/TaskEase/Resources/AppIcon.icon" --export-image --output-file "$PWD/Branding/AppIcon-dark-preview.png" --platform macOS --rendition Dark --width 512 --height 512 --scale 1
```

构建与资源核验记录见 [品牌验证](../Artifacts/branding-resources.json)。

README 的界面图片使用实际视图与示例模型离屏渲染，先构建应用，再运行 `bash Scripts/render-previews.sh`。该程序使用独立资源包，不读取用户配置，并在完成后清理临时构建文件。
