package pcl

import "core:mem"
import "core:log"
import "core:strings"
import "base:runtime"

// memory pool /////////////////////////////////////////////////////////////////

// The current memory pool implementation is not thread safe. If at some point
// PCL supports mutli-threading, the pool should have a mutex.

MemoryPoolNode :: struct($T: typeid) {
    data: T,
    next: ^MemoryPoolNode(T),
    prev: ^MemoryPoolNode(T),
    loc: runtime.Source_Code_Location,
}

MemoryPool :: struct($T: typeid) {
    free_nodes: ^MemoryPoolNode(T),
    used_nodes: ^MemoryPoolNode(T),
    allocator: mem.Allocator,
}

memory_pool_create :: proc($T: typeid, default_capacity := 0, allocator := context.allocator) -> MemoryPool(T) {
    pool := MemoryPool(T){
        allocator = allocator,
    }

    for _ in 0..<default_capacity {
        // the prev field is not used in the free list
        node := new(MemoryPoolNode(T), allocator)
        node.next = pool.free_nodes
        pool.free_nodes = node
    }
    return pool
}


memory_pool_destroy :: proc(pool: ^MemoryPool($T)) {
    node := pool.free_nodes
    nb_nodes := 0
    nb_released_nodes := 0

    for node != nil {
        when ODIN_DEBUG {
            nb_nodes += 1
            nb_released_nodes += 1
        }
        next := node.next
        free(node, pool.allocator)
        node = next
    }
    node = pool.used_nodes
    for node != nil {
        log.warn("non released node, allocated at:", node.loc)
        when ODIN_DEBUG {
            nb_nodes += 1
        }
        next := node.next
        free(node, pool.allocator)
        node = next
    }
    when ODIN_DEBUG {
        if nb_nodes != nb_released_nodes {
            log.info("the memory pool allocated", nb_nodes ,"elements, and ", nb_released_nodes," where released.")
        }
    }
}

memory_pool_allocate :: proc(pool: ^MemoryPool($T), loc := #caller_location) -> ^T {
    if pool.free_nodes == nil {
        node := new(MemoryPoolNode(T), pool.allocator)
        node.next = pool.free_nodes
        pool.free_nodes = node
    }
    node := pool.free_nodes
    pool.free_nodes = node.next
    node.prev = nil
    node.next = pool.used_nodes
    node.loc = loc
    if node.next != nil {
        node.next.prev = node
    }
    pool.used_nodes = node
    return cast(^T)node
}

memory_pool_release :: proc(pool: ^MemoryPool($T), data: ^T, loc := #caller_location) {
    node := cast(^MemoryPoolNode(T))data
    // look for double free
    when ODIN_DEBUG {
        cur := pool.free_nodes
        for cur != nil {
            if cur == node {
                log.error("double free detected in memory pool, at", loc)
                return
            }
            cur = cur.next
        }
    }
    if node.next != nil {
        node.next.prev = node.prev
    }
    if node.prev != nil {
        node.prev.next = node.next
    } else {
        pool.used_nodes = node.next
    }
    node.prev = nil
    node.next = pool.free_nodes
    pool.free_nodes = node
}


memory_pool_release_from_root :: proc(pool: ^MemoryPool($T), root_data: ^T) {
    node := cast(^MemoryPoolNode(T))root_data
    if node.next != nil {
        node.next.prev = nil
    }
    head_node := pool.used_nodes
    pool.used_nodes = node.next
    node.next = pool.free_nodes
    pool.free_nodes = head_node
}

// parsing utilities ///////////////////////////////////////////////////////////

cursor_on_string :: proc(state: ^ParserState, $prefix: string) -> bool {
    return strings.has_prefix(state.global_state.content[state.cur:], prefix);
}
