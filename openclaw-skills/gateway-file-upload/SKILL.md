---
name: gateway-file-upload
description: 上传文件或长文本到 Gateway 并返回下载链接
---

# Gateway File Upload

当出现以下场景时，使用本技能：

1. 用户明确要求“上传文件 / 给我下载链接 / 把结果转成文件”。
2. 你已经在本地生成了文档、报告、代码包，需要发链接给用户。

执行方式：

```bash
python3 "{baseDir}/upload_to_gateway.py" --file "<绝对路径>" [--agent-name "<agent_name>"] [--user-id "<user_id>"] [--expires-seconds 86400]

# 直接上传文本（无需先手动写文件）
python3 "{baseDir}/upload_to_gateway.py" --text "<文本内容>" --name "reply.md" [--agent-name "<agent_name>"] [--user-id "<user_id>"] [--expires-seconds 86400]
```

规则：

1. 如果用户给了真实路径，优先用 `--file` 上传，不要虚构路径。
2. 如果用户要求“把当前回答转文件”，用 `--text` + `--name` 上传。
3. 上传成功后，必须读取 JSON 输出中的 `download_url`、`expires_at`、`storage_mode` 并反馈给用户。
4. 回复用户时使用简洁模板：
   - `已上传文件：<文件名>`
   - `下载链接：<download_url>`
   - `有效期：<expires_at 或 未设置>`
5. 上传失败时直接返回错误信息，并给出下一步建议（例如检查路径/网络/Token）。
6. 不要在回复中泄露 Token 或任何环境变量。
