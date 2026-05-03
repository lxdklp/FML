# 本项目欢迎任何正向贡献

### 新功能、BUG 修复等欢迎直接 PR, 涉及 UI 相关的改动请先在 Issue 中提出并讨论

# 构建 Flutter Minecraft Launcher

安装 [Visual Studio Code](https://code.visualstudio.com) 与 [Flutter](https://docs.flutter.dev/install)

克隆项目 `git clone https://github.com/lxdklp/FML.git`

构建项目 `flutter build [PLATFORM]`

# Shared Preferences
软件配置
| 键 | 值 | 类型 |
| -- | -- |-- |
| version | 软件版本(即将抛弃) | string |
| build | 软件构建号(即将抛弃) | int |
| themeColor | 自定义主题颜色 | int |
| themeMode | 是否跟随深色 | string |
| autoClearLog | 是否自动清理日志 | bool |
| logLevel | 日志等级(0:INFO, 1:WARNING, 2:ERROR) | int |
| SelectedAccountName | 选择的账号名称 | string |
| SelectedAccountType | 选择的账号类型(0:离线, 1:正版, 2:外置) | string |
| SelectedPath | 选择的文件夹 | string |
| SelectedGame | 选择的版本 | string |
| offline_accounts_list | 离线账号列表 | list(string) |
| online_accounts_list | 在线账号列表 | list(string) |
| external_accounts_list | 外置账号列表 | list(string) |
| PathList | 游戏文件夹列表 | list(string) |
| Path_$name | 版本路径 | string |
| Game_$name | 版本列表 | list(string) |
| javaSelectedPath | 所选Java路径 | string |
| javaRuntimes | Java运行时列表（以JSON格式存储） | string |

离线账号配置 offline_account_$name list(string)
| 序号 | 值 |
| -- | -- |
| 0 | 登录模式(0) |
| 1 | 生成UUID |
| 2 | 是否启用自定义UUID(1启用,0禁用) |
| 3 | 自定义UUID |

正版登录账号配置 online_account_$name list(string)
| 序号 | 值 |
| -- | -- |
| 0 | 登录模式(1) |
| 1 | UUID |
| 2 | refreshToken |

外置登录账号配置 external_account_$name list(string)
| 序号 | 值 |
| -- | -- |
| 0 | 登录模式(2) |
| 1 | UUID |
| 2 | 验证服务器URL |
| 3 | 服务器用户名 |
| 4 | 服务器密码 |
| 5 | accessToken |
| 6 | clientToken |

版本配置 Config_${path}_$game list(string)
| 序号 | 值 |
| -- | -- |
| 0 | xmx |
| 1 | 是否启用全屏(1启用,0禁用) |
| 2 | 游戏宽度 |
| 3 | 游戏高度 |
| 4 | 模组加载器 |
