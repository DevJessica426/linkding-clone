// How Python writes JSON values in the messages linkding sends back.

/// Python's `str()` of a JSON value, as it appears in messages.
String pythonStr(Object? value) => switch (value) {
  null => 'None',
  true => 'True',
  false => 'False',
  final String s => s,
  final int i => '$i',
  final double d =>
    d == d.truncateToDouble() && d.abs() < 1e16 ? d.toStringAsFixed(1) : '$d',
  final List<Object?> list => '[${list.map(_repr).join(', ')}]',
  final Map<Object?, Object?> map =>
    '{${map.entries.map((e) => '${_repr(e.key)}: ${_repr(e.value)}').join(', ')}}',
  _ => '$value',
};

String _repr(Object? value) =>
    value is String ? "'${value.replaceAll("'", r"\'")}'" : pythonStr(value);

/// Python's `type(value).__name__` for a JSON value.
String pythonTypeName(Object? value) => switch (value) {
  null => 'NoneType',
  bool() => 'bool',
  String() => 'str',
  int() => 'int',
  double() => 'float',
  List<Object?>() => 'list',
  Map<Object?, Object?>() => 'dict',
  _ => '${value.runtimeType}',
};
