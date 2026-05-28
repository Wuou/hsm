# 🚀 HSM.swift (Hierarchical State Machine)

[English](#english) | [中文版](#中文)

---

<a id="english"></a>
## English Version

A powerful, fully-featured, and type-safe Hierarchical State Machine (HSM) framework implemented in Swift. It strictly follows the UML state machine specification, supporting composite states, orthogonal (parallel) regions, deep/shallow history pseudostates, and Run-To-Completion (RTC) event processing.

### ✨ Features

- **UML Compliant**: Supports standard UML statechart concepts.
- **Hierarchical States**: Simple, Composite, and Sub-machine states.
- **Orthogonal Regions**: Parallel execution within composite states using Fork/Join synchronization.
- **Pseudostates**: Initial, Terminate, EntryPoint, ExitPoint, Choice, Junction, Fork, Join, Shallow History, and Deep History.
- **Run-To-Completion (RTC)**: Guaranteed RTC step execution with internal event queuing.
- **Event Deferral**: Defer unhandled events and release them when exiting specific states.
- **Type-safe Guards & Actions**: Using `AnyGuard` and `AnyAction` with `StateMachineContext`.
- **Asynchronous Do-Activities**: Supports long-running asynchronous tasks within states.
- **Builder Pattern**: Elegant DSL-like construction using `@resultBuilder` (`RegionBuilder`).
- **Delegate & Observability**: Rich delegate protocols for transitions, errors, and lifecycle events.
- **Runtime Context**: Powerful `StateMachineContext` for inspecting states, sending internal signals, and extracting event parameters.

