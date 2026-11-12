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
- Path helpers `tomltcl::get` / `tomltcl::exists` (dotted paths; list paths for array indices)
- `tomltcl::to_json` for interoperability (datetimes as strings; nan/inf as null)
- Tagged JSON in both directions (`to_tagged_json` / `from_tagged_json`), the
  lossless format used by [toml-test](https://github.com/toml-lang/toml-test)
- Strict UTF-8 input (`decode_bytes` / `read_file`): overlong forms, surrogates
  and truncated sequences are rejected with the byte offset; characters past
  U+FFFF round-trip correctly on Tcl 8.6
- A small RFC 8259 JSON reader (`json_decode`)

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

## Tagged JSON

`to_tagged_json` writes every scalar as `{"type": T, "value": "..."}`, where T is
`string`, `integer`, `float`, `bool`, `datetime`, `datetime-local`, `date-local`
or `time-local`; tables become objects and arrays become arrays. Nothing is lost,
so it is a good format for diffing or handing TOML to another language.

```tcl
% tomltcl::to_tagged_json [tomltcl::parse {when = 1979-05-27}]
{"when":{"type":"date-local","value":"1979-05-27"}}
% tomltcl::encode [tomltcl::from_tagged_json {{"n": {"type": "integer", "value": "7"}}}]
n = 7
```

`from_tagged_json` checks each value against the TOML grammar (64-bit integer
range, valid dates and times, known types), so whatever it accepts can be encoded
and parsed back. `-pretty 1` indents the output.

For files, prefer `tomltcl::read_file path`: it reads raw bytes and validates
UTF-8 itself, since Tcl's own decoder silently accepts malformed input.

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
tclsh tomltcl-cli.tcl decode examples/example.toml      # TOML -> tagged JSON
tclsh tomltcl-cli.tcl decode examples/example.toml | tclsh tomltcl-cli.tcl encode
```

`decode` and `encode` read stdin when no file is given and exit 1 on bad input,
matching the decoder/encoder interface `toml-test` expects.

## Tests

```bash
tclsh tests/all.tcl
```

## License

MIT — see [LICENSE](LICENSE).
