package json

import "pcl:pcl"
import "core:strconv"
import "core:fmt"
import "core:testing"
import "core:math"
import "core:mem"
import "core:log"

DEBUG :: false

// JSON ////////////////////////////////////////////////////////////////////////

JSON_Number :: union { i32, f32 }
JSON_String :: distinct string
JSON_List :: distinct [dynamic]JSON_Value

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
    exec_allocator: mem.Allocator,
}

exec_number :: proc($type: typeid) -> pcl.ExecProc {
    return  proc(c: pcl.EC, d: pcl.ED) -> pcl.ER {
        when DEBUG {
            fmt.printfln("number: {}", c)
        }
        ed := cast(^ExecData)d
        value := new(JSON_Value, allocator = ed.exec_allocator)
        when type == i32 {
            value^ = cast(JSON_Number)(cast(i32)strconv.atoi(pcl.ec(c, 0)))
        } else {
            value^ = cast(JSON_Number)(cast(f32)strconv.atof(pcl.ec(c, 0)))
        }
        return cast(rawptr)value
    }
}

exec_string :: proc(c: pcl.EC, d: pcl.ED) -> pcl.ER {
    when DEBUG {
        fmt.printfln("string: {}", c)
    }
    ed := cast(^ExecData)d
    value := new(JSON_Value, allocator = ed.exec_allocator)
    value^ = cast(JSON_String)pcl.ec(c, 0)
    return cast(rawptr)value
}

exec_values :: proc(c: pcl.EC, d: pcl.ED) -> pcl.ER {
    when DEBUG {
        fmt.printfln("values: {}", c)
    }
    ed := cast(^ExecData)d
    values := new([dynamic]JSON_Value, allocator = ed.exec_allocator)
    values^ = make([dynamic]JSON_Value, allocator = ed.exec_allocator)
    if len(c) == 2 {
        star_list := c[0].([dynamic]pcl.ER)
        for elt in star_list {
            value := pcl.ec(^JSON_Value, elt.([dynamic]pcl.ER)[:], 0)
            append(values, value^)
        }
    }
    value := pcl.ec(^JSON_Value, c, len(c) - 1)
    append(values, value^)
    return cast(rawptr)values
}

exec_list :: proc(c: pcl.EC, d: pcl.ED) -> pcl.ER {
    when DEBUG {
        fmt.printfln("list: {}", c)
    }
    ed := cast(^ExecData)d
    value := new(JSON_Value, allocator = ed.exec_allocator)
    list: JSON_List
    if len(c) == 3 {
        values := pcl.ec(^JSON_List, c, 1)
        list = values^
    }
    value^ = list
    return cast(rawptr)value
}

exec_entry :: proc(c: pcl.EC, d: pcl.ED) -> pcl.ER {
    when DEBUG {
        fmt.printfln("entry: {}", c)
    }
    ed := cast(^ExecData)d
    entry := new(JSON_Entry, allocator = ed.exec_allocator)
    entry.id = pcl.ec(c, 0)
    value := pcl.ec(^JSON_Value, c, 2)
    entry.value = value^
    return cast(rawptr)entry
}

exec_entries :: proc(c: pcl.EC, d: pcl.ED) -> pcl.ER {
    when DEBUG {
        fmt.printfln("entries: {}", c)
    }
    ed := cast(^ExecData)d
    entries := new([dynamic]JSON_Entry, allocator = ed.exec_allocator)
    entries^ = make([dynamic]JSON_Entry, allocator = ed.exec_allocator)
    if len(c) == 2 {
        star_list := c[0].([dynamic]pcl.ER)
        for elt in star_list {
            entry := pcl.ec(^JSON_Entry, elt.([dynamic]pcl.ER)[:], 0)
            append(entries, entry^)
        }
    }
    entry := pcl.ec(^JSON_Entry, c, len(c) - 1)
    append(entries, entry^)
    return cast(rawptr)entries
}

exec_object :: proc(c: pcl.EC, d: pcl.ED) -> pcl.ER {
    when DEBUG {
        fmt.printfln("object: {}", c)
    }
    ed := cast(^ExecData)d
    value := new(JSON_Value, allocator = ed.exec_allocator)
    object: JSON_Object
    if len(c) > 2 {
        entries := pcl.ec(^[dynamic]JSON_Entry, c, 1)
        object.entries = entries^
    }
    value^ = object
    return cast(rawptr)value
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
    values  := seq(star(seq(value, lit(','))), value, exec = exec_values)
    number  := single(number_grammar())
    jstring  := block("\"", "\"", exec = exec_string)
    list    := seq(lit('['), opt(values), lit(']'), name = "list", exec = exec_list)
    define(value, or(list, number, jstring, json_object))

    id := block("\"", "\"")
    entry   := seq(id, lit(':'), value, name = "entry", exec = exec_entry)
    entries := seq(star(seq(entry, lit(','))), entry, exec = exec_entries)
    define(json_object, seq(lit('{'), opt(entries), lit('}'), name = "object", exec = exec_object))
    return json_object
}

main :: proc() {
    parser_allocator := pcl.parser_allocator_create()
    defer pcl.parser_allocator_destroy(parser_allocator)
    json_parser := json_grammar(parser_allocator)

    exec_arena_data: [16384]byte
    exec_arena: mem.Arena
    mem.arena_init(&exec_arena, exec_arena_data[:])
    exec_allocator := mem.arena_allocator(&exec_arena)
    exec_data := ExecData{
        exec_allocator = exec_allocator,
    }

    state, result, ok := pcl.parse_string(json_parser, `{
        "number": 4,
        "string": "Hellope",
        "emtpy_object": {},
        "object": {
            "pi": 3.14
        },
        "empty_list": [],
        "list": [1, 2, 3, 4]
    }`, &exec_data)
    object := cast(^JSON_Value)result.(rawptr)
    fmt.println(object)
}
