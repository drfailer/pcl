package main

import "core:fmt"
import "core:strconv"
import "parodin"

NodeData :: union {
    int,
    f64,
    string,
}

Node :: struct {
    name: string,
    data: NodeData,
    childs: [dynamic]Node,
}

parse_digits :: proc() -> parodin.Parser {
    fmt.println("parse digits")
    using parodin
    return plus(range('0', '9'))
}

create_int :: proc(content: string, user_data: rawptr) -> rawptr {
    fmt.println("create int")
    node := new(Node)
    node.name = "int"
    node.data = strconv.atoi(content)
    return node
}

parse_int :: proc() -> parodin.Parser {
    fmt.println("parse int")
    using parodin
    return single(parse_digits(), exec = create_int)
}

create_float :: proc(content: string, user_data: rawptr) -> rawptr {
    fmt.println("create float")
    node := new(Node)
    node.name = "float"
    node.data = strconv.atof(content)
    return node
}

parse_float :: proc() -> parodin.Parser {
    fmt.println("parse float")
    using parodin
    return seq(parse_digits(), lit_c('.'), parse_digits(), exec = create_float)
}

parse_number :: proc() -> parodin.Parser {
    fmt.println("parse number")
    using parodin
    return or(parse_float(), parse_int())
}

// TODO: add a name to the parser rules + use #caller_location.procedure as a
//       default value. -> we could have a rule struct that holds a parser and
//       the name of the rule
// TODO: print the parser.

test_parser :: proc(name: string, parser: parodin.Parser, str: string,) {
    state, ok := parodin.parse_string(parser, str)
    defer free(state.user_data)

    fmt.printf("{} parser result for input \"{}\":\n", name, str)
    fmt.printf("  ok = {}\n", ok)
    fmt.printf("  state = {}\n", state)
    fmt.printf("  user_data = {}\n", (cast(^Node)state.user_data)^)
}

main :: proc() {
    float_parser := parse_float()
    int_parser := parse_int()
    number_parser := parse_number()

    test_parser("int", int_parser, "12345")
    test_parser("int", int_parser, "12345.4638")
    test_parser("float", float_parser, "12345.4638")
    test_parser("float", float_parser, "12345")
    test_parser("number", number_parser, "12345")
    test_parser("number", number_parser, "12345.4638")
}
