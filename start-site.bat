@echo off
rem ============================================
rem 运维知识库网站 - 一键启动(本地预览)
rem 启动后浏览器访问 http://127.0.0.1:8000
rem Ctrl+C 停止
rem ============================================
cd /d "E:\Documents\Hermes knowledge"
py -3.11 -m mkdocs serve -a 127.0.0.1:8000
