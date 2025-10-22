package json

import "pcl:pcl"
import "core:strconv"
import "core:fmt"
import "core:testing"
import "core:math"
import "core:mem"
import "core:log"

DEBUG :: true

ExecData :: struct {
    node_allocator: mem.Allocator
}

skip_spaces :: proc(char: rune) -> bool {
    return u8(char) == ' ' || u8(char) == '\n'
}

print_content :: proc($name: string) -> pcl.ExecProc {
    return  proc(content: pcl.EC, exec_data: pcl.ED) -> pcl.ER {
        fmt.printfln("{}: {}", name, content)
        return nil
    }
}

exec_value :: proc($type: typeid) -> pcl.ExecProc {
    return  proc(content: pcl.EC, exec_data: pcl.ED) -> pcl.ER {
        when DEBUG {
            fmt.printfln("value: {}", content)
        }
        // ed := cast(^ExecData)exec_data
        // node := new(Node, ed.node_allocator)
        // node^ = cast(Value)(cast(type)strconv.atof(content[0].(string)))
        // return cast(rawptr)node
        return content[0].(string)
    }
}

number_grammar :: proc() -> ^pcl.Parser {
    using pcl
    digits := plus(range('0', '9', skip = nil), skip = nil, name = "digits")
    ints := combine(digits, name = "ints", exec = exec_value(i32))
    floats := combine(seq(digits, lit('.'), opt(digits)), skip = nil, name = "floats", exec = exec_value(f32))
    return or(floats, ints)
}

json_grammar :: proc(allocator: pcl.ParserAllocator) -> ^pcl.Parser {
    using pcl

    context.allocator = allocator

    pcl.SKIP = skip_spaces

    json_object := declare(name = "json_object")

    value   := declare(name = "value")
    values  := seq(star(seq(value, lit(','))), value)
    number  := single(number_grammar(), exec = print_content("number"))
    string  := block("\"", "\"", exec = print_content("string"))
    list    := seq(lit('['), opt(values), lit(']'), name = "list", exec = print_content("list"))
    define(value, or(list, number, string, json_object))

    id := block("\"", "\"", exec = print_content("id"))
    entry   := seq(id, lit(':'), value, name = "entry", exec = print_content("entry"))
    entries := seq(star(seq(entry, lit(','))), entry)
    define(json_object, seq(lit('{'), opt(entries), lit('}'), name = "object", exec = print_content("object")))
    return json_object
}

main :: proc() {
    parser_allocator := pcl.parser_allocator_create()
    defer pcl.parser_allocator_destroy(parser_allocator)
    json_parser := json_grammar(parser_allocator)

    node_arena_data: [8192]byte
    node_arena: mem.Arena
    mem.arena_init(&node_arena, node_arena_data[:])
    exec_data := ExecData{ mem.arena_allocator(&node_arena) }

    pcl.parse_string(json_parser, `{
        "number": 4,
        "string": "Hellope",
        "emtpy_object": {},
        "object": {
            "pi": 3.14
        },
        "list_list": [],
        "list": [1, 2, 3, 4]
    }`)
}
