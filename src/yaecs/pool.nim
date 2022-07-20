import options
type
  PoolIndex* = uint32
  PoolPtr*[T, IS, CS] = object
    pool: Pool[T, IS, CS]
    index: PoolIndex
  PoolObject[T] = object
    case isActive: bool:
    of false: next: PoolIndex
    of true: data: T
  PoolChunk[T; Size: static uint32] = array[Size, PoolObject[T]]
  PoolObj[T; InitialSize, ChunkSize: static uint32] = object
    initial: PoolChunk[T, InitialSize]
    chunks: seq[ref PoolChunk[T, ChunkSize]]
    freeList: PoolIndex
    maxLen: uint32
  Pool*[T; InitialSize, ChunkSize: static uint32] = ref PoolObj[T, InitialSize, ChunkSize]
const PoolNoIndex* = PoolIndex.high

# proc `=destroy`[T; InitialSize, ChunkSize: static uint32](e: var PoolObj[T, InitialSize, ChunkSize]) =
#   echo "Pool[", T.typedesc, ", ", InitialSize, ", ", ChunkSize, "] destroyed"

proc newPool*[T; IS, CS: static uint32](): Pool[T, IS, CS] =
  new(result)
  for i in 0..<IS:
    result.initial[i] = PoolObject[T](isActive: false, next: PoolNoIndex)
  result.chunks = @[]
  result.freeList = PoolNoIndex
  result.maxLen = 0

proc getInternal[T; IS, CS: static uint32](p: Pool[T, IS, CS], i: PoolIndex): ptr PoolObject[T] =
  when not defined(ecsDisableChecks):
    if i < 0 or i >= p.maxLen:
      return nil
  if i < IS:
    addr p.initial[i]
  else:
    let 
      chunkIndex = (i - IS) div CS
      objectIndex = (i - IS) mod CS
    addr p.chunks[chunkIndex][objectIndex]

proc add*(p: Pool, data: Pool.T = default(Pool.T)): PoolIndex =
  if p.freeList != PoolNoIndex:
    result = p.freeList
    let o = getInternal[Pool.T, Pool.InitialSize, Pool.ChunkSize](p, result)
    p.freeList = o.next
    o[] = PoolObject[Pool.T](isActive: true, data: data)
  else:
    result = p.maxLen
    p.maxLen.inc
    if p.maxLen == uint32(Pool.InitialSize + p.chunks.len * Pool.ChunkSize):
      p.chunks.add new(PoolChunk[Pool.T, Pool.ChunkSize])
    getInternal[Pool.T, Pool.InitialSize, Pool.ChunkSize](p, result)[] = 
      PoolObject[Pool.T](isActive: true, data: data)

proc delete*(p: Pool, i: PoolIndex) =
  let o = getInternal[Pool.T, Pool.InitialSize, Pool.ChunkSize](p, i)
  if o != nil and o.isActive:
    o[] = PoolObject[Pool.T](isActive: false, next: p.freeList)
    p.freeList = i

proc clear*(p: Pool) {.inline.} =
  for i in 0..<p.maxLen:
    let o = getInternal[Pool.T, Pool.InitialSize, Pool.ChunkSize](p, i)
    if o != nil and o.isActive:
      o[] = PoolObject[Pool.T](isActive: false, next: PoolNoIndex)
  p.maxLen = 0

proc getUnsafe*(p: Pool, i: PoolIndex): var Pool.T {.inline.} = 
  getInternal[Pool.T, Pool.InitialSize, Pool.ChunkSize](p, i).data
proc `[]`*(p: Pool, i: PoolIndex): var Pool.T {.inline.} =
  if i > p.maxLen:
    raise newException(IndexDefect, "Invalid index for pool!")
  let o = getInternal[Pool.T, Pool.InitialSize, Pool.ChunkSize](p, i)
  if o == nil or not o[].isActive:
    raise newException(IndexDefect, "Invalid index for pool!")
  o.data
proc `[]=`*(p: Pool, i: PoolIndex, v: Pool.T) {.inline.} = (p[i]) = v
  
proc get*(p: Pool, i: PoolIndex): Option[Pool.T] {.inline.} =
  if i > p.maxLen:
    return none(Pool.T)
  let o = getInternal[Pool.T, Pool.InitialSize, Pool.ChunkSize](p, i)
  if o != nil and o[].isActive:
    some(o.data)
  else:
    none(Pool.T)

proc `[]`*(p: PoolPtr): var PoolPtr.T {.inline.} = p.pool[p.index]

iterator mitems*[T; IS, CS: static uint32](p: Pool[T, IS, CS]): var T =
  for i in 0..<p.maxLen:
    let o = getInternal[T, IS, CS](p, i)
    if o != nil and o.isActive:
      yield o.data
iterator mpairs*[T; IS, CS: static uint32](p: Pool[T, IS, CS]): tuple[key: PoolIndex, val: var T] =
  for i in 0..<p.maxLen:
    let o = getInternal[T, IS, CS](p, i)
    if o != nil and o.isActive:
      yield (key: i, val: o.data)

iterator items*[T; IS, CS: static uint32](p: Pool[T, IS, CS]): T {.inline.} =
  for x in p.mitems:
    yield x
iterator pairs*[T; IS, CS: static uint32](p: Pool[T, IS, CS]): tuple[key: PoolIndex, val: T] {.inline.} =
  for x in p.mpairs:
    yield x

