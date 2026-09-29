/// linkding's `get_safe_return_url`: a path on this site, or [fallback].
String safeReturnUrl(String? returnUrl, String fallback) =>
    returnUrl == null || !RegExp('^/[a-z]+').hasMatch(returnUrl)
    ? fallback
    : returnUrl;
