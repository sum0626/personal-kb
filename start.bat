@echo off
chcp 65001 >nul
title 终生成长知识库 - 一键启动

REM 切换到本 bat 文件所在目录（项目根目录）
cd /d "%~dp0"

echo ========================================
echo  终生成长知识库一键启动
echo ========================================
echo.
echo 正在启动 poller（本机采集轮询服务）...
start "poller" cmd /k "cd /d ""%~dp0"" && .venv\Scripts\activate && python scripts\poller.py"

echo 正在启动前端开发服务器...
cd /d "%~dp0\frontend"
start "frontend" cmd /k "npm run dev"

echo.
echo 启动完成，请等待 3~5 秒后打开浏览器：
echo http://localhost:5173/
echo.
echo 提示：poller 窗口不要关闭，否则「立即采集」按钮不会执行。
echo ========================================

pause
