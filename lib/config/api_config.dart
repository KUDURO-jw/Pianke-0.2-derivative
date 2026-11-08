/// API 配置
class ApiConfig {
  // 焕新版独立更新渠道；旧版继续使用 update.json。
  static const String updateManifestUrl =
      'https://raw.githubusercontent.com/KUDURO-jw/Pianke-0.2-derivative/main/update-ui.json';

  // 请求头
  static Map<String, String> get defaultHeaders => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Accept': 'application/json',
    'Accept-Language': 'zh-CN,zh;q=0.9',
  };

  // 豆瓣请求头（用于片单爬取）
  static Map<String, String> get doubanHeaders => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Referer': 'https://www.douban.com/',
  };

  // 图片请求头（绕过防盗链）
  static Map<String, String> get imageHeaders => {
    'Referer': 'https://movie.douban.com/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };
}
