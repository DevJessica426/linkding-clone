import 'dart:io';

/// The version of linkding whose behaviour this server reproduces. Clients
/// such as the browser extension read it from `/health` and
/// `/api/user/profile/`.
const linkdingVersion = '1.47.0';

/// Settings, read from the same environment variables linkding reads, so a
/// linkding deployment's configuration works unchanged.
final class ServerConfig {
  const ServerConfig({
    required this.databaseUrl,
    required this.host,
    required this.port,
    required this.dataDir,
    required this.webRoot,
    this.superuserName,
    this.superuserPassword,
    this.disableUrlValidation = false,
    this.allowedInternalHosts = const [],
    this.sessionCookieAge = const Duration(seconds: 1209600),
    this.passwordIterations = 1200000,
    this.enableMetadataScraping = true,
  });

  factory ServerConfig.fromEnvironment([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    bool flag(String name) =>
        const {'True', 'true', '1'}.contains(env[name] ?? '');

    final engine = env['LD_DB_ENGINE'] ?? 'postgres';
    if (engine != 'postgres' && env['DATABASE_URL'] == null) {
      throw StateError(
        'LD_DB_ENGINE=$engine: this server runs on PostgreSQL only; set '
        'LD_DB_ENGINE=postgres and the LD_DB_* variables, or DATABASE_URL.',
      );
    }
    final user = Uri.encodeComponent(env['LD_DB_USER'] ?? 'linkding');
    final password = env['LD_DB_PASSWORD'];
    final credentials = password == null
        ? user
        : '$user:${Uri.encodeComponent(password)}';
    final host = env['LD_DB_HOST'] ?? 'localhost';
    final port = env['LD_DB_PORT'] ?? '5432';
    final database = env['LD_DB_DATABASE'] ?? 'linkding';

    return ServerConfig(
      databaseUrl:
          env['DATABASE_URL'] ??
          'postgres://$credentials@$host:$port/$database?sslmode=disable',
      host: env['LD_SERVER_HOST'] ?? '0.0.0.0',
      port: int.tryParse(env['LD_SERVER_PORT'] ?? '') ?? 9090,
      dataDir: env['LD_DATA_DIR'] ?? 'data',
      webRoot: env['LD_WEB_ROOT'] ?? _defaultWebRoot(),
      superuserName: env['LD_SUPERUSER_NAME'],
      superuserPassword: env['LD_SUPERUSER_PASSWORD'],
      disableUrlValidation: flag('LD_DISABLE_URL_VALIDATION'),
      allowedInternalHosts: (env['LD_ALLOWED_INTERNAL_HOSTS'] ?? '')
          .split(',')
          .map((h) => h.trim())
          .where((h) => h.isNotEmpty)
          .toList(),
      sessionCookieAge: Duration(
        seconds: int.tryParse(env['LD_SESSION_COOKIE_AGE'] ?? '') ?? 1209600,
      ),
      passwordIterations:
          int.tryParse(env['LD_PASSWORD_ITERATIONS'] ?? '') ?? 1200000,
    );
  }

  /// `postgres://user:pass@host:port/db?sslmode=disable`.
  final String databaseUrl;

  final String host;
  final int port;

  /// Where uploaded assets and snapshots are kept, like linkding's `data/`.
  final String dataDir;

  /// The `static/` and `templates/` directory the web interface is served
  /// from.
  final String webRoot;

  /// Created on start-up when set and no user of that name exists, as
  /// linkding's `create_initial_superuser` does.
  final String? superuserName;
  final String? superuserPassword;

  final bool disableUrlValidation;

  /// Hosts, addresses or CIDR ranges that metadata scraping may reach even
  /// though they are not public; `*` allows everything.
  final List<String> allowedInternalHosts;

  final Duration sessionCookieAge;

  /// PBKDF2 rounds for new password hashes. Django's default; tests lower it.
  final int passwordIterations;

  /// Whether empty titles and descriptions are filled in from the page.
  final bool enableMetadataScraping;

  String get redactedDatabaseUrl => databaseUrl.replaceFirstMapped(
    RegExp(r'://([^:/@]+):[^@]*@'),
    (match) => '://${match[1]}:***@',
  );
}

String _defaultWebRoot() {
  for (final candidate in const [
    'packages/linkding_server/web',
    'web',
    '../linkding_server/web',
  ]) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  return 'web';
}
