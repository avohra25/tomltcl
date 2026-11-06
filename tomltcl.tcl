# tomltcl - Pure Tcl 8.6 TOML 1.0.0 toolkit
# Copyright (c) 2026 Aryan Vohra
# SPDX-License-Identifier: MIT

package provide tomltcl 0.1.0

namespace eval ::tomltcl {
    namespace export parse decode encode stringify get exists to_json valid dump
    variable version 0.1.0
    variable _src ""
    variable _pos 0
    variable _len 0
    variable _line 1
    variable _col 1
    variable defined
}

proc ::tomltcl::_err {msg} {
    variable _line
    variable _col
    return -code error "TOML parse error at ${_line}:${_col}: $msg"
}

proc ::tomltcl::_err_at {line col msg} {
    return -code error "TOML parse error at ${line}:${col}: $msg"
}

proc ::tomltcl::_peek {{n 0}} {
    variable _src
    variable _pos
    variable _len
    set i [expr {$_pos + $n}]
    if {$i >= $_len} { return "" }
    return [string index $_src $i]
}

proc ::tomltcl::_advance {} {
    variable _src
    variable _pos
    variable _len
    variable _line
    variable _col
    if {$_pos >= $_len} { return "" }
    set c [string index $_src $_pos]
    incr _pos
    if {$c eq "\n"} {
        incr _line
        set _col 1
    } else {
        incr _col
    }
    return $c
}

proc ::tomltcl::_match {ch} {
    if {[::tomltcl::_peek] eq $ch} {
        ::tomltcl::_advance
        return 1
    }
    return 0
}

proc ::tomltcl::_eof {} {
    variable _pos
    variable _len
    expr {$_pos >= $_len}
}

proc ::tomltcl::_is_ws {c} {
    expr {$c eq " " || $c eq "\t"}
}

proc ::tomltcl::_is_nl {c} {
    expr {$c eq "\n" || $c eq "\r"}
}

proc ::tomltcl::_skip_ws_comments {} {
    while {1} {
        set c [::tomltcl::_peek]
        if {[::tomltcl::_is_ws $c]} {
            ::tomltcl::_advance
            continue
        }
        if {$c eq "#"} {
            while {![::tomltcl::_eof]} {
                set c [::tomltcl::_advance]
                if {$c eq "\n"} break
                if {$c eq "\r"} {
                    if {[::tomltcl::_peek] eq "\n"} { ::tomltcl::_advance }
                    break
                }
            }
            continue
        }
        break
    }
}

proc ::tomltcl::_skip_ws_inline {} {
    while {1} {
        set c [::tomltcl::_peek]
        if {[::tomltcl::_is_ws $c]} {
            ::tomltcl::_advance
            continue
        }
        if {$c eq "#"} {
            while {![::tomltcl::_eof]} {
                set c [::tomltcl::_peek]
                if {$c eq "\n" || $c eq "\r" || $c eq ""} break
                ::tomltcl::_advance
            }
            break
        }
        break
    }
}

proc ::tomltcl::_expect_nl_or_eof {} {
    ::tomltcl::_skip_ws_inline
    set c [::tomltcl::_peek]
    if {$c eq ""} return
    if {$c eq "\n"} { ::tomltcl::_advance; return }
    if {$c eq "\r"} {
        ::tomltcl::_advance
        if {[::tomltcl::_peek] eq "\n"} { ::tomltcl::_advance }
        return
    }
    set shown $c
    if {$c eq "\n"} { set shown "\\n" }
    if {$c eq "\r"} { set shown "\\r" }
    if {$c eq "\t"} { set shown "\\t" }
    ::tomltcl::_err "expected newline or end of file, got '$shown'"
}

proc ::tomltcl::_skip_nl {} {
    set c [::tomltcl::_peek]
    if {$c eq "\n"} { ::tomltcl::_advance; return 1 }
    if {$c eq "\r"} {
        ::tomltcl::_advance
        if {[::tomltcl::_peek] eq "\n"} { ::tomltcl::_advance }
        return 1
    }
    return 0
}

# Typed values: list of type data
proc ::tomltcl::tv {type data} { list $type $data }
proc ::tomltcl::tv_type {v} { lindex $v 0 }
proc ::tomltcl::tv_data {v} { lindex $v 1 }

proc ::tomltcl::unwrap {v} {
    set t [tv_type $v]
    set d [tv_data $v]
    switch -exact -- $t {
        string - integer - float - bool - datetime - datetime-local - date - time {
            return $d
        }
        array {
            set out {}
            foreach item $d { lappend out [unwrap $item] }
            return $out
        }
        table {
            set out [dict create]
            dict for {k vv} $d { dict set out $k [unwrap $vv] }
            return $out
        }
        default { return $d }
    }
}

proc ::tomltcl::_is_bare_key_char {c} {
    if {$c eq ""} { return 0 }
    regexp {^[A-Za-z0-9_\-]$} $c
}

proc ::tomltcl::_parse_bare_key {} {
    variable _line
    variable _col
    set start_line $_line
    set start_col $_col
    set buf ""
    while {[::tomltcl::_is_bare_key_char [::tomltcl::_peek]]} {
        append buf [::tomltcl::_advance]
    }
    if {$buf eq ""} {
        ::tomltcl::_err_at $start_line $start_col "expected bare key"
    }
    return $buf
}

proc ::tomltcl::_parse_key_part {} {
    set c [::tomltcl::_peek]
    if {$c eq "\""} {
        return [::tomltcl::_parse_basic_string 0]
    }
    if {$c eq "'"} {
        return [::tomltcl::_parse_literal_string 0]
    }
    ::tomltcl::_parse_bare_key
}

proc ::tomltcl::_parse_key {} {
    set parts [list [::tomltcl::_parse_key_part]]
    while {1} {
        ::tomltcl::_skip_ws_inline
        if {[::tomltcl::_peek] eq "."} {
            ::tomltcl::_advance
            ::tomltcl::_skip_ws_inline
            lappend parts [::tomltcl::_parse_key_part]
        } else break
    }
    return $parts
}

proc ::tomltcl::_hex_digit {c} {
    regexp {^[0-9A-Fa-f]$} $c
}

proc ::tomltcl::_parse_unicode_escape {n} {
    set hex ""
    for {set i 0} {$i < $n} {incr i} {
        set c [::tomltcl::_peek]
        if {![::tomltcl::_hex_digit $c]} {
            ::tomltcl::_err "invalid unicode escape"
        }
        append hex [::tomltcl::_advance]
    }
    set cp [expr {"0x$hex"}]
    if {$cp >= 0xD800 && $cp <= 0xDFFF} {
        ::tomltcl::_err "unicode escape is a surrogate"
    }
    if {$cp > 0x10FFFF} {
        ::tomltcl::_err "unicode escape out of range"
    }
    format %c $cp
}

proc ::tomltcl::_parse_escape {} {
    set c [::tomltcl::_advance]
    switch -exact -- $c {
        b { return "\b" }
        t { return "\t" }
        n { return "\n" }
        f { return "\f" }
        r { return "\r" }
        \" { return "\"" }
        \\ { return "\\" }
        u { return [::tomltcl::_parse_unicode_escape 4] }
        U { return [::tomltcl::_parse_unicode_escape 8] }
        default { ::tomltcl::_err "invalid escape \\$c" }
    }
}

proc ::tomltcl::_parse_basic_string {multiline} {
    if {$multiline} {
        ::tomltcl::_advance
        ::tomltcl::_advance
        ::tomltcl::_advance
        ::tomltcl::_skip_nl
    } else {
        ::tomltcl::_advance
    }
    set buf ""
    while {1} {
        if {[::tomltcl::_eof]} { ::tomltcl::_err "unterminated string" }
        set c [::tomltcl::_peek]
        if {$multiline} {
            if {$c eq "\"" && [::tomltcl::_peek 1] eq "\"" && [::tomltcl::_peek 2] eq "\""} {
                ::tomltcl::_advance
                ::tomltcl::_advance
                ::tomltcl::_advance
                set extra 0
                while {$extra < 2 && [::tomltcl::_peek] eq "\""} {
                    append buf "\""
                    ::tomltcl::_advance
                    incr extra
                }
                if {[::tomltcl::_peek] eq "\""} {
                    ::tomltcl::_err "too many quotes closing multiline string"
                }
                return $buf
            }
            if {$c eq "\\"} {
                ::tomltcl::_advance
                set n [::tomltcl::_peek]
                if {$n eq "\n" || $n eq "\r" || [::tomltcl::_is_ws $n]} {
                    while {[::tomltcl::_is_ws [::tomltcl::_peek]]} { ::tomltcl::_advance }
                    if {![::tomltcl::_skip_nl]} {
                        ::tomltcl::_err "invalid line-ending backslash"
                    }
                    while {[::tomltcl::_is_ws [::tomltcl::_peek]]} { ::tomltcl::_advance }
                    continue
                }
                append buf [::tomltcl::_parse_escape]
                continue
            }
            append buf [::tomltcl::_advance]
        } else {
            if {$c eq "\""} {
                ::tomltcl::_advance
                return $buf
            }
            if {$c eq "\n" || $c eq "\r"} {
                ::tomltcl::_err "newline in basic string"
            }
            if {$c eq "\\"} {
                ::tomltcl::_advance
                append buf [::tomltcl::_parse_escape]
                continue
            }
            set o [scan $c %c]
            if {$o < 0x20 && $c ne "\t"} {
                ::tomltcl::_err "invalid control character in string"
            }
            append buf [::tomltcl::_advance]
        }
    }
}

proc ::tomltcl::_parse_literal_string {multiline} {
    if {$multiline} {
        ::tomltcl::_advance
        ::tomltcl::_advance
        ::tomltcl::_advance
        ::tomltcl::_skip_nl
    } else {
        ::tomltcl::_advance
    }
    set buf ""
    while {1} {
        if {[::tomltcl::_eof]} { ::tomltcl::_err "unterminated literal string" }
        set c [::tomltcl::_peek]
        if {$multiline} {
            if {$c eq "'" && [::tomltcl::_peek 1] eq "'" && [::tomltcl::_peek 2] eq "'"} {
                ::tomltcl::_advance
                ::tomltcl::_advance
                ::tomltcl::_advance
                set extra 0
                while {$extra < 2 && [::tomltcl::_peek] eq "'"} {
                    append buf "'"
                    ::tomltcl::_advance
                    incr extra
                }
                if {[::tomltcl::_peek] eq "'"} {
                    ::tomltcl::_err "too many quotes closing multiline literal"
                }
                return $buf
            }
            append buf [::tomltcl::_advance]
        } else {
            if {$c eq "'"} {
                ::tomltcl::_advance
                return $buf
            }
            if {$c eq "\n" || $c eq "\r"} {
                ::tomltcl::_err "newline in literal string"
            }
            append buf [::tomltcl::_advance]
        }
    }
}

proc ::tomltcl::_parse_string {} {
    set c [::tomltcl::_peek]
    if {$c eq "\""} {
        if {[::tomltcl::_peek 1] eq "\"" && [::tomltcl::_peek 2] eq "\""} {
            return [tv string [::tomltcl::_parse_basic_string 1]]
        }
        return [tv string [::tomltcl::_parse_basic_string 0]]
    }
    if {$c eq "'"} {
        if {[::tomltcl::_peek 1] eq "'" && [::tomltcl::_peek 2] eq "'"} {
            return [tv string [::tomltcl::_parse_literal_string 1]]
        }
        return [tv string [::tomltcl::_parse_literal_string 0]]
    }
    ::tomltcl::_err "expected string"
}

proc ::tomltcl::_read_digits_underscores {allow_us} {
    set buf ""
    set last_us 0
    set any 0
    while {1} {
        set c [::tomltcl::_peek]
        if {[regexp {^[0-9]$} $c]} {
            append buf $c
            ::tomltcl::_advance
            set last_us 0
            set any 1
            continue
        }
        if {$allow_us && $c eq "_"} {
            if {!$any || $last_us} { ::tomltcl::_err "invalid underscore in number" }
            ::tomltcl::_advance
            set last_us 1
            continue
        }
        break
    }
    if {$last_us} { ::tomltcl::_err "trailing underscore in number" }
    if {!$any} { ::tomltcl::_err "expected digits" }
    return $buf
}

proc ::tomltcl::_read_hex_oct_bin {radix} {
    set buf ""
    set last_us 0
    set any 0
    if {$radix == 16} { set pat {^[0-9A-Fa-f]$} }
    if {$radix == 8} { set pat {^[0-7]$} }
    if {$radix == 2} { set pat {^[01]$} }
    while {1} {
        set c [::tomltcl::_peek]
        if {[regexp $pat $c]} {
            append buf $c
            ::tomltcl::_advance
            set last_us 0
            set any 1
            continue
        }
        if {$c eq "_"} {
            if {!$any || $last_us} { ::tomltcl::_err "invalid underscore in number" }
            ::tomltcl::_advance
            set last_us 1
            continue
        }
        break
    }
    if {$last_us} { ::tomltcl::_err "trailing underscore in number" }
    if {!$any} { ::tomltcl::_err "expected digits" }
    return $buf
}

proc ::tomltcl::_parse_local_time {} {
    set h [::tomltcl::_read_digits_underscores 0]
    if {[string length $h] != 2 || ![::tomltcl::_match :]} { ::tomltcl::_err "invalid time" }
    set m [::tomltcl::_read_digits_underscores 0]
    if {[string length $m] != 2 || ![::tomltcl::_match :]} { ::tomltcl::_err "invalid time" }
    set s [::tomltcl::_read_digits_underscores 0]
    if {[string length $s] != 2} { ::tomltcl::_err "invalid time" }
    set frac ""
    if {[::tomltcl::_peek] eq "."} {
        ::tomltcl::_advance
        set frac .
        append frac [::tomltcl::_read_digits_underscores 0]
    }
    set hi [scan $h %d]
    set mi [scan $m %d]
    set si [scan $s %d]
    if {$hi > 23 || $mi > 59 || $si > 60} { ::tomltcl::_err "time out of range" }
    tv time $h:$m:$s$frac
}

proc ::tomltcl::_parse_datetime {} {
    set Y [::tomltcl::_read_digits_underscores 0]
    if {[string length $Y] != 4 || ![::tomltcl::_match -]} { ::tomltcl::_err "invalid date" }
    set Mo [::tomltcl::_read_digits_underscores 0]
    if {[string length $Mo] != 2 || ![::tomltcl::_match -]} { ::tomltcl::_err "invalid date" }
    set D [::tomltcl::_read_digits_underscores 0]
    if {[string length $D] != 2} { ::tomltcl::_err "invalid date" }
    set Moi [scan $Mo %d]
    set Di [scan $D %d]
    if {$Moi < 1 || $Moi > 12 || $Di < 1 || $Di > 31} { ::tomltcl::_err "date out of range" }
    set date $Y-$Mo-$D

    set c [::tomltcl::_peek]
    if {$c ne "T" && $c ne "t" && $c ne " "} {
        return [tv date $date]
    }
    ::tomltcl::_advance
    set sep T

    set time_tv [::tomltcl::_parse_local_time]
    set time [tv_data $time_tv]

    set c [::tomltcl::_peek]
    if {$c eq "Z" || $c eq "z"} {
        ::tomltcl::_advance
        return [tv datetime $date${sep}$time\Z]
    }
    if {$c eq "+" || $c eq "-"} {
        set sign [::tomltcl::_advance]
        set oh [::tomltcl::_read_digits_underscores 0]
        if {[string length $oh] != 2 || ![::tomltcl::_match :]} { ::tomltcl::_err "invalid offset" }
        set om [::tomltcl::_read_digits_underscores 0]
        if {[string length $om] != 2} { ::tomltcl::_err "invalid offset" }
        set ohi [scan $oh %d]
        set omi [scan $om %d]
        if {$ohi > 23 || $omi > 59} { ::tomltcl::_err "offset out of range" }
        return [tv datetime $date${sep}$time$sign$oh:$om]
    }
    tv datetime-local $date${sep}$time
}

proc ::tomltcl::_parse_number {} {
    set sign ""
    set c [::tomltcl::_peek]
    if {$c eq "+" || $c eq "-"} {
        set sign [::tomltcl::_advance]
    }

    set c [::tomltcl::_peek]
    if {$c eq "i" && [::tomltcl::_peek 1] eq "n" && [::tomltcl::_peek 2] eq "f"} {
        ::tomltcl::_advance
        ::tomltcl::_advance
        ::tomltcl::_advance
        if {$sign eq "-"} { return [tv float -inf] }
        return [tv float inf]
    }
    if {$c eq "n" && [::tomltcl::_peek 1] eq "a" && [::tomltcl::_peek 2] eq "n"} {
        ::tomltcl::_advance
        ::tomltcl::_advance
        ::tomltcl::_advance
        return [tv float nan]
    }

    if {[::tomltcl::_peek] eq "0"} {
        set n1 [::tomltcl::_peek 1]
        if {$n1 eq "x" || $n1 eq "X"} {
            if {$sign ne ""} { ::tomltcl::_err "sign not allowed on hex" }
            ::tomltcl::_advance
            ::tomltcl::_advance
            set digits [::tomltcl::_read_hex_oct_bin 16]
            return [tv integer [expr {wide("0x$digits")}]]
        }
        if {$n1 eq "o" || $n1 eq "O"} {
            if {$sign ne ""} { ::tomltcl::_err "sign not allowed on octal" }
            ::tomltcl::_advance
            ::tomltcl::_advance
            set digits [::tomltcl::_read_hex_oct_bin 8]
            return [tv integer [expr {wide("0$digits")}]]
        }
        if {$n1 eq "b" || $n1 eq "B"} {
            if {$sign ne ""} { ::tomltcl::_err "sign not allowed on binary" }
            ::tomltcl::_advance
            ::tomltcl::_advance
            set digits [::tomltcl::_read_hex_oct_bin 2]
            set val 0
            foreach ch [split $digits ""] {
                set val [expr {wide($val) * 2 + ($ch eq "1")}]
            }
            return [tv integer $val]
        }
    }

    set intpart [::tomltcl::_read_digits_underscores 1]
    if {[string length $intpart] > 1 && [string index $intpart 0] eq "0"} {
        ::tomltcl::_err "leading zeros not allowed"
    }

    set is_float 0
    set frac ""
    set exp ""

    if {[::tomltcl::_peek] eq "."} {
        set is_float 1
        ::tomltcl::_advance
        set frac [::tomltcl::_read_digits_underscores 1]
    }

    set c [::tomltcl::_peek]
    if {$c eq "e" || $c eq "E"} {
        set is_float 1
        ::tomltcl::_advance
        set esign ""
        set c2 [::tomltcl::_peek]
        if {$c2 eq "+" || $c2 eq "-"} { set esign [::tomltcl::_advance] }
        set edigits [::tomltcl::_read_digits_underscores 1]
        set exp $esign$edigits
    }

    if {$is_float} {
        set s $sign$intpart
        if {$frac ne ""} { append s . $frac }
        if {$exp ne ""} { append s e $exp }
        return [tv float [expr {double($s)}]]
    }
    set s $sign$intpart
    if {[catch {expr {wide($s)}} val]} {
        set val [expr {$s}]
    }
    tv integer $val
}

proc ::tomltcl::_parse_number_or_datetime {} {
    set c [::tomltcl::_peek]
    if {[regexp {^[0-9]$} $c]} {
        set look ""
        for {set i 0} {$i < 30} {incr i} {
            set ch [::tomltcl::_peek $i]
            if {$ch eq ""} break
            append look $ch
            if {![regexp {^[0-9T:Z+\-. t]$} $ch]} break
        }
        if {[regexp {^[0-9]{4}-[0-9]{2}-[0-9]{2}} $look]} {
            return [::tomltcl::_parse_datetime]
        }
        if {[regexp {^[0-9]{2}:[0-9]{2}:[0-9]{2}} $look]} {
            return [::tomltcl::_parse_local_time]
        }
    }
    ::tomltcl::_parse_number
}

proc ::tomltcl::_parse_bool {} {
    set c [::tomltcl::_peek]
    if {$c eq "t" && [::tomltcl::_peek 1] eq "r" && [::tomltcl::_peek 2] eq "u" && [::tomltcl::_peek 3] eq "e"} {
        ::tomltcl::_advance
        ::tomltcl::_advance
        ::tomltcl::_advance
        ::tomltcl::_advance
        return [tv bool 1]
    }
    if {$c eq "f" && [::tomltcl::_peek 1] eq "a" && [::tomltcl::_peek 2] eq "l" && [::tomltcl::_peek 3] eq "s" && [::tomltcl::_peek 4] eq "e"} {
        ::tomltcl::_advance
        ::tomltcl::_advance
        ::tomltcl::_advance
        ::tomltcl::_advance
        ::tomltcl::_advance
        return [tv bool 0]
    }
    ::tomltcl::_err "expected boolean"
}

proc ::tomltcl::_parse_array {} {
    ::tomltcl::_advance
    set items {}
    ::tomltcl::_skip_ws_comments
    while {![::tomltcl::_eof]} {
        ::tomltcl::_skip_ws_comments
        while {[::tomltcl::_skip_nl]} { ::tomltcl::_skip_ws_comments }
        if {[::tomltcl::_peek] eq {]}} {
            ::tomltcl::_advance
            return [tv array $items]
        }
        lappend items [::tomltcl::_parse_value]
        ::tomltcl::_skip_ws_comments
        while {[::tomltcl::_skip_nl]} { ::tomltcl::_skip_ws_comments }
        if {[::tomltcl::_peek] eq ","} {
            ::tomltcl::_advance
            ::tomltcl::_skip_ws_comments
            while {[::tomltcl::_skip_nl]} { ::tomltcl::_skip_ws_comments }
            continue
        }
        if {[::tomltcl::_peek] eq {]}} {
            ::tomltcl::_advance
            return [tv array $items]
        }
        ::tomltcl::_err "expected comma or closing bracket in array"
    }
    ::tomltcl::_err "unterminated array"
}

proc ::tomltcl::_inline_set {d path remaining val} {
    set seg [lindex $remaining 0]
    set rest [lrange $remaining 1 end]
    if {[llength $rest] == 0} {
        if {[dict exists $d $seg]} {
            ::tomltcl::_err "duplicate key '[join [concat $path [list $seg]] .]'"
        }
        dict set d $seg $val
        return $d
    }
    if {[dict exists $d $seg]} {
        set ex [dict get $d $seg]
        if {[tv_type $ex] ne "table"} {
            ::tomltcl::_err "cannot extend non-table"
        }
        set sub [tv_data $ex]
        set newsub [::tomltcl::_inline_set $sub [concat $path [list $seg]] $rest $val]
        dict set d $seg [tv table $newsub]
        return $d
    }
    set newsub [::tomltcl::_inline_set [dict create] [concat $path [list $seg]] $rest $val]
    dict set d $seg [tv table $newsub]
    return $d
}

proc ::tomltcl::_parse_inline_table {} {
    ::tomltcl::_advance
    set table [dict create]
    set defined [dict create]
    ::tomltcl::_skip_ws_inline
    if {[::tomltcl::_peek] eq "\}"} {
        ::tomltcl::_advance
        return [tv table $table]
    }
    while {1} {
        ::tomltcl::_skip_ws_inline
        set keyparts [::tomltcl::_parse_key]
        ::tomltcl::_skip_ws_inline
        if {![::tomltcl::_match =]} { ::tomltcl::_err "expected '=' in inline table" }
        ::tomltcl::_skip_ws_inline
        set val [::tomltcl::_parse_value]
        set pk [join $keyparts \0]
        if {[dict exists $defined $pk]} {
            ::tomltcl::_err "duplicate key '[join $keyparts .]'"
        }
        set table [::tomltcl::_inline_set $table {} $keyparts $val]
        dict set defined $pk value
        ::tomltcl::_skip_ws_inline
        if {[::tomltcl::_peek] eq ","} {
            ::tomltcl::_advance
            ::tomltcl::_skip_ws_inline
            if {[::tomltcl::_peek] eq "\}"} {
                ::tomltcl::_err "trailing comma in inline table"
            }
            continue
        }
        if {[::tomltcl::_peek] eq "\}"} {
            ::tomltcl::_advance
            return [tv table $table]
        }
        ::tomltcl::_err "expected comma or closing brace in inline table"
    }
}

proc ::tomltcl::_parse_value {} {
    set c [::tomltcl::_peek]
    if {$c eq "\"" || $c eq "'"} { return [::tomltcl::_parse_string] }
    if {$c eq {[}} { return [::tomltcl::_parse_array] }
    if {$c eq "\{"} { return [::tomltcl::_parse_inline_table] }
    if {$c eq "t" || $c eq "f"} { return [::tomltcl::_parse_bool] }
    if {$c eq "+" || $c eq "-" || [regexp {^[0-9]$} $c] || $c eq "i" || $c eq "n"} {
        return [::tomltcl::_parse_number_or_datetime]
    }
    ::tomltcl::_err "unexpected character '$c' in value"
}

proc ::tomltcl::_path_key {parts} {
    join $parts \0
}

proc ::tomltcl::_mutate {node path remaining mode value} {
    variable defined
    set nrem [llength $remaining]
    if {$nrem == 0} {
        return $value
    }
    set seg [lindex $remaining 0]
    set rest [lrange $remaining 1 end]
    set is_last [expr {[llength $rest] == 0}]
    set prefix [concat $path [list $seg]]
    set pk [::tomltcl::_path_key $prefix]

    if {[tv_type $node] ne "table"} {
        ::tomltcl::_err "cannot assign into non-table at '[join $path .]'"
    }
    set d [tv_data $node]

    if {$is_last} {
        if {$mode eq "value"} {
            if {[dict exists $d $seg]} {
                ::tomltcl::_err "duplicate key '[join $prefix .]'"
            }
            if {[dict exists $defined $pk] && [dict get $defined $pk] ne "implicit"} {
                ::tomltcl::_err "duplicate key '[join $prefix .]'"
            }
            dict set d $seg $value
            dict set defined $pk value
            return [tv table $d]
        }
        if {$mode eq "table"} {
            if {[dict exists $defined $pk]} {
                set k [dict get $defined $pk]
                if {$k eq "table"} {
                    ::tomltcl::_err "redefining table '[join $prefix .]'"
                }
                if {$k eq "value" || $k eq "aot"} {
                    ::tomltcl::_err "conflict at '[join $prefix .]'"
                }
                if {![dict exists $d $seg] || [tv_type [dict get $d $seg]] ne "table"} {
                    ::tomltcl::_err "conflict at '[join $prefix .]'"
                }
                dict set defined $pk table
                return [tv table $d]
            }
            if {[dict exists $d $seg]} {
                ::tomltcl::_err "duplicate key '[join $prefix .]'"
            }
            dict set d $seg [tv table [dict create]]
            dict set defined $pk table
            return [tv table $d]
        }
        if {$mode eq "aot-append"} {
            if {[dict exists $d $seg]} {
                set ex [dict get $d $seg]
                if {[tv_type $ex] ne "array"} {
                    ::tomltcl::_err "cannot use array-of-tables on non-array '[join $prefix .]'"
                }
                if {[dict exists $defined $pk] && [dict get $defined $pk] ne "aot"} {
                    ::tomltcl::_err "conflict at '[join $prefix .]'"
                }
                set arr [tv_data $ex]
                lappend arr [tv table [dict create]]
                dict set d $seg [tv array $arr]
                dict set defined $pk aot
                # Keys under prior AOT elements may be reused in the new element
                set prefix_key "$pk\0"
                foreach k [dict keys $defined] {
                    if {[string first $prefix_key $k] == 0} {
                        dict unset defined $k
                    }
                }
                return [tv table $d]
            }
            dict set d $seg [tv array [list [tv table [dict create]]]]
            dict set defined $pk aot
            return [tv table $d]
        }
    }

    if {[dict exists $d $seg]} {
        set child [dict get $d $seg]
        set ct [tv_type $child]
        if {$ct eq "table"} {
            if {![dict exists $defined $pk]} {
                dict set defined $pk implicit
            }
            set newchild [::tomltcl::_mutate $child $prefix $rest $mode $value]
            dict set d $seg $newchild
            return [tv table $d]
        }
        if {$ct eq "array"} {
            if {[dict exists $defined $pk] && [dict get $defined $pk] eq "value"} {
                ::tomltcl::_err "cannot descend into array value '[join $prefix .]'"
            }
            set arr [tv_data $child]
            if {[llength $arr] == 0} {
                ::tomltcl::_err "empty array-of-tables '[join $prefix .]'"
            }
            set last [lindex $arr end]
            if {[tv_type $last] ne "table"} {
                ::tomltcl::_err "array '[join $prefix .]' is not array-of-tables"
            }
            set newlast [::tomltcl::_mutate $last $prefix $rest $mode $value]
            set arr [lreplace $arr end end $newlast]
            dict set d $seg [tv array $arr]
            return [tv table $d]
        }
        ::tomltcl::_err "cannot descend into '[join $prefix .]'"
    } else {
        dict set defined $pk implicit
        set child [tv table [dict create]]
        set newchild [::tomltcl::_mutate $child $prefix $rest $mode $value]
        dict set d $seg $newchild
        return [tv table $d]
    }
}

proc ::tomltcl::_doc_set {docVar parts value {mode value}} {
    upvar 1 $docVar doc
    set doc [::tomltcl::_mutate $doc {} $parts $mode $value]
}

proc ::tomltcl::_parse_document {} {
    variable defined
    set defined [dict create]
    set doc [tv table [dict create]]
    set current_path {}

    ::tomltcl::_skip_ws_comments
    while {[::tomltcl::_skip_nl]} { ::tomltcl::_skip_ws_comments }

    while {![::tomltcl::_eof]} {
        ::tomltcl::_skip_ws_comments
        while {[::tomltcl::_skip_nl]} { ::tomltcl::_skip_ws_comments }
        if {[::tomltcl::_eof]} break

        set c [::tomltcl::_peek]
        if {$c eq {[}} {
            if {[::tomltcl::_peek 1] eq {[}} {
                ::tomltcl::_advance
                ::tomltcl::_advance
                ::tomltcl::_skip_ws_inline
                set parts [::tomltcl::_parse_key]
                ::tomltcl::_skip_ws_inline
                if {[::tomltcl::_peek] ne {]} || [::tomltcl::_peek 1] ne {]}} {
                    ::tomltcl::_err "expected ]]"
                }
                ::tomltcl::_advance
                ::tomltcl::_advance
                ::tomltcl::_doc_set doc $parts {} aot-append
                set current_path $parts
                ::tomltcl::_expect_nl_or_eof
            } else {
                ::tomltcl::_advance
                ::tomltcl::_skip_ws_inline
                set parts [::tomltcl::_parse_key]
                ::tomltcl::_skip_ws_inline
                if {![::tomltcl::_match {]}]} { ::tomltcl::_err "expected ]" }
                ::tomltcl::_doc_set doc $parts {} table
                set current_path $parts
                ::tomltcl::_expect_nl_or_eof
            }
        } elseif {[::tomltcl::_is_bare_key_char $c] || $c eq "\"" || $c eq "'"} {
            set parts [::tomltcl::_parse_key]
            ::tomltcl::_skip_ws_inline
            if {![::tomltcl::_match =]} { ::tomltcl::_err "expected '='" }
            ::tomltcl::_skip_ws_inline
            set c2 [::tomltcl::_peek]
            if {$c2 eq "\n" || $c2 eq "\r"} { ::tomltcl::_err "newline after '='" }
            set val [::tomltcl::_parse_value]
            set full [concat $current_path $parts]
            ::tomltcl::_doc_set doc $full $val value
            ::tomltcl::_expect_nl_or_eof
        } else {
            ::tomltcl::_err "unexpected character '$c'"
        }
        ::tomltcl::_skip_ws_comments
        while {[::tomltcl::_skip_nl]} { ::tomltcl::_skip_ws_comments }
    }
    return $doc
}

proc ::tomltcl::parse {text} {
    variable _src
    variable _pos
    variable _len
    variable _line
    variable _col
    set _src $text
    set _pos 0
    set _len [string length $text]
    set _line 1
    set _col 1
    ::tomltcl::_parse_document
}

proc ::tomltcl::decode {text} { parse $text }

proc ::tomltcl::valid {text} {
    expr {![catch {parse $text}]}
}

proc ::tomltcl::dump {value {indent 0}} {
    set pad [string repeat "  " $indent]
    set t [tv_type $value]
    set d [tv_data $value]
    switch -exact -- $t {
        string { return "string([list $d])" }
        integer { return "integer($d)" }
        float {
            return "float($d)"
        }
        bool {
            if {$d} { return "bool(true)" }
            return "bool(false)"
        }
        datetime - datetime-local - date - time { return [format {%s(%s)} $t $d] }
        array {
            if {[llength $d] == 0} { return "array\[\]" }
            set lines [list "array\["]
            foreach item $d {
                lappend lines "$pad  [dump $item [expr {$indent+1}]]"
            }
            lappend lines "$pad\]"
            return [join $lines \n]
        }
        table {
            if {[dict size $d] == 0} { return "table\{\}" }
            set lines [list "table\{"]
            foreach k [lsort [dict keys $d]] {
                set v [dict get $d $k]
                lappend lines "$pad  [list $k] = [dump $v [expr {$indent+1}]]"
            }
            lappend lines "$pad\}"
            return [join $lines \n]
        }
        default { return "unknown($value)" }
    }
}


# ---------------------------------------------------------------------------
# Encoder
# ---------------------------------------------------------------------------
proc ::tomltcl::_is_bare_key {k} {
    expr {[regexp {^[A-Za-z0-9_\-]+$} $k]}
}

proc ::tomltcl::_encode_key {k} {
    if {[::tomltcl::_is_bare_key $k]} { return $k }
    return [::tomltcl::_encode_basic_string $k]
}

proc ::tomltcl::_encode_basic_string {s} {
    set out "\""
    foreach ch [split $s {}] {
        set o [scan $ch %c]
        switch -exact -- $ch {
            \" { append out "\\\"" }
            \\ { append out "\\\\" }
            \b { append out "\\b" }
            \t { append out "\\t" }
            \n { append out "\\n" }
            \f { append out "\\f" }
            \r { append out "\\r" }
            default {
                if {$o < 0x20} {
                    append out [format "\\u%04x" $o]
                } else {
                    append out $ch
                }
            }
        }
    }
    append out "\""
    return $out
}

proc ::tomltcl::_prefer_multiline {s} {
    expr {[string first \n $s] >= 0 && [string length $s] > 20}
}

proc ::tomltcl::_encode_ml_basic {s} {
    # Use multiline basic string; escape only what we must
    set body $s
    # Escape sequences that would break out
    set body [string map {"\\" "\\\\"} $body]
    # Avoid """ in content by escaping quotes near triples - simple: escape all "
    set body [string map {"\"" "\\\""} $body]
    return "\"\"\"\n$body\"\"\""
}

proc ::tomltcl::_encode_string {s args} {
    set prefer_ml 0
    if {[lsearch -exact $args -multiline] >= 0} { set prefer_ml 1 }
    if {$prefer_ml || [::tomltcl::_prefer_multiline $s]} {
        return [::tomltcl::_encode_ml_basic $s]
    }
    ::tomltcl::_encode_basic_string $s
}

proc ::tomltcl::_encode_float {d} {
    if {$d eq "nan" || $d eq "inf" || $d eq "-inf"} { return $d }
    # Ensure a decimal point for whole floats so they stay floats
    set s [expr {$d}]
    if {[regexp {^-?[0-9]+$} $s]} { append s .0 }
    return $s
}

proc ::tomltcl::_encode_value {v {inline 0}} {
    set t [tv_type $v]
    set d [tv_data $v]
    switch -exact -- $t {
        string {
            if {$inline} { return [::tomltcl::_encode_basic_string $d] }
            return [::tomltcl::_encode_string $d]
        }
        integer { return $d }
        float { return [::tomltcl::_encode_float $d] }
        bool { return [expr {$d ? "true" : "false"}] }
        datetime - datetime-local - date - time { return $d }
        array {
            if {[llength $d] == 0} { return "\[\]" }
            # Heuristic: use multiline if nested tables/arrays or long
            set parts {}
            set complex 0
            foreach item $d {
                set it [tv_type $item]
                if {$it eq "array" || $it eq "table"} { set complex 1 }
                lappend parts [::tomltcl::_encode_value $item 1]
            }
            if {$complex || [llength $d] > 4} {
                set lines "\["
                foreach p $parts {
                    append lines "\n  " $p ","
                }
                append lines "\n\]"
                return $lines
            }
            return "\[[join $parts {, }]\]"
        }
        table {
            # Inline table encoding
            if {[dict size $d] == 0} { return "\{\}" }
            set parts {}
            foreach k [lsort [dict keys $d]] {
                set vv [dict get $d $k]
                lappend parts "[::tomltcl::_encode_key $k] = [::tomltcl::_encode_value $vv 1]"
            }
            return "\{[join $parts {, }]\}"
        }
        default { return -code error "cannot encode type $t" }
    }
}

proc ::tomltcl::_table_is_aot_only {d} {
    # true if table has only array-of-tables children? not needed
    return 0
}

proc ::tomltcl::_encode_table_body {path d sorted linesVar aotVar} {
    upvar 1 $linesVar lines
    upvar 1 $aotVar aots
    # Emit simple key/values first, then nested tables, collect AOTs
    set keys [dict keys $d]
    if {$sorted} { set keys [lsort $keys] }

    set simple {}
    set subtabl {}
    set aotkeys {}
    foreach k $keys {
        set v [dict get $d $k]
        set t [tv_type $v]
        if {$t eq "table"} {
            lappend subtabl $k
        } elseif {$t eq "array"} {
            set arr [tv_data $v]
            set all_tables 1
            if {[llength $arr] == 0} { set all_tables 0 }
            foreach item $arr {
                if {[tv_type $item] ne "table"} { set all_tables 0; break }
            }
            if {$all_tables} {
                lappend aotkeys $k
            } else {
                lappend simple $k
            }
        } else {
            lappend simple $k
        }
    }

    foreach k $simple {
        set v [dict get $d $k]
        lappend lines "[::tomltcl::_encode_key $k] = [::tomltcl::_encode_value $v]"
    }
    foreach k $subtabl {
        set child [tv_data [dict get $d $k]]
        set subpath [concat $path [list $k]]
        set header [join [lmap p $subpath {::tomltcl::_encode_key $p}] .]
        lappend lines ""
        lappend lines "\[$header\]"
        ::tomltcl::_encode_table_body $subpath $child $sorted lines aots
    }
    foreach k $aotkeys {
        set arr [tv_data [dict get $d $k]]
        set subpath [concat $path [list $k]]
        set header [join [lmap p $subpath {::tomltcl::_encode_key $p}] .]
        foreach item $arr {
            lappend lines ""
            lappend lines "\[\[$header\]\]"
            ::tomltcl::_encode_table_body $subpath [tv_data $item] $sorted lines aots
        }
    }
}

proc ::tomltcl::encode {doc args} {
    set sorted 1
    set style dotted
    foreach {opt val} $args {
        switch -exact -- $opt {
            -sorted { set sorted [expr {!!$val}] }
            -sort { set sorted [expr {!!$val}] }
            -style { set style $val }
            default { return -code error "unknown encode option $opt" }
        }
    }
    if {[tv_type $doc] ne "table"} {
        return -code error "encode expects a root table value"
    }
    set d [tv_data $doc]
    set lines {}
    set aots {}
    ::tomltcl::_encode_table_body {} $d $sorted lines aots
    # Trim leading blank lines
    while {[llength $lines] && [lindex $lines 0] eq ""} {
        set lines [lrange $lines 1 end]
    }
    set out [join $lines \n]
    if {$out ne ""} { append out \n }
    return $out
}

proc ::tomltcl::stringify {doc args} {
    encode $doc {*}$args
}

proc ::tomltcl::get {doc path} {
    return -code error "tomltcl::get not implemented yet; see stage 3"
}
proc ::tomltcl::exists {doc path} {
    return -code error "tomltcl::exists not implemented yet; see stage 3"
}
proc ::tomltcl::to_json {doc} {
    return -code error "tomltcl::to_json not implemented yet; see stage 3"
}
