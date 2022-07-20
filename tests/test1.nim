# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest

import yaecs
test "empty world":
  genWorld World
  let w = newWorld(entityMaxCount=100_000)
  let 
    e1 = w.newEntity()
    e2 = w.newEntity()
    e3 = w.newEntity()
test "1 component":
  type Position = object
    x, y: int
  genWorld World:
    components:
      Position as pos
    filters:
      Position as Position
  let w = newWorld(entityMaxCount=100_000)
    
  let 
    e1 = w.newEntity()
    e2 = w.newEntity()
    e3 = w.newEntity()
  e1.add Position(x: 10, y: 20)
  e2.add Position(x: 30, y: 20)

  check e1.has Position
  check e2.has Position
  check not e3.has Position

  check e1.pos.x == 10
  check e1.pos.y == 20
  check e2.pos.x == 30
  check e2.pos.y == 20
  for e in w.queryPosition():
    if e.pos.x > 20:
      e.pos.x += 10
  
  check e1.pos.x == 10
  check e1.pos.y == 20
  check e2.pos.x == 40
  check e2.pos.y == 20
test "1 component deletion":
  type Position = object
    x, y: int
  genWorld World:
    components:
      Position as pos
  let w = newWorld(entityMaxCount=100_000)
  let 
    e1 = w.newEntity()
    e2 = w.newEntity()
  e1.add Position(x: 10, y: 20)
  e2.add Position(x: 30, y: 40)

  check e1.has Position
  check e2.has Position

  check e1.pos.x == 10
  check e1.pos.y == 20
  check e2.pos.x == 30
  check e2.pos.y == 40

  e2.delete()
  let e3 = w.newEntity()
  check not e3.has Position
  e3.add Position(x: 50, y: 60)
  check e1.pos.x == 10
  check e1.pos.y == 20
  check e3.pos.x == 50
  check e3.pos.y == 60

  e1.delete()
  let e4 = w.newEntity()
  check not e4.has Position
  e4.add Position(x: 70, y: 80)
  check e3.pos.x == 50
  check e3.pos.y == 60
  check e4.pos.x == 70
  check e4.pos.y == 80

test "2 components":
  type 
    Vector = object
      x, y: int
    Position = distinct Vector
    Velocity = distinct Vector

  genWorld World:
    components:
      Position(Vector) as pos
      Velocity(Vector) as vel
    filters:
      (Position, Velocity) as Movable
      (Position, not Velocity) as Stationary
  let w = newWorld(entityMaxCount=100_000)
  let 
    e1 = w.newEntity()
    e2 = w.newEntity()
    e3 = w.newEntity()
    e4 = w.newEntity()
  e1.add Vector(x: 10, y: 20).Position
  e1.add Vector(x: 1, y: 2).Velocity
  e2.add Vector(x: 30, y: 20).Position
  e3.add Vector(x: 30, y: 20).Position
  e3.add Vector(x: -1, y: 2).Velocity

  check e1.has Position
  check e1.has Velocity
  check e2.has Position
  check not e2.has Velocity
  check e3.has Position
  check e3.has Velocity
  check not e4.has Position
  check not e4.has Velocity

  check e1.pos == Vector(x: 10, y: 20)
  check e1.vel == Vector(x: 1, y: 2)
  check e2.pos == Vector(x: 30, y: 20)
  check e3.pos == Vector(x: 30, y: 20)
  check e3.vel == Vector(x: -1, y: 2)

  for e in w.queryMovable():
    e.pos.x += e.vel.x
    e.pos.y += e.vel.y
  
  check e1.pos == Vector(x: 11, y: 22)
  check e1.vel == Vector(x: 1, y: 2)
  check e2.pos == Vector(x: 30, y: 20)
  check e3.pos == Vector(x: 29, y: 22)
  check e3.vel == Vector(x: -1, y: 2)

  for e in w.queryStationary():
    e.pos.x += 100
  
  check e1.pos == Vector(x: 11, y: 22)
  check e1.vel == Vector(x: 1, y: 2)
  check e2.pos == Vector(x: 130, y: 20)
  check e3.pos == Vector(x: 29, y: 22)
  check e3.vel == Vector(x: -1, y: 2)

test "tags":
  type Position = object
    x, y: int
  type Velocity = object
    x, y: int
  genWorld World:
    components:
      Position as pos
      Velocity as vel
    tags:
      Red
      Blue
      Green
    filters:
      (Position, Velocity) as Movable
      (Position, not Velocity) as Stationary
      Red as Red
      (Red, Blue, Green) as Rgb
      (Position, Red) as PositionRed
      (Position, not Red) as PositionNotRed
      (Position, not Red, not Blue, not Green) as PositionNoColor
  genTagTypes Red, Green, Blue

  let w = newWorld(entityMaxCount=100_000)
  let es = w.newEntities(4)
  es[0].add Position(x: 1, y: 2)
  es[1].add Position(x: 1, y: 2)
  es[2].add Position(x: 1, y: 2)
  es[3].add Position(x: 1, y: 2)

  es[0].addRed()
  es[1].addRed()
  es[1].addBlue()
  es[1].addGreen()
  es[2].addGreen()

  for e in w.queryPositionRed():
    e.pos.x += 10
  check es[0].pos == Position(x: 11, y: 2)
  check es[1].pos == Position(x: 11, y: 2)
  check es[2].pos == Position(x: 1, y: 2)
  check es[3].pos == Position(x: 1, y: 2)

  for e in w.queryPositionNotRed():
    e.pos.y += 10
  check es[0].pos == Position(x: 11, y: 2)
  check es[1].pos == Position(x: 11, y: 2)
  check es[2].pos == Position(x: 1, y: 12)
  check es[3].pos == Position(x: 1, y: 12)

  for e in w.queryPositionNoColor():
    e.pos.y += 10
  check es[0].pos == Position(x: 11, y: 2)
  check es[1].pos == Position(x: 11, y: 2)
  check es[2].pos == Position(x: 1, y: 12)
  check es[3].pos == Position(x: 1, y: 22)

  for e in w.queryRgb():
    e.removeGreen()
  check not es[0].has Green
  check not es[1].has Green
  check es[2].has Green
  check not es[3].has Green

  for e in w.queryRed():
    e.addBlue()
  check es[0].has Blue
  check es[1].has Blue
  check not es[2].has Blue
  check not es[3].has Blue
test "5000 entities":
  type Position = object
    x, y: int
  type Velocity = object
    x, y: int
  genWorld World:
    components:
      Position as pos
      Velocity as vel
    filters:
      (Position, Velocity) as Movable
  
  let w = newWorld(entityMaxCount=100_000)
  let es = w.newEntities(5000)
  for i in 0..<5000:
    es[i].add Position(x: i, y: 0)
  for i in 0..<2500:
    es[i].add Velocity(x: 1, y: 2)
  
  for i in 1..100:
    for e in w.queryMovable():
      e.pos.x += e.vel.x
      e.pos.y += e.vel.y
  
  for i in 0..<2500:
    check es[i].pos == Position(x: i + 100, y: 200)
  for i in 2500..<5000:
    check es[i].pos == Position(x: i, y: 0)

test "rare components":
  type 
    Position = object
      x, y: int
    Velocity = object
      x, y: int
    Rare1 = object
      data: string
    Rare2 = object
      data: string
  
  #printMacros:
  genWorld World:
    components:
      Position as pos
      Velocity as vel
      Rare1 as rare1 (rare)
      Rare2 as rare2 (rare)
    tags:
      RareTag (rare)
    filters:
      Position as Position
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
  
  let w = newWorld(entityMaxCount=100_000)
  let es = w.newEntities(2000)
  for i in 0..<2000:
    es[i].add Position(x: i, y: 0)
  for i in 0..<2000:
    es[i].add Velocity(x: 1, y: 2)
  es[10].add Rare1(data: "Hello")
  es[20].add Rare1(data: "World")

  es[20].add Rare2(data: "Testing")
  es[30].add Rare2(data: "Testing")

  es[20].addRareTag()
  es[40].addRareTag()

  for e in w.queryRare1():
    e.rare1.data &= "!"

  check es[10].rare1.data == "Hello!"
  check es[20].rare1.data == "World!"

  for e in w.queryDoubleRare():
    e.rare1.data &= "!"
    e.rare2.data &= "!"

  check es[10].rare1.data == "Hello!"
  check es[20].rare1.data == "World!!"
  check es[20].rare2.data == "Testing!"
  check es[30].rare2.data == "Testing"

  for e in w.queryOnly1():
    e.rare1.data &= "?"
  check es[10].rare1.data == "Hello!?"
  check es[20].rare1.data == "World!!"

  for e in w.queryPositionRare1():
    e.pos.y = 100
  for i in 0..<2000:
    if i == 10 or i == 20:
      check es[i].pos == Position(x: i, y: 100)
    else:
      check es[i].pos == Position(x: i, y: 0)
  
  for e in w.queryPositionNotRare2():
    e.pos.y = 200
  for i in 0..<2000:
    if i == 20:
      check es[i].pos == Position(x: i, y: 100)
    elif i == 30:
      check es[i].pos == Position(x: i, y: 0)
    else:
      check es[i].pos == Position(x: i, y: 200)
  
  for e in w.queryPosition():
    e.pos.y = 0
  for i in 0..<2000:
    check es[i].pos == Position(x: i, y: 0)

  for e in w.queryTripleRare():
    e.rare1.data = "!!!"

  check es[10].rare1.data != "!!!"
  check es[20].rare1.data == "!!!"

  for e in w.queryPositionTagged():
    e.pos.y = 100
  for i in 0..<2000:
    if i == 20 or i == 40:
      check es[i].pos == Position(x: i, y: 100)
    else:
      check es[i].pos == Position(x: i, y: 0)

  for e in w.queryPositionNotTagged():
    e.pos.y += 100
  for i in 0..<2000:
    check es[i].pos == Position(x: i, y: 100)

  for e in w.queryPositionNotTaggedRare1():
    e.pos.y += 1000
  for i in 0..<2000:
    if i == 10:
      check es[i].pos == Position(x: i, y: 1100)
    else:
      check es[i].pos == Position(x: i, y: 100)

test "owned entities":
  type Destroyable = object
  var destroyCounter = 0

  proc `=destroy`(d: var Destroyable) =
    destroyCounter.inc

  genWorld World:
    components:
      Destroyable as pos
    filters:
      Destroyable as Destroyable
  let w = newWorld(entityMaxCount=100_000)
  check destroyCounter == 0
  block:
    let oe = w.newOwnedEntity()
    oe.get.add Destroyable()
  check destroyCounter == 1
  block:
    let oe = w.newOwnedEntity()
    oe.get.add Destroyable()
  check destroyCounter == 2