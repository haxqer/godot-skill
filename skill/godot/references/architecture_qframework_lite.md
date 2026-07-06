# QFramework Lite Architecture For Godot

Use this reference when a Godot task is about architecture design, modular
refactoring, feature slicing, or a request that mentions QFramework-style
Controller, System, Model, Utility, Command, Query, Event, DDD, CQRS, or
bindable state.

Keep the shell small. The value is in naming, dependency direction, and stable
module boundaries, not in recreating a giant framework inside Godot.

## Core Shape

Use this minimal shape:

- `Architecture`: composition root and service registry. In Godot this is often
  an autoload, a root service node, or a feature bootstrap script.
- `Controller`: scene scripts, input handlers, UI binding, and other
  presentation-edge code.
- `System`: reusable application workflows and orchestration shared by more than
  one controller or command.
- `Model`: domain state, invariants, collections, indexes, and repository-like
  ownership of data.
- `Utility`: persistence, file IO, HTTP, SDK, analytics, serialization, clock,
  RNG, and engine or platform adapters.
- `Command`: explicit write use case.
- `Query`: explicit side-effect-free read use case.
- `Event`: typed notification after a state change.
- `Bindable state`: signal-backed or observable state used for fine-grained UI
  synchronization.

## Dependency Direction

Respect these allowed directions:

| From | Allowed Dependencies | Notes |
| --- | --- | --- |
| `Controller` | `Command`, `Query`, `System`, `Model` reads, `Event` subscription | Read directly only when trivial. Write through commands or a narrow write API. |
| `Command` | `System`, `Model`, `Utility`, other `Command`, `Event` | Keep stateless. Represent a use case. |
| `System` | `System`, `Model`, `Utility`, `Event` | Coordinate reusable workflows. |
| `Model` | `Utility`, `Event` | Own state and invariants. Do not know about controllers. |
| `Utility` | external APIs only | Do not hold business policy. |
| `Query` | `Model`, `System` | Never mutate state. |

Enforce these prohibitions:

- Do not let a scene script mutate model or system state directly when the
  write path is non-trivial.
- Do not let `Utility` depend on `Controller`, `System`, or `Model`.
- Do not let `Query` trigger writes, signals, or hidden cache mutation unless
  the user explicitly accepts that tradeoff.
- Do not turn an autoload into a catch-all global mutable state manager.

## Godot Mapping

Map the architecture to Godot like this:

| This shape | Godot form |
| --- | --- |
| `Architecture` | autoload singleton, root bootstrap node, or feature composition script |
| `Controller` | scene root script, UI widget script, input coordinator, presentation node |
| `System` | autoload service, plain script service, domain workflow object |
| `Model` | `Resource`, plain script object, state-owning node, save-state facade |
| `Utility` | save service, HTTP client wrapper, SDK adapter, repo or serialization helper |
| `Command` | command object, use-case script, or narrow write service method |
| `Query` | query object, read service, or projection helper |
| `Event` | typed signal payload, event bus message, or C# event |

Use this placement rule:

- Put input handling, scene callbacks, node wiring, UI binding, animation
  triggers, and screen transitions in `Controller`.
- Put reusable gameplay or app workflows in `System`.
- Put state ownership and invariants in `Model`.
- Put infrastructure concerns in `Utility`.
- Put explicit writes in `Command`.
- Put non-trivial reads in `Query`.

When torn between `System` and `Model`, put invariants and owned state in
`Model`, and put orchestration plus cross-model coordination in `System`.

## CQRS And Event Rules

Apply CQRS with restraint:

- Put state changes behind `Command` when the write path is shared, validated,
  or likely to grow.
- Allow direct reads from a model only when the read is simple and local.
- Use `Query` when the read spans multiple models, needs aggregation, or would
  otherwise leak read logic into scene scripts.
- Return DTO-like dictionaries, resources, or small data structs from complex
  queries instead of exposing write-side state everywhere.

Prefer typed events by default.

Use events or signals when:

- a committed state change must notify other modules,
- a workflow should react without tight coupling,
- the sender should not know the receivers.

Emit events after the state change is already committed. Name them as completed
facts such as `inventory_item_added`, `quest_started`, or `ProfileSaved`.

Do not use events for ordinary parent-child synchronous calls.

## Module Recipe

Build each module in this order:

1. Name the bounded context by capability, not by scene name.
2. List write use cases as commands.
3. List read use cases as queries.
4. Identify the state owner for each piece of data.
5. Extract persistence or platform concerns into utilities.
6. Add only the systems required to coordinate shared workflows.
7. Add events only where decoupling pays for itself.

Use one architecture root per app, tool, or bounded context root. Register or
bootstrap models first, then systems, then utilities if the project needs a
formal startup sequence.

## Review Checklist

Review every module for these failure modes:

- A scene script writes directly into domain state and persistence in one
  method.
- An autoload owns business state that should live in a model.
- A utility contains business rules.
- A command stores long-lived mutable state.
- A query has side effects.
- Event names describe intentions instead of facts.
- Multiple scenes duplicate the same workflow because a system is missing.
- The project has a `GameManager`, `AppManager`, or `DataManager` catch-all.

## Output Standard

When asked to design or refactor, return:

- the bounded context name,
- the folder layout,
- the list of models, systems, commands, queries, utilities, and events,
- the dependency rationale,
- the code skeleton or concrete edits.
