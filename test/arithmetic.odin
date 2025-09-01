package artihmetic

import "../src/parodin"
import "core:fmt"

skip_spaces :: proc(char: rune) -> bool {
    return u8(char) == ' '
}

arithmetic_grammar :: proc() -> ^parodin.Parser {
    using parodin

    digits := plus(range('0', '9'))
    floats := seq(digits, lit_c('.'), opt(digits))
    number := or(digits, floats)
    add := declare()
    sub := declare()
    expr := or(add, sub, number, skip = skip_spaces)
    // define(add, lrec(expr, lit_c('+'), number, skip = skip_spaces))
    // define(sub, lrec(expr, lit_c('-'), number, skip = skip_spaces))
    define(add, seq(number, lit_c('+'), expr, skip = skip_spaces))
    define(sub, seq(number, lit_c('-'), expr, skip = skip_spaces))

    return expr;
}

main :: proc() {
    arithmetic_parser := arithmetic_grammar()
    defer parodin.parser_destroy(arithmetic_parser)

    state, ok := parodin.parse_string(arithmetic_parser, "12345")
    fmt.printfln("{}, {}", state, ok);
    state, ok = parodin.parse_string(arithmetic_parser, "1 - 2 + 3")
    fmt.printfln("{}, {}", state, ok);
}
