@echo off
rem 调用 PowerShell 工作区启动脚本，减少手动逐个打开工具的操作。
powershell -ExecutionPolicy Bypass -File "%~dp0tools\start-workspace.ps1"
