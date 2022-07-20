import pool, common
from sequtils import newSeqWith
import std/enumerate

type 
  ComponentPool*[T] = object
    pool*: Pool[T, 1000, 100]
    sparse*: seq[PoolIndex]
  RareComponentPool*[T] = object
    pool*: Pool[T, 10, 10]
    entityList*: seq[(int, PoolIndex)]
    lastAccess*: int
  RareTagPool* = object
    list*: seq[int]

proc initComponentPool*[T](entityMaxCount: int): ComponentPool[T] {.inline.} =
  result.pool = newPool[T, 1000, 100]()
  result.sparse = newSeqWith(entityMaxCount, PoolNoIndex)

proc `[]`*[T](pool: ComponentPool[T], index: int): var T {.inline.} =
  let i = pool.sparse[index]
  when not defined(ecsDisableChecks):
    if i == PoolNoIndex:
      raise newException(YaecsDefect, "No such component in the pool")
  pool.pool[i]
proc `[]=`*[T](pool: ComponentPool[T], index: int, v: T) {.inline.} = (pool[index]) = v

proc initRareComponentPool*[T](): RareComponentPool[T] {.inline.} =
  result.pool = newPool[T, 10, 10]()
  result.lastAccess = -1

proc `[]`*[T](pool: RareComponentPool[T], index: int): var T {.inline.} =
  result = pool.pool[0] # this should never be used
  if pool.lastAccess != -1 and pool.entityList[pool.lastAccess][0] == index:
    return pool.pool[pool.entityList[pool.lastAccess][1]]

  #var counter = 0
  for (i, j) in pool.entityList:
    if i == index:
      #pool.lastIndex = counter
      return pool.pool[j]
    #counter.inc
  raise newException(YaecsDefect, "No such component in the pool")

proc find*[T](pool: RareComponentPool[T], index: EntityId): PoolIndex {.inline.} =
  if pool.lastAccess != -1 and pool.entityList[pool.lastAccess][0] == index.int:
    return pool.entityList[pool.lastAccess][1]

  #var counter = 0
  for (i, j) in pool.entityList:
    if i == index.int:
      #pool.lastAccess = counter
      return j
    #counter.inc
  return PoolNoIndex

proc contains*[T](pool: RareComponentPool[T], index: EntityId): bool {.inline.} =
  pool.find(index) != PoolNoIndex
proc contains*(pool: RareTagPool, index: EntityId): bool {.inline.} =
  pool.list.contains(index.int)

proc remove*[T](pool: var RareComponentPool[T], index: EntityId) {.inline.} =
  for i in 0..<pool.entityList.len:
    if pool.entityList[i][0] == index.int:
      pool.pool.delete(pool.entityList[i][1])
      pool.entityList.delete(i)
      return

proc remove*(pool: var RareTagPool, index: EntityId) {.inline.} =
  for i in 0..<pool.list.len:
    if pool.list[i] == index.int:
      pool.list.delete(i)
      return


proc listLen*[T](pool: RareComponentPool[T]): int {.inline.} =
  pool.entityList.len
proc listLen*(pool: RareTagPool): int {.inline.} =
  pool.list.len

proc getId*[T](pool: RareComponentPool[T], i: int): int {.inline.} =
  pool.entityList[i][0]
proc getId*(pool: RareTagPool, i: int): int {.inline.} =
  pool.list[i]