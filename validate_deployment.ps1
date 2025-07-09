# MySQL InnoDB Cluster 部署验证脚本 (PowerShell版本)
# 这个脚本会全面检查项目的完整性和可部署性

param(
    [switch]$Verbose
)

# 计数器
$script:TotalChecks = 0
$script:PassedChecks = 0
$script:FailedChecks = 0
$script:WarningChecks = 0

# 日志函数
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[PASS] $Message" -ForegroundColor Green
    $script:PassedChecks++
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
    $script:WarningChecks++
}

function Write-Error {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    $script:FailedChecks++
}

function Test-FileExists {
    param(
        [string]$FilePath,
        [string]$Description
    )
    
    $script:TotalChecks++
    
    if (Test-Path $FilePath) {
        Write-Success "$Description : $FilePath"
    } else {
        Write-Error "$Description : $FilePath 不存在"
    }
}

function Test-DirectoryExists {
    param(
        [string]$DirectoryPath,
        [string]$Description
    )
    
    $script:TotalChecks++
    
    if (Test-Path $DirectoryPath -PathType Container) {
        Write-Success "$Description : $DirectoryPath"
    } else {
        Write-Error "$Description`: $DirectoryPath 不存在"
    }
}

function Test-YamlSyntax {
    param([string]$FilePath)
    
    $script:TotalChecks++
    
    try {
        # 简单的YAML语法检查 - 检查基本结构
        $content = Get-Content $FilePath -Raw
        if ($content -match "^\s*---" -or $content -match "^\s*[a-zA-Z_][a-zA-Z0-9_]*:") {
            Write-Success "YAML语法检查: $FilePath"
        } else {
            Write-Warning "YAML语法检查: $FilePath (简单检查通过，建议使用Python验证)"
        }
    } catch {
        Write-Error "YAML语法检查: $FilePath 读取失败"
    }
}

function Test-VariableInFile {
    param(
        [string]$FilePath,
        [string]$VariableName
    )
    
    $script:TotalChecks++
    
    if (Test-Path $FilePath) {
        $content = Get-Content $FilePath
        if ($content -match "^${VariableName}:") {
            Write-Success "变量定义: $VariableName"
        } else {
            Write-Error "变量定义: $VariableName 未在 $FilePath 中定义"
        }
    } else {
        Write-Error "变量检查: $FilePath 文件不存在"
    }
}

function Test-PackageInRequirements {
    param(
        [string]$PackageName
    )
    
    $script:TotalChecks++
    
    if (Test-Path "requirements.txt") {
        $content = Get-Content "requirements.txt"
        if ($content -match $PackageName) {
            Write-Success "依赖包: $PackageName 已在requirements.txt中"
        } else {
            Write-Error "依赖包: $PackageName 未在requirements.txt中"
        }
    } else {
        Write-Error "依赖检查: requirements.txt 文件不存在"
    }
}

Write-Host "=================================================================="
Write-Host "             MySQL InnoDB Cluster 部署验证"
Write-Host "=================================================================="
Write-Host "项目路径: $(Get-Location)"
Write-Host "检查时间: $(Get-Date)"
Write-Host ""

# 1. 检查核心文件结构
Write-Info "1. 检查核心文件结构"
Test-FileExists "deploy.sh" "主部署脚本"
Test-FileExists "ansible.cfg" "Ansible配置文件"
Test-FileExists "requirements.txt" "Python依赖文件"

# 2. 检查目录结构
Write-Info "2. 检查目录结构"
Test-DirectoryExists "playbooks" "Playbooks目录"
Test-DirectoryExists "inventory" "Inventory目录"
Test-DirectoryExists "roles" "Roles目录"
Test-DirectoryExists "scripts" "Scripts目录"

# 3. 检查核心playbook文件
Write-Info "3. 检查核心Playbook文件"
Test-FileExists "playbooks/site.yml" "主playbook文件"
Test-FileExists "playbooks/install-mysql.yml" "MySQL安装playbook"
Test-FileExists "playbooks/configure-cluster.yml" "集群配置playbook"
Test-FileExists "playbooks/install-router.yml" "Router安装playbook"

# 4. 检查inventory文件
Write-Info "4. 检查Inventory配置文件"
Test-FileExists "inventory/hosts.yml" "基础hosts文件"
Test-FileExists "inventory/hosts-recommended-router.yml" "推荐Router配置"
Test-FileExists "inventory/hosts-with-dedicated-routers.yml" "专用Router配置"
Test-FileExists "inventory/group_vars/all.yml" "全局变量文件"

# 5. 检查roles结构
Write-Info "5. 检查Roles结构"
Test-DirectoryExists "roles/mysql-server" "MySQL服务器角色"
Test-DirectoryExists "roles/mysql-cluster" "MySQL集群角色"
Test-DirectoryExists "roles/mysql-router" "MySQL Router角色"
Test-FileExists "roles/mysql-server/templates/my.cnf.j2" "MySQL配置模板"
Test-FileExists "roles/mysql-router/templates/mysqlrouter.service.j2" "Router服务模板"

# 6. 检查脚本文件
Write-Info "6. 检查脚本文件"
Test-FileExists "scripts/cluster-status.sh" "集群状态检查脚本"
Test-FileExists "scripts/setup-servers.sh" "服务器设置脚本"
Test-FileExists "scripts/failover-test.sh" "故障转移测试脚本"
Test-FileExists "scripts/config_manager.sh" "配置管理脚本"

# 7. 检查YAML语法
Write-Info "7. 检查YAML文件语法"
$yamlFiles = @(
    "playbooks/site.yml",
    "playbooks/install-mysql.yml",
    "playbooks/configure-cluster.yml",
    "playbooks/install-router.yml",
    "inventory/hosts.yml",
    "inventory/group_vars/all.yml"
)

foreach ($yamlFile in $yamlFiles) {
    if (Test-Path $yamlFile) {
        Test-YamlSyntax $yamlFile
    }
}

# 8. 检查脚本文件shebang
Write-Info "8. 检查脚本文件"
$scriptFiles = Get-ChildItem -Path "." -Include "*.sh" -Recurse

foreach ($script in $scriptFiles) {
    $script:TotalChecks++
    $firstLine = Get-Content $script.FullName -TotalCount 1
    if ($firstLine -eq "#!/bin/bash") {
        Write-Success "Shebang检查: $($script.Name)"
    } else {
        Write-Error "Shebang检查: $($script.Name) 缺少 #!/bin/bash"
    }
}

# 9. 检查必要的变量定义
Write-Info "9. 检查关键变量定义"
$configFile = "inventory/group_vars/all.yml"
$keyVars = @("mysql_version", "mysql_root_password", "mysql_cluster_name", "mysql_cluster_user", "mysql_port")

foreach ($var in $keyVars) {
    Test-VariableInFile $configFile $var
}

# 10. 检查Python依赖
Write-Info "10. 检查Python依赖"
$requiredPackages = @("ansible", "PyMySQL", "mysql-connector-python")

foreach ($package in $requiredPackages) {
    Test-PackageInRequirements $package
}

# 11. 检查系统兼容性
Write-Info "11. 检查系统兼容性要求"

$script:TotalChecks++
try {
    $pythonVersion = & python --version 2>&1
    if ($pythonVersion -match "Python") {
        Write-Success "Python 可用 ($pythonVersion)"
    } else {
        Write-Warning "Python 未安装或不在PATH中（部署时需要）"
    }
} catch {
    Write-Warning "Python 未安装或不在PATH中（部署时需要）"
}

$script:TotalChecks++
try {
    $ansibleVersion = & ansible --version 2>&1
    if ($ansibleVersion -match "ansible") {
        Write-Success "Ansible 已安装"
    } else {
        Write-Warning "Ansible 未安装（部署时需要）"
    }
} catch {
    Write-Warning "Ansible 未安装（部署时需要）"
}

# 12. 检查网络配置示例
Write-Info "12. 检查网络配置示例"
$inventoryFiles = @("inventory/hosts.yml", "inventory/hosts-recommended-router.yml")

foreach ($invFile in $inventoryFiles) {
    if (Test-Path $invFile) {
        $script:TotalChecks++
        $content = Get-Content $invFile -Raw
        if ($content -match "192\.168\.1") {
            Write-Warning "网络配置: $invFile 使用示例IP地址，部署前需要修改"
        } else {
            Write-Success "网络配置: $invFile 已自定义IP地址"
        }
        
        $script:TotalChecks++
        if ($content -match "your_password") {
            Write-Warning "密码配置: $invFile 使用示例密码，部署前需要修改"
        } else {
            Write-Success "密码配置: $invFile 已自定义密码"
        }
    }
}

# 13. 检查文档完整性
Write-Info "13. 检查文档完整性"
$docFiles = @("README.md", "DEPLOYMENT_COMPLETE_GUIDE.md", "TROUBLESHOOTING.md", "QUICK_START.md")

foreach ($doc in $docFiles) {
    Test-FileExists $doc "文档文件"
}

# 14. 检查配置文件一致性
Write-Info "14. 检查配置文件一致性"
$configFiles = @("inventory/group_vars/all.yml", "inventory/group_vars/all-8c32g-optimized.yml")

foreach ($config in $configFiles) {
    if (Test-Path $config) {
        $script:TotalChecks++
        $content = Get-Content $config
        $clusterNameLine = $content | Where-Object { $_ -match "mysql_cluster_name:" }
        if ($clusterNameLine -match '"prodCluster"') {
            Write-Success "集群名称一致性: $config"
        } else {
            Write-Warning "集群名称一致性: $config 使用了不同的集群名称"
        }
    }
}

# 15. 检查模板文件
Write-Info "15. 检查模板文件完整性"
$templateFiles = @("roles/mysql-server/templates/my.cnf.j2", "roles/mysql-router/templates/mysqlrouter.service.j2")

foreach ($template in $templateFiles) {
    if (Test-Path $template) {
        $script:TotalChecks++
        $content = Get-Content $template -Raw
        if ($content -match "\{\{") {
            Write-Success "模板变量: $template 包含Ansible变量"
        } else {
            Write-Warning "模板变量: $template 可能缺少必要的变量"
        }
    }
}

# 16. 最终安全检查
Write-Info "16. 安全配置检查"
$script:TotalChecks++

$passwordFiles = Get-ChildItem -Path "inventory/group_vars/" -Include "*.yml" -Recurse
$hasStrongPassword = $false

foreach ($file in $passwordFiles) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match "password.*P@ss" -and $content -notmatch "your_password") {
        $hasStrongPassword = $true
        break
    }
}

if ($hasStrongPassword) {
    Write-Success "密码强度: 使用了强密码模式"
} else {
    Write-Warning "密码强度: 建议使用更强的密码模式"
}

# 总结报告
Write-Host ""
Write-Host "=================================================================="
Write-Host "                         检查结果汇总"
Write-Host "=================================================================="
Write-Host "总检查项目: $script:TotalChecks" -ForegroundColor Blue
Write-Host "通过检查: $script:PassedChecks" -ForegroundColor Green
Write-Host "警告项目: $script:WarningChecks" -ForegroundColor Yellow
Write-Host "失败项目: $script:FailedChecks" -ForegroundColor Red
Write-Host ""

# 计算成功率
$successRate = [math]::Round(($script:PassedChecks * 100) / $script:TotalChecks, 2)
Write-Host "成功率: $successRate%" -ForegroundColor Blue

# 总体评估
if ($script:FailedChecks -eq 0) {
    if ($script:WarningChecks -eq 0) {
        Write-Host "`n✅ 项目完全通过验证，可以安全部署！" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "`n⚠️  项目基本通过验证，但有 $script:WarningChecks 个警告项需要注意" -ForegroundColor Yellow
        Write-Host "请检查警告项目，建议解决后再部署"
        exit 1
    }
} else {
    Write-Host "`n❌ 项目验证失败，有 $script:FailedChecks 个严重问题需要修复" -ForegroundColor Red
    Write-Host "请修复所有失败项目后再进行部署"
    exit 2
} 