# =================================================================================
# 脚本名称：硬盘 SMART 状态稳健监控脚本 (.NET 发信版)
# =================================================================================

# 强制开启 TLS 1.2 加密协议
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# -------------------------- 1. 配置项 --------------------------
$smtpConfig = @{
    SmtpServer  = "smtp.163.com"
    Port        = 25                    # 建议先试 25，若不通再改 587
    From        = "F@163.com"           # 填入发信邮箱账号
    To          = "A@163.com,B@qq.com"  # 多个地址用逗号或分号
    User        = "F@163.com"           # 填入发信邮箱账号
    Pass        = "XXXXXX"              # 填入授权码
    UseSsl      = $true
    Subject     = "【紧急告警】服务器硬盘SMART异常" # 邮件主题
}

$monitorConfig = @{
    CheckInterval = 10 * 60            # 检测间隔：10分钟
    AlertInterval = 30 * 60            # 告警频率：30分钟
    LogPath       = "C:\Users\reinf\Desktop\diskSmart\SmartMonitor.log"
    LastAlertPath = "C:\Users\reinf\Desktop\diskSmart\LastAlert_Time.txt"
}

# -------------------------- 2. 工具函数 --------------------------

function Write-MonitorLog {
    param([string]$Content, [string]$Level = "Info")
    
    # 确保目录存在
    $logDir = [System.IO.Path]::GetDirectoryName($monitorConfig.LogPath)
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
    
    $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Content"
    $logEntry | Add-Content -Path $monitorConfig.LogPath -Encoding UTF8
    
    # 颜色控制
    if ($Level -eq "Error") {
        Write-Host $logEntry -ForegroundColor Red
    } elseif ($Level -eq "Warn") {
        Write-Host $logEntry -ForegroundColor Yellow
    } else {
        Write-Host $logEntry -ForegroundColor White
    }
}

<#
.NET 发信函数
#>
function Send-RobustEmail {
    param([string]$HtmlBody)
    try {
        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = $smtpConfig.From
        foreach ($address in $smtpConfig.To -split "[,;]") {
            if ($address.Trim()) { $mail.To.Add($address.Trim()) }
        }
        $mail.Subject = $smtpConfig.Subject
        $mail.Body = $HtmlBody
        $mail.IsBodyHtml = $true

        $smtp = New-Object System.Net.Mail.SmtpClient($smtpConfig.SmtpServer, $smtpConfig.Port)
        $smtp.EnableSsl = $smtpConfig.UseSsl
        $smtp.Credentials = New-Object System.Net.NetworkCredential($smtpConfig.User, $smtpConfig.Pass)
        
        # 执行发送
        $smtp.Send($mail)
        $mail.Dispose()
        $smtp.Dispose()
        return $true
    }
    catch {
        Write-MonitorLog -Content "邮件发信底层报错：$($_.Exception.Message)" -Level "Error"
        return $false
    }
}

function Send-AlertEmail {
    param([Array]$ErrorDiskList)

    $emailBody = "<h2>服务器硬盘SMART异常告警</h2><p>时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>"
    foreach ($disk in $ErrorDiskList) {
        $dNum = if($disk.DiskNumber){$disk.DiskNumber}else{"Unknown"}
        $dName = if($disk.DiskName){$disk.DiskName}else{"Unknown"}
        
        $emailBody += @"
        <div style='border:1px solid #ccc; padding:10px; margin-bottom:10px;'>
            <b>硬盘编号：</b> $dNum <br/>
            <b>名称：</b> $dName <br/>
            <b>状态：</b> <span style='color:red;'>$($disk.HealthStatus)</span> <br/>
            <b>异常描述：</b> $($disk.ErrorMsg)
        </div>
"@
    }

    if (Send-RobustEmail -HtmlBody $emailBody) {
        Write-MonitorLog -Content "告警邮件已成功送达至：$($smtpConfig.To)" -Level "Warn"
        Set-Content -Path $monitorConfig.LastAlertPath -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
}

# -------------------------- 3. 检测逻辑 --------------------------
# 初始化全局哈希表 存储上次状态
if ($null -eq $global:LastDiskErrors) { $global:LastDiskErrors = @{} }
function Test-AllSmart {
    $errorDiskList = @()
    try {
        $allDisks = Get-PhysicalDisk
        foreach ($disk in $allDisks) {
            $isError = $false
            $msg = ""
            $id = $disk.DeviceId # 使用 DeviceId 作为唯一标识
            
            # 获取当前计数器
            $counters = Get-StorageReliabilityCounter -PhysicalDisk $disk
            $currentRead = if ($null -ne $counters.ReadErrorsTotal) { $counters.ReadErrorsTotal } else { 0 }
            $currentWrite = if ($null -ne $counters.WriteErrorsTotal) { $counters.WriteErrorsTotal } else { 0 }

            # 如果是第一次运行，记录当前值，但不告警 除非已经是预测性故障
            if (-not $global:LastDiskErrors.ContainsKey($id)) {
                $global:LastDiskErrors[$id] = @{ Read = $currentRead; Write = $currentWrite }
            }

            # 获取上次记录的值
            $lastRead = $global:LastDiskErrors[$id].Read
            $lastWrite = $global:LastDiskErrors[$id].Write

            # 1. 基础健康检查
            if ($disk.HealthStatus -ne "Healthy") {
                $isError = $true; $msg += "状态异常: $($disk.HealthStatus); "
            }

            # 2. 预测故障
            if ($counters.PredictiveFailure -eq $true) {
                $isError = $true; $msg += "预测故障(SMART Warning): 紧迫感:极高 硬盘在接下来的 24 小时到 60 天内，发生灾难性硬件失效的概率可能超过 60%; "
            }

            # 3. 读取/写入错误 增量判断
            if ($currentRead -gt $lastRead) {
                $newErrors = $currentRead - $lastRead
                $isError = $true; $msg += "新增读取错误: $newErrors (总计: $currentRead); "
            }
            if ($currentWrite -gt $lastWrite) {
                $newErrors = $currentWrite - $lastWrite
                $isError = $true; $msg += "新增写入错误: $newErrors (总计: $currentWrite); "
            }

            # 4. 温度检查
            $tempThreshold = 50
            if ($disk.MediaType -eq "SSD") { $tempThreshold = 65 }

            if ($null -ne $counters.Temperature -and $counters.Temperature -gt $tempThreshold) {
                $isError = $true; $msg += "温度过高: $($counters.Temperature)℃; "
            }

            # 更新记录，以便下次对比
            $global:LastDiskErrors[$id].Read = $currentRead
            $global:LastDiskErrors[$id].Write = $currentWrite

            if ($isError) {
                $errorDiskList += New-Object PSObject -Property @{
                    DiskNumber   = $disk.DeviceId
                    DiskName     = "$($disk.FriendlyName) ($($disk.MediaType))"
                    HealthStatus = $disk.HealthStatus
                    ErrorMsg     = $msg.TrimEnd("; ")
                }
            }
        }
    } catch {
        Write-MonitorLog -Content "硬盘扫描失败：$($_.Exception.Message)" -Level "Error"
    }
    return $errorDiskList
}

# -------------------------- 主程序运行 --------------------------

Write-Host "===== SMART 监控服务已启动 =====" -ForegroundColor Cyan

try {
    # 数组确保 .Count 生效
    $initialDisks = @(Get-PhysicalDisk)
    $global:diskCount = $initialDisks.Count  # 使用 global 确保全局可见
    
    $initLog = "初始化检查：系统当前识别到 $($global:diskCount) 块物理硬盘。"
    Write-MonitorLog -Content $initLog -Level "Info"
    
    Write-Host "--------------------------------------------------" -ForegroundColor Gray
    foreach ($d in $initialDisks) {
        # 计算容量，增加非空保护
        $sizeGB = 0
        if ($d.Size) { $sizeGB = [math]::Round($d.Size / 1GB, 2) }
        
        # 格式化输出
        $info = "ID:{0} | {1} | {2} | {3}GB | {4}" -f $d.DeviceId, $d.MediaType, $d.HealthStatus, $sizeGB, $d.FriendlyName
        Write-Host "  [硬盘检测] $info" -ForegroundColor White
    }
    Write-Host "--------------------------------------------------" -ForegroundColor Gray

} catch {
    Write-MonitorLog -Content "初始化识别硬盘失败：$($_.Exception.Message)" -Level "Error"
    $global:diskCount = 0
}

# # --- 测试环节：测试发信 ---
# $testDisk = @(New-Object PSObject -Property @{
#     DiskNumber   = "TEST"
#     DiskName     = "发信连接测试"
#     HealthStatus = "Warning"
#     ErrorMsg     = "当你看到这封邮件说明脚本已经在正常运行。"
# })
# Send-AlertEmail -ErrorDiskList $testDisk
# Write-Host "测试邮件已发出，请检查邮箱。脚本将在10秒后进入常规循环..." ; Start-Sleep -Seconds 10
# # --- 测试环节结束 ---



Write-Host "`n监控循环已开启，每隔 $($monitorConfig.CheckInterval) 秒检测一次..." -ForegroundColor Cyan

while ($true) {
    # 1. 检测当前的 SMART 异常情况
    $errors = Test-AllSmart
    
    # 2. 检测硬盘数量变动逻辑
    try {
        $currentDisks = @(Get-PhysicalDisk)
        $currentCount = $currentDisks.Count
        
        # 如果当前数量小于初始启动时的数量，手动构造一个丢盘错误
        if ($currentCount -lt $global:diskCount) {
            $lostCount = $global:diskCount - $currentCount
            $lostDiskError = New-Object PSObject -Property @{
                DiskNumber   = "CRITICAL"
                DiskName     = "硬件丢失告警"
                HealthStatus = "离线"
                ErrorMsg     = "系统检测到有 $lostCount 块硬盘失联！预期 $global:diskCount 块，当前仅剩余 $currentCount 块。请检查 Hyper-V 透传状态或物理接线。"
            }
            $errors += $lostDiskError
            Write-MonitorLog -Content "警告：检测到硬盘数量减少！" -Level "Error"
        }
    } catch {
        Write-MonitorLog -Content "数量统计逻辑异常：$($_.Exception.Message)" -Level "Error"
    }

    # 3. 判断是否需要发信
    if ($errors.Count -gt 0) {
        # 频率控制逻辑
        $needAlert = $true
        if (Test-Path $monitorConfig.LastAlertPath) {
            $lastTime = [DateTime]::Parse((Get-Content $monitorConfig.LastAlertPath))
            if (((Get-Date) - $lastTime).TotalSeconds -lt $monitorConfig.AlertInterval) {
                $needAlert = $false
            }
        }

        if ($needAlert) {
            Send-AlertEmail -ErrorDiskList $errors
        } else {
            Write-MonitorLog -Content "检测到异常但处于静默期，跳过发信。"
        }
    } else {
        Write-MonitorLog -Content "所有硬盘状态良好。"
    }

    Start-Sleep -Seconds $monitorConfig.CheckInterval
}