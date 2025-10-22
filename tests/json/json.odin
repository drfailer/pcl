package json

import "pcl:pcl"
import "core:strconv"
import "core:fmt"
import "core:testing"
import "core:math"
import "core:mem"
import "core:log"

DEBUG :: true

// JSON ////////////////////////////////////////////////////////////////////////

JSON_Number :: union { i32, f32 }
JSON_String :: string
JSON_List :: [dynamic]JSON_Value

JSON_Value :: union {
    JSON_Number,
    JSON_String,
    JSON_List,
    JSON_Object,
}

JSON_Entry :: struct {
    id: string,
    value: JSON_Value,
}

JSON_Object :: struct {
    entries: [dynamic]JSON_Entry
}

// parser execute //////////////////////////////////////////////////////////////

ExecData :: struct {
    node_allocator: mem.Allocator
}

print_content :: proc($name: string) -> pcl.ExecProc {
    return  proc(content: pcl.EC, exec_data: pcl.ED) -> pcl.ER {
        fmt.printfln("{}: {}", name, content)
        return nil
    }
}

exec_number :: proc($type: typeid) -> pcl.ExecProc {
    return  proc(c: pcl.EC, d: pcl.ED) -> pcl.ER {
        when DEBUG {
            fmt.printfln("number: {}", c)
        }
        // ed := cast(^ExecData)d
        // value := new(JSON_Value, ed.node_allocator)
        // when type == i32 {
        //     node^ = cast(JSON_Value)(cast(i32)strconv.atoi(pcl.ec(c, 0)))
        // } else {
        //     node^ = cast(JSON_Value)(cast(f32)strconv.atof(pcl.ec(c, 0)))
        // }
        // return cast(rawptr)node
        return nil
    }
}

number_grammar :: proc() -> ^pcl.Parser {
    using pcl
    digits := plus(range('0', '9', skip = nil), skip = nil, name = "digits")
    ints := combine(digits, name = "ints", exec = exec_number(i32))
    floats := combine(seq(digits, lit('.'), opt(digits)), skip = nil, name = "floats", exec = exec_number(f32))
    return or(floats, ints)
}

json_grammar :: proc(allocator: pcl.ParserAllocator) -> ^pcl.Parser {
    using pcl

    context.allocator = allocator

    pcl.SKIP = proc(char: rune) -> bool { return u8(char) == ' ' || u8(char) == '\n' }

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
