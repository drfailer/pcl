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
    lhs: ^Node,
    rhs: ^Node,
    kind: Operator,
}

Parent :: struct {
    expr: ^Node,
}

FunctionId :: enum {
    Sin,
    Cos,
    Tan,
}

Function :: struct {
    id: FunctionId,
    expr: ^Node,
}

Node :: union {
    Value,
    Operation,
    Parent,
    Function,
}

ExecData :: struct {
    nodes: [dynamic]Node,
    count1: int,
    count2: int,
}

tree_print_indent :: proc(lvl: int, last_line := false) {
    for i in 0..<lvl {
        fmt.print("|  ")
    }
    if last_line do fmt.print("+---\n")
}

tree_print :: proc(node: ^Node, lvl := 0) {
    if node == nil {
        return
    }

    tree_print_indent(lvl)
    switch n in node^ {
    case Value:
        switch v in n {
        case i32: fmt.printfln("value: {}", v)
        case f32: fmt.printfln("value: {}", v)
        }
    case Operation:
        fmt.printfln("operator({})", n.kind)
        tree_print(n.lhs, lvl + 1)
        tree_print(n.rhs, lvl + 1)
        tree_print_indent(lvl, true)
    case Parent:
        fmt.println("parent:")
        tree_print(n.expr, lvl + 1)
        tree_print_indent(lvl, true)
    case Function:
        fmt.printfln("function({}):", n.id)
        tree_print(n.expr, lvl + 1)
        tree_print_indent(lvl, true)
    }
}

// TODO: create a proper ast and proper tests

exec_value :: proc($type: typeid) -> parodin.ExecProc {
    return  proc(content: []parodin.ParseResult, exec_data: rawptr) -> parodin.ParseResult {
        node := new(Node)
        node^ = cast(Value)(cast(type)strconv.atof(content[0].(string)))
        return cast(rawptr)node
    }
}

exec_operator :: proc($op: Operator) -> parodin.ExecProc {
    return proc(content: []parodin.ParseResult, exec_data: rawptr) -> parodin.ParseResult {
        node := new(Node)
        node^ = Operation{
            kind = op,
            lhs = cast(^Node)content[0].(rawptr),
            rhs = cast(^Node)content[1].(rawptr),
        }
        return cast(rawptr)node
    }
}

exec_function :: proc($id: FunctionId) -> parodin.ExecProc {
    return proc(content: []parodin.ParseResult, exec_data: rawptr) -> parodin.ParseResult {
        node := new(Node)
        node^ = Function{
            id = id,
            expr = cast(^Node)content[0].(rawptr),
        }
        return cast(rawptr)node
    }
}

exec_parent :: proc(content: []parodin.ParseResult, exec_data: rawptr) -> parodin.ParseResult {
    node := new(Node)
    node^ = Parent{
        expr = cast(^Node)content[0].(rawptr),
    }
    return cast(rawptr)node
}

skip_spaces :: proc(char: rune) -> bool {
    return u8(char) == ' ' || u8(char) == '\n'
}

// <expr> := <expr> "+" <term> | <term>
//
// <expr> := <term> <expr'>
// <expr'> := "+" <term> <expr'> | empty
//
// <term> := <factor> <term'>
// <term'> := "*" <factor> <term'> | emtpy
//
// <factor> := <number> | <parent>
arithmetic_grammar :: proc() -> ^parodin.Parser {
    using parodin

    parodin.SKIP = skip_spaces

    expr := declare(name = "expr")

    digits := plus(range('0', '9'), name = "digits")

    ints := combine(digits, name = "ints", exec = exec_value(i32))
    floats := combine(seq(digits, lit('.'), opt(digits)), name = "floats", exec = exec_value(f32))

    parent := seq(lit('('), rec(expr), lit(')'), name = "parent", exec = exec_parent)
    sin := seq(lit("sin"), parent, exec = exec_function(.Sin))
    cos := seq(lit("cos"), parent, exec = exec_function(.Cos))
    tan := seq(lit("tan"), parent, exec = exec_function(.Tan))
    functions := or(cos, sin, tan)
    factor := or(floats, ints, parent, functions, name = "factor")

    term := declare(name = "term")
    mul := lrec(term, lit('*'), factor, exec = exec_operator(.Mul))
    div := lrec(term, lit('/'), factor, exec = exec_operator(.Div))
    define(term, or(mul, div, factor))

    add := lrec(expr, lit('+'), term, exec = exec_operator(.Add))
    sub := lrec(expr, lit('-'), term, exec = exec_operator(.Sub))
    define(expr, or(add, sub, term))
    return expr
}

print_tree_of_expression :: proc(str: string) {
    arithmetic_parser := arithmetic_grammar()
    defer parodin.parser_destroy(arithmetic_parser)

    state, res, ok := parodin.parse_string(arithmetic_parser, str)
    if !ok {
        fmt.printfln("parsing the expression `{}` failed.", str)
        return
    }
    fmt.printfln("tree of `{}`:", str)
    tree_print(cast(^Node)res.(rawptr))
}

main :: proc() {
    print_tree_of_expression("123.3")
    // print_tree_of_expression("234 + 356 - 123")
    // print_tree_of_expression("1 - (2 + 3)")
    // print_tree_of_expression("(1 - 2) - 3*3 + 4/2")
    // print_tree_of_expression("(1 - (2 + 3*12.4)) - 3*3 + 4/2")
    // print_tree_of_expression("(1 - (2 + 3*12.4)) - 3*3 - (3*4) + 4/2 + (2 + 2)")
    print_tree_of_expression("sin(1 - (2 + 3*12.4)) - 3*3 - cos(3*4) + 4/2 + (2 + 2)")
}
