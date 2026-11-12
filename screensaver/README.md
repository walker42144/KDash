# 默认屏保

公开源码使用由项目生成的纯白示例图，不包含私人壁纸。`wallpaper.y8` 是 1072×1448 的 8 位灰度资源；`wallpaper.ttf` 是兼容绘制路径资源。

替换壁纸需要本机安装 Pillow 和 fontTools：

```powershell
python scripts/prepare_wallpaper.py <你的图片> screensaver/wallpaper.ttf
```

该脚本也会生成同目录的 `wallpaper.y8`。请使用有权使用的图片，并在设备升级前备份现有壁纸；不要无意上传私人图片。
