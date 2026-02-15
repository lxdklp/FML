<p align="center"><img src="./assets/img/icon/logo_rounded.png"  width="20%" /><img src="./assets/img/logo/flutter.png"  width="25%" /></p>

# Flutter Minecraft Launcher

一个由Flutter编写的Material Design 3风格的使用GPL3.0协议开源跨平台Vanilla/Fabric/NeoForge Minecraft Java启动器,支持Windows、macOS、Linux

***需要更多Windows ARM64、macOS x86、 Linux的反馈!***

# Shared Preferences
软件配置
| 键 | 值 | 类型 |
| -- | -- |-- |
| version | 软件版本 | string |
| build | 软件构建号 | int |
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
| java | Java路径 | string |

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

###### Flutter logo : [Sawaratsuki](https://github.com/SAWARATSUKI)