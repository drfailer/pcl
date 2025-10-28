package json1

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
    return  proc(data: ^pcl.ExecData) -> pcl.ExecResult {
        when DEBUG {
            fmt.printfln("number: {}", data.content)
        }
        value: JSON_Value
        when type == i32 {
            int_value, ok := strconv.parse_int(pcl.content(data, 0))
            assert(ok)
            value = cast(JSON_Number)(cast(i32)int_value)
        } else {
            f32_value, ok := strconv.parse_f32(pcl.content(data, 0))
            assert(ok)
            value = cast(JSON_Number)f32_value
        }
        return pcl.result(data, value)
    }
}

exec_string :: proc(data: ^pcl.ExecData) -> pcl.ExecResult {
    when DEBUG {
        fmt.printfln("string: {}", data.content)
    }
    value: JSON_Value = cast(JSON_String)pcl.content(data, 0)
    return pcl.result(data, value)
}

// exec using separated itmes rule
exec_values :: proc(data: ^pcl.ExecData) -> pcl.ExecResult {
    when DEBUG {
        fmt.printfln("values: {}", data.content)
    }
    ed := pcl.user_data(data, ^ExecData)
    values := make([dynamic]JSON_Value, allocator = ed.exec_allocator)
    for i in 0..<len(data.content) {
        append(&values, pcl.content(data, JSON_Value, i))
    }
    return pcl.result(data, values)
}

// exec using star
exec_entries :: proc(data: ^pcl.ExecData) -> pcl.ExecResult {
    when DEBUG {
        fmt.printfln("entries: {}", data.content)
    }
    ed := pcl.user_data(data, ^ExecData)
    entries := make([dynamic]JSON_Entry, allocator = ed.exec_allocator)
    if len(data.content) == 2 {
        for elt in pcl.contents(data, 0) {
            append(&entries, pcl.content(elt, JSON_Entry, 0))
        }
    }
    append(&entries, pcl.content(data, JSON_Entry, len(data.content) - 1))
    return pcl.result(data, entries)
}

exec_list :: proc(data: ^pcl.ExecData) -> pcl.ExecResult {
    when DEBUG {
        fmt.printfln("list: {}", data.content)
    }
    value: JSON_Value = JSON_List{}
    if len(data.content) == 3 {
        value = pcl.content(data, JSON_List, 1)
    }
    return pcl.result(data, value)
}

exec_entry :: proc(data: ^pcl.ExecData) -> pcl.ExecResult {
    when DEBUG {
        fmt.printfln("entry: {}", data.content)
    }
    return pcl.result(data, JSON_Entry{
        id = pcl.content(data, 0),
        value = pcl.content(data, JSON_Value, 2),
    })
}

exec_object :: proc(data: ^pcl.ExecData) -> pcl.ExecResult {
    when DEBUG {
        fmt.printfln("object: {}", data.content)
    }
    value: JSON_Value = JSON_Object{}
    if len(data.content) > 2 {
        value = JSON_Object{
            entries = pcl.content(data, [dynamic]JSON_Entry, 1)
        }
    }
    return pcl.result(data, value)
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

    json_object := declare(name = "object", exec = exec_object)

    value   := declare(name = "value")
    values  := separated_items(value, ',', false, false, exec = exec_values)
    number  := single(number_grammar())
    jstring := block('"', '"', exec = exec_string)
    list    := seq('[', opt(values), ']', name = "list", exec = exec_list)
    define(value, or(list, number, jstring, json_object))

    id      := block('"', '"')
    entry   := seq(id, ':', value, name = "entry", exec = exec_entry)
    entries := seq(star(entry, ','), entry, exec = exec_entries)
    define(json_object, seq('{', opt(entries), '}'))
    return json_object
}

@(test)
test_object :: proc(t: ^testing.T) {
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
        "empty_object": {},
        "object": {
            "pi": 3.14
        },
        "empty_list": [],
        "list": [1, 2, 3, 4]
    }`, &exec_data)
    object := (cast(^JSON_Value)result.(rawptr)).(JSON_Object)

    testing.expect(t, ok == true)
    testing.expect(t, len(object.entries) == 6)

    testing.expect(t, object.entries[0].id == "number")
    testing.expect(t, object.entries[0].value.(JSON_Number).(i32) == 4)

    testing.expect(t, object.entries[1].id == "string")
    testing.expect(t, string(object.entries[1].value.(JSON_String)) == "Hellope")

    testing.expect(t, object.entries[2].id == "empty_object")
    testing.expect(t, len(object.entries[2].value.(JSON_Object).entries) == 0)

    testing.expect(t, object.entries[3].id == "object")
    testing.expect(t, len(object.entries[3].value.(JSON_Object).entries) == 1)
    testing.expect(t, object.entries[3].value.(JSON_Object).entries[0].id == "pi")
    testing.expect(t, object.entries[3].value.(JSON_Object).entries[0].value.(JSON_Number).(f32) == 3.14)

    testing.expect(t, object.entries[4].id == "empty_list")
    testing.expect(t, len(object.entries[4].value.(JSON_List)) == 0)

    testing.expect(t, object.entries[5].id == "list")
    testing.expect(t, len(object.entries[5].value.(JSON_List)) == 4)
    for v, i in object.entries[5].value.(JSON_List) {
        testing.expect(t, v.(JSON_Number).(i32) == i32(i + 1))
    }
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
