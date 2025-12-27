# SmartMonitor_EmailAlert
window 环境 一件配置自启动任务 监控硬盘Smart信息并发送邮件; powershell底层.NET发送邮件服务



**该脚本是为了在windows宿主机中监控 直连到hyperV虚拟机中的硬盘smart状态信息（非DDA直通SATA控制器的场景）**

**脚本编码GBK，编辑前请确认。**

**使用方式**
1. 双击执行`一件安装监控服务.bat`


- `SmartMonitor_EmailAlert.ps1` —— **核心监控**

  - 配置

    `CheckInterval` 

    如果设置了硬盘休眠，间隔建议大一点；

    检测时会唤醒影响（**机械硬盘频繁启停可能会影响寿命）；**

    ```powershell
    $smtpConfig = @{
        SmtpServer  = "smtp.163.com"
        Port        = 25              		# 建议先试 25，若不通再改 587
        From        = "F@163.com"           # 填入发信邮箱账号
        To          = "A@163.com,B@qq.com"  # 多个地址用逗号或分号
        User        = "F@163.com"           # 填入发信邮箱账号
        Pass        = "XXXXXX"          	# 填入授权码
        UseSsl      = $true
        Subject     = "【紧急告警】服务器硬盘SMART异常" # 邮件主题
    }
    ```

    **安装任务运行时，日志路径建议使用绝对路径** 

     ```powershell
    $monitorConfig = @{
        CheckInterval = 10 * 60            # 检测间隔：10分钟
        AlertInterval = 30 * 60            # 告警频率：30分钟
        LogPath       = "C:\Users\reinf\Desktop\diskSmart\SmartMonitor.log"
        LastAlertPath = "C:\Users\reinf\Desktop\diskSmart\LastAlert_Time.txt"
    }
     ```



目录

- `Install-MonitorService.ps1` —— **任务安装逻辑**

- `Uninstall-MonitorService.ps1` —— **任务卸载逻辑**

- **`一键安装监控服务.bat`** —— **双击安装入口**

- **`一键卸载监控服务.bat`** —— **双击卸载入口**





**测试系统**

- windows 11
- windows 10
