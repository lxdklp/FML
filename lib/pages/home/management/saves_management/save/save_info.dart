import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:dart_nbt/dart_nbt.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class SaveInfoTab extends StatefulWidget {
  final String savePath;
  final String saveName;

  const SaveInfoTab({
    super.key,
    required this.savePath,
    required this.saveName,
  });

  @override
  State<SaveInfoTab> createState() => _SaveInfoTabState();
}

class _SaveInfoTabState extends State<SaveInfoTab> {
  bool _isLoading = true;
  String? _error;
  NbtCompound? _levelData;
  int _currentDifficulty = 2;
  bool _allowCommands = false;
  bool _generateFeatures = true;
  String _levelName = '';
  String _gameVersion = '';
  int _gameType = 0;
  int _lastPlayed = 0;
  int _dayTime = 0;
  bool _hardcore = false;
  int _spawnX = 0;
  int _spawnY = 0;
  int _spawnZ = 0;
  String _seed = '';
  List<PlayerData> _players = [];
  bool _isLoadingPlayers = false;

  @override
  void initState() {
    super.initState();
    _loadLevelData();
  }

  // 加载存档信息
  Future<void> _loadLevelData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final levelDatFile = File('${widget.savePath}/level.dat');
      if (!await levelDatFile.exists()) {
        throw Exception('level.dat 文件不存在');
      }
      final bytes = await levelDatFile.readAsBytes();
      final nbt = Nbt();
      final compound = nbt.read(bytes);
      _levelData = compound;
      final data = compound['Data'] as NbtCompound?;
      if (data != null) {
        _levelName =
            (data['LevelName'] as NbtString?)?.value ?? widget.saveName;
        final version = data['Version'] as NbtCompound?;
        if (version != null) {
          _gameVersion = (version['Name'] as NbtString?)?.value ?? '未知';
        }
        _gameType = (data['GameType'] as NbtInt?)?.value ?? 0;
        final lastPlayedValue = data['LastPlayed'] as NbtLong?;
        _lastPlayed = lastPlayedValue != null
            ? lastPlayedValue.value.toInt()
            : 0;
        final dayTimeValue = data['DayTime'] as NbtLong?;
        _dayTime = dayTimeValue != null ? dayTimeValue.value.toInt() : 0;
        _hardcore = ((data['hardcore'] as NbtByte?)?.value ?? 0) == 1;
        _spawnX = (data['SpawnX'] as NbtInt?)?.value ?? 0;
        _spawnY = (data['SpawnY'] as NbtInt?)?.value ?? 0;
        _spawnZ = (data['SpawnZ'] as NbtInt?)?.value ?? 0;
        _currentDifficulty = (data['Difficulty'] as NbtByte?)?.value ?? 2;
        _allowCommands = ((data['allowCommands'] as NbtByte?)?.value ?? 0) == 1;
        final worldGenSettings = data['WorldGenSettings'] as NbtCompound?;
        if (worldGenSettings != null) {
          _generateFeatures = ((worldGenSettings['generate_features'] as NbtByte?)?.value ?? 1) == 1;
          _seed = (worldGenSettings['seed'] as NbtLong?)?.value.toString() ?? '';
        }
      }
      await _loadPlayerData();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = '加载存档信息失败: $e';
      });
    }
  }

  // 加载玩家数据
  Future<void> _loadPlayerData() async {
    setState(() {
      _isLoadingPlayers = true;
    });
    try {
      final playerDataDir = Directory('${widget.savePath}/playerdata');
      if (await playerDataDir.exists()) {
        final files = await playerDataDir.list().where((entity) {
          return entity is File && entity.path.endsWith('.dat');
        }).toList();
        _players = [];
        for (final file in files) {
          try {
            final bytes = await (file as File).readAsBytes();
            final nbt = Nbt();
            final compound = nbt.read(bytes);
            final uuid = file.path.split('/').last.replaceAll('.dat', '');
            final player = PlayerData.fromNbt(uuid, file.path, compound);
            _players.add(player);
          } catch (e) {
            debugPrint('解析玩家数据失败: ${file.path}, $e');
          }
        }
      }
    } catch (e) {
      debugPrint('加载玩家数据失败: $e');
    } finally {
      setState(() {
        _isLoadingPlayers = false;
      });
    }
  }

  // 保存所有数据
  Future<void> _saveAllData() async {
    try {
      // 保存世界数据
      await _saveLevelData();
      // 保存所有玩家数据
      for (final player in _players) {
        await _savePlayerData(player, showSnackBar: false);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('所有数据已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  // 保存存档信息
  Future<void> _saveLevelData() async {
    if (_levelData == null) return;
    final data = _levelData!['Data'] as NbtCompound?;
    if (data == null) return;
    data['Difficulty'] = NbtByte(value: _currentDifficulty);
    data['allowCommands'] = NbtByte(value: _allowCommands ? 1 : 0);
    final worldGenSettings = data['WorldGenSettings'] as NbtCompound?;
    if (worldGenSettings != null) {
      worldGenSettings['generate_features'] = NbtByte(
        value: _generateFeatures ? 1 : 0,
      );
    }
    final nbt = Nbt();
    final bytes = nbt.write(_levelData!);
    final levelDatFile = File('${widget.savePath}/level.dat');
    await levelDatFile.writeAsBytes(bytes);
  }

  // 保存玩家数据
  Future<void> _savePlayerData(PlayerData player, {bool showSnackBar = true}) async {
    if (player.nbtData == null) return;
    final compound = player.nbtData!;
    compound['playerGameType'] = NbtInt(value: player.gameType);
    compound['Health'] = NbtFloat(value: player.health);
    compound['foodLevel'] = NbtInt(value: player.foodLevel);
    compound['XpLevel'] = NbtInt(value: player.xpLevel);
    final nbt = Nbt();
    final bytes = nbt.write(compound);
    final playerFile = File(player.filePath);
    await playerFile.writeAsBytes(bytes);
    if (showSnackBar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('玩家数据已保存')),
      );
    }
  }

  // 打开URL
  Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接: $url')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发生错误: $e')),
      );
    }
  }

  // 获取难度名称
  String _getDifficultyName(int difficulty) {
    switch (difficulty) {
      case 0:
        return '和平';
      case 1:
        return '简单';
      case 2:
        return '普通';
      case 3:
        return '困难';
      default:
        return '未知';
    }
  }

  // 获取游戏模式名称
  String _getGameTypeName(int gameType) {
    switch (gameType) {
      case 0:
        return '生存模式';
      case 1:
        return '创造模式';
      case 2:
        return '冒险模式';
      case 3:
        return '旁观模式';
      default:
        return '未知';
    }
  }

  // 格式化最后游玩时间
  String _formatLastPlayed(int timestamp) {
    if (timestamp == 0) return '未知';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  // 格式化游戏时间
  String _formatDayTime(int dayTime) {
    final days = dayTime ~/ 24000;
    final timeOfDay = dayTime % 24000;
    final hours = (timeOfDay ~/ 1000 + 6) % 24;
    final minutes = ((timeOfDay % 1000) / 1000 * 60).round();
    return '第 $days 天 ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _saveAllData,
        child: const Icon(Icons.save),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadLevelData, child: const Text('重试')),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBasicInfoCard(),
          const SizedBox(height: 16),
          _buildPlayerDataCard(),
          const SizedBox(height: 16),
          _buildMapCard(),
        ],
      ),
    );
  }

  // 世界信息卡片
  Widget _buildBasicInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info),
                const SizedBox(width: 8),
                Text('世界信息', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const Divider(),
            _buildInfoRow('存档名称', _levelName),
            _buildInfoRow('游戏版本', _gameVersion),
            _buildInfoRow('游戏模式', _getGameTypeName(_gameType)),
            _buildInfoRow('当前难度', _getDifficultyName(_currentDifficulty)),
            _buildInfoRow('极限模式', _hardcore ? '是' : '否'),
            _buildInfoRow('最后游玩', _formatLastPlayed(_lastPlayed)),
            _buildInfoRow('游戏时间', _formatDayTime(_dayTime)),
            _buildInfoRow('出生点坐标', 'X: ${_spawnX.toString()} Y: ${_spawnY.toString()} Z: ${_spawnZ.toString()}'),
            _buildInfoRow('世界种子', _seed),
            _buildWorldSettings()
          ],
        ),
      ),
    );
  }

  // 世界设置
  Widget _buildWorldSettings() {
    return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('难度'),
                DropdownButton<int>(
                  value: _currentDifficulty,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('和平')),
                    DropdownMenuItem(value: 1, child: Text('简单')),
                    DropdownMenuItem(value: 2, child: Text('普通')),
                    DropdownMenuItem(value: 3, child: Text('困难')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _currentDifficulty = value;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('允许作弊'),
                Switch(
                  value: _allowCommands,
                  onChanged: (value) {
                    setState(() {
                      _allowCommands = value;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('生成结构'),
                Switch(
                  value: _generateFeatures,
                  onChanged: (value) {
                    setState(() {
                      _generateFeatures = value;
                    });
                  },
                ),
              ],
            ),
          ],
    );
  }

  // 玩家数据卡片
  Widget _buildPlayerDataCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people),
                const SizedBox(width: 8),
                Text('玩家数据', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_isLoadingPlayers)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const Divider(),
            if (_players.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('暂无玩家数据')),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _players.length,
                itemBuilder: (context, index) {
                  final player = _players[index];
                  return _buildPlayerTile(player);
                },
              ),
          ],
        ),
      ),
    );
  }

  // 玩家信息展开项
  Widget _buildPlayerTile(PlayerData player) {
    return ExpansionTile(
      leading: const Icon(Icons.person),
      title: Text(player.uuid),
      subtitle: Text(
        '${_getGameTypeName(player.gameType)} - 等级 ${player.xpLevel}',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              _buildInfoRow('UUID', player.uuid),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('游戏模式'),
                  DropdownButton<int>(
                    value: player.gameType,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('生存模式')),
                      DropdownMenuItem(value: 1, child: Text('创造模式')),
                      DropdownMenuItem(value: 2, child: Text('冒险模式')),
                      DropdownMenuItem(value: 3, child: Text('旁观模式')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          player.gameType = value;
                        });
                      }
                    },
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('生命值'),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      initialValue: player.health.toInt().toString(),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (value) {
                        final intValue = int.tryParse(value) ?? 0;
                        player.health = intValue.toDouble();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('饥饿值'),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      initialValue: player.foodLevel.toString(),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (value) {
                        final intValue = int.tryParse(value) ?? 0;
                        player.foodLevel = intValue.clamp(0, 20);
                      },
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('经验等级'),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      initialValue: player.xpLevel.toString(),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (value) {
                        final intValue = int.tryParse(value) ?? 0;
                        player.xpLevel = intValue.clamp(0, 2147483647);
                      },
                    ),
                  ),
                ],
              ),
              _buildInfoRow('总经验', player.xpTotal.toString()),
              _buildInfoRow('当前维度', player.dimension),
              _buildInfoRow('飞行中', player.flying ? '是' : '否'),
              _buildInfoRow('允许飞行', player.mayFly ? '是' : '否'),
              _buildInfoRow('无敌', player.invulnerable ? '是' : '否'),
              _buildInfoRow('可建造', player.mayBuild ? '是' : '否'),
              _buildInfoRow('瞬间建造', player.instabuild ? '是' : '否'),
            ],
          ),
        ),
      ],
    );
  }

  // 地图卡片
  Widget _buildMapCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.map),
                const SizedBox(width: 8),
                Text('种子地图 (chunkbase)', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const Divider(),
            ListTile(
              title: const Text('主世界'),
              onTap: () => _launchURL('https://www.chunkbase.com/apps/biome-finder#seed=$_seed&platform=java_${_gameVersion.replaceAll('.', '_')}&dimension=overworld&x=$_spawnX&z=$_spawnZ&zoom=0.5'),
            ),
            ListTile(
              title: const Text('下界'),
              onTap: () => _launchURL('https://www.chunkbase.com/apps/biome-finder#seed=$_seed&platform=java_${_gameVersion.replaceAll('.', '_')}&dimension=nether&x=$_spawnX&z=$_spawnZ&zoom=0.5'),
            ),
            ListTile(
              title: const Text('末地'),
              onTap: () => _launchURL('https://www.chunkbase.com/apps/biome-finder#seed=$_seed&platform=java_${_gameVersion.replaceAll('.', '_')}&dimension=end&x=$_spawnX&z=$_spawnZ&zoom=0.5'),
            ),
          ],
        ),
      ),
    );
  }

  // 信息行
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// 玩家数据类
class PlayerData {
  final String uuid;
  final String filePath;
  int gameType;
  double health;
  int foodLevel;
  int xpLevel;
  final int xpTotal;
  final String dimension;
  final bool flying;
  final bool mayFly;
  final bool invulnerable;
  final bool mayBuild;
  final bool instabuild;
  NbtCompound? nbtData;

  PlayerData({
    required this.uuid,
    required this.filePath,
    required this.gameType,
    required this.health,
    required this.foodLevel,
    required this.xpLevel,
    required this.xpTotal,
    required this.dimension,
    required this.flying,
    required this.mayFly,
    required this.invulnerable,
    required this.mayBuild,
    required this.instabuild,
    this.nbtData,
  });

  factory PlayerData.fromNbt(
    String uuid,
    String filePath,
    NbtCompound compound,
  ) {
    // 能力
    final abilities = compound['abilities'] as NbtCompound?;
    return PlayerData(
      uuid: uuid,
      filePath: filePath,
      gameType: (compound['playerGameType'] as NbtInt?)?.value ?? 0,
      health: (compound['Health'] as NbtFloat?)?.value ?? 20.0,
      foodLevel: (compound['foodLevel'] as NbtInt?)?.value ?? 20,
      xpLevel: (compound['XpLevel'] as NbtInt?)?.value ?? 0,
      xpTotal: (compound['XpTotal'] as NbtInt?)?.value ?? 0,
      dimension:
          (compound['Dimension'] as NbtString?)?.value ?? 'minecraft:overworld',
      flying: abilities != null
          ? ((abilities['flying'] as NbtByte?)?.value ?? 0) == 1
          : false,
      mayFly: abilities != null
          ? ((abilities['mayfly'] as NbtByte?)?.value ?? 0) == 1
          : false,
      invulnerable: abilities != null
          ? ((abilities['invulnerable'] as NbtByte?)?.value ?? 0) == 1
          : false,
      mayBuild: abilities != null
          ? ((abilities['mayBuild'] as NbtByte?)?.value ?? 1) == 1
          : true,
      instabuild: abilities != null
          ? ((abilities['instabuild'] as NbtByte?)?.value ?? 0) == 1
          : false,
      nbtData: compound,
    );
  }
}
