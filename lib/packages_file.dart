// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library package_config.packages_file;

import "package:charcode/ascii.dart";
import "src/util.dart" show isValidPackageName;

/// Parses a `.packages` file into a map from package name to base URI.
///
/// The [source] is the byte content of a `.packages` file, assumed to be
/// UTF-8 encoded. In practice, all significant parts of the file must be ASCII,
/// so Latin-1 or Windows-1252 encoding will also work fine.
///
/// If the file content is available as a string, its [String.codeUnits] can
/// be used as the `source` argument of this function.
///
/// The [baseLocation] is used as a base URI to resolve all relative
/// URI references against.
/// If the content was read from a file, `baseLocation` should be the
/// location of that file.
///
/// Returns a simple mapping from package name to package location.
Map<String, Uri> parse(List<int> source, Uri baseLocation) {
  int index = 0;
  Map<String, Uri> result = <String, Uri>{};
  while (index < source.length) {
    bool isComment = false;
    int start = index;
    int separatorIndex = -1;
    int end = source.length;
    int char = source[index++];
    if (char == $cr || char == $lf) {
      continue;
    }
    if (char == $colon) {
      throw new FormatException("Missing package name", source, index - 1);
    }
    isComment = char == $hash;
    while (index < source.length) {
      char = source[index++];
      if (char == $colon && separatorIndex < 0) {
        separatorIndex = index - 1;
      } else if (char == $cr || char == $lf) {
        end = index - 1;
        break;
      }
    }
    if (isComment) continue;
    if (separatorIndex < 0) {
      throw new FormatException("No ':' on line", source, index - 1);
    }
    var packageName = new String.fromCharCodes(source, start, separatorIndex);
    if (!isValidPackageName(packageName)) {
      throw new FormatException("Not a valid package name", packageName, 0);
    }
    var packageUri = new String.fromCharCodes(source, separatorIndex + 1, end);
    var packageLocation = Uri.parse(packageUri);
    if (!packageLocation.path.endsWith('/')) {
      packageLocation =
          packageLocation.replace(path: packageLocation.path + "/");
    }
    packageLocation = baseLocation.resolveUri(packageLocation);
    if (result.containsKey(packageName)) {
      throw new FormatException(
          "Same package name occured twice.", source, start);
    }
    result[packageName] = packageLocation;
  }
  return result;
}

/// Writes the mapping to a [StringSink].
///
/// If [comment] is provided, the output will contain this comment
/// with `# ` in front of each line.
/// Lines are defined as ending in line feed (`'\n'`). If the final
/// line of the comment doesn't end in a line feed, one will be added.
///
/// If [baseUri] is provided, package locations will be made relative
/// to the base URI, if possible, before writing.
///
/// All the keys of [packageMapping] must be valid package names,
/// and the values must be URIs that do not have the `package:` scheme.
void write(StringSink output, Map<String, Uri> packageMapping,
           {Uri baseUri, String comment}) {
  if (baseUri != null && !baseUri.isAbsolute) {
    throw new ArgumentError.value(baseUri, "baseUri", "Must be absolute");
  }

  if (comment != null) {
    var lines = comment.split('\n');
    if (lines.last.isEmpty) lines.removeLast();
    for (var commentLine in lines) {
      output.write('# ');
      output.writeln(commentLine);
    }
  } else {
    output.write("# generated by package:package_config at ");
    output.write(new DateTime.now());
    output.writeln();
  }

  packageMapping.forEach((String packageName, Uri uri) {
    // Validate packageName.
    if (!isValidPackageName(packageName)) {
      throw new ArgumentError('"$packageName" is not a valid package name');
    }
    if (uri.scheme == "package") {
      throw new ArgumentError.value(
          "Package location must not be a package: URI", uri);
    }
    output.write(packageName);
    output.write(':');
    // If baseUri provided, make uri relative.
    if (baseUri != null) {
      uri = _relativize(uri, baseUri);
    }
    output.write(uri);
    if (!uri.path.endsWith('/')) {
      output.write('/');
    }
    output.writeln();
  });
}

/// Attempts to return a relative URI for [uri].
///
/// The result URI satisfies `baseUri.resolveUri(result) == uri`,
/// but may be relative.
/// The `baseUri` must be absolute.
Uri _relativize(Uri uri, Uri baseUri) {
  assert(baseUri.isAbsolute);
  if (uri.hasQuery || uri.hasFragment) {
    uri = new Uri(
        scheme: uri.scheme,
        userInfo: uri.hasAuthority ? uri.userInfo : null,
        host: uri.hasAuthority ? uri.host : null,
        port: uri.hasAuthority ? uri.port : null,
        path: uri.path);
  }

  // Already relative. We assume the caller knows what they are doing.
  if (!uri.isAbsolute) return uri;

  if (baseUri.scheme != uri.scheme) {
    return uri;
  }

  // If authority differs, we could remove the scheme, but it's not worth it.
  if (uri.hasAuthority != baseUri.hasAuthority) return uri;
  if (uri.hasAuthority) {
    if (uri.userInfo != baseUri.userInfo ||
        uri.host.toLowerCase() != baseUri.host.toLowerCase() ||
        uri.port != baseUri.port) {
      return uri;
    }
  }

  baseUri = _normalizePath(baseUri);
  List<String> base = baseUri.pathSegments.toList();
  if (base.isNotEmpty) {
    base = new List<String>.from(base)..removeLast();
  }
  uri = _normalizePath(uri);
  List<String> target = uri.pathSegments.toList();
  if (target.isNotEmpty && target.last.isEmpty) target.removeLast();
  int index = 0;
  while (index < base.length && index < target.length) {
    if (base[index] != target[index]) {
      break;
    }
    index++;
  }
  if (index == base.length) {
    if (index == target.length) {
      return new Uri(path: "./");
    }
    return new Uri(path: target.skip(index).join('/'));
  } else if (index > 0) {
    return new Uri(
        path: '../' * (base.length - index) + target.skip(index).join('/'));
  } else {
    return uri;
  }
}

// TODO: inline to uri.normalizePath() when we move to 1.11
Uri _normalizePath(Uri uri) => new Uri().resolveUri(uri);
