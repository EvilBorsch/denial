import 'dart:io';

/// eb20 track O, measurement build only: the words in
/// /run/user/1000/eb20o-diag switch parts of the overview off to measure
/// what they cost on the GPU (nofade: the overview backdrop without its
/// fade; nowinglass: no window glass while a window is transformed).
Set<String> eb20oDiag() {
  try {
    return File('/run/user/1000/eb20o-diag')
        .readAsStringSync()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toSet();
  } on FileSystemException {
    return const <String>{};
  }
}
