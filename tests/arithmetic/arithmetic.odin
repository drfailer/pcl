#+feature using-stmt
package artihmetic

import "pcl:pcl"
import "core:strconv"
import "core:fmt"
import "core:testing"
import "core:math"
import "core:mem"
import "core:log"

DEBUG :: false

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
    node_allocator: mem.Allocator,
}

node_print_indent :: proc(lvl: int, last_line := false) {
    for i in 0..<lvl {
        fmt.print("|  ")
    }
    if last_line do fmt.print("+---\n")
}

node_print :: proc(node: ^Node, lvl := 0) {
    if node == nil {
        return
    }

    node_print_indent(lvl)
    switch n in node^ {
    case Value:
        switch v in n {
        case i32: fmt.printfln("value: {}", v)
        case f32: fmt.printfln("value: {}", v)
        }
    case Operation:
        fmt.printfln("operator({})", n.kind)
        node_print(n.lhs, lvl + 1)
        node_print(n.rhs, lvl + 1)
        node_print_indent(lvl, true)
    case Parent:
        fmt.println("parent:")
        node_print(n.expr, lvl + 1)
        node_print_indent(lvl, true)
    case Function:
        fmt.printfln("function({}):", n.id)
        node_print(n.expr, lvl + 1)
        node_print_indent(lvl, true)
    }
}

node_eval :: proc(node: ^Node) -> f32 {
    if node == nil {
        return 0
    }

    switch n in node^ {
    case Value:
        switch v in n {
        case i32: return cast(f32)v
        case f32: return v
        }
    case Operation:
        l := node_eval(n.lhs)
        r := node_eval(n.rhs)
        switch n.kind {
        case .Add: return l + r
        case .Sub: return l - r
        case .Mul: return l * r
        case .Div: return l / r
        }
    case Parent:
        return node_eval(n.expr)
    case Function:
        e := node_eval(n.expr)
        switch n.id {
        case .Sin: return math.sin_f32(e)
        case .Cos: return math.cos_f32(e)
        case .Tan: return math.tan_f32(e)
        }
    }
    return 0
}

// exec functions //////////////////////////////////////////////////////////////

exec_value :: proc($type: typeid) -> pcl.ExecProc {
    return  proc(data: ^pcl.ExecData) -> pcl.ExecResult {
        when DEBUG {
            fmt.printfln("value: {}", data.content)
        }
        ed := pcl.user_data(data, ^ExecData)
        node := new(Node, ed.node_allocator)
        when type == i32 {
            value, ok := strconv.parse_int(pcl.content(data, 0))
            assert(ok)
            node^ = cast(Value)cast(i32)value
        } else {
            value, ok := strconv.parse_f32(pcl.content(data, 0))
            assert(ok)
            node^ = cast(Value)value
        }
        return pcl.result(data, node)
    }
}

exec_operator :: proc($op: Operator) -> pcl.ExecProc {
    return proc(data: ^pcl.ExecData) -> pcl.ExecResult {
        when DEBUG {
            fmt.printfln("operator: {}", data.content)
        }
        ed := pcl.user_data(data, ^ExecData)
        node := new(Node, ed.node_allocator)
        node^ = Operation{
            kind = op,
            lhs = pcl.content(data, ^Node, 0),
            rhs = pcl.content(data, ^Node, 2),
        }
        return pcl.result(data, node)
    }
}

exec_function :: proc($id: FunctionId) -> pcl.ExecProc {
    return proc(data: ^pcl.ExecData) -> pcl.ExecResult {
        when DEBUG {
            fmt.printfln("function: {}", data.content)
        }
        ed := pcl.user_data(data, ^ExecData)
        node := new(Node, ed.node_allocator)
        node^ = Function{
            id = id,
            expr = pcl.content(data, ^Node, 1)
        }
        return pcl.result(data, node)
    }
}

exec_parent :: proc(data: ^pcl.ExecData) -> pcl.ExecResult {
    when DEBUG {
        fmt.printfln("parent: {}", data.content)
    }
    ed := pcl.user_data(data, ^ExecData)
    node := new(Node, ed.node_allocator)
    node^ = Parent{
        expr = pcl.content(data, ^Node, 1),
    }
    return pcl.result(data, node)
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
arithmetic_grammar :: proc(allocator: pcl.ParserAllocator) -> ^pcl.Parser {
    using pcl
    context.allocator = allocator

    pcl.SKIP = skip_spaces

    expr := declare(name = "expr")

    digits := plus(range('0', '9'), name = "digits")

    ints := combine(digits, name = "ints", exec = exec_value(i32))
    floats := combine(digits, '.', opt(digits), name = "floats", exec = exec_value(f32))

    parent := seq('(', rec(expr), ')', name = "parent", exec = exec_parent)
    sin := seq("sin", parent, exec = exec_function(.Sin))
    cos := seq("cos", parent, exec = exec_function(.Cos))
    tan := seq("tan", parent, exec = exec_function(.Tan))
    functions := or(cos, sin, tan)
    factor := or(floats, ints, parent, functions, name = "factor")

    term := declare(name = "term")
    mul := lrec(term, '*', factor, exec = exec_operator(.Mul))
    div := lrec(term, '/', factor, exec = exec_operator(.Div))
    define(term, or(mul, div, factor))

    add := lrec(expr, '+', term, exec = exec_operator(.Add))
    sub := lrec(expr, '-', term, exec = exec_operator(.Sub))
    define(expr, or(add, sub, term))
    return expr
}

print_tree_of_expression :: proc(str: string) {
    parser_allocator := pcl.parser_allocator_create()
    arithmetic_parser := arithmetic_grammar(parser_allocator)
    defer pcl.parser_allocator_destroy(parser_allocator)

    node_arena_data: [8192]byte
    node_arena: mem.Arena
    mem.arena_init(&node_arena, node_arena_data[:])
    exec_data := ExecData{ mem.arena_allocator(&node_arena) }

    state, res, ok := pcl.parse_string(arithmetic_parser, str, &exec_data)
    if !ok {
        fmt.printfln("parsing the expression `{}` failed.", str)
        return
    }
    fmt.printfln("tree of `{}`:", str)
    node_print(cast(^Node)res.(rawptr))
}

@(test)
test_numbers :: proc(t: ^testing.T) {
    parser_allocator := pcl.parser_allocator_create()
    arithmetic_parser := arithmetic_grammar(parser_allocator)
    defer pcl.parser_allocator_destroy(parser_allocator)

    node_arena_data: [8192]byte
    node_arena: mem.Arena
    mem.arena_init(&node_arena, node_arena_data[:])
    exec_data := ExecData{ mem.arena_allocator(&node_arena) }

    state, res, ok := pcl.parse_string(arithmetic_parser, "123", &exec_data)
    testing.expect(t, ok == true)
    testing.expect(t, node_eval(cast(^Node)res.(rawptr)) == 123)

    mem.arena_free_all(&node_arena)

    state, res, ok = pcl.parse_string(arithmetic_parser, "3.14", &exec_data)
    testing.expect(t, ok == true)
    testing.expect(t, node_eval(cast(^Node)res.(rawptr)) == 3.14)
}

@(test)
test_operation :: proc(t: ^testing.T) {
    parser_allocator := pcl.parser_allocator_create()
    arithmetic_parser := arithmetic_grammar(parser_allocator)
    defer pcl.parser_allocator_destroy(parser_allocator)

    node_arena_data: [8192]byte
    node_arena: mem.Arena
    mem.arena_init(&node_arena, node_arena_data[:])
    exec_data := ExecData{ mem.arena_allocator(&node_arena) }

    state, res, ok := pcl.parse_string(arithmetic_parser, "1 - 2 + 3", &exec_data)
    testing.expect(t, ok == true)
    testing.expect(t, node_eval(cast(^Node)res.(rawptr)) == (1 - 2 + 3))

    mem.arena_free_all(&node_arena)

    state, res, ok = pcl.parse_string(arithmetic_parser, "(1 - 2) - 3*3 + 4/2", &exec_data)
    testing.expect(t, ok == true)
    testing.expect(t, node_eval(cast(^Node)res.(rawptr)) == ((1 - 2) - 3*3 + 4/2))
}

@(test)
test_functions :: proc(t: ^testing.T) {
    parser_allocator := pcl.parser_allocator_create()
    arithmetic_parser := arithmetic_grammar(parser_allocator)
    defer pcl.parser_allocator_destroy(parser_allocator)

    node_arena_data: [8192]byte
    node_arena: mem.Arena
    mem.arena_init(&node_arena, node_arena_data[:])
    exec_data := ExecData{ mem.arena_allocator(&node_arena) }

    state, res, ok := pcl.parse_string(arithmetic_parser, "sin(3.14)", &exec_data)
    testing.expect(t, ok == true)
    testing.expect(t, node_eval(cast(^Node)res.(rawptr)) == math.sin_f32(3.14))

    mem.arena_free_all(&node_arena)

    state, res, ok = pcl.parse_string(arithmetic_parser, "sin(1 - (2 + 3*12.4)) - 3*3 - cos(3*4) + 4/2 + (2 + 2)", &exec_data)
    testing.expect(t, ok == true)
    eval := node_eval(cast(^Node)res.(rawptr))
    expected := math.sin_f32(1 - (2 + 3*12.4)) - 3*3 - math.cos_f32(3*4) + 4/2 + (2 + 2)
    testing.expect(t, expected - 1e-5 <= eval && eval <= expected + 1e-5)
}

main :: proc() {
    print_tree_of_expression("123.3")
    print_tree_of_expression("234 + 356 - 123")
    print_tree_of_expression("1 - (2 + 3)")
    print_tree_of_expression("(1 - 2) - 3*3 + 4/2")
    print_tree_of_expression("(1 - (2 + 3*12.4)) - 3*3 + 4/2")
    print_tree_of_expression("(1 - (2 + 3*12.4)) - 3*3 - (3*4) + 4/2 + (2 + 2)")
    print_tree_of_expression("1 + sin(1 - (2 + 3*12.4)) - 3*3 - cos(3*4) + 4/2 + (2 + 2)")
}
