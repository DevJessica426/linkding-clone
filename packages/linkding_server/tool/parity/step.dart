// What one request of the parity run is.

final class Step {
  const Step(
    this.name,
    this.method,
    this.path, {
    this.json,
    this.form,
    this.raw,
    this.contentType,
    this.files,
    this.auth = Auth.token,
  }) : sql = null;

  /// Runs [sql] on each server's own database; both use linkding's schema,
  /// so one statement changes the same thing in each.
  const Step.sql(this.name, this.sql)
    : method = 'SQL',
      path = '',
      json = null,
      form = null,
      raw = null,
      contentType = null,
      files = null,
      auth = Auth.none;

  final String name;
  final String method;
  final String path;
  final Object? json;
  final Map<String, Object>? form;
  final String? raw;
  final String? contentType;

  /// Sent as `multipart/form-data`, with [form] as its text fields: each
  /// file is (field, file name, content type, content).
  final List<(String, String, String, String)>? files;
  final Auth auth;
  final String? sql;
}

enum Auth { token, bearer, none, badToken, emptyToken }

const post = 'POST';
const get = 'GET';
const put = 'PUT';
const patch = 'PATCH';
const delete = 'DELETE';

const noScrape = '?disable_scraping';
const pagesUrl = 'http://localhost:9099';
