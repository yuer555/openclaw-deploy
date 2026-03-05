#!/usr/bin/env python3
import argparse
import json
import mimetypes
import os
import sys
import tempfile
import urllib.error
import urllib.request
import uuid


def _build_multipart_form(fields, file_field, file_path):
    boundary = f"----openclaw{uuid.uuid4().hex}"
    chunks = []

    for key, value in fields.items():
        if value is None or value == '':
            continue
        chunks.extend([
            f"--{boundary}\r\n".encode('utf-8'),
            f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode('utf-8'),
            str(value).encode('utf-8'),
            b"\r\n",
        ])

    filename = os.path.basename(file_path)
    content_type = mimetypes.guess_type(filename)[0] or 'application/octet-stream'
    with open(file_path, 'rb') as f:
        file_data = f.read()

    chunks.extend([
        f"--{boundary}\r\n".encode('utf-8'),
        f'Content-Disposition: form-data; name="{file_field}"; filename="{filename}"\r\n'.encode('utf-8'),
        f"Content-Type: {content_type}\r\n\r\n".encode('utf-8'),
        file_data,
        b"\r\n",
        f"--{boundary}--\r\n".encode('utf-8'),
    ])

    body = b''.join(chunks)
    headers = {
        'Content-Type': f'multipart/form-data; boundary={boundary}',
        'Content-Length': str(len(body)),
    }
    return body, headers


def _env_required(name):
    value = os.getenv(name, '').strip()
    if not value:
        raise RuntimeError(f"缺少环境变量: {name}")
    return value


def _safe_upload_name(name):
    base = os.path.basename((name or '').strip())
    if not base:
        return 'upload.txt'
    return base


def _prepare_upload_file(args):
    """准备上传文件路径，支持 --file 或 --text"""
    has_file = bool((args.file or '').strip())
    has_text = bool((args.text or '').strip())

    if has_file == has_text:
        raise RuntimeError('必须且只能传入 --file 或 --text 其中一个')

    if has_file:
        file_path = os.path.abspath(args.file)
        if not os.path.isfile(file_path):
            raise RuntimeError(f"文件不存在: {file_path}")
        return file_path, None

    upload_name = _safe_upload_name(args.name)
    temp_dir = os.getenv('OPENCLAW_FILE_UPLOAD_TEMP_DIR', '').strip() or tempfile.gettempdir()
    os.makedirs(temp_dir, exist_ok=True)
    temp_path = os.path.join(temp_dir, f"upload-{uuid.uuid4().hex[:8]}-{upload_name}")
    with open(temp_path, 'w', encoding='utf-8') as f:
        f.write(args.text)
    return temp_path, temp_path


def main():
    parser = argparse.ArgumentParser(description='通过 Gateway 内部接口上传文件并返回下载链接')
    parser.add_argument('--file', default='', help='本地文件绝对路径')
    parser.add_argument('--text', default='', help='直接上传文本内容')
    parser.add_argument('--name', default='upload.txt', help='使用 --text 时的文件名')
    parser.add_argument('--agent-name', default='', help='可选，网关 agent 名称')
    parser.add_argument('--user-id', default='', help='可选，业务用户标识')
    parser.add_argument('--source', default='openclaw-skill', help='上传来源标识')
    parser.add_argument('--msg-type', default='internal_upload', help='文件消息类型')
    parser.add_argument('--expires-seconds', type=int, default=0, help='覆盖默认链接过期秒数')
    args = parser.parse_args()

    file_path, cleanup_path = _prepare_upload_file(args)

    gateway_url = _env_required('OPENCLAW_FILE_UPLOAD_GATEWAY_URL').rstrip('/')
    token = _env_required('OPENCLAW_FILE_UPLOAD_TOKEN')

    expires_seconds = args.expires_seconds
    if expires_seconds <= 0:
        env_expires = os.getenv('OPENCLAW_FILE_UPLOAD_EXPIRES', '').strip()
        if env_expires:
            try:
                expires_seconds = int(env_expires)
            except ValueError:
                raise RuntimeError('OPENCLAW_FILE_UPLOAD_EXPIRES 必须为整数')

    body, form_headers = _build_multipart_form(
        fields={
            'agent_name': args.agent_name,
            'user_id': args.user_id,
            'source': args.source,
            'msg_type': args.msg_type,
            'expires_seconds': expires_seconds if expires_seconds > 0 else '',
        },
        file_field='file',
        file_path=file_path,
    )

    url = f"{gateway_url}/internal/files/upload"
    req = urllib.request.Request(
        url,
        data=body,
        method='POST',
        headers={
            'Authorization': f'Bearer {token}',
            **form_headers,
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            payload = resp.read().decode('utf-8', errors='replace')
            data = json.loads(payload)
            print(json.dumps(data, ensure_ascii=False))
    except urllib.error.HTTPError as e:
        detail = e.read().decode('utf-8', errors='replace') if hasattr(e, 'read') else str(e)
        raise RuntimeError(f"Gateway 返回 HTTP {e.code}: {detail}")
    except urllib.error.URLError as e:
        raise RuntimeError(f"请求 Gateway 失败: {e}")
    finally:
        if cleanup_path and os.path.isfile(cleanup_path):
            try:
                os.remove(cleanup_path)
            except Exception:
                pass


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(json.dumps({'status': 'error', 'error': str(e)}, ensure_ascii=False), file=sys.stderr)
        sys.exit(1)
