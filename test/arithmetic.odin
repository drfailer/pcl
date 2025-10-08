package artihmetic

import "../src/parodin"
import "core:fmt"

exec_ints :: proc(content: string, user_data: rawptr) -> rawptr {
    fmt.printfln("int: {}", content)
    return user_data
}

exec_floats :: proc(content: string, user_data: rawptr) -> rawptr {
    fmt.printfln("float: {}", content)
    return user_data
}

exec_add :: proc(content: string, user_data: rawptr) -> rawptr {
    fmt.printfln("add: {}", content)
    return user_data
}

exec_sub :: proc(content: string, user_data: rawptr) -> rawptr {
    fmt.printfln("sub: {}", content)
    return user_data
}

exec_number :: proc(content: string, user_data: rawptr) -> rawptr {
    fmt.printfln("number: {}", content)
    return user_data
}


skip_spaces :: proc(char: rune) -> bool {
    return u8(char) == ' '
}

arithmetic_grammar :: proc() -> ^parodin.Parser {
    using parodin

    // left recursive grammar
    digits := plus(range('0', '9'), name = "digits")
    ints := single(digits, name = "ints", exec = exec_ints)
    floats := seq(digits, lit_c('.'), opt(digits), name = "floats", exec = exec_floats)
    number := or(floats, ints, name = "number", exec = exec_number)
    add := declare(name = "add", exec = exec_add)
    sub := declare(name = "sub", exec = exec_sub)
    expr := or(add, sub, number, skip = skip_spaces)
    define(add, lrec(expr, lit_c('+'), number, skip = skip_spaces))
    define(sub, lrec(expr, lit_c('-'), number, skip = skip_spaces))

    // non left recursive grammar
    // digits := plus(range('0', '9'), name = "digits", exec = exec_ints)
    // floats := seq(digits, lit_c('.'), opt(digits), name = "floats", exec = exec_floats)
    // number := or(digits, floats, name = "number", exec = exec_number)
    // expr := seq(number, star(seq(or(lit_c('+'), lit_c('-'), skip = skip_spaces), number, skip = skip_spaces), skip = skip_spaces), skip = skip_spaces)
    return expr
}

main :: proc() {
    arithmetic_parser := arithmetic_grammar()
    defer parodin.parser_destroy(arithmetic_parser)

    state, ok := parodin.parse_string(arithmetic_parser, "12345")
    fmt.printfln("{}, {}", state, ok);
    state, ok = parodin.parse_string(arithmetic_parser, "1 + 2")
    fmt.printfln("{}, {}", state, ok);
    state, ok = parodin.parse_string(arithmetic_parser, "1 - 2 + 3")
    fmt.printfln("{}, {}", state, ok);
}
