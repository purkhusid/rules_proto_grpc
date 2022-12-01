"""Common generic rules used by rules_proto_grpc."""

_rust_keywords = [
    "as",
    "break",
    "const",
    "continue",
    "crate",
    "else",
    "enum",
    "extern",
    "false",
    "fn",
    "for",
    "if",
    "impl",
    "let",
    "loop",
    "match",
    "mod",
    "move",
    "mut",
    "pub",
    "ref",
    "return",
    "self",
    "Self",
    "static",
    "struct",
    "super",
    "trait",
    "true",
    "type",
    "unsafe",
    "use",
    "where",
    "while",
]

_objc_upper_segments = {
    "url": "URL",
    "http": "HTTP",
    "https": "HTTPS",
}

def capitalize(s):
    """
    Capitalize a string - only first letter

    Args:
        s (string): The input string to be capitalized.

    Returns:
        (string): The capitalized string.
    """
    return s[0:1].upper() + s[1:]

def pascal_objc(s):
    """
    Convert pascal_case -> PascalCase

    Objective C uses pascal case, but there are e exceptions that it uppercases
    the entire segment: url, http, and https.

    https://github.com/protocolbuffers/protobuf/blob/54176b26a9be6c9903b375596b778f51f5947921/src/google/protobuf/compiler/objectivec/objectivec_helpers.cc#L91

    Args:
        s (string): The input string to be capitalized.

    Returns:
        (string): The capitalized string.

    """

    # It is possible for proto files to be named with dashes.
    # e.g. company-proto.proto, this ensures the output file names for ObjC
    # correctly match.
    s = s.replace("-", "_")

    segments = []
    for segment in s.split("_"):
        repl = _objc_upper_segments.get(segment)
        if repl:
            segment = repl
        else:
            segment = capitalize(segment)
        segments.append(segment)
    return "".join(segments)

def pascal_case(s):
    """
    Convert pascal_case -> PascalCase

    Args:
        s (string): The input string to be capitalized.

    Returns:
        (string): The capitalized string.

    """
    return "".join([capitalize(part) for part in s.split("_")])

def rust_keyword(s):
    """
    Check if arg is a rust keyword and append '_pb' if true.

    Args:
        s (string): The input string to be capitalized.

    Returns:
        (string): The appended string.

    """
    return s + "_pb" if s in _rust_keywords else s

def python_path(s):
    """
    Convert a path string to a python import compatible path as is generated by the python plugin.

    Python import paths cannot contain dashes, so these are replaced by underscores.
    See https://github.com/protocolbuffers/protobuf/blob/master/src/google/protobuf/compiler/python/python_generator.cc#L89-L95

    Args:
        s (string): The input string to be converted.

    Returns:
        (string): The converted string.

    """
    return s.replace("-", "_")

def php_path(s):
    """
    Convert a path string to a php path as is generated by the php plugin.

    Args:
        s (string): The input string to be converted.

    Returns:
        (string): The converted string.

    """
    return "/".join([capitalize(c) for c in s.split("/")])

def get_output_filename(src_file, pattern, proto_info):
    """
    Build the predicted filename for file generated by the given plugin.

    A 'proto_plugin' rule allows one to define the predicted outputs.  For
    flexibility, we allow special tokens in the output filename that get
    replaced here. The overall pattern is '{token}' mimicking the python
    'format' feature.

    Additionally, there are '|' characters like '{basename|pascal}' that can be
    read as 'take the basename and pipe that through the pascal function'.

    Args:
        src_file: the .proto <File>
        pattern: the input pattern string
        proto_info: The <ProtoInfo> object

    Returns:
        The replaced string

    """

    # Get proto path and strip extension
    protopath = descriptor_proto_path(src_file, proto_info)
    if protopath.endswith(".proto"):
        protopath = protopath[:-6]
    elif protopath.endswith(".protodevel"):
        protopath = protopath[:-11]
    protopath_partitions = protopath.rpartition("/")

    # Get output basename and strip extension
    basename = src_file.basename
    if basename.endswith(".proto"):
        basename = basename[:-6]
    elif basename.endswith(".protodevel"):
        basename = basename[:-11]

    # Replace tokens
    filename = ""
    if "{basename}" in pattern:
        filename = pattern.replace("{basename}", basename)
    elif "{protopath}" in pattern:
        filename = pattern.replace("{protopath}", protopath)
    elif "{basename|pascal}" in pattern:
        filename = pattern.replace("{basename|pascal}", pascal_case(basename))
    elif "{protopath|pascal}" in pattern:
        filename = pattern.replace("{protopath|pascal}", "/".join([
            # Pascal case only the file name
            protopath_partitions[0],
            pascal_case(protopath_partitions[2]),
        ]))
    elif "{basename|python}" in pattern:
        filename = pattern.replace("{basename|python}", python_path(basename))
    elif "{protopath|python}" in pattern:
        filename = pattern.replace("{protopath|python}", python_path(protopath))
    elif "{basename|php}" in pattern:
        filename = pattern.replace("{basename|php}", php_path(basename))
    elif "{protopath|php}" in pattern:
        filename = pattern.replace("{protopath|php}", php_path(protopath))
    elif "{basename|pascal|objc}" in pattern:
        filename = pattern.replace("{basename|pascal|objc}", pascal_objc(basename))
    elif "{protopath|pascal|objc}" in pattern:
        filename = pattern.replace("{protopath|pascal|objc}", "/".join([
            # Pascal case only the file name
            protopath_partitions[0],
            pascal_objc(protopath_partitions[2]),
        ]))
    elif "{basename|rust_keyword}" in pattern:
        filename = pattern.replace("{basename|rust_keyword}", rust_keyword(basename))
    elif "{protopath|rust_keyword}" in pattern:
        filename = pattern.replace("{basename|rust_keyword}", rust_keyword(protopath))
    else:
        filename += basename + pattern

    return filename

def copy_file(ctx, src_file, dest_path, sibling = None):
    """
    Copy a file to a new path destination

    Args:
        ctx: the <ctx> object
        src_file: the source file <File>
        dest_path: the destination path of the file
        sibling: a file to use as a sibling to declare_file <File>

    Returns:
        <Generated File> for the copied file

    """
    dest_file = ctx.actions.declare_file(dest_path, sibling = sibling)
    ctx.actions.run_shell(
        mnemonic = "CopyFile",
        inputs = [src_file],
        outputs = [dest_file],
        command = "cp '{}' '{}'".format(src_file.path, dest_file.path),
        progress_message = "copying file {} to {}".format(src_file.path, dest_file.path),
    )
    return dest_file

def descriptor_proto_path(proto, proto_info):
    """
    Convert a proto File to the path within the descriptor file.

    Adapted from https://github.com/bazelbuild/rules_go

    Args:
        proto: The proto file.
        proto_info: The ProtoInfo provider the file is from.

    Returns:
        The path to the proto file, as seen when making the descriptor.

    """

    # Strip proto_source_root
    path = strip_path_prefix(proto.path, proto_info.proto_source_root)

    # Strip root
    path = strip_path_prefix(path, proto.root.path)

    # Strip workspace root
    path = strip_path_prefix(path, proto.owner.workspace_root)

    return path

def strip_path_prefix(path, prefix):
    """
    Strip a prefix from a path if it exists and any remaining prefix slashes.

    Args:
        path: The path string to strip.
        prefix: The prefix to remove.

    Returns:
        The stripped path. If the prefix is not present, this will be the same as the input.

    """
    if path.startswith(prefix):
        path = path[len(prefix):]
    if path.startswith("/"):
        path = path[1:]
    return path

def parse_version(version_str):
    """
    Parse the bazel version string, returning a tuple.

    Derived from https://github.com/tensorflow/tensorflow/blob/master/tensorflow/version_check.bzl

    Args:
        version_str: The version string to parse.

    Returns:
        The tuple of version elements.

    """

    # Extract just the semver part
    semver_str = version_str.partition(" ")[0].partition("-")[0]

    # Return version tuple
    return tuple([n for n in semver_str.split(".")])

# Check that a specific bazel version is being used.
def check_bazel_minimum_version(minimum_bazel_version):
    """
    Check that the bazel version meets or exceeds the required version.

    Derived from https://github.com/tensorflow/tensorflow/blob/master/tensorflow/version_check.bzl

    Args:
        minimum_bazel_version: The minimum supported version

    Returns:
        Nothing

    """

    # Check for bazel versions that did not support version checking
    if "bazel_version" not in dir(native):
        fail("Bazel version is lower than 0.2.1, rules_proto_grpc requires at least {}".format(minimum_bazel_version))

    # Check for non-release versions
    if not native.bazel_version:
        print("Bazel is not a release version, rules_proto_grpc requires at least {}".format(minimum_bazel_version))  # buildifier: disable=print
        return

    # Check version strings
    current_version_tuple = parse_version(native.bazel_version)
    minimum_version_tuple = parse_version(minimum_bazel_version)
    if current_version_tuple < minimum_version_tuple:
        fail(
            "Bazel version is {}, rules_proto_grpc requires at least {}".format(
                native.bazel_version,
                minimum_bazel_version,
            ),
        )

def get_package_root(ctx):
    """
    Get the full path to the package output directory, relative to workspace root.

    Args:
        ctx: The Bazel rule execution context object.

    Returns:
        The full path.

    """
    package_root = ctx.bin_dir.path
    if ctx.label.workspace_root:
        package_root += "/" + ctx.label.workspace_root
    if ctx.label.package:
        package_root += "/" + ctx.label.package

    return package_root

def get_parent_dirname(label):
    """
    Get the name of the parent directory of a label.

    Args:
        label: The label to get the parent directory of.

    Returns:
        The name of the parent directory.

    """
    if label.startswith("//"):
        label = label[2:]
    return label.partition("/")[0]

# All common attrs from https://bazel.build/reference/be/common-definitions#common-attributes
# These are listed here to be correctly propagated through *_library macros to the underlying
# rules without just passing the entirety of kwargs, although maybe that's the better choice...
bazel_rule_common_attrs = [
    'compatible_with',
    'deprecation',
    'distribs',
    'exec_compatible_with',
    'exec_properties',
    'features',
    'restricted_to',
    'tags',
    'target_compatible_with',
    'testonly',
    'toolchains',
    'visibility',
]
