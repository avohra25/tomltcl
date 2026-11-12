#!/usr/bin/env tclsh
package require tcltest
namespace import ::tcltest::*

set root [file dirname [file dirname [file normalize [info script]]]]
set auto_path [linsert $auto_path 0 $root]
if {[catch {package require tomltcl 0.1.0}]} {
    source [file join $root tomltcl.tcl]
}

proc rootdict {text} { ::tomltcl::tv_data [::tomltcl::parse $text] }

# --- strings ---
test str-basic-1 {basic string} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = "hello"}] a]
} -result hello

test str-escape-1 {escapes} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = "a\nb\tc\\d\"e"}] a]
} -result "a\nb\tc\\d\"e"

test str-unicode-1 {unicode escape} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = "\u0041\U00000042"}] a]
} -result AB

test str-literal-1 {literal string} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = 'C:\Users\path'}] a]
} -result {C:\Users\path}

test str-ml-basic-1 {multiline basic} -body {
    ::tomltcl::tv_data [dict get [rootdict {
s = """
hello
world"""}] s]
} -result "hello\nworld"

test str-ml-basic-trim {multiline trims first newline} -body {
    ::tomltcl::tv_data [dict get [rootdict {
s = """
abc"""}] s]
} -result abc

test str-ml-literal-1 {multiline literal} -body {
    ::tomltcl::tv_data [dict get [rootdict {
s = '''
keep\nslash'''}] s]
} -result "keep\\nslash"

test str-quoted-key {quoted key} -body {
    ::tomltcl::tv_data [dict get [rootdict {"127.0.0.1" = "value"}] "127.0.0.1"]
} -result value

# --- integers ---
test int-dec {decimal} -body {
    list [::tomltcl::tv_type [dict get [rootdict {a = 42}] a]] \
         [::tomltcl::tv_data [dict get [rootdict {a = 42}] a]]
} -result {integer 42}

test int-neg {negative} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = -17}] a]
} -result -17

test int-plus {plus} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = +99}] a]
} -result 99

test int-underscore {underscores} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = 1_000_000}] a]
} -result 1000000

test int-hex {hex} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = 0xDEAD}] a]
} -result 57005

test int-oct {octal} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = 0o755}] a]
} -result 493

test int-bin {binary} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = 0b1010}] a]
} -result 10

test int-leading-zero-bad {leading zero rejected} -body {
    expr {[catch {::tomltcl::parse {a = 01}}] == 1}
} -result 1

# --- floats ---
test float-basic {float} -body {
    list [::tomltcl::tv_type [dict get [rootdict {a = 1.5}] a]] \
         [::tomltcl::tv_data [dict get [rootdict {a = 1.5}] a]]
} -result {float 1.5}

test float-exp {exponent} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = 1e2}] a]
} -result 100.0

test float-inf {inf} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = inf}] a]
} -result inf

test float-ninf {-inf} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = -inf}] a]
} -result -inf

test float-nan {nan} -body {
    set v [::tomltcl::tv_data [dict get [rootdict {a = nan}] a]]
    expr {$v eq "nan"}
} -result 1

# --- bools ---
test bool-true {true} -body {
    list [::tomltcl::tv_type [dict get [rootdict {a = true}] a]] \
         [::tomltcl::tv_data [dict get [rootdict {a = true}] a]]
} -result {bool 1}

test bool-false {false} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = false}] a]
} -result 0

# --- dates ---
test date-local {local date} -body {
    list [::tomltcl::tv_type [dict get [rootdict {d = 2020-01-01}] d]] \
         [::tomltcl::tv_data [dict get [rootdict {d = 2020-01-01}] d]]
} -result {date 2020-01-01}

test time-local {local time} -body {
    ::tomltcl::tv_data [dict get [rootdict {t = 12:34:56}] t]
} -result 12:34:56

test time-frac {time with frac} -body {
    ::tomltcl::tv_data [dict get [rootdict {t = 12:34:56.789}] t]
} -result 12:34:56.789

test dt-offset-z {offset datetime Z} -body {
    list [::tomltcl::tv_type [dict get [rootdict {d = 2020-01-01T12:00:00Z}] d]] \
         [::tomltcl::tv_data [dict get [rootdict {d = 2020-01-01T12:00:00Z}] d]]
} -result {datetime 2020-01-01T12:00:00Z}

test dt-offset {offset datetime} -body {
    ::tomltcl::tv_data [dict get [rootdict {d = 2020-01-01T12:00:00-07:00}] d]
} -result 2020-01-01T12:00:00-07:00

test dt-local {local datetime} -body {
    list [::tomltcl::tv_type [dict get [rootdict {d = 2020-01-01T12:00:00}] d]] \
         [::tomltcl::tv_data [dict get [rootdict {d = 2020-01-01T12:00:00}] d]]
} -result {datetime-local 2020-01-01T12:00:00}

test dt-space {space separator} -body {
    ::tomltcl::tv_data [dict get [rootdict {d = 2020-01-01 12:00:00Z}] d]
} -result 2020-01-01T12:00:00Z

# --- arrays ---
test arr-ints {int array} -body {
    set a [::tomltcl::tv_data [dict get [rootdict {a = [1, 2, 3]}] a]]
    set out {}
    foreach x $a { lappend out [::tomltcl::tv_data $x] }
    set out
} -result {1 2 3}

test arr-empty {empty array} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = []}] a]
} -result {}

test arr-trailing-comma {trailing comma} -body {
    llength [::tomltcl::tv_data [dict get [rootdict {a = [1, 2,]}] a]]
} -result 2

test arr-multiline {multiline array} -body {
    llength [::tomltcl::tv_data [dict get [rootdict {
a = [
  1,
  2,
]}] a]]
} -result 2

test arr-nested {nested arrays} -body {
    set a [::tomltcl::tv_data [dict get [rootdict {a = [[1],[2]]}] a]]
    list [llength $a] [::tomltcl::tv_type [lindex $a 0]]
} -result {2 array}

test arr-mixed {mixed types allowed} -body {
    set a [::tomltcl::tv_data [dict get [rootdict {a = [1, "two", true]}] a]]
    list [::tomltcl::tv_type [lindex $a 0]] \
         [::tomltcl::tv_type [lindex $a 1]] \
         [::tomltcl::tv_type [lindex $a 2]]
} -result {integer string bool}

# --- inline tables ---
test inline-1 {inline table} -body {
    set t [::tomltcl::tv_data [dict get [rootdict {p = {x = 1, y = 2}}] p]]
    list [::tomltcl::tv_data [dict get $t x]] [::tomltcl::tv_data [dict get $t y]]
} -result {1 2}

test inline-empty {empty inline} -body {
    dict size [::tomltcl::tv_data [dict get [rootdict {p = {}}] p]]
} -result 0

test inline-dotted {dotted in inline} -body {
    set t [::tomltcl::tv_data [dict get [rootdict {p = {a.b = 1}}] p]]
    ::tomltcl::tv_data [dict get [::tomltcl::tv_data [dict get $t a]] b]
} -result 1

test inline-dup-bad {inline dup rejected} -body {
    expr {[catch {::tomltcl::parse {p = {a = 1, a = 2}}}] == 1}
} -result 1

test inline-trail-bad {inline trailing comma rejected} -body {
    expr {[catch {::tomltcl::parse {p = {a = 1,}}}] == 1}
} -result 1

# --- tables ---
test table-1 {standard table} -body {
    set d [rootdict {
[server]
host = "localhost"
port = 8080
}]
    set s [::tomltcl::tv_data [dict get $d server]]
    list [::tomltcl::tv_data [dict get $s host]] [::tomltcl::tv_data [dict get $s port]]
} -result {localhost 8080}

test table-dotted-header {dotted table header} -body {
    set d [rootdict {
[a.b]
c = 1
}]
    ::tomltcl::tv_data [dict get [::tomltcl::tv_data [dict get [::tomltcl::tv_data [dict get $d a]] b]] c]
} -result 1

test dotted-kv {dotted key assignment} -body {
    set d [rootdict {a.b.c = 9}]
    ::tomltcl::tv_data [dict get [::tomltcl::tv_data [dict get [::tomltcl::tv_data [dict get $d a]] b]] c]
} -result 9

test table-redef-bad {redefine table rejected} -body {
    expr {[catch {::tomltcl::parse {
[a]
b = 1
[a]
c = 2
}}] == 1}
} -result 1

test table-implicit-ok {implicit then explicit ok} -body {
    set d [rootdict {
a.b = 1
[a]
c = 2
}]
    list [::tomltcl::tv_data [dict get [::tomltcl::tv_data [dict get $d a]] b]] \
         [::tomltcl::tv_data [dict get [::tomltcl::tv_data [dict get $d a]] c]]
} -result {1 2}

# --- array of tables ---
test aot-1 {array of tables} -body {
    set d [rootdict {
[[prod]]
name = "A"
[[prod]]
name = "B"
}]
    set arr [::tomltcl::tv_data [dict get $d prod]]
    list [llength $arr] \
         [::tomltcl::tv_data [dict get [::tomltcl::tv_data [lindex $arr 0]] name]] \
         [::tomltcl::tv_data [dict get [::tomltcl::tv_data [lindex $arr 1]] name]]
} -result {2 A B}

test aot-nested {aot with subtable} -body {
    set d [rootdict {
[[fruit]]
name = "apple"
[fruit.physical]
color = "red"
[[fruit]]
name = "banana"
}]
    set arr [::tomltcl::tv_data [dict get $d fruit]]
    list [llength $arr] \
         [::tomltcl::tv_data [dict get [::tomltcl::tv_data [dict get [::tomltcl::tv_data [lindex $arr 0]] physical]] color]] \
         [::tomltcl::tv_data [dict get [::tomltcl::tv_data [lindex $arr 1]] name]]
} -result {2 red banana}

# --- duplicates / conflicts ---
test dup-key {duplicate key} -body {
    expr {[catch {::tomltcl::parse {
a = 1
a = 2
}}] == 1}
} -result 1

test conflict-value-table {value then table conflict} -body {
    expr {[catch {::tomltcl::parse {
a = 1
[a]
b = 2
}}] == 1}
} -result 1

test conflict-table-value {implicit table then value conflict} -body {
    expr {[catch {::tomltcl::parse {
a.b = 1
a = 2
}}] == 1}
} -result 1

# --- comments / whitespace ---
test comments {comments ignored} -body {
    ::tomltcl::tv_data [dict get [rootdict {
# comment
a = 1 # trailing
# more
}] a]
} -result 1

test empty-doc {empty document} -body {
    dict size [rootdict {}]
} -result 0

test only-comments {comments only} -body {
    dict size [rootdict {
# hi
# there
}]
} -result 0

test valid-ok {valid true} -body {
    ::tomltcl::valid {a = 1}
} -result 1

test valid-bad {valid false} -body {
    ::tomltcl::valid {a = }
} -result 0

test err-linecol {error has line:col} -body {
    catch {::tomltcl::parse {
a = 1
b = 
}} err
    regexp {at [0-9]+:[0-9]+:} $err
} -result 1

test keys-bare {bare key chars} -body {
    ::tomltcl::tv_data [dict get [rootdict {key_1-2 = "ok"}] key_1-2]
} -result ok

test decode-alias {decode alias} -body {
    ::tomltcl::tv_type [::tomltcl::decode {a = 1}]
} -result table

test package-version {package version} -body {
    set ::tomltcl::version
} -result 0.1.0

test dump-runs {dump does not error} -body {
    string match *string* [::tomltcl::dump [::tomltcl::parse {a = "x"}]]
} -result 1

test ml-line-ending-backslash {line ending backslash} -body {
    set bs [format %c 92]
    set toml "s = \"\"\"
a${bs}
b\"\"\""
    ::tomltcl::tv_data [dict get [rootdict $toml] s]
} -result ab

test bool-not-ident {true as key ok} -body {
    ::tomltcl::tv_data [dict get [rootdict {true = false}] true]
} -result 0


# --- stage 2: encode / round-trip ---
test enc-simple {encode simple} -body {
    set doc [::tomltcl::parse {a = 1
b = "x"}]
    set s [::tomltcl::encode $doc]
    set d2 [::tomltcl::tv_data [::tomltcl::parse $s]]
    list [::tomltcl::tv_data [dict get $d2 a]] [::tomltcl::tv_data [dict get $d2 b]]
} -result {1 x}

test enc-sorted {stable key ordering} -body {
    set doc [::tomltcl::parse {z = 1
a = 2}]
    set s [::tomltcl::encode $doc -sorted 1]
    # a should appear before z
    expr {[string first a $s] < [string first z $s]}
} -result 1

test enc-bool-float {encode bool float} -body {
    set doc [::tomltcl::tv table [dict create \
        t [::tomltcl::tv bool 1] \
        f [::tomltcl::tv float 1.5] \
        n [::tomltcl::tv float nan]]]
    set s [::tomltcl::encode $doc]
    set d [::tomltcl::tv_data [::tomltcl::parse $s]]
    list [::tomltcl::tv_data [dict get $d t]] \
         [::tomltcl::tv_data [dict get $d f]] \
         [::tomltcl::tv_data [dict get $d n]]
} -result {1 1.5 nan}

test enc-array {encode array} -body {
    set doc [::tomltcl::parse {a = [1, 2, 3]}]
    set s [::tomltcl::encode $doc]
    llength [::tomltcl::tv_data [dict get [::tomltcl::tv_data [::tomltcl::parse $s]] a]]
} -result 3

test enc-table {encode standard table} -body {
    set doc [::tomltcl::parse {
[server]
host = "localhost"
}]
    set s [::tomltcl::encode $doc]
    set d [::tomltcl::tv_data [::tomltcl::parse $s]]
    ::tomltcl::tv_data [dict get [::tomltcl::tv_data [dict get $d server]] host]
} -result localhost

test enc-aot {encode array of tables} -body {
    set doc [::tomltcl::parse {
[[p]]
n = "A"
[[p]]
n = "B"
}]
    set s [::tomltcl::encode $doc]
    set arr [::tomltcl::tv_data [dict get [::tomltcl::tv_data [::tomltcl::parse $s]] p]]
    list [llength $arr] [::tomltcl::tv_data [dict get [::tomltcl::tv_data [lindex $arr 1]] n]]
} -result {2 B}

test enc-escape {encode escapes} -body {
    set doc [::tomltcl::tv table [dict create s [::tomltcl::tv string "a\nb\"c\\"]]]
    set s [::tomltcl::encode $doc]
    ::tomltcl::tv_data [dict get [::tomltcl::tv_data [::tomltcl::parse $s]] s]
} -result "a\nb\"c\\"

test enc-datetime {encode datetime} -body {
    set doc [::tomltcl::parse {d = 2020-01-01T00:00:00Z}]
    set s [::tomltcl::encode $doc]
    list [::tomltcl::tv_type [dict get [::tomltcl::tv_data [::tomltcl::parse $s]] d]] \
         [::tomltcl::tv_data [dict get [::tomltcl::tv_data [::tomltcl::parse $s]] d]]
} -result {datetime 2020-01-01T00:00:00Z}

test enc-inline-roundtrip {inline table roundtrip via encode} -body {
    set doc [::tomltcl::parse {p = {x = 1, y = 2}}]
    # encode may expand to [p] table form
    set s [::tomltcl::encode $doc]
    set d [::tomltcl::tv_data [::tomltcl::parse $s]]
    list [::tomltcl::tv_data [dict get [::tomltcl::tv_data [dict get $d p]] x]] \
         [::tomltcl::tv_data [dict get [::tomltcl::tv_data [dict get $d p]] y]]
} -result {1 2}

test enc-stringify {stringify alias} -body {
    string length [::tomltcl::stringify [::tomltcl::parse {a = 1}]]
} -match glob -result {[1-9]*}

test enc-ml-string {multiline string choice} -body {
    set long "line1\nline2\nline3\nline4\nline5\nextra text here!!"
    set doc [::tomltcl::tv table [dict create s [::tomltcl::tv string $long]]]
    set s [::tomltcl::encode $doc]
    expr {[string first {"""} $s] >= 0}
} -result 1

test enc-empty {empty doc} -body {
    ::tomltcl::encode [::tomltcl::tv table [dict create]]
} -result {}

test roundtrip-property {parse-encode-parse several docs} -body {
    set samples {
        {a = 1}
        {s = "hi"
n = 3.5
b = true}
        {[t]
x = 1}
        {[[a]]
k = 1
[[a]]
k = 2}
        {arr = [1, "two", false]}
        {d = 2021-06-15
t = 08:30:00}
    }
    set ok 1
    foreach sample $samples {
        set d1 [::tomltcl::parse $sample]
        set enc [::tomltcl::encode $d1]
        set d2 [::tomltcl::parse $enc]
        if {[::tomltcl::dump $d1] ne [::tomltcl::dump $d2]} {
            set ok 0
            break
        }
    }
    set ok
} -result 1

test ml-nested-inline {nested inline tables} -body {
    set d [rootdict {a = {b = {c = 1}}}]
    ::tomltcl::tv_data [dict get [::tomltcl::tv_data [dict get [::tomltcl::tv_data [dict get $d a]] b]] c]
} -result 1

test aot-edge-empty-then-key {aot then keys} -body {
    set d [rootdict {
[[x]]
[[x]]
a = 1
}]
    set arr [::tomltcl::tv_data [dict get $d x]]
    list [llength $arr] [::tomltcl::tv_data [dict get [::tomltcl::tv_data [lindex $arr 1]] a]]
} -result {2 1}



# --- stage 3: get / exists / to_json / more invalid ---
test get-simple {get simple key} -body {
    set doc [::tomltcl::parse {a = 42}]
    ::tomltcl::tv_data [::tomltcl::get $doc a]
} -result 42

test get-dotted {get dotted path} -body {
    set doc [::tomltcl::parse {
[a.b]
c = 7
}]
    ::tomltcl::tv_data [::tomltcl::get $doc a.b.c]
} -result 7

test get-array-index {get array index via list path} -body {
    set doc [::tomltcl::parse {a = [10, 20, 30]}]
    ::tomltcl::tv_data [::tomltcl::get $doc {a 1}]
} -result 20

test get-aot {get aot element} -body {
    set doc [::tomltcl::parse {
[[x]]
n = "A"
[[x]]
n = "B"
}]
    ::tomltcl::tv_data [::tomltcl::get $doc {x 1 n}]
} -result B

test get-missing {get missing errors} -body {
    set doc [::tomltcl::parse {a = 1}]
    expr {[catch {::tomltcl::get $doc z}] == 1}
} -result 1

test exists-true {exists true} -body {
    ::tomltcl::exists [::tomltcl::parse {a = 1}] a
} -result 1

test exists-false {exists false} -body {
    ::tomltcl::exists [::tomltcl::parse {a = 1}] b
} -result 0

test exists-nested {exists nested} -body {
    ::tomltcl::exists [::tomltcl::parse {
[t]
x = 1
}] t.x
} -result 1

test json-object {to_json object} -body {
    set doc [::tomltcl::parse {a = 1
b = "x"
c = true}]
    ::tomltcl::to_json $doc
} -result {{"a":1,"b":"x","c":true}}

test json-array {to_json array} -body {
    set doc [::tomltcl::parse {a = [1, 2]}]
    ::tomltcl::to_json $doc
} -result {{"a":[1,2]}}

test json-datetime {to_json datetime as string} -body {
    set doc [::tomltcl::parse {d = 2020-01-01}]
    ::tomltcl::to_json $doc
} -result {{"d":"2020-01-01"}}

test json-escape {to_json escapes} -body {
    set doc [::tomltcl::tv table [dict create s [::tomltcl::tv string "a\"b"]]]
    ::tomltcl::to_json $doc
} -result {{"s":"a\"b"}}

test json-nested {to_json nested table} -body {
    set doc [::tomltcl::parse {
[t]
x = 1
}]
    ::tomltcl::to_json $doc
} -result {{"t":{"x":1}}}

test json-nan {nan becomes null} -body {
    set doc [::tomltcl::tv table [dict create n [::tomltcl::tv float nan]]]
    ::tomltcl::to_json $doc
} -result {{"n":null}}

# more invalid document rejection
test inv-bare-newline-string {newline in basic string} -body {
    expr {[catch {::tomltcl::parse "a = \"hi\nthere\""}] == 1}
} -result 1

test inv-trailing-inline {trailing comma inline} -body {
    expr {[catch {::tomltcl::parse {a = {b = 1,}}}] == 1}
} -result 1

test inv-unclosed-array {unclosed array} -body {
    expr {[catch {::tomltcl::parse {a = [1, 2}}] == 1}
} -result 1

test inv-unclosed-string {unclosed string} -body {
    expr {[catch {::tomltcl::parse {a = "hi}}] == 1}
} -result 1

test inv-bad-key {bad key char} -body {
    expr {[catch {::tomltcl::parse {a$b = 1}}] == 1}
} -result 1

test inv-double-eq {missing value} -body {
    expr {[catch {::tomltcl::parse {a = }}] == 1}
} -result 1

test inv-aot-on-value {aot on static array} -body {
    expr {[catch {::tomltcl::parse {
a = [1, 2]
[[a]]
x = 1
}}] == 1}
} -result 1

test inv-redef-key-via-dot {duplicate via dotted} -body {
    expr {[catch {::tomltcl::parse {
a = 1
a.b = 2
}}] == 1}
} -result 1

test inv-escape {bad escape} -body {
    expr {[catch {::tomltcl::parse {a = "\q"}}] == 1}
} -result 1

test inv-leading-us {leading underscore number} -body {
    expr {[catch {::tomltcl::parse {a = _1}}] == 1}
} -result 1

test key-literal {literal quoted key} -body {
    ::tomltcl::tv_data [dict get [rootdict {'a b' = 1}] {a b}]
} -result 1

test mixed-table-then-aot {table then aot conflict} -body {
    expr {[catch {::tomltcl::parse {
[a]
b = 1
[[a]]
c = 2
}}] == 1}
} -result 1

test empty-array-key {empty array value} -body {
    ::tomltcl::tv_type [dict get [rootdict {a = []}] a]
} -result array

test deep-dotted {deep dotted keys} -body {
    set d [rootdict {a.b.c.d.e = 5}]
    ::tomltcl::tv_data [::tomltcl::get [::tomltcl::tv table $d] a.b.c.d.e]
} -result 5

test hex-lower {hex lower} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = 0xff}] a]
} -result 255

test float-us {float underscores} -body {
    ::tomltcl::tv_data [dict get [rootdict {a = 1_000.5_0}] a]
} -result 1000.5

test offset-plus {positive offset} -body {
    ::tomltcl::tv_data [dict get [rootdict {d = 2020-01-01T00:00:00+05:30}] d]
} -result 2020-01-01T00:00:00+05:30

test comment-only-line-in-array {comment in array} -body {
    llength [::tomltcl::tv_data [dict get [rootdict {
a = [
1,
# c
2
]}] a]]
} -result 2


# --- JSON reader ---
test json-decode-scalars {json_decode scalars} -body {
    ::tomltcl::json_decode {[1, -2.5e3, "x", true, false, null]}
} -result {array {{number 1} {number -2.5e3} {string x} {bool 1} {bool 0} {null {}}}}

test json-decode-object-order {object keys keep source order} -body {
    ::tomltcl::json_decode { {"b": 1, "a": {"c": []}} }
} -result {object {b {number 1} a {object {c {array {}}}}}}

test json-decode-escapes {string escapes} -body {
    lindex [::tomltcl::json_decode {"a\"b\\c\/\n\t\u00e9"}] 1
} -result "a\"b\\c/\n\t\u00e9"

test json-decode-surrogates {surrogate pair becomes one character in UTF-8} -body {
    binary encode hex [encoding convertto utf-8 [lindex [::tomltcl::json_decode {"\ud83d\ude00"}] 1]]
} -result f09f9880

test json-decode-errors {malformed JSON is rejected with a position} -body {
    set out {}
    foreach bad {{[1,]} {{"a":1,"a":2}} {"\ud800"} {01} {[1] x} "\"a\x01\"" {} {{"a" 1}}} {
        lappend out [catch {::tomltcl::json_decode $bad} err]
    }
    list $out [string match {JSON parse error at 1:4:*} [catch {::tomltcl::json_decode {[1,]}} e; set e]]
} -result {{1 1 1 1 1 1 1 1} 1}

# --- tagged JSON ---
test tagged-scalars {to_tagged_json scalar tags} -body {
    ::tomltcl::to_tagged_json [::tomltcl::parse {
s = "x"
i = 42
f = 1e3
b = true
odt = 1979-05-27T07:32:00Z
ldt = 1979-05-27T07:32:00
ld = 1979-05-27
lt = 07:32:00
}]
} -result {{"b":{"type":"bool","value":"true"},"f":{"type":"float","value":"1000.0"},"i":{"type":"integer","value":"42"},"ld":{"type":"date-local","value":"1979-05-27"},"ldt":{"type":"datetime-local","value":"1979-05-27T07:32:00"},"lt":{"type":"time-local","value":"07:32:00"},"odt":{"type":"datetime","value":"1979-05-27T07:32:00Z"},"s":{"type":"string","value":"x"}}}

test tagged-special-floats {inf and nan keep their names} -body {
    ::tomltcl::to_tagged_json [::tomltcl::parse "a = inf\nb = -inf\nc = nan\nd = -0.0"]
} -result {{"a":{"type":"float","value":"inf"},"b":{"type":"float","value":"-inf"},"c":{"type":"float","value":"nan"},"d":{"type":"float","value":"-0.0"}}}

test tagged-nesting {arrays and tables nest as plain JSON} -body {
    ::tomltcl::to_tagged_json [::tomltcl::parse "a = \[\[1\], {x = 'y'}\]\n\[\[t\]\]\n\[\[t\]\]\nk = 1"]
} -result {{"a":[[{"type":"integer","value":"1"}],{"x":{"type":"string","value":"y"}}],"t":[{},{"k":{"type":"integer","value":"1"}}]}}

test tagged-roundtrip {from_tagged_json inverts to_tagged_json} -body {
    set src {
title = "TOML \u00e9"
n = -17
f = 6.02e23
when = 1979-05-27T00:32:00.999999-07:00
[db]
ports = [ 8000, 8001 ]
on = false
[[db.replica]]
host = "a"
[[db.replica]]
}
    set doc [::tomltcl::parse $src]
    set json [::tomltcl::to_tagged_json $doc]
    expr {[::tomltcl::to_tagged_json [::tomltcl::from_tagged_json $json]] eq $json}
} -result 1

test tagged-pretty {pretty output is the same JSON} -body {
    set doc [::tomltcl::parse "a = 1\n\[b\]\nc = \[1, 2\]"]
    expr {[::tomltcl::json_decode [::tomltcl::to_tagged_json $doc -pretty 1]]
          eq [::tomltcl::json_decode [::tomltcl::to_tagged_json $doc]]}
} -result 1

test tagged-validation {from_tagged_json rejects values TOML can't hold} -body {
    set out {}
    foreach bad {
        {{"a": {"type": "integer", "value": "9223372036854775808"}}}
        {{"a": {"type": "integer", "value": "1.5"}}}
        {{"a": {"type": "float", "value": "abc"}}}
        {{"a": {"type": "bool", "value": "yes"}}}
        {{"a": {"type": "datetime", "value": "1979-05-27"}}}
        {{"a": {"type": "date-local", "value": "1979-13-01"}}}
        {{"a": {"type": "color", "value": "red"}}}
        {{"a": 1}}
        {[]}
    } {
        lappend out [catch {::tomltcl::from_tagged_json $bad}]
    }
    set out
} -result {1 1 1 1 1 1 1 1 1}

test tagged-int-bounds {64-bit integer limits survive} -body {
    set doc [::tomltcl::from_tagged_json {{"lo": {"type": "integer", "value": "-9223372036854775808"}, "hi": {"type": "integer", "value": "9223372036854775807"}}}]
    ::tomltcl::encode $doc
} -result "hi = 9223372036854775807\nlo = -9223372036854775808\n"

test tagged-encode-reparse {encode output of a tagged document parses back} -body {
    set j {{"a": {"b": [{"c": {"type": "string", "value": "x\ny"}}, {}]}, "t": {"type": "time-local", "value": "07:32:00.5"}}}
    set doc [::tomltcl::from_tagged_json $j]
    expr {[::tomltcl::to_tagged_json [::tomltcl::parse [::tomltcl::encode $doc]]]
          eq [::tomltcl::to_tagged_json $doc]}
} -result 1

# --- strict UTF-8 input ---
test utf8-valid {decode_bytes accepts UTF-8 and skips a BOM} -body {
    set s [::tomltcl::tv_data [dict get [::tomltcl::tv_data [::tomltcl::decode_bytes "\xEF\xBB\xBFa = \"\xC3\xA9\xF0\x9F\x98\x80\""]] a]]
    binary encode hex [encoding convertto utf-8 $s]
} -result c3a9f09f9880

test utf8-errors {overlongs, surrogates, truncation and stray bytes are rejected} -body {
    set out {}
    foreach bad {"a = '\xC0\xAF'" "a = '\xED\xA0\x80'" "a = '\xF4\x90\x80\x80'"
                 "a = '\xE2\x82'" "a = '\x80'" "a = '\xFF'"} {
        lappend out [::tomltcl::utf8_error $bad]
    }
    set out
} -result {5 5 5 5 5 5}

test utf8-error-message {decode_bytes reports line and byte offset} -body {
    catch {::tomltcl::decode_bytes "a = 1\nb = '\xFF'"} err
    set err
} -result {TOML parse error at line 2: invalid UTF-8 at byte offset 11}

test unicode-escape-astral {\U escapes past U+FFFF encode to 4-byte UTF-8} -body {
    binary encode hex [encoding convertto utf-8 [::tomltcl::tv_data [dict get [rootdict {a = "\U0001F600"}] a]]]
} -result f09f9880

# --- CLI decode / encode ---
proc cli {args} {
    set script [file join $::root tomltcl-cli.tcl]
    set input ""
    if {[lindex $args 0] eq "-input"} { set input [lindex $args 1]; set args [lrange $args 2 end] }
    set f [open |[list [info nameofexecutable] $script {*}$args 2>@1] r+]
    fconfigure $f -translation binary
    puts -nonewline $f $input
    close $f write
    set out [read $f]
    set code 0
    if {[catch {close $f} err opts]} {
        set ec [dict get $opts -errorcode]
        if {[lindex $ec 0] eq "CHILDSTATUS"} { set code [lindex $ec 2] }
    }
    list $code [encoding convertfrom utf-8 $out]
}

test cli-decode {decode prints tagged JSON} -body {
    lassign [cli -input "a = 1\nb = \[true\]\n" decode] code out
    list $code [::tomltcl::json_decode $out]
} -result {0 {object {a {object {type {string integer} value {string 1}}} b {array {{object {type {string bool} value {string true}}}}}}}}

test cli-decode-invalid {decode exits 1 on invalid TOML} -body {
    lassign [cli -input "a = \n" decode] code out
    list $code [string match {TOML parse error at 1:*} $out]
} -result {1 1}

test cli-encode {encode turns tagged JSON into TOML} -body {
    cli -input {{"t": {"x": {"type": "float", "value": "inf"}}, "a": {"type": "string", "value": "\u00e9"}}} encode
} -result [list 0 "a = \"\u00e9\"\n\n\[t\]\nx = inf\n"]

test cli-encode-invalid {encode rejects untagged JSON} -body {
    lassign [cli -input {{"a": 1}} encode] code out
    list $code [string trim $out]
} -result {1 {a: bare JSON number is not a tagged value}}

puts ""
set ::_failed $::tcltest::numTests(Failed)
cleanupTests
if {$_failed > 0} { exit 1 }
exit 0
