load("//csharp:csharp_proto_compile.bzl", "csharp_proto_compile")
load("@io_bazel_rules_dotnet//dotnet:defs.bzl", "csharp_library")

def csharp_proto_library(**kwargs):
    # Compile protos
    name_pb = kwargs.get("name") + "_pb"
    csharp_proto_compile(
        name = name_pb,
        **{k: v for (k, v) in kwargs.items() if k in ("deps", "verbose")} # Forward args
    )

    # Create csharp library
    csharp_library(
        name = kwargs.get("name"),
        srcs = [name_pb],
        deps = PROTO_DEPS,
        visibility = kwargs.get("visibility"),
        tags = kwargs.get("tags"),
    )

PROTO_DEPS = [
    "@google.protobuf//:core",
    "@io_bazel_rules_dotnet//dotnet/stdlib.core:netstandard.dll",
]
