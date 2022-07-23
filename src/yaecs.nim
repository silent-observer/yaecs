import macros, yaecs/[pool, components, bitarray, common], tables, std/enumerate
import std/genasts
export bitarray, pool, components, common

type
  Entity*[W] = object
    world*: W
    id*: EntityId


type
  ComponentData = object
    typeName: string
    convert: NimNode
    alias: string
    isRare: bool
  TagData = object
    typeName: string
    isRare: bool
  Filter = object
    whiteList: seq[string]
    blackList: seq[string]
    alias: string
  WorldInternalData = object
    components: Table[string, ComponentData]
    tags: Table[string, TagData]
    bitarrayNames: seq[string]

    filters: seq[Filter]
    filterNames: seq[string]

    bitArraySize: int

proc globalName(name: NimNode, global: bool): NimNode {.compileTime, inline.} =
  if global:
    nnkPostfix.newTree(ident"*", name)
  else:
    name

proc defineWorld(name: NimNode, internal: WorldInternalData, global: bool): NimNode {.compileTime.} =
  var recList = nnkRecList.newTree()
  for component in internal.components.values:
    let name = ident("pool_" & component.typeName)
    if component.isRare:
      recList.add newIdentDefs(name, nnkBracketExpr.newTree(
        bindSym"RareComponentPool", newIdentNode(component.typeName)
      ))
    else:
      recList.add newIdentDefs(name, nnkBracketExpr.newTree(
        bindSym"ComponentPool", newIdentNode(component.typeName)
      ))
  for tag in internal.tags.values:
    if tag.isRare:
      let name = newIdentNode("pool_" & tag.typeName)
      recList.add newIdentDefs(name, bindSym"RareTagPool")

  recList.add newIdentDefs(
    ident"entities",
    nnkBracketExpr.newTree(
      bindSym"seq",
      nnkBracketExpr.newTree(
        bindSym"BitArray",
        newLit(internal.bitArraySize)
      )
    )
  )
  recList.add newIdentDefs(
    ident"entityFreeList",
    nnkBracketExpr.newTree(bindSym"seq", bindSym"EntityId")
  )
  
  nnkTypeDef.newTree(
    name.globalName(global),
    newEmptyNode(),
    nnkRefTy.newTree(
      nnkObjectTy.newTree(
        newEmptyNode(),
        newEmptyNode(),
        recList
      )
    )
  )

proc defineWorldConstructor(name: NimNode, internal: WorldInternalData, global: bool): NimNode {.compileTime.} =
  let procName = ident("new" & name.strVal).globalName(global)
  let entityMaxCount = genSym(nskParam, "entityMaxCount")
  result = quote do:
    proc `procName`(`entityMaxCount`: int = 10_000): `name` =
      discard
  var stmtList = newStmtList(
    newCall(bindSym"new", ident"result")
  )

  for component in internal.components.values:
    let compPool = ident("pool_" & component.typeName)
    let val = if component.isRare:
        newAssignment(
          newDotExpr(ident"result", compPool),
          newCall(
            nnkBracketExpr.newTree(bindSym"initRareComponentPool", ident(component.typeName))
          )
        )
      else: 
        newAssignment(
          newDotExpr(ident"result", compPool),
          newCall(
            nnkBracketExpr.newTree(bindSym"initComponentPool", ident(component.typeName)),
            entityMaxCount
          )
        )
    stmtList.add val
  let bitArrSize = newLit(internal.bitArraySize)
  stmtList.add newAssignment(
    newDotExpr(ident"result", ident"entities"),
    newCall(
      nnkBracketExpr.newTree(bindSym"newSeqOfCap",
        nnkBracketExpr.newTree(bindSym"BitArray", bitArrSize)),
      entityMaxCount
    )
  )
  stmtList.add quote do:
    result.entityFreeList = @[]
  result[^1] = stmtList

proc defineAddComponent(name: NimNode, internal: WorldInternalData, global: bool): seq[NimNode] {.compileTime.} =
  var index = 0
  for component in internal.components.values:
    let pool = ident("pool_" & component.typeName)
    let compType = ident(component.typeName)
    let addName = ident("add").globalName(global)
    let removeName = ident("remove" & component.typeName).globalName(global)

    if component.isRare:
      let p1 = quote do:
        proc `addName`(e: Entity[`name`], c: `compType`) {.inline.} =
          let compId = e.world.`pool`.pool.add(c)
          when not defined(ecsDisableChecks):
            if e.world.`pool`.contains(e.id):
              raise newException(YaecsDefect, "Cannot add a component twice")
          e.world.`pool`.entityList.add (e.id.int, compId)
      let p2 = quote do:
        proc `removeName`(e: Entity[`name`]) {.inline.} =
          when not defined(ecsDisableChecks):
            if not e.world.`pool`.contains(e.id):
              raise newException(YaecsDefect, "Cannot delete a component that entity doesn't have")
          e.world.`pool`.remove(e.id)
      result.add p1
      result.add p2
    else:
      let p1 = quote do:
        proc `addName`(e: Entity[`name`], c: `compType`) =
          when not defined(ecsDisableChecks):
            if e.world.entities[e.id.int][`index.int`]:
              raise newException(YaecsDefect, "Cannot add a component twice")
          e.world.entities[e.id.int].setBit `index.int`
          if e.id.int > e.world.`pool`.sparse.len:
            let prevLen = e.world.`pool`.sparse.len
            e.world.`pool`.sparse.setLen(e.id.int + 1)
            for i in prevLen..<e.id.int:
              e.world.`pool`.sparse[i] = PoolNoIndex
          let compId = e.world.`pool`.pool.add(c)
          e.world.`pool`.sparse[e.id.int] = compId.PoolIndex
      
      let p2 = quote do:
        proc `removeName`(e: Entity[`name`]) =
          when not defined(ecsDisableChecks):
            if not e.world.entities[e.id.int][`index.int`]:
              raise newException(YaecsDefect, "Cannot delete a component that entity doesn't have")
          e.world.entities[e.id.int].clearBit `index.int`
          let i = e.world.`pool`.sparse[e.id.int]
          e.world.`pool`.pool.delete(i.PoolIndex)
          e.world.`pool`.sparse[e.id.int] = PoolNoIndex

      result.add p1
      result.add p2
      index.inc
  
  for tag in internal.tags.values:
    let addName = ident("add" & tag.typeName).globalName(global)
    let removeName = ident("remove" & tag.typeName).globalName(global)
    if tag.isRare:
      let pool = ident("pool_" & tag.typeName) 
      let p1 = quote do:
        proc `addName`(e: Entity[`name`]) {.inline.} =
          if not e.world.`pool`.contains(e.id):
            e.world.`pool`.list.add e.id.int
      let p2 = quote do:
        proc `removeName`(e: Entity[`name`]) {.inline.} =
          if e.world.`pool`.contains(e.id):
            e.world.`pool`.remove e.id
      result.add p1
      result.add p2
    else:
      let p1 = quote do:
        proc `addName`(e: Entity[`name`]) {.inline.} =
          e.world.entities[e.id.int].setBit `index.int`
      let p2 = quote do:
        proc `removeName`(e: Entity[`name`]) {.inline.} =
          e.world.entities[e.id.int].clearBit `index.int`
      result.add p1
      result.add p2
      index.inc

proc newEntity*[W: ref object](w: W): Entity[W] =
  if w.entityFreeList.len == 0:
    result = Entity[W](world: w, id: w.entities.len.EntityId)
    w.entities.setLen(w.entities.len + 1)
  else:
    result = Entity[W](world: w, id: w.entityFreeList.pop)
proc newEntities*[W: ref object](w: W, count: int): seq[Entity[W]] =
  for i in 0..<count:
    result.add w.newEntity()
proc initEmptyEntity*[W: ref object](): Entity[W] {.inline.} =
  Entity[W](world: nil, id: -1)

proc defineDelete(name: NimNode, internal: WorldInternalData, global: bool): NimNode {.compileTime.} =
  let e = genSym(nskParam, "e")
  let deleteName = ident("delete").globalName(global)
  result = quote do:
    proc `deleteName`(`e`: sink Entity[`name`]) =
      if `e`.world == nil: return
      `e`.world.entityFreeList.add `e`.id
  for component in internal.components.values:
    let pool = ident("pool_" & component.typeName)
    if component.isRare:
      result[^1].add quote do:
        `e`.world.`pool`.remove `e`.id
    else:
      let compName = ident(component.typeName)
      let removeName = ident("remove" & component.typeName)
      result[^1].add quote do:
        if `e`.has `compName`:
          `e`.`removeName`()
  for tag in internal.tags.values:
    if tag.isRare:
      let pool = ident("pool_" & tag.typeName)
      result[^1].add quote do:
        `e`.world.`pool`.remove `e`.id
  result[^1].add quote do:
    `e`.world.entities[`e`.id.int].clear()

proc defineComponentGetters(name: NimNode, internal: WorldInternalData, global: bool): seq[NimNode] {.compileTime.} =
  for index, component in enumerate(internal.components.values):
    let pool = ident("pool_" & component.typeName)
    let compType = ident(component.typeName)
    let aliasId = ident(component.alias).globalName(global)
    let aliasIdSetter = ident(component.alias & "=").globalName(global)
    let convertType = component.convert
    if convertType == nil:
      result.add quote do:
        template `aliasId`(e: Entity[`name`]): var `compType` =
          when not defined(ecsDisableChecks):
            if not e.has `compType`:
              raise newException(YaecsDefect, "Cannot access a component entity doesn't have")
          e.world.`pool`[e.id.int]
        template `aliasIdSetter`(e: Entity[`name`], v: `compType`) =
          when not defined(ecsDisableChecks):
            if not e.has `compType`:
              raise newException(YaecsDefect, "Cannot access a component entity doesn't have")
          e.world.`pool`[e.id.int] = v
    else:
      result.add quote do:
        template `aliasId`(e: Entity[`name`]): var `convertType` =
          when not defined(ecsDisableChecks):
            if not e.has `compType`:
              raise newException(YaecsDefect, "Cannot access a component entity doesn't have")
          `convertType`(e.world.`pool`[e.id.int])
        template `aliasIdSetter`(e: Entity[`name`], v: `convertType`)  =
          when not defined(ecsDisableChecks):
            if not e.has `compType`:
              raise newException(YaecsDefect, "Cannot access a component entity doesn't have")
          e.world.`pool`[e.id.int] = `compType`(v)

proc defineHas(name: NimNode, internal: WorldInternalData, global: bool): NimNode {.compileTime.} =
  let 
    e = genSym(nskParam, "e")
    c = genSym(nskParam, "c")
    hasName = ident("has").globalName(global)
  result = quote do:
    template `hasName`(`e`: Entity[`name`], `c`: untyped): bool =
      discard
  result[^1][0] = nnkWhenStmt.newTree()
  var index = 0
  for component in internal.components.values:
    let compType = ident(component.typeName)
    let cond = quote do:
      `c` is `compType`
    if component.isRare:
      let pool = ident("pool_" & component.typeName)
      let body = quote do:
        `e`.world.`pool`.contains(`e`.id)
      result[^1][0].add nnkElifBranch.newTree(cond, body)
    else:
      let body = quote do:
        `e`.world.entities[`e`.id.int][`index.int`]
      result[^1][0].add nnkElifBranch.newTree(cond, body)
      index.inc
  
  for tag in internal.tags.values:
    let compType = ident(tag.typeName)
    let cond = quote do:
      `c` is `compType`
    if tag.isRare:
      let pool = ident("pool_" & tag.typeName)
      let body = quote do:
        `e`.world.`pool`.contains(`e`.id)
      result[^1][0].add nnkElifBranch.newTree(cond, body)
    else:
      let body = quote do:
        `e`.world.entities[`e`.id.int][`index.int`]
      result[^1][0].add nnkElifBranch.newTree(cond, body)
      index.inc
  #result[^1][0].add nnkElse.newTree(nnk)

proc defineRegularQuery(name: NimNode, internal: WorldInternalData, filter: Filter, global: bool): NimNode {.compileTime.} =
  let queryName = ident("query" & filter.alias).globalName(global)
  var wlArr = nnkBracket.newTree()
  for c in filter.whiteList:
    wlArr.add newIntLitNode(internal.bitarrayNames.find(c))

  let 
    world = genSym(nskParam, "world")
    index = genSym(nskVar, "index")

  var blArr = nnkBracket.newTree()
  var blackListRare: NimNode = newStmtList()
  for c in filter.blackList:
    if c in internal.bitarrayNames:
      blArr.add newIntLitNode(internal.bitarrayNames.find(c))
    else:
      let pool = ident("pool_" & c)
      blackListRare.add quote do:
        if `index`.EntityId in `world`.`pool`:
          `index`.inc
          continue

  quote do:
    iterator `queryName`(`world`: `name`): Entity[`name`] =
      var `index` = 0
      for arr in `world`.entities:
        if checkMasks(arr, `wlArr`, `blArr`):
          `blackListRare`
          yield Entity[`name`](world: `world`, id: `index`.EntityId)
        `index`.inc

proc defineRareQuery(name: NimNode, internal: WorldInternalData, 
    filter: Filter, rareObject: string, global: bool): NimNode {.compileTime.} =
  let queryName = ident("query" & filter.alias).globalName(global)

  let 
    world = genSym(nskParam, "world")
    id = genSym(nskLet, "id")

  var wlArr = nnkBracket.newTree()
  var wlRare: NimNode = newStmtList()
  for c in filter.whiteList:
    if c in internal.bitarrayNames:
      wlArr.add newIntLitNode(internal.bitarrayNames.find(c))
    elif c != rareObject:
      let pool = ident("pool_" & c)
      wlRare.add quote do:
        if `id`.EntityId notin `world`.`pool`: continue

  var blArr = nnkBracket.newTree()
  var blRare: NimNode = newStmtList()
  for c in filter.blackList:
    if c in internal.bitarrayNames:
      blArr.add newIntLitNode(internal.bitarrayNames.find(c))
    else:
      let pool = ident("pool_" & c)
      blRare.add quote do:
        if `id`.EntityId in `world`.`pool`: continue

  let rarePool = ident("pool_" & rareObject)

  quote do:
    iterator `queryName`(`world`: `name`): Entity[`name`] =
      var i: int = 0
      while i < `world`.`rarePool`.listLen:
        let `id` = `world`.`rarePool`.getId(i)
        let arr = `world`.entities[`id`]
        if checkMasks(arr, `wlArr`, `blArr`):
          `wlRare`
          `blRare`
          let oldLen = `world`.`rarePool`.listLen
          yield Entity[`name`](world: `world`, id: `id`.EntityId)
          i -= oldLen - `world`.`rarePool`.listLen
        inc i

proc defineIs(name: NimNode, internal: WorldInternalData, filter: Filter, global: bool): NimNode {.compileTime.} =
  let isName = ident("is" & filter.alias).globalName(global)

  let e = genSym(nskParam, "e")

  var wlArr = nnkBracket.newTree()
  var wlRare: NimNode = newStmtList()
  for c in filter.whiteList:
    if c in internal.bitarrayNames:
      wlArr.add newIntLitNode(internal.bitarrayNames.find(c))
    else:
      let pool = ident("pool_" & c)
      wlRare.add quote do:
        if `e`.id notin `e`.world.`pool`: return false

  var blArr = nnkBracket.newTree()
  var blRare: NimNode = newStmtList()
  for c in filter.blackList:
    if c in internal.bitarrayNames:
      blArr.add newIntLitNode(internal.bitarrayNames.find(c))
    else:
      let pool = ident("pool_" & c)
      blRare.add quote do:
        if `e`.id in `e`.world.`pool`: return false

  quote do:
    proc `isName`(`e`: Entity[`name`]): bool {.inline.} =
      let arr = `e`.world.entities[`e`.id.int]
      if checkMasks(arr, `wlArr`, `blArr`):
        `wlRare`
        `blRare`
        true
      else:
        false

proc defineQuery(name: NimNode, internal: WorldInternalData, global: bool): seq[NimNode] {.compileTime.} =
  for filter in internal.filters:
    var rareObject: string = ""
    for name in filter.whiteList:
      if (name in internal.components and internal.components[name].isRare) or
          (name in internal.tags and internal.tags[name].isRare):
        rareObject = name
        break
    
    if rareObject == "":
      result.add defineRegularQuery(name, internal, filter, global)
    else:
      result.add defineRareQuery(name, internal, filter, rareObject, global)
    result.add defineIs(name, internal, filter, global)

proc defineOwned(name: NimNode, internal: WorldInternalData, global: bool): NimNode {.compileTime.} =
  let 
    OwnedEntity = ident("OwnedEntity" & name.strVal)
    destroyProc = ident("=destroy").globalName(global)
    copyProc = ident("=copy").globalName(global)
    getProc = ident("get").globalName(global)
    newOwnedEntityProc = ident("newOwnedEntity").globalName(global)
    printEntityCountProc = ident("printEntityCount").globalName(global)
  if global:
    result = genAst(name, OwnedEntity):
      type OwnedEntity* = object
        e: Entity[name]
  else:
    result = genAst(name, OwnedEntity):
      type OwnedEntity = object
        e: Entity[name]
  
  result = genAst(name, definition=result, OwnedEntity, destroyProc, copyProc, 
      getProc, newOwnedEntityProc, printEntityCountProc):
    definition
      
    proc destroyProc(e: var OwnedEntity) =
    # echo "destroying"
      if e.e.world != nil:
        delete[name](e.e)
    proc copyProc(dest: var OwnedEntity; source: OwnedEntity) {.error.}
    proc getProc(e: OwnedEntity): Entity[name] {.inline.} = e.e
    proc newOwnedEntityProc(w: name): OwnedEntity {.inline.} = OwnedEntity(e: w.newEntity())

    proc printEntityCountProc(w: name) {.inline.} =
      echo "entityCount=", w.entities.len - w.entityFreeList.len

proc genWorldProc(name: NimNode, list: NimNode, global: bool): NimNode {.compileTime.} =
  var internal = WorldInternalData(
    components: initTable[string, ComponentData](),
    tags: initTable[string, TagData](),
    filters: @[]
  )

  if list != nil:
    list.expectKind nnkStmtList
    for child in list:
      child.expectKind nnkCall
      child.expectLen 2
      child[0].expectKind nnkIdent
      child[1].expectKind nnkStmtList
      if child[0].eqIdent "components":
        for l in child[1]:
          l.expectKind nnkInfix
          l.expectLen 3
          l[0].expectIdent "as"
          let (typeName, convert) = (if l[1].kind == nnkCall:
            l[1].expectLen 2
            l[1][0].expectKind nnkIdent
            (l[1][0].strVal, l[1][1])
          else:
            l[1].expectKind nnkIdent
            (l[1].strVal, nil)
          )
          
          let (alias, isRare) = (if l[2].kind == nnkCommand:
            l[2].expectLen 2
            l[2][0].expectKind nnkIdent
            l[2][1].expectKind nnkPar
            l[2][1].expectLen 1
            l[2][1][0].expectIdent "rare"
            (l[2][0].strVal, true)
          else:
            l[2].expectKind nnkIdent
            (l[2].strVal, false)
          )
          internal.components[typeName] = ComponentData(
            typeName: typeName,
            convert: convert,
            alias: alias,
            isRare: isRare)
      elif child[0].eqIdent "tags":
        for l in child[1]:
          let (typeName, isRare) = (if l.kind == nnkCommand:
            l.expectLen 2
            l[0].expectKind nnkIdent
            l[1].expectKind nnkPar
            l[1].expectLen 1
            l[1][0].expectIdent "rare"
            (l[0].strVal, true)
          else:
            l.expectKind nnkIdent
            (l.strVal, false)
          )
          internal.tags[typeName] = TagData(typeName: typeName, isRare: isRare)
      elif child[0].eqIdent "filters":
        for line in child[1]:
          line.expectKind nnkInfix
          line.expectLen 3
          line[0].expectIdent "as"
          line[2].expectKind nnkIdent
          if line[1].kind == nnkIdent:
            internal.filters.add Filter(
              whiteList: @[line[1].strVal],
              blackList: @[],
              alias: line[2].strVal)
          else:
            line[1].expectKind nnkTupleConstr
            var whiteList: seq[string] = @[]
            var blackList: seq[string] = @[]
            for t in line[1]:
              if t.kind == nnkPrefix:
                t[0].expectIdent "not"
                t[1].expectKind nnkIdent
                blackList.add t[1].strVal
              else:
                t.expectKind nnkIdent
                whiteList.add t.strVal
            internal.filters.add Filter(
              whiteList: whiteList,
              blackList: blackList,
              alias: line[2].strVal)
      else:
        error("Can only have components and filters specifications in the ECS description", child[0])

  for c in internal.components.values:
    if not c.isRare:
      internal.bitarrayNames.add c.typeName
  for t in internal.tags.values:
    if not t.isRare:
      internal.bitarrayNames.add t.typeName

  internal.bitArraySize = internal.bitarrayNames.len

  let worldDef = defineWorld(name, internal, global)
  let worldConstDef = defineWorldConstructor(name, internal, global)
  let worldAddComponentDef = defineAddComponent(name, internal, global)
  let componentGettersDef = defineComponentGetters(name, internal, global)
  result = newStmtList(
    nnkTypeSection.newTree(worldDef),
    worldConstDef
  )
  for n in worldAddComponentDef:
    result.add n
  for n in componentGettersDef:
    result.add n
  result.add defineHas(name, internal, global)
  result.add defineDelete(name, internal, global)
  result.add defineOwned(name, internal, global)
  result.add defineQuery(name, internal, global)

macro genWorld*(name: untyped, list: untyped = nil): untyped =
  genWorldProc(name, list, false)
macro genWorldGlobal*(name: untyped, list: untyped = nil): untyped =
  genWorldProc(name, list, true)

macro genTagTypes*(body: varargs[untyped]): untyped =
  result = newStmtList()
  for b in body:
    b.expectKind nnkIdent
    result.add quote do:
      when not declared(`b`):
        type `b` = object

macro genTagTypesGlobal*(body: varargs[untyped]): untyped =
  result = newStmtList()
  for b in body:
    b.expectKind nnkIdent
    result.add quote do:
      when not declared(`b`):
        type `b`* = object

macro printMacros*(body: typed) = echo body.toStrLit

when isMainModule:
  dumpTree:
    components:
      Position(Vector) as pos (rare)
      Velocity(Vector) as vel
    tags:
      Tag (rare)
    filters:
      (Position, not Velocity)
  dumpAstGen:
    a and b and c and d

  type
    Vector = object
      x, y: int
    Position = distinct Vector
    Velocity = distinct Vector
    Rare1 = object
      data: string
    Rare2 = object
      data: string

  printMacros:
    genWorld World:
      components:
        Position(Vector) as pos
        Velocity(Vector) as vel
        Rare1 as rare1 (rare)
        Rare2 as rare2 (rare)
      tags:
        RareTag (rare)
      filters:
        (Position, Velocity) as Movable
        (Position, not Velocity) as Stationary
        Rare1 as Rare1
        (Rare1, Rare2) as DoubleRare
        (Rare1, not Rare2) as Only1
        (Position, Rare1) as PositionRare1
        (Position, not Rare2) as PositionNotRare2

        (Rare1, Rare2, RareTag) as TripleRare
        (Position, RareTag) as PositionTagged
        (Position, not RareTag) as PositionNotTagged
        (Position, not RareTag, Rare1) as PositionNotTaggedRare1
    genTagTypes RareTag

  genWorldGlobal TestWorld:
    components:
      Position as pos

  type MaybeOwned = object
    case owned: bool:
    of true: e: OwnedEntityTestWorld
    of false: discard

  proc f(o: sink MaybeOwned) =
    discard