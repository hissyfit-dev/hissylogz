# Third-party libraries

## Useful Zig docs

- https://ziggit.dev/t/how-to-package-a-zig-source-module-and-how-to-use-it/3457


## Adding a third-party library

### Fetch the library

Using a tag:

```shell
zig fetch --save https://github.com/${repo_name}/archive/refs/tags/${tag_name}.tar.gz
```

Using a branch:

```shell
zig fetch --save https://github.com/${repo_name}/archive/refs/heads/${branch_name}.zip
```

### Integrate into build

Add dependency import in `build.zig`:

```zig
    const new_lib = b.dependency("new_lib", .{});
    // .
    // .
    // .
    lib.root_module.addImport("new_lib", new_lib.module("new_lib_module"));
    // .
    // .
    // .
    exe.root_module.addImport("new_lib", new_lib.module("new_lib_module"));
    // .
    // .
    // .
    lib_unit_tests.root_module.addImport("new_lib", new_lib.module("new_lib_module"));
    // .
    // .
    // .

```


## Third-party libraries that may prove useful in the future

### [known-folders](https://github.com/ziglibs/known-folders)

Provides easy access to Known Folders, as per XDG spec and OS conventions.

