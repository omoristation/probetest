@echo off
setlocal

:: 生成 monitor.sh 的 MD5
certutil -hashfile "monitor.sh" MD5 | find /i /v "certutil" | find /i /v "MD5" > "monitor.sh.md5"

:: 生成 daemon.sh 的 MD5
certutil -hashfile "daemon.sh" MD5 | find /i /v "certutil" | find /i /v "MD5" > "daemon.sh.md5"

echo MD5 文件生成完成
pause