# ==========================================================
# 脚本名称：SmartMonitor 自动化安装启动工具
# 功能：一键配置监控脚本为“开机自启+隐藏窗口+最高权限”
# ==========================================================

# 1. 设置路径（请确保你的监控脚本文件名正确）
$MonitorScriptName = "SmartMonitor_EmailAlert.ps1"
$CurrentDir = Get-Location
$ScriptPath = Join-Path $CurrentDir $MonitorScriptName

if (-not (Test-Path $ScriptPath)) {
    Write-Host "错误：未在当前目录找到监控脚本 $MonitorScriptName ！" -ForegroundColor Red
    return
}

# 2. 创建一个中转的 VBS 脚本来实现“完全隐藏窗口”
$VBSPath = Join-Path $CurrentDir "Launcher.vbs"
$VBSContent = @"
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -ExecutionPolicy Bypass -File ""$ScriptPath""", 0, False
"@
$VBSContent | Set-Content -Path $VBSPath -Encoding Default

# 3. 定义任务计划
$TaskName = "DiskSmartMonitor"
$TaskDescription = "24小时硬盘SMART健康监控及邮件告警服务"

# 定义动作：运行 wscript.exe 来执行 VBS
$Action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$VBSPath`""

# 定义触发器：开机自启
$Trigger = New-ScheduledTaskTrigger -AtStartup

# 定义设置：允许在电池模式运行，不停止任务
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0

# 4. 注册任务到系统（需要管理员权限）
try {
    # 如果已存在旧任务，先删除
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    
    # 注册新任务：使用 SYSTEM 账户运行，实现真正的后台静默
    Register-ScheduledTask -TaskName $TaskName `
                           -Action $Action `
                           -Trigger $Trigger `
                           -Settings $Settings `
                           -User "SYSTEM" `
                           -RunLevel Highest `
                           -Description $TaskDescription `
                           -Force

    Write-Host "恭喜！一键配置成功。" -ForegroundColor Cyan
    Write-Host "1. 任务名：$TaskName"
    Write-Host "2. 运行账户：SYSTEM (后台静默)"
    Write-Host "3. 启动方式：开机自动启动"
    Write-Host "4. 日志文件：$CurrentDir\SmartMonitor.log"
    
    # 询问是否现在立即启动
    $choice = Read-Host "是否现在立即启动监控服务？(Y/N)"
    if ($choice -eq "Y" -or $choice -eq "y") {
        Start-ScheduledTask -TaskName $TaskName
        Write-Host "服务已在后台启动。" -ForegroundColor Green
    }
} catch {
    Write-Host "安装失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "请确保以【管理员身份】运行此安装脚本！" -ForegroundColor Yellow
}