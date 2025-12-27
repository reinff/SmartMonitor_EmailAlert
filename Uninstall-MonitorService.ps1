# ==========================================================
# 脚本名称：SmartMonitor 自动化卸载工具
# 功能：停止监控并从系统中彻底移除后台任务
# ==========================================================

$TaskName = "DiskSmartMonitor"
$VBSName = "Launcher.vbs"
$CurrentDir = Get-Location
$VBSPath = Join-Path $CurrentDir $VBSName

Write-Host "===== 正在启动卸载程序 =====" -ForegroundColor Cyan

try {
    # 1. 检查任务是否存在
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        Write-Host "提示：未在系统中找到名为 '$TaskName' 的后台任务，可能已经卸载。" -ForegroundColor Yellow
    } else {
        # 2. 停止并删除任务
        Write-Host "正在停止并删除后台任务..." -ForegroundColor White
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "任务计划已成功移除。" -ForegroundColor Green
    }

    # 3. 清理生成的辅助文件
    if (Test-Path $VBSPath) {
        Remove-Item -Path $VBSPath -Force
        Write-Host "已清理辅助启动脚本 (Launcher.vbs)。" -ForegroundColor Green
    }

    # 4. 尝试结束可能残留的进程
    Write-Host "正在清理后台进程..." -ForegroundColor White
    $processes = Get-Process -Name "powershell" -ErrorAction SilentlyContinue | Where-Object { 
        $_.CommandLine -like "*SmartMonitor_EmailAlert.ps1*" 
    }
    if ($processes) {
        $processes | Stop-Process -Force
        Write-Host "已结束正在运行的监控进程。" -ForegroundColor Green
    }

    Write-Host "`n===== 卸载完成！监控服务已彻底停止 =====" -ForegroundColor Cyan
} catch {
    Write-Host "卸载过程中出现错误：$($_.Exception.Message)" -ForegroundColor Red
}