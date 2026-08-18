# AddOn, catalog, and protocol checks

This directory contains the maintained contract checks for the current
SoloCollections AddOn, generated catalog, SC2 wire format, and camera data.
Early phase deployment scripts and the unsafe player-M2 camera experiment are
intentionally not part of the public source line.

Run the portable checks from the repository root:

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
python -m unittest discover -s .\tools\collections\tests -p "test_*.py" -v
```

The checks do not replace an AzerothCore build, a live server session, or
visual acceptance in the 3.3.5a client. See:

- [`docs/BUILDING.en.md`](../../docs/BUILDING.en.md)
- [`docs/BUILDING.zh-CN.md`](../../docs/BUILDING.zh-CN.md)
- [`docs/CAMERA_CONTRIBUTIONS.md`](../../docs/CAMERA_CONTRIBUTIONS.md)

## 中文

本目录只保留当前 AddOn、生成目录、SC2 协议和镜头数据的可移植检查。早期部署
脚本以及已确认不适合生产的玩家 M2 追加 camera 实验不再随公共源码保留。

这些检查不能代替 AzerothCore 编译、真实服务端运行或 3.3.5a 客户端视觉验收。
