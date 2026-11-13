import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/settings_controller.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/video_repository.dart';
import '../../data/source/proxy_pool.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _SectionHeader('站点'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('当前站点'),
            subtitle: Text(settings.host),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickHost(context, settings),
          ),
          const _SectionHeader('播放'),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('默认倍速'),
            subtitle: Text('${settings.defaultSpeed}x'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickSpeed(context, settings),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.screen_rotation_outlined),
            title: const Text('进入播放自动横屏'),
            value: settings.autoLandscape,
            onChanged: settings.setAutoLandscape,
          ),
          const _SectionHeader('反限额（每日 10 次）'),
          SwitchListTile(
            secondary: const Icon(Icons.shield_outlined),
            title: const Text('启用每日 10 次绕过'),
            subtitle: const Text('每次起播轮换 伪造IP / UA / Cookie / 镜像，命中限额自动换身份重试'),
            value: settings.bypassEnabled,
            onChanged: (v) async {
              await settings.setBypassEnabled(v);
              if (context.mounted) _applyBypass(context, settings);
            },
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('代理池（真实 IP 轮换）'),
            subtitle: Text(_proxySummary(settings.proxyPoolText)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editProxyPool(context, settings),
          ),
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('最大尝试次数'),
            subtitle: Text('${settings.maxAttempts} 次'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editAttempts(context, settings),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.travel_explore),
            title: const Text('镜像 JS 反爬（WKWebView 兜底）'),
            subtitle: const Text('镜像返回 “Redirecting…”/Cloudflare 挑战时，用隐藏 WKWebView 过盾并复用 Cookie'),
            value: settings.webviewFallback,
            onChanged: (v) async {
              await settings.setWebviewFallback(v);
              if (context.mounted) _applyBypass(context, settings);
            },
          ),
          const _SectionHeader('列表'),
          ListTile(
            leading: const Icon(Icons.grid_view_outlined),
            title: const Text('每页视频数'),
            subtitle: Text('${settings.pageSize} 个/页'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editPageSize(context, settings),
          ),
          const _SectionHeader('外观'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题'),
            subtitle: Text(_themeLabel(settings.themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickTheme(context, settings),
          ),
          const _SectionHeader('存储'),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('清除网络缓存'),
            onTap: () {
              context.read<VideoRepository>().clearCache();
              _toast(context, '缓存已清除');
            },
          ),
          ListTile(
            leading: const Icon(Icons.link_off),
            title: const Text('清空直链缓存'),
            subtitle: const Text('已解析的播放直链（按 e= 过期自动失效）'),
            onTap: () async {
              await context.read<VideoRepository>().directLinks.clear();
              _toast(context, '直链缓存已清除');
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('清空观看历史'),
            onTap: () async {
              await context.read<LibraryRepository>().clearHistory();
              _toast(context, '历史已清空');
            },
          ),
          const _SectionHeader('关于'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('P91 Player'),
            subtitle: Text('版本 1.0.0 · iOS 重构版\n数据来源：91porn'),
          ),
        ],
      ),
    );
  }

  static String _themeLabel(ThemeMode m) =>
      switch (m) { ThemeMode.system => '跟随系统', ThemeMode.light => '浅色', ThemeMode.dark => '深色' };

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _applyBypass(BuildContext context, SettingsController s) {
    context.read<VideoRepository>().configureBypass(
          enabled: s.bypassEnabled,
          proxyPoolText: s.proxyPoolText,
          maxAttempts: s.maxAttempts,
          webviewFallback: s.webviewFallback,
        );
  }

  String _proxySummary(String text) {
    final pool = ProxyPool.parse(text);
    if (pool.isEmpty) return '未配置（仅伪造 IP，源站若忽略头则无效）';
    return '已配置 ${pool.length} 个代理，起播时随机轮换';
  }

  void _editProxyPool(BuildContext context, SettingsController settings) {
    final controller = TextEditingController(text: settings.proxyPoolText);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('代理池'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '每行一个 HTTP 代理 host:port。起播解析时随机挑选真实出口 IP，'
              '用于绕过按 IP 计数的每日限额。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLines: 6,
              minLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '127.0.0.1:7890\n1.2.3.4:8080',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await settings.setProxyPoolText(controller.text);
              if (context.mounted) _applyBypass(context, settings);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _editAttempts(BuildContext context, SettingsController settings) {    const options = [4, 8, 12, 16];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('最大尝试次数', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Wrap(spacing: 8, children: [
              for (final n in options)
                ChoiceChip(
                  label: Text('$n'),
                  selected: settings.maxAttempts == n,
                  onSelected: (_) async {
                    await settings.setMaxAttempts(n);
                    if (context.mounted) _applyBypass(context, settings);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
            ]),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _editPageSize(BuildContext context, SettingsController settings) {
    const options = [10, 20, 30, 50, 100];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('每页视频数', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final n in options)
                  ChoiceChip(
                    label: Text('$n 个'),
                    selected: settings.pageSize == n,
                    onSelected: (_) async {
                      await settings.setPageSize(n);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('每页数量越多，翻页找旧视频越快；受源站每页条数限制，App 会自动跨多页拼够数量。',
                  style: TextStyle(fontSize: 12), textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _pickHost(BuildContext context, SettingsController settings) {
    final controller = TextEditingController(text: settings.host);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换站点'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              children: ApiConstants.altHosts
                  .map((h) => ActionChip(
                        label: Text(h.replaceFirst('https://', '')),
                        onPressed: () {
                          settings.setHost(h);
                          ctx.read<VideoRepository>().host = h;
                          Navigator.pop(ctx);
                        },
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '自定义域名',
                hintText: 'https://example.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              settings.setHost(controller.text);
              ctx.read<VideoRepository>().host = controller.text;
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _pickSpeed(BuildContext context, SettingsController settings) {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          spacing: 8,
          children: speeds
              .map((s) => ChoiceChip(
                    label: Text('${s}x'),
                    selected: settings.defaultSpeed == s,
                    onSelected: (_) {
                      settings.setDefaultSpeed(s);
                      Navigator.pop(ctx);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _pickTheme(BuildContext context, SettingsController settings) {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('主题'),
        children: ThemeMode.values
            .map((m) => RadioListTile<ThemeMode>(
                  value: m,
                  groupValue: settings.themeMode,
                  title: Text(_themeLabel(m)),
                  onChanged: (v) {
                    if (v != null) settings.setThemeMode(v);
                    Navigator.pop(ctx);
                  },
                ))
            .toList(),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
