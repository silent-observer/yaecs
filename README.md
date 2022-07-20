# Yet Another Entity Component System (yaecs)
**YAECS** is a simple ECS library for Nim, written specifically for my
[Nickel](https://github.com/silent-observer/nickel) game engine.
YAECS is still very much WIP, so lots of changes are to be expected.

It's main idea is generating the whole ECS using a single macro, which lists all the components and
tags and filters used in the ECS.

Features:
- *Components* are arbitrary Nim types (please don't put recursive data structures in there).
- *Entities* are simple IDs, to which components are attached to.
- All the entities are contained in *worlds* - separate instances of a ECS. You can define many
  of them and nothing bad will happen.
- Systems are implemented using *queries*, which are iterators of entities in the world, that fit
  a specific *filter*. Filters can have white-listed components (components entity must have to
  be included in the query) and black-listed components (components entity must *not* have).
  All the used filters have to be declared beforehand in the macro to define the query procedures.
- All the component data is pooled and the components of the entites are stored as a combination of
  a bitarray and a sparse array.
- *Tags* are like components, but they don't have any data. You can attach a tag to an entity and
  remove it very easily, and tags can also be used in filters.
- Both tags and components can be *rare*, meaning that there will be optimizations in place for
  components and tags that only a few entities have at every single time. For example, in most games
  there won't be thousands of players at the same time, so `Player` component can be made rare.
  Rare tags and components are stored in a simple list instead of using space in the bitarray, which
  speeds up all the queries for filters containing them. Note that queries that black-list rare 
  components are actually a bit slower than queries that black-list regular ones.
- *Owned entities* are like `unique_ptr`s in C++. You can have an owned reference to the entity that
  will be deleted from the ECS once the garbage collector deletes it. If you are using the Nim's ORC
  GC (as is recommended for this), it means it is deleted from the basically immediately after the
  variable containing it goes out of scope, just as in C++.