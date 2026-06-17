# EDTA 采血管 OCR 录入系统

基于 Mac 原生 API 的 EDTA 采血管文字识别录入系统，可选接入 Qwen VL 视觉模型增强识别。

## 功能

- 摄像头实时预览拍照（支持多摄像头切换）
- Vision 框架本地 OCR（零依赖，< 0.5s）
- Qwen VL 视觉模型直接看图提取字段（可选，需 API Key）
- 自动提取标签字段：姓名、性别、年龄、住院号、采血时间、科室、床号
- 支持用户录入「子弹头编号」，自动递增
- 三级识别策略：正则匹配 → 特征推断 → Qwen VL 视觉识别
- 标本盒孔位计算：81 孔/盒，按子弹头编号排序序号推算盒号和孔位
- 重复检测基于子弹头编号，支持覆盖更新或同时保留
- 用户核对编辑后存入 SQLite3 数据库
- 历史记录查询、编辑、删除、CSV 导出
- 编辑记录时可对已有截图重新 AI 识别
- 全键盘操作（Enter 贯穿首页→拍照→保存→继续）

## 技术栈

| 组件 | 技术 |
|------|------|
| UI | SwiftUI |
| 摄像头 | AVFoundation |
| 本地 OCR | Vision (VNRecognizeTextRequest Revision 3) |
| AI 视觉识别 | Qwen VL (qwen3-vl-flash 等) |
| 数据库 | SQLite3 (C API) |
| 字段提取 | NSRegularExpression + 启发式推断 |

## 运行方式

```bash
git clone https://github.com/hustlxc/EDTA-OCR.git
cd EDTA-OCR
./build_and_run.sh
```

macOS 14.0+，Xcode Command Line Tools 已安装即可，无需额外依赖。

## Qwen VL AI 视觉识别（可选）

Qwen VL 直接"看"采血管标签图片，比纯文本 OCR + LLM 更准确。

### 方式一：环境变量

```bash
export QWEN_API_KEY=sk-your-key-here
./build_and_run.sh
```

### 方式二：应用内设置

启动应用后，点击首页的「配置 Qwen VL API」按钮，输入 API Key 并选择模型即可。Key 存储在本地 UserDefaults 中。

### 可选模型

| 模型 | 说明 |
|------|------|
| `qwen-vl-ocr` | 专为 OCR 优化 |
| `qwen3.6-flash` | 最新·快（默认） |
| `qwen3.6-plus` | 最新·强 |
| `qwen3-vl-flash` | 快速 |
| `qwen3-vl-plus` | 均衡 |

### 工作流程（AI 模式下）

1. Vision OCR 快速提取原始文字（< 0.5s）
2. 本地 FieldExtractor 立即显示初步结果
3. Qwen VL 直接看图提取字段 → 覆盖结果（标注紫色 `AI` 标签）
4. 用户核对 → 保存入库

未配置 API Key 时，系统仅使用本地 Vision OCR + 字段提取器。

## 标本盒孔位计算

每个标本盒有 81 个孔（1-81）。系统将盒子视为连续编号空间：从盒号 1 孔号 1 开始，孔 81 的下一个是盒 2 孔 1。

用户设定起始子弹头编号和对应的盒号、孔号后，所有记录的盒·孔位置自动实时计算。小于起始编号的记录显示为 NA。

## 使用流程

1. 首页配置 Qwen VL API Key 和标本盒起始位置
2. 点击「开始拍照识别」或按 Enter
3. 将 EDTA 采血管对准镜头 → 按空格键拍照
4. Vision OCR 即时识别文字，Qwen VL 异步看图提取
5. 核对/修改识别结果，填写子弹头编号
6. Enter 确认保存
7. 历史记录可查看、编辑、删除、导出 CSV

## 项目结构

```
EDTA-OCR/
├── Package.swift              # Swift Package Manager 配置
├── Sources/EDTAOCR/           # 源代码
│   ├── App.swift              # 应用入口 + 状态管理
│   ├── CameraManager.swift    # 摄像头管理 + 多摄像头切换
│   ├── OCRProcessor.swift     # Vision OCR + 字段提取
│   ├── QwenVLClient.swift     # Qwen VL API 客户端
│   ├── BoxPositionCalculator.swift  # 盒孔位置计算
│   ├── DatabaseManager.swift  # SQLite3 数据库
│   ├── AppPaths.swift         # 路径管理
│   ├── HomeView.swift         # 首页
│   ├── CameraView.swift       # 拍照界面
│   ├── ReviewView.swift       # 审核编辑界面
│   └── HistoryView.swift      # 历史记录 + 编辑删除 + CSV 导出
├── build_and_run.sh           # 编译启动脚本
├── server.py                  # Web 数据库查看器
├── templates/
│   ├── index.html             # 查看器前端
│   └── login.html             # 登录页面
├── merge_db.py                # 合并多个数据库 + 图片
├── merge_embedded_db.py       # 合并含 BLOB 图片的数据库
├── embed_images.py            # 将 PNG 图片嵌入数据库 BLOB 列
├── embed_images.sh            # 批量嵌入 + 合并脚本
└── edta_ocr.db                # 数据库文件（运行时生成）
```

## 数据库结构

```sql
CREATE TABLE records (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    姓名           TEXT,
    性别           TEXT,
    年龄           TEXT,
    住院号         TEXT,
    子弹头编号      TEXT UNIQUE,
    采血时间        TEXT,
    科室           TEXT,
    床号           TEXT,
    原始OCR文本     TEXT,
    录入时间        TEXT DEFAULT (datetime('now','localtime'))
);
```

数据库文件 `edta_ocr.db` 在应用启动时自动创建。子弹头编号为唯一键，重复保存时覆盖更新。

## 合并多个数据库

### 方式一：分离存储（数据库 + captures 目录）

`merge_db.py` 可将多个 EDTA-OCR 数据库及对应 captures/ 目录合并为一个。

```bash
# 准备 paths.txt，每行一对：db_path captures_dir
python3 merge_db.py paths.txt            # 查重（dry run）
python3 merge_db.py paths.txt --force \   # 合并
    --out merged.db --out-captures merged_captures/
python3 merge_db.py paths.txt --force --keep-duplicates \  # 保留所有重复记录
    --out merged.db --out-captures merged_captures/
```

- 冲突时默认最后出现的记录获胜；`--keep-duplicates` 保留全部
- 递归遍历 captures 子目录
- 自动跳过 `_latest.png`（应用临时文件）

### 方式二：内嵌存储（图片 BLOB）

先将每张 PNG 嵌入各自数据库，再合并为单个文件：

```bash
# 第一步：逐条嵌入图片
while read -r db captures; do
    python3 embed_images.py "$db" "$captures" --out "merged_db/$(basename $(dirname "$db")).db"
done < paths.txt

# 或直接运行批量脚本
bash embed_images.sh

# 第二步：合并
python3 merge_embedded_db.py merged_db/ --force --out merged_embedded.db
python3 merge_embedded_db.py merged_db/ --force --keep-duplicates --out merged_embedded.db
```

`--keep-duplicates` 时每个重复编号保留各自来源的图片。

## Web 数据库查看器

基于 Flask 的 Web 界面，用于浏览和管理合并后的数据库。

```bash
# 环境变量（可选，有默认值）
export WEB_USER=admin
export WEB_PASS=your-password
export FIRST_BOX=34
export FIRST_HOLE=29
export START_BULLET=2801

python3 server.py
# → http://localhost:8087
```

**功能：**
- 🔐 登录认证保护
- 📊 分页浏览 10,000+ 条记录
- 🔍 实时搜索（姓名 / 住院号 / 子弹头编号 / 床号）
- 🏥 科室筛选
- 🔄 点击列头排序（支持数字/文本）
- 📦 盒·孔列显示（按排序序号计算）
- 🖼️ 点击记录查看详情 + 原始图片
- 📥 导出 Excel（支持当前筛选条件）
- ⚙️ 在线修改起始管号 / 盒号 / 孔号

## 图片存储说明

图片与记录的关联方式有两种：

| 方式 | 存储 | 查看 |
|------|------|------|
| 分离 | `captures/{{子弹头编号}}.png` | 文件系统 |
| 内嵌 | `records.图片` BLOB 列 | 数据库 |

`server.py` 默认使用内嵌方式（`merged_embedded.db`）。如需从文件系统读取，修改 `DB_PATH` 并恢复 `CAPTURES_DIR` 配置。
