/// The icon `bookmarks/details/assets.html` shows for a file of
/// [contentType].
String assetIcon(String contentType) {
  const head =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
      'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
      'stroke-linecap="round" stroke-linejoin="round"> '
      '<path stroke="none" d="M0 0h24v24H0z" fill="none" />';
  final paths = switch (contentType) {
    'text/html' => const [
      'M14 3v4a1 1 0 0 0 1 1h4',
      'M5 12v-7a2 2 0 0 1 2 -2h7l5 5v4',
      'M2 21v-6',
      'M5 15v6',
      'M2 18h3',
      'M20 15v6h2',
      'M13 21v-6l2 3l2 -3v6',
      'M7.5 15h3',
      'M9 15v6',
    ],
    'application/pdf' => const [
      'M14 3v4a1 1 0 0 0 1 1h4',
      'M5 12v-7a2 2 0 0 1 2 -2h7l5 5v4',
      'M5 18h1.5a1.5 1.5 0 0 0 0 -3h-1.5v6',
      'M17 18h2',
      'M20 15h-3v6',
      'M11 15v6h1a2 2 0 0 0 2 -2v-2a2 2 0 0 0 -2 -2h-1z',
    ],
    'image/png' || 'image/jpeg' || 'image.gif' => const [
      'M15 8h.01',
      'M3 6a3 3 0 0 1 3 -3h12a3 3 0 0 1 3 3v12a3 3 0 0 1 -3 3h-12a3 3 0 0 1 -3 -3v-12z',
      'M3 16l5 -5c.928 -.893 2.072 -.893 3 0l5 5',
      'M14 14l1 -1c.928 -.893 2.072 -.893 3 0l3 3',
    ],
    _ => const [
      'M14 3v4a1 1 0 0 0 1 1h4',
      'M17 21h-10a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2h7l5 5v11a2 2 0 0 1 -2 2z',
    ],
  };
  return '$head ${paths.map((d) => '<path d="$d" />').join(' ')} </svg>';
}
