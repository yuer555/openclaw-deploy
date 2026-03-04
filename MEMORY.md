# MEMORY

更新时间：2026-03-04 19:34:49 CST

## 当前状态

- 仓库：`/Users/user/Developer/git-resources/ly.com/ai/openclaw-deploy`
- 当前分支：`20260304_fix_wecom_file_parsing`
- 分支状态：`ahead 1`（本地比远端多 1 个 commit）
- 未提交改动：
  - `bin/01-upload.sh`
  - `bin/02-install-gateway.sh`

## 近期关键提交

- `86817e6`：高风险文档直接删除，不保存不下发；并扩展文件类型识别
- `0131a85`：完善微信文件类型识别 + 脚本文案部署引导
- `d98aff4`：修复微信解密后 OOXML（docx/xlsx/pptx）被误判为 zip
- `d8534c5`：共享路径迁移到 `/app/shared`，收口稳定性校验

## 架构与约定（当前生效）

- 宿主机共享目录：`~/.openclaw/workspace-<agent_id>/shared`
- 容器内共享路径：`/app/shared`
- 不再使用 `/workspace/shared`（OpenClaw 沙箱保留前缀冲突）
- 管理命令：`/opt/openclaw/gateway/bin/04-manage-agent.sh ...`（不要 sudo 运行该脚本）

## Token 对齐策略

- 需要保持一致：
  - `gateway.auth.token`
  - `gateway.remote.token`
  - 服务侧 token（systemd daemon 实际使用）
- `bin/03-install-openclaw.sh` 已有：
  - token 自动对齐
  - mismatch 自动修复（必要时 `openclaw gateway install --force`）
  - RPC/doctor 硬校验

## 微信文件处理策略（当前生效）

### 1) 下载与解密

- 微信文件先下载到临时文件，再用 `encoding_aes_key` 进行 AES-CBC 解密
- 采用流式下载，防止大文件内存峰值
- 默认单文件大小上限：20MB（`MAX_DOWNLOAD_FILE_SIZE`）

### 2) 文件类型识别（已支持）

- Office OOXML：`docx/xlsx/pptx`
- Office 变体：`docm/dotx/dotm/xlsm/xltx/xltm/xlsb/pptm/potx/potm/ppsx/ppsm`
- 旧 OLE：`doc/xls/ppt/vsd/wps`
- Visio：`vsdx`
- iWork：`key/numbers/pages`
- ODF：`odt/ods/odp`
- 图片：`png/jpg/jpeg/gif/webp/avif/heic/heif/bmp/tiff/svg`
- 其他：`pdf/zip/drawio/rtf/txt`

### 3) 风险文件处理（已实现）

- 高风险扩展名默认集合：
  - `.docm,.dotx,.dotm,.xlsm,.xltx,.xltm,.xlsb,.pptm,.potx,.potm,.ppsx,.ppsm`
- 命中后：
  - **直接删除临时文件**
  - **不保存到 shared 目录**
  - **不下发给数字人**
  - 返回提示：`[用户发送了一个文件，文件有风险，已删除]`
- 可通过环境变量覆盖：`RISKY_FILE_EXTENSIONS`

## 回归测试结论（本地）

- 使用目录：`/Users/user/Desktop/操作步骤`
- 测试方式：模拟企业微信加密（AES-CBC + PKCS#7）-> 消息解析 -> 文件复原/删除策略验证
- 最终结果：`PASS 33 / FAIL 0`
- 结论：
  - 普通文件可正确解密与扩展名复原
  - 高风险 Office 变体已按策略删除并返回风险提示

## 未提交改动说明（重要）

### `bin/02-install-gateway.sh`

- 已改为：
  - 服务运行中 -> `restart`
  - 服务未运行 -> `start`
- 目的：更新代码后执行安装脚本即可加载最新代码，不再需要手动补重启步骤

### `bin/01-upload.sh`

- 已改为远端部署时“白名单保留”策略：
  - 仅保留：`.env`、`data/`、当前上传包
  - 其余全部删除后再解压
- 目的：避免历史残留文件导致“看起来更新了但实际没生效”

## 部署建议（下一会话可直接用）

1. 提交并推送当前未提交脚本改动（`01-upload.sh`、`02-install-gateway.sh`）
2. 服务器更新流程：
   - 上传/拉取代码
   - 执行：`sudo bash bin/02-install-gateway.sh`
   - 执行：`openclaw gateway restart`
   - 执行：`/opt/openclaw/gateway/bin/04-manage-agent.sh sync-token`
   - 执行：`sudo systemctl restart openclaw-gateway`
3. 验证：
   - `openclaw gateway status`
   - `openclaw doctor`
   - 发一条微信文件消息验证风险删除与普通文件复原
