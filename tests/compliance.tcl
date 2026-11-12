#!/usr/bin/env tclsh
# Runs the vendored toml-test suite (TOML 1.0.0 subset of
# https://github.com/toml-lang/toml-test, MIT) against tomltcl.
#
#   valid/*.toml    decoder: parse, emit tagged JSON, compare with the .json
#                   encoder: build the document from the .json, encode it,
#                            parse the result again and compare
#   invalid/*.toml  decoder must reject the file
#
# Usage: tclsh tests/compliance.tcl [-v] [-decoder-only] [glob ...]
# Exit status is 1 if any result differs from tests/toml-test/known-failures.

set here [file dirname [file normalize [info script]]]
set root [file dirname $here]
set auto_path [linsert $auto_path 0 $root]
if {[catch {package require tomltcl}]} { source [file join $root tomltcl.tcl] }

namespace eval ::compliance {
    variable suite [file join [file dirname [file normalize [info script]]] toml-test]
}

proc ::compliance::slurp {path {binary 0}} {
    set f [open $path [expr {$binary ? "rb" : "r"}]]
    if {!$binary} { fconfigure $f -encoding utf-8 }
    try { return [read $f] } finally { close $f }
}

# Canonical form of a datetime string: upper-case T/Z, space separator
# replaced, fractional seconds without trailing zeros.
proc ::compliance::norm_dt {s} {
    set s [string toupper $s]
    regsub {^([0-9]{4}-[0-9]{2}-[0-9]{2}) } $s {\1T} s
    if {[regexp {^(.*:[0-9]{2})\.([0-9]+)(.*)$} $s -> head frac tail]} {
        set frac [string trimright $frac 0]
        set s [expr {$frac eq "" ? "" : ".$frac"}]
        set s $head$s$tail
    }
    regsub {\+00:00$|-00:00$} $s Z s
    return $s
}

# Compare two json_decode trees holding tagged values. Returns "" when equal,
# otherwise a description of the first difference.
proc ::compliance::diff {want got path} {
    lassign $want wt wd
    lassign $got gt gd
    if {$wt ne $gt} { return "$path: expected JSON $wt, got $gt" }
    if {$wt eq "array"} {
        if {[llength $wd] != [llength $gd]} {
            return "$path: expected [llength $wd] array elements, got [llength $gd]"
        }
        set n 0
        foreach a $wd b $gd {
            set r [diff $a $b "$path\[$n\]"]
            if {$r ne ""} { return $r }
            incr n
        }
        return ""
    }
    if {$wt ne "object"} { return "$path: unexpected bare JSON $wt" }
    if {[lsort [dict keys $wd]] eq {type value}} {
        if {[lsort [dict keys $gd]] ne {type value}} { return "$path: expected a tagged value" }
        set type [lindex [dict get $wd type] 1]
        set gtype [lindex [dict get $gd type] 1]
        if {$type ne $gtype} { return "$path: expected type $type, got $gtype" }
        set a [lindex [dict get $wd value] 1]
        set b [lindex [dict get $gd value] 1]
        switch -glob -- $type {
            integer { set same [expr {$a == $b}] }
            float {
                set a [string trimleft [string tolower $a] +]
                set b [string trimleft [string tolower $b] +]
                if {[string match *nan $a] || [string match *nan $b]} {
                    set same [expr {[string match *nan $a] && [string match *nan $b]}]
                } elseif {[string match *inf $a] || [string match *inf $b]} {
                    set same [expr {$a eq $b}]
                } else {
                    set same [expr {double($a) == double($b)}]
                }
            }
            date* - time* { set same [expr {[norm_dt $a] eq [norm_dt $b]}] }
            default { set same [expr {$a eq $b}] }
        }
        if {!$same} { return "$path: expected $type [list $a], got [list $b]" }
        return ""
    }
    set wk [lsort [dict keys $wd]]
    set gk [lsort [dict keys $gd]]
    if {$wk ne $gk} { return "$path: expected keys [list $wk], got [list $gk]" }
    foreach k $wk {
        set sub [expr {$path eq "" ? "" : "$path."}]$k
        set r [diff [dict get $wd $k] [dict get $gd $k] $sub]
        if {$r ne ""} { return $r }
    }
    return ""
}

proc ::compliance::check_valid {name decoder_only} {
    variable suite
    set base [file join $suite [file rootname $name]]
    set want [::tomltcl::json_decode [slurp $base.json]]
    if {[catch {::tomltcl::read_file $base.toml} doc]} {
        return [list decoder "rejected: $doc"]
    }
    set got [::tomltcl::json_decode [::tomltcl::to_tagged_json $doc]]
    set d [diff $want $got ""]
    if {$d ne ""} { return [list decoder $d] }
    if {$decoder_only} { return {} }
    if {[catch {
        set doc2 [::tomltcl::from_tagged_json [slurp $base.json]]
        set text [::tomltcl::encode $doc2]
        set again [::tomltcl::parse $text]
    } err]} {
        return [list encoder "round trip failed: $err"]
    }
    set d [diff $want [::tomltcl::json_decode [::tomltcl::to_tagged_json $again]] ""]
    if {$d ne ""} { return [list encoder $d] }
    return {}
}

proc ::compliance::check_invalid {name} {
    variable suite
    if {[catch {::tomltcl::read_file [file join $suite $name]}]} { return {} }
    return [list decoder "accepted an invalid document"]
}

proc ::compliance::run {argv} {
    variable suite
    set verbose 0
    set decoder_only 0
    set globs {}
    foreach a $argv {
        switch -- $a {
            -v { set verbose 1 }
            -decoder-only { set decoder_only 1 }
            default { lappend globs $a }
        }
    }
    if {![llength $globs]} { set globs * }
    set known {}
    set kf [file join $suite known-failures]
    if {[file exists $kf]} {
        foreach line [split [slurp $kf] \n] {
            set line [string trim $line]
            if {$line eq "" || [string index $line 0] eq "#"} continue
            dict set known [lindex $line 0] 1
        }
    }
    set pass 0; set fail 0; set unexpected {}; set fixed {}
    foreach name [split [string trim [slurp [file join $suite files]]] \n] {
        if {[file extension $name] ne ".toml"} continue
        set id [file rootname $name]
        set match 0
        foreach g $globs { if {[string match $g $id]} { set match 1; break } }
        if {!$match} continue
        if {[string match valid/* $name]} {
            set r [check_valid $name $decoder_only]
        } else {
            set r [check_invalid $name]
        }
        if {[llength $r] == 0} {
            incr pass
            if {[dict exists $known $id]} { lappend fixed $id }
        } else {
            incr fail
            if {![dict exists $known $id]} { lappend unexpected "$id ([lindex $r 0]): [lindex $r 1]" }
            if {$verbose} { puts "FAIL $id ([lindex $r 0]): [lindex $r 1]" }
        }
    }
    puts "toml-test 1.0.0: [expr {$pass + $fail}] files, $pass passed, $fail failed ([dict size $known] known)"
    foreach u $unexpected { puts "  unexpected failure: $u" }
    foreach f $fixed { puts "  now passing (remove from known-failures): $f" }
    return [expr {[llength $unexpected] == 0 && [llength $fixed] == 0}]
}

if {[info exists argv0] && [file normalize $argv0] eq [file normalize [info script]]} {
    exit [expr {[::compliance::run $argv] ? 0 : 1}]
}
