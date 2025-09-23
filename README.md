# hissylogz

Structured logging support for Zig 0.15.1, enjoy, or my cat may hiss at you. 😸

This is a minimal logging framework to satisfy basic logging needs:

- Log levels configurable at *runtime*, not compiled in
- Simple, low ceremony, structured logging
- Thread-safe, yet performant with efficient resource usage
- Out-of-the-box log output friendly to cloud deployments (EKS, LOKI, etc) and log scrapers
    - JSON output (machine friendly)
    - Text output (human friendly)
- [ULID](https://github.com/ulid/spec) (Universally Unique Lexicographically Sortable Identifiers) support
- Pluggable timestamp supplier (e.g. simulations)

Non-goals:
- Do everything (loading config from various sources, have rolling file appenders, etc)
- Become baggage-laden (dependencies on everything else out there)

These are early days, and the feature set may grow, bugs will be found and fixed.

## Getting Started
---

### Fetch the package

Let zig fetch the latest package and integrate it into your `build.zig.zon` automagically:

```shell
zig fetch --save https://github.com/hissyfit-dev/hissylogz/archive/refs/tags/v0.2.2.tar.gz
```

#### Package for Zig 0.15.x

```shell
zig fetch --save https://github.com/hissyfit-dev/hissylogz/archive/refs/tags/v0.2.2.tar.gz
```

#### Package for Zig 0.14.x

```shell
zig fetch --save https://github.com/hissyfit-dev/hissylogz/archive/refs/tags/v0.1.1.tar.gz
```

#### Package for Zig 0.13.x

```shell
zig fetch --save https://github.com/hissyfit-dev/hissylogz/archive/refs/tags/v0.0.12.tar.gz
```

### Integrate into your build

Add dependency import in `build.zig`:

```zig
    const hissylogz = b.dependency("hissylogz", .{
        .target = target,
        .optimize = optimize,
    });

    // .
    // .
    // .
    lib.root_module.addImport("hissylogz", hissylogz.module("hissylogz"));
    // .
    // .
    // .
    exe.root_module.addImport("hissylogz", hissylogz.module("hissylogz"));
    // .
    // .
    // .
    lib_unit_tests.addImport("hissylogz", hissylogz.module("hissylogz"));
    // .
    // .
    // .

```


## Usage

### Overview

There may multiple logger pools, optionally, a global logger pool is supported.
Each logger pool is thread-safe.

Logger pools provision and cache loggers, each of which are in turn thread-safe (loggers are shared).

Using a logger, entries my be created at various log levels (`fine`, `debug`, `info`, `warn`, `err`, `fatal`), and named values attached to log entries via chain calls.
Such entries are "borrowed" from entry pools in loggers, and will be returned to the pool upon a terminating call to `log()`.

> Gotcha: Do *not* use a `stdout` writer for logging in unit tests, use `stderr` instead.
> See open Zig issue: [zig build test hangs if stdout included](https://github.com/ziglang/zig/issues/18111)

### Using independent logger pools

Prepare a logger pool for use:

```zig

const std = @import("std");
const debug = std.debug;
const io = std.io;

const hissylogz = @import("hissylogz");

pub fn main() !void {
    // Prepare allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Prepare STDOUT
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);

    // Prepare logger pool
    const pool = try hissylogz.loggerPool(allocator, .{
        .writer = &stdout_writer,
        .filter_level = .info,
    });
    defer pool.deinit();

    // Do your thing

}
```

### Logging

Once you have a pool, you can "tear-off" loggers, and create entries at various levels:

```zig
fn useLoggerPool(pool: *LoggerPool) void {
    var logger = pool.logger("my very own logger");
    logger.debug()
        .str("first", "Non-rendered entry")
        .boolean("rendered", false)
        .log();
    logger.info()
        .str("first", "Rendered entry")
        .boolean("rendered", true)
        .log();
    logger.warn()
        .src(@src())
        .str("another", "Another rendered entry")
        .log();
}

```

A few trivial examples:

```zig

for (0..5) |idx| {

    // Log at fine level, include a source code reference, and with idx in binary
    logger.fine()
        .msg("Fine entry")
        .src(@src())
        .intb("idx", idx)
        .log();

    // Log at debug level, include a source code reference, and with idx in hexadecimal
    logger.debug()
        .msg("Debug entry")
        .src(@src())
        .intx("idx", idx)
        .log();

    // Log at info level, with idx in decimal
    logger.info()
        .msg("Info entry")
        .int("idx", idx)
        .log();

    // Log at warning level, with idx in decimal
    logger.warn()
        .msg("Warning entry")
        .int("idx", idx)
        .log();

    // Log at error level, with idx in decimal and an error enum name
    doSomethingHorrible() catch |e| {
        logger.err()
            .msg("Error entry")
            .err(e)
            .int("idx", idx)
            .log();
    }

    // Log a fatal message
    logger.fatal()
        .msg("Fatal error entry")
        .log();
}

```

### The source of timestamps may be overridden

`LogOptions.ns_ts_supplier` defaults to the system's nanosecond-precision timestamp supplier.
If running a simulator with accellerated time, for example, you can provide your own, e.g.

Given a `simulator` package with a function having the signature:
```zig
pub fn virtualNanosSinceEpoch() i128
```

We can use the simulator's virtual timestamps as follows:

```zig

    const sim = @import("simulator");

    var log_options: LogOptions = .{
        // other overrides
        // ...
        // now provide our timestamp supplier
        .ns_ts_supplier = sim.virtualNanosSinceEpoch,
    };

```


### Using the global logger pool (optional)

In your main module, initialize the global logger pool, e.g.

```zig

const std = @import("std");
const debug = std.debug;
const io = std.io;

const hissylogz = @import("hissylogz");

pub fn main() !void {
    // Prepare allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Prepare STDOUT
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);

    // Prepare global logger pool
    try hissylogz.initGlobalLoggerPool(allocator, .{
        .writer = &stdout_writer,
        .filter_level = .info,
    });
    defer hissylogz.deinitGlobalLoggerPool();

    // Do your thing

}
```

### ULIDs

I added [ULID](https://github.com/ulid/spec) support for logging needs, but it may be useful by itself.

- `Ulid` struct and `Generator`.
    - The `Ulid` struct is packed such that it is trivially bit-castable to `u128` or `[16]u8`.
    - Maintains monotonic sort order (correctly detects and handles the same millisecond) per `generator`.

> For all-singing, all-dancing ULID support, consider [ulid-zig](https://github.com/rsepassi/ulid-zig).


```zig

const hissylogz = @import("hissylogz");
const ulid = hissylogz.ulid;

pub fn main() !void {

    var gen = ulid.generator();

    const ulid_0 = try gen.next();
    const ulid_1 = try gen.next();

    const str = ulid_0.encode();
    const ulid_from_str = try ulid.decode(&str);

    const bytes = ulid_0.bytes();
    const ulid_from_bytes = try ulid.fromBytes(&bytes);

}

```


## Dependencies

NONE!

## Acknowledgements

I drew inspiration for the logger/entry API from [`log.zig`](https://github.com/karlseguin/log.zig).

I vendored in a few bits lifted from [ulid-zig](https://github.com/rsepassi/ulid-zig) under 0BSD.
This is a solid library and comes with plenty of bells and whistles, a nice C ABI, the works.
I've added known error sets, and a heavily trimmed down, restructured API.

## License

This project is licensed under the [MIT License](./LICENSE.md).

## Project status

*Active*.

---
hissylogz.

(c) 2024-2025 Kevin Poalses
