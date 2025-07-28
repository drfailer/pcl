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

create_int :: proc(content: string, user_data: rawptr) -> rawptr {
    node := new(Node)
    node.name = "int"
    node.data = strconv.atoi(content)
    return node
}

create_float :: proc(content: string, user_data: rawptr) -> rawptr {
    node := new(Node)
    node.name = "float"
    node.data = strconv.atof(content)
    return node
}

parse_float :: proc() -> parodin.Parser {
    using parodin
    parse_number := star(range('0', '9'))
    parse_dot := lit_c('.')
    return seq(parse_number, parse_dot, parse_number, exec = create_float)
}

// TODO: add a name to the parser rules + use #caller_location.procedure as a
//       default value. -> we could have a rule struct that holds a parser and
//       the name of the rule
// TODO: print the parser.

main :: proc() {
    parser := parse_float()

    state, ok := parodin.parse_string(parser, "12345.4638")
    defer free(state.user_data)
    fmt.printfln("ok = {}\n", ok)
    fmt.printfln("state = {}\n", state)
    fmt.printfln("user_data = {}\n", (cast(^Node)state.user_data)^)
}
