# Copyright (C) 2018 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@io_bazel_rules_go//go:def.bzl", "go_context")
load(":gapil.bzl", "ApicTemplate")

def api_search_path(inputs):
    roots = {}
    for dep in inputs:
        if dep.root.path:
            roots[dep.root.path] = True
    return ",".join(["."] + roots.keys())

def _apic_library_to_source(go, attr, source, merge):
  for t in attr.templates: merge(source, t)

def _apic_template_impl(ctx):
    go = go_context(ctx)
    api = ctx.attr.api
    apiname = api.apiname
    apilist = api.includes.to_list()
    generated = depset()
    go_srcs = []
    for template in ctx.attr.templates:
        template = template[ApicTemplate]
        templatelist = template.uses.to_list()
        outputs = [ctx.new_file(out.format(api=apiname)) for out in template.outputs]
        generated += outputs
        ctx.actions.run(
            inputs = apilist + templatelist,
            outputs = outputs,
            arguments = [
                "template",
                "--dir", outputs[0].dirname,
                "--search", api_search_path(apilist),
                api.main.path,
                template.main.path,
            ],
            mnemonic = "apic",
            progress_message = "apic generating " + api.main.short_path + " with " + template.main.short_path,
            executable = ctx.executable._apic,
            use_default_shell_env = True,
        )
    go_srcs.extend([f for f in generated if f.basename.endswith(".go")])
    library = go.new_library(go, srcs=go_srcs, resolver=_apic_library_to_source)
    source = go.library_to_source(go, ctx.attr, library, ctx.coverage_instrumented())
    return [
        library, source,
        DefaultInfo(files = depset(generated)),
    ]

"""Adds an API template rule"""
apic_template = rule(
    _apic_template_impl,
    attrs = {
        "api": attr.label(
            allow_files = False,
            mandatory = True,
            providers = [
                "apiname",
                "main",
                "includes",
            ],
        ),
        "templates": attr.label_list(
            allow_files = False,
            mandatory = True,
            providers = [ApicTemplate],
        ),
        "_apic": attr.label(
            executable = True,
            cfg = "host",
            allow_files = True,
            default = Label("//cmd/apic:apic"),
        ),
        "_go_context_data": attr.label(default=Label("@io_bazel_rules_go//:go_context_data")),
    },
    toolchains = ["@io_bazel_rules_go//go:toolchain"],
    output_to_genfiles = True,
)


def _apic_compile_impl(ctx):
    api = ctx.attr.api
    apiname = api.apiname
    apilist = api.includes.to_list()
    generated = depset()

    target = ctx.fragments.cpp.cpu
    outputs = [ctx.new_file(ctx.label.name + ".o")]
    generated += outputs

    ctx.actions.run(
        inputs = apilist,
        outputs = outputs,
        arguments = [
            "compile",
            "--search", api_search_path(apilist),
            "--target", target,
            "--output", outputs[0].path,
            "--optimize=%s" % ctx.attr.optimize,
            "--dump=%s" % ctx.attr.dump,
            "--namespace", ctx.attr.namespace,
            "--symbols", ctx.attr.symbols,
        ] + ["--emit-" + emit for emit in ctx.attr.emit] + [
            api.main.path,
        ],
        mnemonic = "apic",
        progress_message = "apic compiling " + api.main.short_path + " for " + target,
        executable = ctx.executable._apic,
        use_default_shell_env = True,
    )

    return [
        DefaultInfo(files = depset(generated)),
    ]

"""Adds an API compile rule"""
apic_compile = rule(
    _apic_compile_impl,
    attrs = {
        "api": attr.label(
            allow_files = False,
            mandatory = True,
            providers = [
                "apiname",
                "main",
                "includes",
            ],
        ),
        "optimize": attr.bool(default = False),
        "dump": attr.bool(default = False),
        "emit": attr.string_list(
            allow_empty = False,
            mandatory = True,
        ),
        "namespace": attr.string(
            default = "",
            mandatory = False,
        ),
        "symbols": attr.string(
            default = "c++",
            mandatory = False,
        ),
        "_apic": attr.label(
            executable = True,
            cfg = "host",
            allow_files = True,
            default = Label("//cmd/apic:apic"),
        ),
    },
    fragments = ["cpp"],
)
