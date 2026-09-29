/// html5lib's serializer: text escapes `&`, `<` and `>`.
String escapeText(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String escapeAttribute(String value) =>
    value.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
