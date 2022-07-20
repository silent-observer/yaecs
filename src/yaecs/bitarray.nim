import bitops
from math import `^`

type
  BitArray*[N: static[int]] = object
    arr*: array[(N + 63) div 64, uint64]


proc `[]`*[N: static int](b: BitArray[N], i: int): bool {.inline.} =
  when N <= 64:
    b.arr[0].testBit i
  else:
    let
      intIndex = i div 64
      bitIndex = i mod 64
    b.arr[intIndex].testBit bitIndex

proc `[]=`*[N: static int](b: var BitArray[N], i: int, val: bool) {.inline.} =
  when N <= 64:
    if val:
      b.arr[0].setBit i
    else:
      b.arr[0].clearBit i
  else:
    let
      intIndex = i div 64
      bitIndex = i mod 64
    if val:
      b.arr[intIndex].setBit bitIndex
    else:
      b.arr[intIndex].clearBit bitIndex

proc setBit*[N: static int](b: var BitArray[N], i: int) {.inline.} =
  when N <= 64:
    b.arr[0].setBit i
  else:
    let
      intIndex = i div 64
      bitIndex = i mod 64
    b.arr[intIndex].setBit bitIndex

proc clearBit*[N: static int](b: var BitArray[N], i: int) {.inline.} =
  when N <= 64:
    b.arr[0].clearBit i
  else:
    let
      intIndex = i div 64
      bitIndex = i mod 64
    b.arr[intIndex].clearBit bitIndex

proc clear*[N: static int](b: var BitArray[N]) {.inline.} =
  for x in b.arr.mitems:
    x = 0'u64

proc checkMask*[N: static int](b: BitArray[N], whiteList: BitArray[N]): bool =
  when N <= 64:
    bitand(b.arr[0], whiteList.arr[0]) == whiteList.arr[0]
  else:
    for i in 0..<b.arr.len:
      if bitand(b.arr[i], whiteList.arr[i]) != whiteList.arr[i]:
        return false
    return true

proc bitnot*[N: static int](b: BitArray[N]): BitArray[N] =
  const endMask = 2'u64^((N - 1) mod 64 + 1) - 1'u64
  when N <= 64:
    result.arr[0] = bitand(b.arr[0].bitnot, endMask)
  else:
    for i in 0..<b.arr.len - 1:
      result.arr[i] = b.arr[i].bitnot
    result.arr[^1] = bitand(b.arr[^1].bitnot, endMask)
    return true

proc checkMasks*[N: static int](b: BitArray[N], whiteList, blackList: BitArray[N]): bool {.inline.} =
   checkMask(b, whiteList) and checkMask(b.bitnot, whiteList)

proc constructBitArray*[N: static int](bits: openArray[int]): BitArray[N] =
  for b in bits:
    result.setBit b

proc checkMasks*[N: static int](b: BitArray[N], whiteList, blackList: static[openArray[int]]): bool {.inline.} =
  when whiteList.len == 0:
    result = true
  elif whiteList.len == 1:
    result = b[whiteList[0]]
  else:
    result = checkMask(b, constructBitArray[N](whiteList))

  when blackList.len == 0:
    discard
  elif blackList.len == 1:
    result = result and not b[blackList[0]]
  else:
    result = result and checkMask(b.bitnot, constructBitArray[N](blackList))