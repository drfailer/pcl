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
    return  proc(c: pcl.EC, d: pcl.ED) -> pcl.ER {
        when DEBUG {
            fmt.printfln("number: {}", c)
        }
        ed := cast(^ExecData)d
        value := new(JSON_Value, allocator = ed.exec_allocator)
        when type == i32 {
            int_value, ok := strconv.parse_int(pcl.ec(c, 0))
            assert(ok)
            value^ = cast(JSON_Number)(cast(i32)int_value)
        } else {
            f32_value, ok := strconv.parse_f32(pcl.ec(c, 0))
            assert(ok)
            value^ = cast(JSON_Number)f32_value
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

exec_comma_separated_list :: proc($T: typeid, $name: string) -> pcl.ExecProc {
    return proc(c: pcl.EC, d: pcl.ED) -> pcl.ER {
        when DEBUG {
            fmt.printfln("{}: {}", name, c)
        }
        ed := cast(^ExecData)d
        entries := new([dynamic]T, allocator = ed.exec_allocator)
        entries^ = make([dynamic]T, allocator = ed.exec_allocator)
        if len(c) == 2 {
            for elt in c[0].([dynamic]pcl.ER) {
                append(entries, pcl.ec(^T, elt.([dynamic]pcl.ER)[:], 0)^)
            }
        }
        append(entries, pcl.ec(^T, c, len(c) - 1)^)
        return cast(rawptr)entries
    }
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

    json_object := declare(name = "object", exec = exec_object)

    value   := declare(name = "value")
    values  := seq(star(seq(value, ',')), value, exec = exec_comma_separated_list(JSON_Value, "values"))
    number  := single(number_grammar())
    jstring := block("\"", "\"", exec = exec_string)
    list    := seq('[', opt(values), ']', name = "list", exec = exec_list)
    define(value, or(list, number, jstring, json_object))

    id      := block("\"", "\"")
    entry   := seq(id, ':', value, name = "entry", exec = exec_entry)
    entries := seq(star(seq(entry, ',')), entry, exec = exec_comma_separated_list(JSON_Entry, "entries"))
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
