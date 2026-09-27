-- Data for tool/web_parity.sh, loaded into both databases after the API
-- parity run: enough bookmarks to page through, other users who share, a
-- tag spelled differently by different owners, notes, descriptions and
-- dates far enough back for every date format. Fixed ids keep the two
-- databases identical.
--
-- Not included: two owners sharing tags whose names differ only in case.
-- linkding's tag cloud then keeps whichever PostgreSQL's hash DISTINCT
-- happens to return last, which is not stable.

INSERT INTO auth_user (id, password, last_login, is_superuser, username,
                       first_name, last_name, email, is_staff, is_active,
                       date_joined)
VALUES (1000, '!unusable', NULL, false, 'other', '', '', '', false, true,
        '2024-01-01T00:00:00Z'),
       (1001, '!unusable', NULL, false, 'Zed', '', '', '', false, true,
        '2024-01-01T00:00:00Z');

INSERT INTO bookmarks_userprofile (
  user_id, theme, bookmark_date_display, bookmark_link_target,
  web_archive_integration, enable_sharing, enable_favicons, tag_search,
  display_url, permanent_notes, enable_public_sharing, search_preferences,
  custom_css, bookmark_description_display, bookmark_description_max_lines,
  display_archive_bookmark_action, display_edit_bookmark_action,
  display_remove_bookmark_action, display_view_bookmark_action,
  enable_automatic_html_snapshots, default_mark_unread, enable_preview_images,
  tag_grouping, auto_tagging_rules, items_per_page, sticky_pagination,
  custom_css_hash, collapse_side_panel, hide_bundles, default_mark_shared,
  legacy_search)
SELECT id, 'auto', 'relative', '_blank', 'disabled', true, false, 'strict',
       false, false, id = 1000, '{}'::jsonb, '', 'inline', 1, true, true,
       true, true, true, false, false, 'alphabetical', '', 30, false, '',
       false, false, false, false
FROM auth_user WHERE id IN (1000, 1001);

INSERT INTO bookmarks_tag (id, name, date_added, owner_id) VALUES
  (1000, 'python', '2024-02-01T00:00:00Z', 1),
  (1001, 'Python', '2024-02-01T00:00:00Z', 1000),
  (1002, 'pythonic', '2024-02-01T00:00:00Z', 1001),
  (1003, '日本', '2024-02-01T00:00:00Z', 1),
  (1004, 'Émile', '2024-02-01T00:00:00Z', 1),
  (1005, 'go', '2024-02-01T00:00:00Z', 1000),
  (1006, 'rust', '2024-02-01T00:00:00Z', 1),
  (1007, 'a&b<c>', '2024-02-01T00:00:00Z', 1);

-- Admin's: 48 bookmarks from a year and a half ago to yesterday.
INSERT INTO bookmarks_bookmark (
  id, url, url_normalized, title, description, notes, website_title,
  website_description, web_archive_snapshot_url, favicon_file,
  preview_image_file, unread, is_archived, shared, date_added, date_modified,
  date_accessed, owner_id, latest_snapshot_id)
SELECT 1000 + n,
       'https://site' || n || '.example.org/path?q=' || n,
       'https://site' || n || '.example.org/path?q=' || n,
       CASE WHEN n % 7 = 0 THEN '' ELSE 'Filler <' || n || '> & "title"' END,
       CASE WHEN n % 3 = 0 THEN 'Description ' || n ELSE '' END,
       CASE WHEN n % 5 = 0 THEN E'Some *notes* for ' || n ||
            E'\nsecond line https://example.com/x\n\n- item\n- `code`'
            ELSE '' END,
       NULL, NULL,
       CASE WHEN n % 11 = 0 THEN 'https://web.archive.org/web/2020/x' ELSE '' END,
       '', '',
       n % 4 = 0, n % 9 = 0, n % 6 = 0,
       timestamptz '2026-09-26T12:00:00Z' - make_interval(days => n * 12),
       timestamptz '2026-09-26T12:00:00Z' - make_interval(days => n * 12),
       NULL, 1, NULL
FROM generate_series(1, 48) AS n;

-- Others' shared bookmarks.
INSERT INTO bookmarks_bookmark (
  id, url, url_normalized, title, description, notes, website_title,
  website_description, web_archive_snapshot_url, favicon_file,
  preview_image_file, unread, is_archived, shared, date_added, date_modified,
  date_accessed, owner_id, latest_snapshot_id)
SELECT 1100 + n,
       'https://shared' || n || '.example.org/',
       'https://shared' || n || '.example.org',
       'Shared ' || n, '', '', NULL, NULL, '', '', '',
       false, false, n <> 3,
       timestamptz '2026-09-20T08:30:00Z' - make_interval(days => n),
       timestamptz '2026-09-20T08:30:00Z' - make_interval(days => n),
       NULL, CASE WHEN n % 2 = 0 THEN 1000 ELSE 1001 END, NULL
FROM generate_series(1, 6) AS n;

INSERT INTO bookmarks_bookmark_tags (bookmark_id, tag_id)
SELECT 1000 + n, 1000 FROM generate_series(1, 48, 2) AS n
UNION ALL SELECT 1000 + n, 1006 FROM generate_series(3, 48, 5) AS n
UNION ALL SELECT 1000 + n, 1003 FROM generate_series(4, 48, 8) AS n
UNION ALL SELECT 1000 + n, 1004 FROM generate_series(2, 48, 10) AS n
UNION ALL SELECT 1000 + n, 1007 FROM generate_series(6, 48, 12) AS n
UNION ALL SELECT 1000 + n, 1 FROM generate_series(1, 48, 16) AS n
UNION ALL SELECT 1100 + n, 1001 FROM generate_series(2, 6, 2) AS n
UNION ALL SELECT 1100 + n, 1005 FROM generate_series(4, 6, 2) AS n
UNION ALL SELECT 1100 + n, 1002 FROM generate_series(1, 5, 2) AS n;

INSERT INTO bookmarks_bookmarkbundle (
  id, name, search, any_tags, all_tags, excluded_tags, "order",
  date_created, date_modified, owner_id, filter_unread, filter_shared)
VALUES (1000, 'Pythonic & <co>', '', 'python rust', '', '日本', 9,
        '2024-03-01T00:00:00Z', '2024-03-01T00:00:00Z', 1, 'off', 'off');
