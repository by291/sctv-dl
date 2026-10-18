import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

const _layers = {'app', 'domain', 'data', 'platform', 'features', 'design'};

List<String> checkBoundaries(Directory library) {
  final root = library.absolute.uri;
  final failures = <String>[];
  final files = library
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where(
        (file) => file.path.endsWith('.dart') && !file.path.endsWith('.g.dart'),
      );

  for (final file in files) {
    final path = file.absolute.uri.path.substring(root.path.length);
    final owner = path.split('/');
    final parsed = parseString(
      content: file.readAsStringSync(),
      path: file.path,
    );
    for (final directive
        in parsed.unit.directives.whereType<UriBasedDirective>()) {
      final targets = [
        directive.uri.stringValue,
        if (directive is NamespaceDirective)
          ...directive.configurations.map((option) => option.uri.stringValue),
      ].whereType<String>();
      for (final target in targets) {
        final reason = _violation(root, file.absolute.uri, owner, target);
        if (reason != null) {
          failures.add(
            '$path:${parsed.lineInfo.getLocation(directive.offset).lineNumber}: $reason ($target)',
          );
        }
      }
    }
  }
  return failures..sort();
}

String? _violation(Uri root, Uri source, List<String> owner, String target) {
  final uri = Uri.parse(target);
  if (uri.scheme == 'dart') {
    return owner.first == 'domain' && {'io', 'ui', 'ffi'}.contains(uri.path)
        ? 'Domain must remain platform independent'
        : null;
  }
  final internalPackage =
      uri.scheme == 'package' && uri.path.startsWith('sctv_dl_mobile/');
  if (uri.scheme == 'package' && !internalPackage) {
    if (owner.first == 'domain') {
      return 'Domain must not depend on framework or adapter packages';
    }
    const nativePackages = {
      'better_player_plus',
      'background_downloader',
      'dio',
      'drift',
      'path_provider',
      'share_plus',
      'device_info_plus',
      'package_info_plus',
    };
    if ({'features', 'design'}.contains(owner.first) &&
        nativePackages.contains(uri.pathSegments.first)) {
      return 'Presentation must consume domain contracts instead of native/data packages';
    }
    return null;
  }

  final resolved = internalPackage
      ? root.resolve(uri.path.substring('sctv_dl_mobile/'.length))
      : source.resolveUri(uri);
  if (resolved.scheme != root.scheme || !resolved.path.startsWith(root.path)) {
    return 'Internal source reference resolves outside lib';
  }
  final destination = resolved.path.substring(root.path.length).split('/');
  final from = owner.first;
  final to = destination.first;
  if (!_layers.contains(from) || !_layers.contains(to)) return null;

  final allowed = switch (from) {
    'domain' => {'domain'},
    'data' => {'data', 'domain'},
    'platform' => {'platform', 'domain'},
    'design' => {'design', 'domain'},
    'features' => {'features', 'domain', 'design'},
    _ => _layers,
  };
  if (!allowed.contains(to)) return '$from must not depend on $to';
  if (from == 'features' && to == 'features' && owner[1] != destination[1]) {
    return 'Features must not depend on sibling features';
  }
  return null;
}

void main(List<String> arguments) {
  final failures = checkBoundaries(Directory(arguments.firstOrNull ?? 'lib'));
  for (final failure in failures) {
    stderr.writeln(failure);
  }
  if (failures.isNotEmpty) {
    exitCode = 1;
  } else {
    stdout.writeln('Flutter dependency boundaries passed.');
  }
}
