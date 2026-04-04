# 工作环境一键启动

双击这个文件即可启动：

`C:\Users\huawei\Desktop\project_codex\一键启动工作环境.bat`

真正控制启动内容的是这个配置文件：

`C:\Users\huawei\Desktop\project_codex\tools\workday-startup.json`

## 你现在可以改的地方

### 1. 打开哪些网页

修改 `chrome.urls`，例如：

```json
"urls": [
  "https://chatgpt.com/",
  "https://mail.google.com/"
]
```

### 2. VS Code 打开什么

修改 `vscode.targets`，可以放文件夹，也可以放文件：

```json
"targets": [
  "C:\\Users\\huawei\\Desktop\\project_codex",
  "C:\\Users\\huawei\\Desktop\\notes\\daily.md"
]
```

### 3. 自动打开哪些笔记

修改 `documents.paths`，例如：

```json
"paths": [
  "C:\\Users\\huawei\\Desktop\\notes\\daily.md",
  "C:\\Users\\huawei\\Desktop\\notes\\todo.md"
]
```

如果 `openWith` 是 `vscode`，这些文档会用 VS Code 打开。

如果 `openWith` 是 `default`，这些文档会按系统默认方式打开。

## 预演测试

如果你想先测试逻辑、不真正打开软件，可以在 PowerShell 里运行：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\start-workspace.ps1" -DryRun
```
