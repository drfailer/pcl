package artihmetic

import "../src/parodin"
import "core:strconv"
import "core:fmt"

Operator :: enum {
    Add,
    Sub,
    Mul,
    Div,
}

Value :: union {
    i32,
    f32,
}

Operation :: struct {
    lhs: Node,
    rhs: Node,
    kind: Operator,
}

Parent :: struct {
    content: Node,
}

Node :: union {
    ^Value,
    ^Operation,
    ^Parent,
}

ExecData :: struct {
    nodes: [dynamic]Node,
    count1: int,
    count2: int,
}

print_indent :: proc(lvl: int) {
    for i in 0..<lvl {
        fmt.print("  ")
    }
}

node_print :: proc(node: Node, lvl: int = 0) {
    switch n in node {
    case ^Value:
        print_indent(lvl)
        switch v in n {
        case i32: fmt.printfln("{}", v)
        case f32: fmt.printfln("{}", v)
        }
    case ^Operation:
        node_print(n.rhs, lvl + 1)
        print_indent(lvl)
        switch n.kind {
        case .Add: fmt.println("+")
        case .Sub: fmt.println("-")
        case .Mul: fmt.println("*")
        case .Div: fmt.println("/")
        }
        node_print(n.lhs, lvl + 1)
    case ^Parent:
        print_indent(lvl)
        fmt.println("(")
        node_print(n.content, lvl + 1)
        print_indent(lvl)
        fmt.println(")")
    }
}

// TODO: create a proper ast and proper tests

exec_ints :: proc(content: string, exec_data: rawptr) {
    fmt.printfln("value: {}", content)
    // ed := cast(^ExecData)exec_data
    // node := new(Value)
    // node^ = cast(i32)strconv.atoi(content)
    // append(&ed.nodes, node)
}

exec_floats :: proc(content: string, exec_data: rawptr) {
    fmt.printfln("value: {}", content)
    // ed := cast(^ExecData)exec_data
    // node := new(Value)
    // node^ = cast(f32)strconv.atof(content)
    // append(&ed.nodes, node)
}

exec_operator :: proc(content: string, exec_data: rawptr, op: Operator) {
    fmt.printfln("operator({}): {}", op, content)
    // ed := cast(^ExecData)exec_data
    // node := new(Operation)
    // node.kind = op
    // node.rhs = pop(&ed.nodes)
    // node.lhs = pop(&ed.nodes)
    // append(&ed.nodes, node)
}

exec_parent :: proc(content: string, exec_data: rawptr) {
    fmt.printfln("parent: {}", content)
    // ed := cast(^ExecData)exec_data
    // node := new(Parent)
    // node.content = pop(&ed.nodes)
    // append(&ed.nodes, node)
}

skip_spaces :: proc(char: rune) -> bool {
    return u8(char) == ' '
}

arithmetic_grammar :: proc() -> ^parodin.Parser {
    using parodin

    parodin.SKIP = skip_spaces

    expr := declare(name = "expr")

    digits := plus(range('0', '9'), name = "digits")

    ints := single(digits, name = "ints", exec = exec_ints)
    floats := seq(digits, lit_c('.'), opt(digits), name = "floats", exec = exec_floats)
    parent := seq(lit_c('('), expr, lit_c(')'), name = "parent", exec = exec_parent)
    factor := or(floats, ints, parent, name = "factor")

    term := declare(name = "term")
    mul := lrec(term, lit_c('*'), factor, exec = proc(content: string, exec_data: rawptr) { exec_operator(content, exec_data, .Mul) })
    div := lrec(term, lit_c('/'), factor, exec = proc(content: string, exec_data: rawptr) { exec_operator(content, exec_data, .Div) })
    define(term, or(mul, div, factor))

    add := lrec(expr, lit_c('+'), term, exec = proc(content: string, exec_data: rawptr) { exec_operator(content, exec_data, .Add) })
    sub := lrec(expr, lit_c('-'), term, exec = proc(content: string, exec_data: rawptr) { exec_operator(content, exec_data, .Sub) })
    define(expr, or(add, sub, term))

    return expr
}

// <expr> := <expr> "+" <term> | <term>
//
// <expr> := <term> <expr'>
// <expr'> := "+" <term> <expr'> | empty
//
// <term> = <factor> <term'>
// <term'> = "*" <factor> <term'> | emtpy
//
// <factor> = <number> | <parent>

main :: proc() {
    ed: ExecData
    arithmetic_parser := arithmetic_grammar()
    defer parodin.parser_destroy(arithmetic_parser)

    str := "(1 - 2) - 3*3 + 4/2"
    fmt.println(str)
    state, ok := parodin.parse_string(arithmetic_parser, str, &ed)
    fmt.printfln("{}, {}", state, ok);
    // node_print(ed.nodes[0])
}

// val: 2
// val: 4
// div: 4/2
// val: 3
// val: 3
// mul: 3*3
// val: 2
// val: 1
// sub: 1 - 2
// par: (1 - 2)
// add: (1 - 2) + 3*3
// sub: (1 - 2) + 3*3 - 4/2
