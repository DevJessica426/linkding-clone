# linkding, in Dart

A clone of [linkding](https://github.com/sissbruecker/linkding) 1.47.0, the
self-hosted bookmark manager, written end to end in Dart with
[Dust](https://pub.dev/packages/dust_dart) and PostgreSQL. It is meant to be
indistinguishable from linkding: same URLs, same pages down to the pixel,
same REST API answers, same database schema, so linkding's browser
extension, mobile apps and API clients should work against it unchanged.

The goal is linkding's behaviour, not its code. The server is built the way
[Dust](https://pub.dev/packages/dust_dart) builds things, and only its
outcome has to match linkding's: pages are `dust_server` handlers behind
layers and extractors that render Mustache templates, each database access is
a fixed SQL statement checked by Dust against the real schema (no ORM, no
query builder), and the code follows Dust's layout rules (split by feature, a
barrel per folder, no hand-written file over 180 lines, `test/` mirroring
`lib/src`). Where linkding's behaviour comes from Python or Django (URL
parsing, form validation, the Markdown renderer, the RSS writer, password
validators, the Netscape importer), that piece is ported and tested against
output recorded from the real thing.

## How close it is

`tool/web_parity.sh` runs linkding and the clone side by side on fresh
databases with the same data and compares them four ways. The current run:

| Check | Result |
| --- | --- |
| REST API: status, headers that matter and JSON bodies of 234 requests | 234 of 234 identical |
| Pages: normalized DOM of 295 page loads and form submissions | 295 of 295 identical |
| Browser: the same clicks and keys on both, in Chromium | 11 of 11 scenarios identical |
| Screenshots: 13 pages at desktop and phone width | 26 of 26 identical, pixel for pixel |

Deliberate differences:

- No Django admin (`/admin/`). Everything it offers for a single user is in
  the pages and the API.
- English only. linkding follows the browser's `Accept-Language` for
  Django's own strings (form errors, the feed `<language>`); the clone
  always answers in English.
- Website metadata is fetched as linkding fetches it, but favicons,
  preview images and HTML snapshots are not produced; those settings
  behave as if the feature were turned off.
- Error pages are Django's production pages (linkding's development
  server shows debug pages instead; the parity run compares only their
  status).

## Layout

```
packages/
  linkding_shared/   models, the typed API client and the search query
                     language, shared by the server and the browser
  linkding_server/   the server
    lib/src/
      app/            buildApp: the routers, layers and state, composed
      pages/          what every page shares: the visitor and CSRF layers
                      (session/), error pages (errors/), rendering (support/)
      accounts/       sign in, password change, sessions, password rules
      bookmarks/      lists/, details/, forms/ and service/ (saving, tagging)
      bundles/        the bundle list and its editor with a live preview
      tags/           the tags page, its dialogs and the merge
      assets/         serving a bookmark's files, reader mode, storing them
      settings/       general settings, integrations, import and export
      feeds/ site/    RSS feeds; the manifest, OpenSearch, custom CSS, root
      search/         the query string's filters and the search itself
      netscape/       importing and exporting the Netscape bookmarks file
      notes/          the Markdown renderer for bookmark notes
      metadata/       loading a website's title and description
      api/            the REST API, one folder per resource
      core/ compat/   linkding's own rules; ports of Python and Django pieces
      db/             rows/ (one file per table group), repos/ (one DAO per
                      area, fixed SQL), the database and its migrations
    web/templates/    the Mustache templates; partials are flat-named
    migrations/       linkding's schema, plus the clone's session tables
    web/static/       linkding's CSS, icons and images
    test/             mirrors lib/src
    tool/             parity tools (see below)
  linkding_web/      linkding's browser code, in Dart (see below)
tool/                build and parity scripts, fixture generators
```

Each folder carries a barrel named after it (`bookmarks/bookmarks.dart`), and
`tool/check_loc.sh` fails the run when a hand-written Dart file passes 180
lines.

### How a request is handled

`buildApp` composes a `Router` the way `dust_server` intends. Page routes are
merged from each feature's `Router` behind three route layers: `VisitorLayer`
(who is asking, their preferences and CSRF secret, stored as an `Extension`),
`CsrfProtection` and `PageErrors` (turns `Rejection`s into Django's error
pages and the sign-in redirect). Features that need a signed-in user add
`routeLayer(fromExtractor(const RequireSignIn()))`. Handlers are plain
functions of the `Request`; the database, the services and the template
engine are read with `request.state<T>()`, forms with the `PostedForm`
extractor. The API runs each endpoint behind `apiView`, which authenticates
the caller and turns an `ApiException` (an `IntoResponse`) into DRF's error
bodies.

## Running it

Needs Dart 3.13 and PostgreSQL.

```sh
dart pub get
tool/build_web.sh                  # builds web/static/bundle.js

export LD_DB_USER=linkding LD_DB_PASSWORD=... LD_DB_DATABASE=linkding
export LD_SUPERUSER_NAME=admin LD_SUPERUSER_PASSWORD=...
dart run packages/linkding_server/bin/server.dart
```

The server reads linkding's own environment variables (`LD_DB_*` or
`DATABASE_URL`, `LD_SERVER_HOST`/`LD_SERVER_PORT`, `LD_SUPERUSER_*`,
`LD_DISABLE_URL_VALIDATION`, `LD_ALLOWED_INTERNAL_HOSTS`,
`LD_SESSION_COOKIE_AGE`, `LD_DISABLE_ASSET_UPLOAD`), so a linkding
deployment's configuration works as it is. It applies its migrations on
start. Pointed at a database linkding created, it adopts it: linkding's
tables are left as they are and only the clone's session tables are added.

`dart run packages/linkding_server/bin/manage.dart` has `create_user` and
`create_token`, like linkding's `manage.py`.

## The browser side

linkding draws its search box and tag fields in the browser and runs its
modals, dropdowns, bulk editing and shortcuts there, in about 2,000 lines of
JavaScript on top of Turbo, Lit and Floating UI. `packages/linkding_web`
is that code in Dart, compiled with `dart compile js`: the same `ld-*`
custom elements, rendering the markup linkding's Lit templates render.

Turbo and Floating UI are libraries linkding builds on rather than part of
linkding, so they are vendored as published (`packages/linkding_web/vendor`,
MIT). Lit is not needed. Custom element classes have to be JavaScript
classes, so `web/elements.js` is a 30-line shim that defines them and hands
their callbacks to Dart. `tool/build_web.sh` joins these into the single
`bundle.js` the pages load, as linkding's esbuild step does.

## Checking it against linkding

```sh
LINKDING_DIR=~/src/linkding tool/web_parity.sh
```

`LINKDING_DIR` is a linkding checkout with its Python environment set up
(`uv sync`, `npm install && npm run build`). The script creates two
databases (`linkding_ref`, `linkding_clone`, as the PostgreSQL user in
`PGUSER`/`PGPASSWORD`), starts both servers, and runs:

1. `parity.dart`: the API requests.
2. `html_parity.py` with `web_parity_steps.txt`: the pages, after
   `web_parity_seed.sql`.
3. `browser_parity.js` and `screenshot_parity.js`, when Playwright for
   Node is installed (`npm i -g playwright`). Screenshot pairs and diff
   images go to `build/screenshots/`.

(all in `packages/linkding_server/tool/`).

Unit tests: `dart test` in `packages/linkding_server` (1,256 tests, most of
them fixtures recorded from linkding's Python code by the scripts in
`tool/`) and `packages/linkding_shared` (1,929).

## Dust

The server uses Dust for its SQL (`@SqlxDao` with `@Query` statements,
checked with `dust db build` against a live database and `dust check --db
--offline` from the committed `.dust_sql/` metadata), its row and JSON
types (`@Derive`), its migrations and its HTTP server (`dust_server`).

After changing a repository file, run `dust build` and then
`dust db build` (in that order; see below), apply new migrations to the
database `DUST_DATABASE_URL` names, and check with
`dust check --db --offline`.

Things found along the way, as of Dust 0.2.0:

- A DAO method cannot return a list of plain values
  (`Future<Result<List<int>, SqlxError>>`); a one-column result needs a
  one-field row type (`IdRow` in `db/rows/bookmark_rows.dart`).
- A DAO resolves the row types it returns from the files it imports, not
  through a barrel, so each repo imports its own row file.
- A route pattern in `dust_server` never matches a parameter pattern that
  contains `/`, even inside a character class; the API writes it as
  `\x2f`.
- `serve()` keeps `dart:io`'s default response headers
  (`X-Frame-Options: SAMEORIGIN`, `X-XSS-Protection`) and shelf's
  `X-Powered-By`, with no way to clear them; pages set linkding's own
  headers, but responses that do not still carry these.
- `dart format` over the generated `.g.dart` files makes `dust check`
  report them as stale.
- `dust build` and `dust db build` write the same `.g.dart` part of a
  repository file. Running `dust build` after `dust db build` removes the
  DAO code, so the order is `dust build`, then `dust db build`.
- `dust_server`'s `MultipartForm` keeps only the last part of a repeated
  field name, where Django keeps every value; the clone parses multipart
  bodies itself (`compat/form_data.dart`).

## Credits

linkding is by Sascha Ißbrücker and contributors, under the MIT License
(`packages/linkding_server/web/static/LICENSE-linkding.txt`). The CSS,
icons, images and the text of the pages are linkding's. Turbo is by
37signals and Floating UI by its contributors, both MIT. Django's list of
common passwords (BSD-3-Clause) is embedded for the password validators.
