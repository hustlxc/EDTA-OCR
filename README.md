# EDTA 采血管 OCR 录入系统

基于 Mac 原生 API 的 EDTA 采血管文字识别录入系统，零额外依赖。

## 功能

- 摄像头实时预览拍照
- Vision 框架 OCR 识别中英文
- 自动提取 7 个字段：姓名、性别、年龄、流水号、采血时间、科室、床号
- 正则匹配优先，匹配不到时用字段特征启发式推断（标注"推测"）
- 用户核对编辑后存入 SQLite3 数据库
- 历史记录查询

## 技术栈

| 组件 | 技术 |
|------|------|
| UI | SwiftUI |
| 摄像头 | AVFoundation |
| OCR | Vision (VNRecognizeTextRequest) |
| 数据库 | SQLite3 (C API) |
| 字段提取 | NSRegularExpression |

## 运行方式

```bash
git clone https://github.com/hustlxc/EDTA-OCR.git
cd EDTA-OCR
./build_and_run.sh
```

macOS 14.0+，Xcode Command Line Tools 已安装即可，无需额外依赖。

## 可选：PP-OCRv5 模型

本项目默认使用 Mac 自带的 Vision 框架做 OCR。如需使用 PaddleOCR 的 PP-OCRv5 模型（识别精度更高），请下载模型文件：

```bash
# 安装 ModelScope CLI
pip install modelscope

# 下载检测模型和识别模型到项目目录
modelscope download --model PaddlePaddle/PP-OCRv5_server_det --local_dir ./PP-OCRv5_server_det
modelscope download --model PaddlePaddle/PP-OCRv5_server_rec --local_dir ./PP-OCRv5_server_rec
```

模型来源：[PP-OCRv5_server_det - ModelScope](https://modelscope.cn/models/PaddlePaddle/PP-OCRv5_server_det/files)

> 注意：使用 PP-OCRv5 需要额外安装 `paddlepaddle` 和 `paddleocr`，不在本项目零依赖范围内。

## 使用流程

1. 启动应用，点击「打开摄像头并拍照」
2. 弹出摄像头窗口，将 EDTA 采血管对准镜头
3. 点击「拍照识别」或按空格键
4. 系统自动识别文字，展示在审核界面
5. 核对/修改识别结果，点击「确认保存」
6. 数据存入 SQLite3 数据库，可在历史记录中查看

## 项目结构

```
EDTA-OCR/
├── Package.swift           # Swift Package Manager 配置
├── Sources/EDTAOCR/        # 源代码
│   ├── App.swift           # 应用入口 + 状态管理
│   ├── CameraManager.swift # 摄像头管理
│   ├── OCRProcessor.swift  # Vision OCR + 字段提取
│   ├── DatabaseManager.swift # SQLite3 数据库
│   ├── HomeView.swift      # 首页
│   ├── CameraView.swift    # 拍照界面
│   ├── ReviewView.swift    # 审核编辑界面
│   └── HistoryView.swift   # 历史记录
├── build_and_run.sh        # 编译启动脚本
└── edta_ocr.db             # 数据库文件（运行时生成）
```

## 数据库结构

```sql
CREATE TABLE records (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    姓名         TEXT,
    性别         TEXT,
    年龄         TEXT,
    流水号        TEXT,
    采血时间      TEXT,
    科室         TEXT,
    床号         TEXT,
    录入时间      TEXT DEFAULT (datetime('now','localtime'))
);
```

数据库文件 `edta_ocr.db` 在应用启动时自动创建于当前工作目录。
