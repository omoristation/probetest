@echo off
setlocal

:: 生成 v2ray-arm64 的 MD5
certutil -hashfile "v2ray-arm64" MD5 | find /i /v "certutil" | find /i /v "MD5" > "v2ray-arm64.md5"

:: 生成 v2ray-amd64 的 MD5
certutil -hashfile "v2ray-amd64" MD5 | find /i /v "certutil" | find /i /v "MD5" > "v2ray-amd64.md5"

echo MD5 文件生成完成
pause