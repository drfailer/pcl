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
    fmt.println("create int!")
    return node
}

main :: proc() {
    parse_int := parodin.star(parodin.range('0', '9'), exec = create_int)

    state, ok := parodin.parse_string(parse_int, "12345")
    defer free(state.user_data)
    fmt.printfln("ok = {}\n", ok)
    fmt.printfln("state = {}\n", state)
    fmt.printfln("user_data = {}\n", (cast(^Node)state.user_data)^)
}
