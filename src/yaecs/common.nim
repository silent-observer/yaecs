import hashes

type
  EntityId* = distinct int
  YaecsDefect* = object of Defect

proc `==`*(a, b: EntityId): bool {.borrow.}
proc hash*(a: EntityId): Hash {.borrow.}