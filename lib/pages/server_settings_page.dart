/// 服务器设置页面
import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/server_client.dart';
import 'package:pica_comic/tools/translations.dart';

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({Key? key}) : super(key: key);

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  late TextEditingController _serverUrlController;

  ServerClient? _client;
  bool _isConnected = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController(
      text: appdata.settings[90],
    );

    if (_serverUrlController.text.isNotEmpty) {
      _checkConnection();
    }
  }

  Future<void> _checkConnection() async {
    if (_serverUrlController.text.isEmpty) return;

    setState(() => _isChecking = true);

    try {
      _client = ServerClient(_serverUrlController.text);
      final isHealthy = await _client!.checkHealth();
      
      setState(() {
        _isConnected = isHealthy;
        _isChecking = false;
      });

      if (isHealthy) {
        showToast(message: '连接成功'.tl);
      } else {
        showToast(message: '连接失败'.tl);
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
        _isChecking = false;
      });
      showToast(message: '连接失败: $e');
    }
  }

  Future<void> _saveServerUrl() async {
    final url = _serverUrlController.text.trim();

    if (url.isEmpty) {
      showToast(message: '请输入服务器地址'.tl);
      return;
    }

    // 验证 URL 格式
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      showToast(message: '服务器地址必须以 http:// 或 https:// 开头'.tl);
      return;
    }

    appdata.settings[90] = url;
    await appdata.writeData();

    await _checkConnection();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('服务器设置'.tl),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildConnectionCard(),
          const SizedBox(height: 16),
          _buildInfoCard(),
        ],
      ),
    );
  }

  Widget _buildConnectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: _isConnected ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  '服务器连接'.tl,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _serverUrlController,
              decoration: InputDecoration(
                labelText: '服务器地址'.tl,
                hintText: 'http://192.168.1.100:8080',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.dns),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isChecking ? null : _saveServerUrl,
                icon: _isChecking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isChecking ? '检查中...'.tl : '保存并测试连接'.tl),
              ),
            ),
            if (_isConnected)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '已连接到服务器'.tl,
                      style: const TextStyle(color: Colors.green),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 8),
                Text(
                  '使用说明'.tl,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoItem('1. ', '在服务器上运行 PicaComic Server'),
            _buildInfoItem('2. ', '填写服务器地址（如: http://192.168.1.100:8080）'),
            _buildInfoItem('3. ', '点击"保存并测试连接"验证连接'),
            _buildInfoItem('4. ', '在漫画详情页选择下载章节时，选择"远程服务器"'),
            _buildInfoItem('5. ', '漫画将自动下载到服务器，无需账号同步'),
            _buildInfoItem('6. ', '在"服务器漫画"页面浏览和管理服务器上的漫画'),
            _buildInfoItem('7. ', '可以在"已下载"页面导出本地漫画到服务器'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.blue[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '提示：服务器可以在家里的电脑、NAS 或云服务器上运行，使用直接下载模式无需在服务器上登录账号',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }
}
