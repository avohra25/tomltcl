# tomltcl

Pure **Tcl 8.6** toolkit for [TOML 1.0.0](https://toml.io/en/v1.0.0). No Critcl, tdom, or tcllib required at runtime (`tcltest` is used only for tests).

## Features (0.1.0 + encode)

- Lexer + recursive-descent parser for TOML 1.0.0 values and documents
- Keys (bare, quoted, dotted), basic/literal/multiline strings, integers (hex/oct/bin + underscores), floats (`inf`/`nan`), booleans
- Offset and local datetimes, local dates and times
- Arrays, inline tables, standard tables, array-of-tables
- Strict duplicate-key / table-conflict detection with line:column errors
- Typed document model for faithful round-trips
- `tomltcl::encode` / `tomltcl::stringify` with sorted keys and multiline-string heuristics

## Document model

Every value is a two-element list `{type data}`:

| type | data |
|------|------|
| `string` | Tcl string |
| `integer` | Tcl integer (wide) |
| `float` | double, or `inf` / `-inf` / `nan` |
| `bool` | `1` / `0` |
| `datetime` / `datetime-local` / `date` / `time` | ISO-like string |
| `array` | list of typed values |
| `table` | dict of key → typed value |

`tomltcl::parse` / `tomltcl::decode` return a root `table` value. Use `tomltcl::tv_type` / `tomltcl::tv_data` or `tomltcl::unwrap` / `tomltcl::dump`.

## Install / use

```tcl
tclsh
% set auto_path [linsert $auto_path 0 /path/to/tomltcl]
% package require tomltcl
% set doc [tomltcl::parse {title = "hey"}]
% puts [tomltcl::dump $doc]
```

CLI:

```bash
tclsh tomltcl-cli.tcl parse examples/example.toml
tclsh tomltcl-cli.tcl valid examples/example.toml
```

## Tests

```bash
tclsh tests/all.tcl
```

## License

MIT — see [LICENSE](LICENSE).
