# EDTA 采血管 OCR 录入系统

基于 Mac 原生 API 的 EDTA 采血管文字识别录入系统，零额外依赖。

## 功能

- 摄像头实时预览拍照
- Vision 框架 OCR 识别中英文
- 自动提取标签字段：姓名、性别、年龄、住院号、采血时间、科室、床号
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

## 部署 PP-OCRv5 OCR API 服务到 s4

本仓库提供了一个 FastAPI 服务，行为与 `ocr_daemon.py` 对齐，封装 PaddleOCR 的完整 OCR pipeline：

- `GET /health`：检查服务与模型配置
- `POST /ocr`：上传图片文件并返回识别文字、置信度和 bbox
- `POST /ocr/json`：传入服务器本地 `image_path` 或 `image_base64`
- `POST /detect` 和 `POST /detect/json`：兼容别名，返回同样的 OCR 结果

默认模型与 `ocr_daemon.py` 一致：

- 检测：`PP-OCRv5_mobile_det`
- 识别：`PP-OCRv5_mobile_rec`

首次部署前，请确保本机可以免密码登录 `s4`：

```bash
ssh-copy-id s4
ssh s4 'hostname'
```

部署并启动：

```bash
./deploy_ppocr_api_s4.sh
```

默认部署目录是 `s4:~/edta-ppocr-api`，可用 `REMOTE_DIR=/path/to/dir` 覆盖。脚本默认不创建虚拟环境，也不安装依赖；它使用 `s4` 上已有的 `python3` 和已安装包。若需要临时安装依赖，可显式设置 `INSTALL_DEPS=1`。

默认服务只监听 `s4` 本机 `127.0.0.1:8008`。在本机打开 SSH 隧道后调用：

```bash
ssh -N -L 8008:127.0.0.1:8008 s4
curl http://127.0.0.1:8008/health
curl -F "file=@captures/example.png" http://127.0.0.1:8008/ocr
```

服务使用 `nohup` 后台运行，不依赖 `tmux`。在 `s4` 上查看或停止：

```bash
cd ~/edta-ppocr-api
tail -f ppocr-api.log
kill "$(cat ppocr-api.pid)"
```

常用配置：

```bash
# 使用 GPU 0
PPOCR_DEVICE=gpu:0 ./deploy_ppocr_api_s4.sh

# 如需由脚本安装依赖，再启用 INSTALL_DEPS
INSTALL_DEPS=1 PADDLE_PACKAGE=paddlepaddle-gpu PPOCR_DEVICE=gpu:0 ./deploy_ppocr_api_s4.sh

# 改端口
PORT=8010 ./deploy_ppocr_api_s4.sh

# 使用 ModelScope 下载到本地的模型目录
PPOCR_DET_MODEL_DIR=/path/to/PP-OCRv5_mobile_det \
PPOCR_REC_MODEL_DIR=/path/to/PP-OCRv5_mobile_rec \
./deploy_ppocr_api_s4.sh
```

GPU 是否可用可在 `s4` 上检查：

```bash
cd ~/edta-ppocr-api
python - <<'PY'
import paddle
paddle.utils.run_check()
print(paddle.device.get_device())
PY
```

如果 `paddle.device.get_device()` 显示 `gpu:0`，服务启动时设置 `PPOCR_DEVICE=gpu:0` 即可使用 GPU。PaddleOCR 的 `device` 参数支持 `cpu`、`gpu`、`gpu:0`、`gpu:0,1` 等写法。

## 使用流程

1. 启动应用，点击「打开摄像头并拍照」
2. 弹出摄像头窗口，将 EDTA 采血管对准镜头
3. 点击「拍照识别」或按空格键
4. 系统自动识别文字，展示在审核界面
5. 核对/修改识别结果，点击「确认保存」
6. 数据存入 SQLite3 数据库，可在历史记录中查看

## DeepSeek AI 智能识别（可选）

AI 模式可以理解语义，自动分辨哪个字符串是姓名、哪个是住院号，效果远超正则。

## OCR 引擎选择

首页提供两种 OCR 引擎：

| 引擎 | 特点 | 依赖 |
|------|------|------|
| Mac Vision | 系统自带，零依赖，速度快 | 无 |
| PP-OCRv5 | 中文更准，手写/旋转/小字效果好 | `pip3 install paddlepaddle paddleocr` |

PP-OCRv5 首次启动需加载模型（2-3 秒），之后推理速度与 Vision 相当。

## DeepSeek AI 智能识别（可选）

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
│   ├── DeepSeekClient.swift # DeepSeek API 客户端
│   └── PaddleOCRClient.swift # PP-OCRv5 桥接客户端
├── ocr_daemon.py            # PP-OCRv5 Python 守护进程
├── build_and_run.sh         # 编译启动脚本
└── edta_ocr.db             # 数据库文件（运行时生成）
```

## 数据库结构

```sql
CREATE TABLE records (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    姓名         TEXT,
    性别         TEXT,
    年龄         TEXT,
    住院号        TEXT,
    子弹头编号      TEXT,
    采血时间      TEXT,
    科室         TEXT,
    床号         TEXT,
    录入时间      TEXT DEFAULT (datetime('now','localtime'))
);
```

数据库文件 `edta_ocr.db` 在应用启动时自动创建于当前工作目录。
