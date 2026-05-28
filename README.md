# EDTA 采血管 OCR 录入系统

基于 Mac 原生 API 的 EDTA 采血管文字识别录入系统，零额外依赖。

## 功能

- 摄像头实时预览拍照
- Vision 框架 OCR 识别中英文
- 自动提取标签字段：姓名、性别、年龄、流水号、采血时间、科室、床号
- 支持用户录入「子弹头编号」，默认按上一条编号自动递增
- 三级识别策略：正则匹配 → 特征推断 → DeepSeek AI（可选）
- 接入 DeepSeek API 后可启用 AI 智能识别，准确率大幅提升
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

## DeepSeek AI 智能识别（可选）

AI 模式可以理解语义，自动分辨哪个字符串是姓名、哪个是流水号，效果远超正则。

### 方式一：环境变量

```bash
export DEEPSEEK_API_KEY=sk-your-key-here
./build_and_run.sh
```

### 方式二：应用内设置

启动应用后，点击首页的「AI 设置」按钮，输入 API Key 保存即可。Key 存储在本地 UserDefaults 中。

### 获取 API Key

前往 [DeepSeek 开放平台](https://platform.deepseek.com/api_keys) 注册并创建 API Key。API 调用按量计费，每条 EDTA 管识别成本约 0.001 元。

### 工作流程（AI 模式下）

1. Vision OCR 快速提取原始文字（< 0.5s）
2. 本地 FieldExtractor 立即显示初步结果
3. DeepSeek AI 异步分析 → 自动覆盖 AI 识别的字段（标注紫色 `AI` 标签）
4. 用户核对并填写/确认子弹头编号 → 存入数据库

未配置 API Key 时，系统仅使用本地字段提取器。

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
│   ├── HistoryView.swift   # 历史记录
│   └── DeepSeekClient.swift # DeepSeek API 客户端
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
    子弹头编号      TEXT,
    采血时间      TEXT,
    科室         TEXT,
    床号         TEXT,
    录入时间      TEXT DEFAULT (datetime('now','localtime'))
);
```

数据库文件 `edta_ocr.db` 在应用启动时自动创建于当前工作目录。
