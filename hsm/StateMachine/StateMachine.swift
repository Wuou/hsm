//
//  StateMachine.swift
//  hsm
//
//  Created by wuou on 2026/5/28.
//

import Foundation
import os

// ============================================================================

// MARK: - 日志开关与工具

// ============================================================================
public enum StateMachineLogger {
    public static var isEnabled: Bool = true
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    public static func log(event: String, details: [String: Any]) {
        let timestamp = dateFormatter.string(from: Date())
        var logString = "[\(timestamp)] [\(event)]"
        for (key, value) in details {
            logString += " | \(key): \(value)"
        }
        print(logString)
    }

    public static func log(_ message: String, function: String = #function) {
        if isEnabled { print("[SM-DEBUG] \(function): \(message)") }
    }
}

// ============================================================================

// MARK: - 状态机委托协议

// ============================================================================
public protocol StateMachineDelegate: AnyObject {
    func stateMachine(_ stateMachine: StateMachine, didTransitionFrom fromState: State?, to toState: State?, by event: EventProtocol?)
    func stateMachineDidStart(_ stateMachine: StateMachine)
    func stateMachineDidComplete(_ stateMachine: StateMachine)
    func stateMachineDidStop(_ stateMachine: StateMachine)
    func stateMachine(_ stateMachine: StateMachine, didFailWithError error: StateMachineError)
    func stateMachine(_ stateMachine: StateMachine, willProcessEvent event: EventProtocol)
    func stateMachine(_ stateMachine: StateMachine, didProcessEvent event: EventProtocol, handled: Bool)
}

public extension StateMachineDelegate {
    func stateMachine(_ stateMachine: StateMachine, didTransitionFrom fromState: State?, to toState: State?, by event: EventProtocol?) {}
    func stateMachineDidStart(_ stateMachine: StateMachine) {}
    func stateMachineDidComplete(_ stateMachine: StateMachine) {}
    func stateMachineDidStop(_ stateMachine: StateMachine) {}
    func stateMachine(_ stateMachine: StateMachine, didFailWithError error: StateMachineError) {}
    func stateMachine(_ stateMachine: StateMachine, willProcessEvent event: EventProtocol) {}
    func stateMachine(_ stateMachine: StateMachine, didProcessEvent event: EventProtocol, handled: Bool) {}
}

// ============================================================================

// MARK: - 错误定义与处理策略

// ============================================================================
public enum StateMachineError: Error, LocalizedError {
    case validationError(String)
    case unhandledEvent(EventProtocol, StateConfiguration)
    case noEnabledChoice(String)
    case joinSyncError(String)
    case forkConstraintViolation(String)
    public var errorDescription: String? {
        switch self {
        case .validationError(let msg): return "状态机验证错误：\(msg)"
        case .unhandledEvent(let event, let config): return "运行时错误：事件 '\(event.eventType.identifier)' 在当前配置中未处理：\(config.activeStates.map { $0.name ?? "匿名状态" })"
        case .noEnabledChoice(let msg): return "运行时错误：选择/连接伪状态死锁 - \(msg)"
        case .joinSyncError(let msg): return "运行时错误：Join 伪状态同步错误 - \(msg)"
        case .forkConstraintViolation(let msg): return "运行时错误：Fork 伪状态约束违反 - \(msg)"
        }
    }
}

public enum ErrorHandlingStrategy {
    case assertionFailure
    case logWarning
    case customHandler((StateMachineError) -> Void)
}

// ============================================================================

// MARK: - 核心类型与协议

// ============================================================================
public protocol EventProtocol { var eventType: EventType { get } }
public struct EventType: Hashable, Equatable, CustomStringConvertible {
    public let identifier: String
    public init(_ identifier: String) { self.identifier = identifier }
    public var description: String { identifier }
}

public protocol TriggerProtocol { var eventType: EventType { get }
    func matches(_ event: EventProtocol) -> Bool
}

public struct Trigger: TriggerProtocol {
    public let eventType: EventType
    public init(eventType: EventType) { self.eventType = eventType }
    public func matches(_ event: EventProtocol) -> Bool { return event.eventType == eventType }
}

public protocol GuardProtocol { associatedtype Context
    func evaluate(in context: Context) -> Bool
}

public struct AnyGuard<Context> {
    private let _evaluate: (Context) -> Bool
    public init<G: GuardProtocol>(_ guard: G) where G.Context == Context { self._evaluate = { `guard`.evaluate(in: $0) } }
    public init(_ closure: @escaping (Context) -> Bool) { self._evaluate = closure }
    public func evaluate(in context: Context) -> Bool { return _evaluate(context) }
}

public protocol ActionProtocol { associatedtype Context
    func execute(in context: Context)
}

public struct AnyAction<Context> {
    private let _execute: (Context) -> Void
    public init<A: ActionProtocol>(_ action: A) where A.Context == Context { self._execute = { action.execute(in: $0) } }
    public init(_ closure: @escaping (Context) -> Void) { self._execute = closure }
    public func execute(in context: Context) { _execute(context) }
}

public struct StateCompletionEvent: EventProtocol {
    public let state: State
    public var eventType: EventType { return EventType("__completion__\(ObjectIdentifier(state).hashValue)__") }
    public init(state: State) { self.state = state }
}

public struct StateConfiguration {
    public let activeStates: [State]
    public init(states: [State]) { self.activeStates = states }
    public func contains(_ state: State) -> Bool { return activeStates.contains { $0 === state } }
    public var leafStates: [State] {
        return activeStates.filter { state in
            !activeStates.contains { potentialDescendant in
                potentialDescendant !== state && isAncestor(state, of: potentialDescendant)
            }
        }
    }

    private func isAncestor(_ potentialAncestor: State, of state: State) -> Bool {
        var current = state.parentRegion?.parentState
        while let parent = current {
            if parent === potentialAncestor { return true }
            current = parent.parentRegion?.parentState
        }
        return false
    }
}

public final class StateMachineContext {
    public weak var stateMachine: StateMachine?
    public internal(set) var currentEvent: EventProtocol?
    public var userInfo: [String: Any] = [:]
    public init(stateMachine: StateMachine) { self.stateMachine = stateMachine }
    public func eventParameter<T>(named name: String) -> T? {
        guard let event = currentEvent else { return nil }
        let mirror = Mirror(reflecting: event)
        for child in mirror.children {
            if child.label == name { return child.value as? T }
        }
        return nil
    }

    public func sendSignal(_ event: EventProtocol) { stateMachine?.post(event: event) }
    public func isInState(_ state: State) -> Bool { stateMachine?.getActiveStateConfiguration().contains(state) ?? false }
}

// ============================================================================

// MARK: - 顶点基类

// ============================================================================
public protocol VertexProtocol: AnyObject, CustomStringConvertible {
    var name: String? { get }
    var parentRegion: Region? { get set }
    var incomingTransitions: [Transition] { get set }
    var outgoingTransitions: [Transition] { get set }
}

open class Vertex: VertexProtocol {
    public let name: String?
    public weak var parentRegion: Region?
    public var incomingTransitions: [Transition] = []
    public var outgoingTransitions: [Transition] = []
    public init(name: String? = nil) { self.name = name }
    public var description: String { return name ?? "Anonymous\(type(of: self))" }
    @discardableResult
    public func addTransition(
        to target: Vertex, triggers: [Trigger] = [], guardCondition: AnyGuard<StateMachineContext>? = nil, isElse: Bool = false, action: AnyAction<StateMachineContext>? = nil
    ) -> Transition {
        let transition = Transition(source: self, target: target, triggers: triggers, guardCondition: guardCondition, isElse: isElse, action: action)
        outgoingTransitions.append(transition)
        target.incomingTransitions.append(transition)
        return transition
    }

    @discardableResult
    public func addTransition(
        to target: Vertex, trigger: Trigger, guardCondition: AnyGuard<StateMachineContext>? = nil, isElse: Bool = false, action: AnyAction<StateMachineContext>? = nil
    ) -> Transition {
        return addTransition(to: target, triggers: [trigger], guardCondition: guardCondition, isElse: isElse, action: action)
    }

    public var stateMachine: StateMachine? {
        var current: Vertex? = self
        while let vertex = current {
            if let region = vertex.parentRegion { return region.stateMachine }
            current = vertex.parentRegion?.parentState
        }
        return nil
    }
}

// ============================================================================

// MARK: - 状态类型

// ============================================================================
public protocol StateProtocol: VertexProtocol {
    var entryAction: AnyAction<StateMachineContext>? { get set }
    var exitAction: AnyAction<StateMachineContext>? { get set }
    var doActivity: AnyAction<StateMachineContext>? { get set }
    var deferredEvents: Set<EventType> { get set }
    var internalTransitions: [InternalTransition] { get set }
    func enter(context: StateMachineContext, skipSubregions: Bool, targetHint: Vertex?)
    func exit(context: StateMachineContext)
}

public struct InternalTransition {
    public let trigger: Trigger
    public let guardCondition: AnyGuard<StateMachineContext>?
    public let action: AnyAction<StateMachineContext>?
    public init(trigger: Trigger, guardCondition: AnyGuard<StateMachineContext>? = nil, action: AnyAction<StateMachineContext>? = nil) {
        self.trigger = trigger; self.guardCondition = guardCondition; self.action = action
    }
}

open class State: Vertex, StateProtocol {
    public var entryAction: AnyAction<StateMachineContext>?
    public var exitAction: AnyAction<StateMachineContext>?
    public var doActivity: AnyAction<StateMachineContext>?
    public var deferredEvents: Set<EventType> = []
    public var internalTransitions: [InternalTransition] = []
    public var doActivityTask: DispatchWorkItem?
    public internal(set) var isDoActivityCompleted: Bool = true
    public internal(set) var isActive: Bool = false
    
    open func enter(context: StateMachineContext, skipSubregions: Bool = false, targetHint: Vertex? = nil) {
        StateMachineLogger.log("🟢 进入状态: \(name ?? "匿名"), 跳过子区域: \(skipSubregions)")
        isActive = true
        isDoActivityCompleted = (doActivity == nil)
        if let entry = entryAction {
            StateMachineLogger.log("   ➡️ 执行 Entry 动作")
            entry.execute(in: context)
        }
        if let doAct = doActivity {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isActive else { return }
                StateMachineLogger.log("   ⚙️ 执行 Do Activity (异步): \(self.name ?? "匿名")")
                doAct.execute(in: context)
                guard self.isActive else { return }
                self.isDoActivityCompleted = true
                if let region = self.parentRegion { region.handleCompletion(for: self, context: context) }
            }
            doActivityTask = workItem
            DispatchQueue.global().async(execute: workItem)
        } else {
            if let region = parentRegion { region.handleCompletion(for: self, context: context) }
        }
    }
    
    open func exit(context: StateMachineContext) {
        StateMachineLogger.log("🔴 退出状态: \(name ?? "匿名")")
        isActive = false
        doActivityTask?.cancel()
        doActivityTask = nil
        if let exit = exitAction {
            StateMachineLogger.log("   ⬅️ 执行 Exit 动作")
            exit.execute(in: context)
        }
        if let sm = stateMachine { sm.releaseDeferredEvents(for: self) }
    }
    
    @discardableResult
    public func addInternalTransition(trigger: Trigger, guardCondition: AnyGuard<StateMachineContext>? = nil, action: AnyAction<StateMachineContext>? = nil) -> InternalTransition {
        let t = InternalTransition(trigger: trigger, guardCondition: guardCondition, action: action)
        internalTransitions.append(t); return t
    }
}

public final class SimpleState: State {}

public final class CompositeState: State {
    public private(set) var regions: [Region] = []
    private var entryPoints: [EntryPoint] = []
    private var exitPoints: [ExitPoint] = []
    public init(name: String? = nil, regions: [Region] = []) {
        super.init(name: name)
        self.regions = regions
        regions.forEach { $0.parentState = self }
    }

    public func addRegion(_ region: Region) { region.parentState = self; regions.append(region) }
    public var isOrthogonal: Bool { regions.count > 1 }
    public func addEntryPoint(_ ep: EntryPoint) { ep.parentState = self; entryPoints.append(ep) }
    public func addExitPoint(_ ep: ExitPoint) { ep.parentState = self; exitPoints.append(ep) }
    
    override public func enter(context: StateMachineContext, skipSubregions: Bool = false, targetHint: Vertex? = nil) {
        super.enter(context: context, skipSubregions: skipSubregions, targetHint: targetHint)
        if !skipSubregions {
            var resolvedTarget = targetHint
            
            if let pseudo = resolvedTarget as? Pseudostate, pseudo.kind == .entryPoint, pseudo.parentState === self, pseudo.parentRegion == nil {
                if let outTransition = pseudo.outgoingTransitions.first, let innerTarget = outTransition.target {
                    StateMachineLogger.log("   🔑 解析复合状态 EntryPoint: \(pseudo.name ?? "") -> \(innerTarget.name ?? "")")
                    resolvedTarget = innerTarget
                }
            }
            
            if let pseudo = resolvedTarget as? HistoryPseudostate {
                StateMachineLogger.log("   🔽 复合状态通过历史伪状态进入 (目标: \(pseudo.name ?? ""))")
                if let region = pseudo.parentRegion {
                    region.handlePseudostate(pseudo, context: context, incomingEvent: nil, incomingTransition: nil)
                }
                return
            }
            
            if let target = resolvedTarget {
                StateMachineLogger.log("   🔽 复合状态定向进入子区域 (目标: \(target.name ?? ""))")
                for region in regions {
                    var belongsToRegion = false
                    var currentRegion = target.parentRegion
                    while let r = currentRegion {
                        if r === region { belongsToRegion = true; break }
                        currentRegion = r.parentState?.parentRegion
                    }
                    if belongsToRegion {
                        region.enterVertex(target, context: context, event: nil, transition: nil, targetHint: target)
                    } else {
                        region.enterDefault(context: context)
                    }
                }
            } else {
                StateMachineLogger.log("   🔽 复合状态进入默认子区域")
                regions.forEach { $0.enterDefault(context: context) }
            }
        }
    }
    
    override public func exit(context: StateMachineContext) {
        StateMachineLogger.log("   🔼 复合状态退出所有子区域")
        regions.forEach { $0.exitAll(context: context) }
        super.exit(context: context)
    }
}

public final class SubmachineState: State {
    public let submachine: StateMachine
    public init(name: String? = nil, submachine: StateMachine) { self.submachine = submachine; super.init(name: name) }
    override public func enter(context: StateMachineContext, skipSubregions: Bool = false, targetHint: Vertex? = nil) {
        StateMachineLogger.log("🟢 进入状态: \(name ?? "匿名"), 跳过子区域: \(skipSubregions)")
        isActive = true
        isDoActivityCompleted = (doActivity == nil)
        if let entry = entryAction { StateMachineLogger.log("   ➡️ 执行 Entry 动作"); entry.execute(in: context) }
        StateMachineLogger.log("   🔄 启动子状态机: \(submachine.name ?? "匿名")")
        submachine.onCompletion = { [weak self] in
            guard let self = self, self.isActive else { return }
            StateMachineLogger.log("   ✅ 子状态机内部完成，触发外部 Completion")
            self.parentRegion?.handleCompletion(for: self, context: context)
        }
        submachine.start(in: context)
    }

    override public func exit(context: StateMachineContext) {
        isActive = false
        submachine.onCompletion = nil
        StateMachineLogger.log("   🛑 停止子状态机: \(submachine.name ?? "匿名")")
        submachine.stop()
        super.exit(context: context)
    }
}

public final class FinalState: State {
    override public init(name: String? = nil) { super.init(name: name) }
    override public func enter(context: StateMachineContext, skipSubregions: Bool = false, targetHint: Vertex? = nil) {
        StateMachineLogger.log("🛑 进入终态: \(name ?? "匿名")")
        entryAction?.execute(in: context)
        parentRegion?.notifyCompleted()
    }

    override public func exit(context: StateMachineContext) { exitAction?.execute(in: context) }
}

// ============================================================================

// MARK: - 伪状态

// ============================================================================
public enum PseudostateKind { case initial, terminate, entryPoint, exitPoint
    case choice, fork, join, junction
    case shallowHistory, deepHistory
}

open class Pseudostate: Vertex {
    public let kind: PseudostateKind
    public weak var parentState: CompositeState?
    public init(kind: PseudostateKind, name: String? = nil) { self.kind = kind; super.init(name: name) }
}

public final class InitialPseudostate: Pseudostate { public init(name: String? = nil) { super.init(kind: .initial, name: name) } }
public final class TerminatePseudostate: Pseudostate { public init(name: String? = nil) { super.init(kind: .terminate, name: name) } }
public final class EntryPoint: Pseudostate { public init(name: String? = nil) { super.init(kind: .entryPoint, name: name) } }
public final class ExitPoint: Pseudostate { public init(name: String? = nil) { super.init(kind: .exitPoint, name: name) } }
public final class Choice: Pseudostate {
    public init(name: String? = nil) { super.init(kind: .choice, name: name) }
    public func resolveTransition(context: StateMachineContext) -> Transition? {
        var elseTransition: Transition?
        for transition in outgoingTransitions {
            if transition.isElse { elseTransition = transition; continue }
            if transition.evaluateGuard(context: context) { return transition }
        }
        return elseTransition
    }
}

public final class Fork: Pseudostate { public init(name: String? = nil) { super.init(kind: .fork, name: name) } }
public final class Join: Pseudostate {
    private var receivedTransitions: Set<ObjectIdentifier> = []
    private let lock = NSLock()
    public init(name: String? = nil) { super.init(kind: .join, name: name) }
    public func markReceivedAndCheckCompletion(_ transition: Transition) -> Bool {
        lock.lock(); defer { lock.unlock() }
        receivedTransitions.insert(ObjectIdentifier(transition))
        let isComplete = receivedTransitions.count == incomingTransitions.count
        if isComplete { receivedTransitions.removeAll() }
        return isComplete
    }
}

public final class Junction: Pseudostate {
    public init(name: String? = nil) { super.init(kind: .junction, name: name) }
    public func selectTransition(context: StateMachineContext) -> Transition? {
        var elseTransition: Transition?
        for transition in outgoingTransitions {
            if transition.isElse { elseTransition = transition; continue }
            if transition.evaluateGuard(context: context) { return transition }
        }
        return elseTransition
    }
}

open class HistoryPseudostate: Pseudostate {
    public private(set) var defaultTransition: Transition?
    override public init(kind: PseudostateKind, name: String? = nil) { super.init(kind: kind, name: name) }
    public func setDefaultTransition(_ transition: Transition) { defaultTransition = transition }
}

public final class ShallowHistory: HistoryPseudostate {
    public init(name: String? = nil) { super.init(kind: .shallowHistory, name: name) }
    public func getMostRecentSubstate() -> State? { return parentRegion?.shallowHistoryState }
}

public final class DeepHistory: HistoryPseudostate { public init(name: String? = nil) { super.init(kind: .deepHistory, name: name) } }

// ============================================================================

// MARK: - 转换

// ============================================================================
public final class Transition: CustomStringConvertible {
    public weak var source: Vertex?
    public weak var target: Vertex?
    public let triggers: [Trigger]
    public let guardCondition: AnyGuard<StateMachineContext>?
    public let isElse: Bool
    public let action: AnyAction<StateMachineContext>?
    public init(source: Vertex, target: Vertex, triggers: [Trigger], guardCondition: AnyGuard<StateMachineContext>? = nil, isElse: Bool = false, action: AnyAction<StateMachineContext>? = nil) {
        self.source = source; self.target = target; self.triggers = triggers
        self.guardCondition = guardCondition; self.isElse = isElse; self.action = action
    }

    public func matchesTrigger(_ event: EventProtocol) -> Bool { if triggers.isEmpty { return false }; return triggers.contains { $0.matches(event) } }
    public func evaluateGuard(context: StateMachineContext) -> Bool {
        if isElse { return false }
        let result = guardCondition?.evaluate(in: context) ?? true
        StateMachineLogger.log("   🛡️ 守卫评估 (\(source?.name ?? "?")->\(target?.name ?? "?")): \(result)")
        return result
    }

    public var description: String {
        let sourceName = source?.name ?? "?"; let targetName = target?.name ?? "?"
        let trigStr = triggers.isEmpty ? "completion" : triggers.map { $0.eventType.identifier }.joined(separator: ",")
        return "\(sourceName) --[\(trigStr)]--> \(targetName)"
    }
}

// ============================================================================

// MARK: - 区域 (核心调度逻辑 - 终极优化版)

// ============================================================================
public final class Region: CustomStringConvertible, Hashable {
    public let name: String?
    public weak var parentState: CompositeState?
    public weak var stateMachine: StateMachine?
    public private(set) var vertices: [Vertex] = []
    private var _currentState: State?
    public var currentState: State? { lock.lock(); defer { lock.unlock() }; return _currentState }
    public private(set) var shallowHistoryState: State?
    public var isCompleted: Bool = false
    private let lock = NSLock()
    // 🌟 核心修复：恢复内部 RTC 队列，保证完成事件的同步级联消耗
    private var rtcLock = os_unfair_lock_s()
    private var rtcEventQueue: [EventProtocol] = []
    private var isProcessingRTC: Bool = false
    
    public init(name: String? = nil) { self.name = name }
    public var description: String { name ?? "Region" }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
    public static func == (lhs: Region, rhs: Region) -> Bool { lhs.name == rhs.name }
    
    public func addVertex(_ vertex: Vertex) {
        vertex.parentRegion = self
        vertices.append(vertex)
        if let pseudo = vertex as? Pseudostate, pseudo.parentState == nil { pseudo.parentState = parentState }
    }
    
    public func enterDefault(context: StateMachineContext) {
        StateMachineLogger.log("🔵 区域[\(name ?? "R")] 执行 enterDefault")
        guard let initial = vertices.first(where: { $0 is InitialPseudostate }) as? InitialPseudostate,
              let transition = initial.outgoingTransitions.first else { return }
        executeTransition(transition, context: context, event: nil)
    }
    
    private func findLCAState(source: State, target: Vertex) -> State? {
        var sourceAncestors: Set<ObjectIdentifier> = []
        var current: State? = source
        while let s = current {
            sourceAncestors.insert(ObjectIdentifier(s))
            current = s.parentRegion?.parentState
        }
        var targetAncestor: State? = target.parentRegion?.parentState
        while let t = targetAncestor {
            if sourceAncestors.contains(ObjectIdentifier(t)) { return t }
            targetAncestor = t.parentRegion?.parentState
        }
        return nil
    }
    
    public func executeTransition(_ transition: Transition, context: StateMachineContext, event: EventProtocol? = nil) {
        var transitionToExecute = transition
        var accumulatedActions: [AnyAction<StateMachineContext>] = []
        
        while let junction = transitionToExecute.target as? Junction {
            if let action = transitionToExecute.action { accumulatedActions.append(action) }
            if let nextTransition = junction.selectTransition(context: context) {
                transitionToExecute = nextTransition
            } else {
                StateMachineLogger.log("   ⛔ Junction 预评估失败，转换中止，源状态不退出")
                return
            }
        }
        
        if let finalAction = transitionToExecute.action { accumulatedActions.append(finalAction) }
        
        let isTermination = (transitionToExecute.target as? Pseudostate)?.kind == .terminate
        let target = transitionToExecute.target
        
        StateMachineLogger.log("🔄 执行转换: \(transitionToExecute.source?.name ?? "?") -> \(target?.name ?? "?"), 触发事件: \(event?.eventType.identifier ?? "无")")
        
        if let currentSourceState = currentState, let targetVertex = target, !isTermination {
            if !(targetVertex is Join) {
                let lcaState = findLCAState(source: currentSourceState, target: targetVertex)
                var stateToExit: State? = currentSourceState
                while let s = stateToExit, s !== lcaState {
                    s.parentRegion?.exitState(s, context: context)
                    stateToExit = s.parentRegion?.parentState
                }
            } else {
                exitState(currentSourceState, context: context)
            }
        }
        
        for action in accumulatedActions {
            StateMachineLogger.log("   ⚡ 执行转换动作")
            action.execute(in: context)
        }
        
        if let target = target {
            if target.parentRegion === self {
                enterVertex(target, context: context, event: event, transition: transitionToExecute)
            } else {
                handleCrossRegionTransition(target: target, context: context, event: event, transition: transitionToExecute)
            }
        }
    }
    
    public func enterVertex(_ vertex: Vertex, context: StateMachineContext, event: EventProtocol?, transition: Transition?, targetHint: Vertex? = nil) {
        if let state = vertex as? State { enterState(state, context: context, targetHint: targetHint) }
        else if let pseudo = vertex as? Pseudostate { handlePseudostate(pseudo, context: context, incomingEvent: event, incomingTransition: transition) }
    }
    
    private func handleCrossRegionTransition(target: Vertex, context: StateMachineContext, event: EventProtocol?, transition: Transition) {
        StateMachineLogger.log("🌉 触发跨区域转换，目标: \(target.name ?? "nil")")
        if let join = target as? Join {
            if join.markReceivedAndCheckCompletion(transition) {
                StateMachineLogger.log("   🔗 Join 同步完成，触发输出转换")
                if let outTransition = join.outgoingTransitions.first { join.parentRegion?.executeTransition(outTransition, context: context, event: event) }
            } else { StateMachineLogger.log("   ⏳ Join 等待其他入转换同步...") }
            return
        }
        
        if let composite = target.parentRegion?.parentState {
            if !composite.isActive {
                if let parentRegion = composite.parentRegion { parentRegion.enterState(composite, context: context, skipSubregions: false, targetHint: target) }
                else { enterState(composite, context: context, skipSubregions: false, targetHint: target) }
                return
            }
        }
        
        if let targetRegion = target.parentRegion, let current = targetRegion.currentState { targetRegion.exitState(current, context: context) }
        target.parentRegion?.enterVertex(target, context: context, event: event, transition: transition, targetHint: nil)
    }
    
    private func enterState(_ state: State, context: StateMachineContext, skipSubregions: Bool = false, targetHint: Vertex? = nil) {
        lock.lock(); _currentState = state; lock.unlock()
        StateMachineLogger.log("➡️ 区域[\(name ?? "R")] 设置当前状态: \(state.name ?? "nil") (跳过子区域: \(skipSubregions))")
        stateMachine?.invalidateConfigurationCache()
        state.enter(context: context, skipSubregions: skipSubregions, targetHint: targetHint)
        
        if state is FinalState {
            isCompleted = true
            if let parent = parentState, parent.regions.allSatisfy({ $0.isCompleted }) {
                StateMachineLogger.log("🏁 复合状态 \(parent.name ?? "匿名") 所有区域完成，发送完成事件")
                context.sendSignal(StateCompletionEvent(state: parent))
            }
        }
    }
    
    private func exitState(_ state: State, context: StateMachineContext) {
        StateMachineLogger.log("⬅️ 区域[\(name ?? "R")] 退出状态: \(state.name ?? "nil") | 更新浅历史为: \(state.name ?? "nil")")
        stateMachine?.invalidateConfigurationCache()
        state.exit(context: context)
        lock.lock(); shallowHistoryState = state; _currentState = nil; isCompleted = false; lock.unlock()
    }
    
    public func exitAll(context: StateMachineContext) { if let state = currentState { exitState(state, context: context) } }
    
    public func handleCompletion(for state: State, context: StateMachineContext) {
        StateMachineLogger.log("✅ 状态 \(state.name ?? "匿名") Do Activity 或隐式完成")
        if let comp = state as? CompositeState, !comp.regions.isEmpty {
            if comp.isDoActivityCompleted && comp.regions.allSatisfy({ $0.isCompleted }) {
                enqueueRTC(StateCompletionEvent(state: comp))
            } else { StateMachineLogger.log("   ⏳ 复合状态等待子区域完成或自身 Do Activity 完成") }
        } else { enqueueRTC(StateCompletionEvent(state: state)) }
    }
    
    private func enqueueRTC(_ event: EventProtocol) {
        os_unfair_lock_lock(&rtcLock)
        rtcEventQueue.append(event)
        let shouldStart = !isProcessingRTC
        os_unfair_lock_unlock(&rtcLock)
        if shouldStart { processRTCQueue() }
    }
    
    private func processRTCQueue() {
        os_unfair_lock_lock(&rtcLock)
        guard !isProcessingRTC else { os_unfair_lock_unlock(&rtcLock); return }
        isProcessingRTC = true
        os_unfair_lock_unlock(&rtcLock)
        
        while true {
            os_unfair_lock_lock(&rtcLock)
            guard !rtcEventQueue.isEmpty else { isProcessingRTC = false; os_unfair_lock_unlock(&rtcLock); break }
            let event = rtcEventQueue.removeFirst()
            os_unfair_lock_unlock(&rtcLock)
            
            guard let sm = stateMachine, let ctx = sm.context else {
                os_unfair_lock_lock(&rtcLock); isProcessingRTC = false; os_unfair_lock_unlock(&rtcLock); return
            }
            ctx.currentEvent = event
            let _ = processEventInRTC(event, context: ctx)
        }
    }
    
    public func processEventInRTC(_ event: EventProtocol, context: StateMachineContext) -> Bool {
        var handled = false
        if let compEvent = event as? StateCompletionEvent { if compEvent.state === currentState { checkCompletionTransition(for: compEvent.state, context: context); handled = true } }
        
        if let current = currentState {
            for internalTrans in current.internalTransitions {
                if internalTrans.trigger.matches(event) {
                    if internalTrans.guardCondition?.evaluate(in: context) ?? true {
                        StateMachineLogger.log("🔹 触发内部转换: 事件 \(event.eventType.identifier)")
                        internalTrans.action?.execute(in: context); return true
                    }
                }
            }
        }
        
        var childHandled = false
        if let composite = currentState as? CompositeState { for region in composite.regions {
            if region.processEventInRTC(event, context: context) { childHandled = true }
        } } else if let submachineState = currentState as? SubmachineState, submachineState.submachine.active { for region in submachineState.submachine.regions {
            if region.processEventInRTC(event, context: context) { childHandled = true }
        } }
        if childHandled { return true }
        
        if let current = currentState { handled = tryTransitions(current.outgoingTransitions, event: event, context: context) }
        
        if !handled {
            var isDeferred = false; var stateToDeferTo: State? = nil
            if let current = currentState, current.deferredEvents.contains(event.eventType) { isDeferred = true; stateToDeferTo = current }
            if !isDeferred, let current = currentState {
                var ancestor = current.parentRegion?.parentState
                while let parent = ancestor {
                    if parent.deferredEvents.contains(event.eventType) { isDeferred = true; stateToDeferTo = parent; break }
                    ancestor = parent.parentRegion?.parentState
                }
            }
            if isDeferred, let deferState = stateToDeferTo {
                StateMachineLogger.log("⏳ 事件 \(event.eventType.identifier) 被延迟 (由状态 \(deferState.name ?? "匿名") 延迟)")
                stateMachine?.deferEvent(event, for: deferState); return true
            }
        }
        return handled
    }
    
    private func checkCompletionTransition(for state: State, context: StateMachineContext) {
        guard state === currentState else { return }
        let completionTransitions = state.outgoingTransitions.filter { $0.triggers.isEmpty }
        guard !completionTransitions.isEmpty else { return }
        StateMachineLogger.log("🔔 检查到完成转换")
        for transition in completionTransitions {
            if transition.isElse || transition.evaluateGuard(context: context) { executeTransition(transition, context: context, event: nil); break }
        }
    }
    
    public func handlePseudostate(_ pseudo: Pseudostate, context: StateMachineContext, incomingEvent: EventProtocol?, incomingTransition: Transition?) {
        StateMachineLogger.log("🔶 处理伪状态: \(pseudo.name ?? "nil") (类型: \(pseudo.kind))")
        switch pseudo.kind {
        case .terminate: stateMachine?.terminate()
        case .choice:
            if let choice = pseudo as? Choice, let transition = choice.resolveTransition(context: context) {
                StateMachineLogger.log("   🔀 Choice 选中转换 -> \(transition.target?.name ?? "?")")
                executeTransition(transition, context: context, event: incomingEvent)
            } else {
                stateMachine?.handleError(.noEnabledChoice("Choice '\(pseudo.name ?? "")' 没有启用的转换 (Guard 死锁)"))
                stateMachine?.terminate()
            }
        case .fork:
            if let fork = pseudo as? Fork {
                let targets = fork.outgoingTransitions.compactMap { $0.target }
                guard let composite = targets.first?.parentRegion?.parentState else { stateMachine?.handleError(.forkConstraintViolation("Fork 的目标必须在同一个复合状态的不同区域中")); return }
                enterState(composite, context: context, skipSubregions: true)
                for region in composite.regions {
                    if let transition = fork.outgoingTransitions.first(where: { $0.target?.parentRegion === region }) { region.enterVertex(transition.target!, context: context, event: incomingEvent, transition: transition) } else { region.enterDefault(context: context) }
                }
            }
        case .join:
            if let join = pseudo as? Join, let transition = incomingTransition {
                if join.markReceivedAndCheckCompletion(transition) {
                    StateMachineLogger.log("   🔗 Join 同步完成，触发输出转换")
                    if let outTransition = join.outgoingTransitions.first { join.parentRegion?.executeTransition(outTransition, context: context, event: incomingEvent) }
                } else { StateMachineLogger.log("   ⏳ Join 等待其他入转换同步...") }
            }
        case .shallowHistory, .deepHistory:
            guard let composite = pseudo.parentState else { return }
            let isDeep = pseudo.kind == .deepHistory
            StateMachineLogger.log("   \(isDeep ? "⏪⏪深" : "⏪浅") 历史查找")
            for region in composite.regions {
                let historyState = region.shallowHistoryState ?? (pseudo as? HistoryPseudostate)?.defaultTransition?.target as? State ?? pseudo.outgoingTransitions.first?.target as? State
                if let state = historyState { if isDeep { region.enterDeepHistory(state: state, context: context) } else { region.enterState(state, context: context) } } else { region.enterDefault(context: context) }
            }
        case .junction:
            if let junction = pseudo as? Junction, let transition = junction.selectTransition(context: context) {
                StateMachineLogger.log("   🔀 Junction 选中转换 -> \(transition.target?.name ?? "?")")
                executeTransition(transition, context: context, event: incomingEvent)
            } else { stateMachine?.handleError(.noEnabledChoice("Junction '\(pseudo.name ?? "")' 没有启用的转换")) }
        case .entryPoint: if let transition = pseudo.outgoingTransitions.first { executeTransition(transition, context: context, event: incomingEvent) }
        case .exitPoint:
            if let transition = pseudo.outgoingTransitions.first {
                guard let composite = pseudo.parentState, let outerRegion = composite.parentRegion else { executeTransition(transition, context: context, event: incomingEvent); return }
                StateMachineLogger.log("   🚪 ExitPoint 跨区域跳出至区域[\(outerRegion.name ?? "R")]")
                outerRegion.executeTransition(transition, context: context, event: incomingEvent)
            } else {
                if parentState == nil, let sm = stateMachine { StateMachineLogger.log("   🚪 ExitPoint 到达顶层边界，触发状态机完成"); sm.onCompletion?(); sm.delegate?.stateMachineDidComplete(sm); sm.complete() }
            }
        default: break
        }
    }
    
    private func enterDeepHistory(state: State, context: StateMachineContext) {
        StateMachineLogger.log("   🏛️ 深历史递归进入: \(state.name ?? "nil")")
        enterState(state, context: context)
        guard let composite = state as? CompositeState else { return }
        for region in composite.regions {
            if let subHistoryState = region.shallowHistoryState { region.enterDeepHistory(state: subHistoryState, context: context) } else { region.enterDefault(context: context) }
        }
    }
    
    private func tryTransitions(_ transitions: [Transition], event: EventProtocol, context: StateMachineContext) -> Bool {
        var elseTransition: Transition? = nil
        for transition in transitions {
            guard !transition.triggers.isEmpty else { continue }
            if transition.matchesTrigger(event) {
                if transition.isElse { elseTransition = transition; continue }
                if transition.evaluateGuard(context: context) { executeTransition(transition, context: context, event: event); return true }
            }
        }
        if let elseTrans = elseTransition { executeTransition(elseTrans, context: context, event: event); return true }
        return false
    }
    
    public func notifyCompleted() {
        isCompleted = true
        if let parent = parentState {
            if parent.regions.allSatisfy({ $0.isCompleted }) {
                if parent.isDoActivityCompleted { parent.parentRegion?.handleCompletion(for: parent, context: context!) } else { StateMachineLogger.log("   ⏳ 复合状态子区域已全部完成，等待自身 Do Activity 完成") }
            }
        }
        if parentState == nil {
            if let sm = stateMachine, sm.regions.allSatisfy({ $0.isCompleted }) { StateMachineLogger.log("🏁 状态机所有区域已完成"); sm.onCompletion?(); sm.delegate?.stateMachineDidComplete(sm); sm.complete() }
        }
    }
    
    private var context: StateMachineContext? { stateMachine?.context }
}

// ============================================================================

// MARK: - 状态机核心类

// ============================================================================
public class StateMachine {
    public let name: String?
    public private(set) var regions: [Region] = []
    public var eventQueue: [EventProtocol] = []
    private var isProcessing: Bool = false
    private var isRunning: Bool = false
    private var isTerminated: Bool = false
    private let executionLock = NSLock()
    private let queueLock = NSLock()
    public private(set) var context: StateMachineContext!
    public weak var delegate: StateMachineDelegate?
    public var onCompletion: (() -> Void)?
    public var errorStrategy: ErrorHandlingStrategy = .logWarning
    private var deferredPool: [ObjectIdentifier: [EventProtocol]] = [:]
    private var cachedConfiguration: StateConfiguration?
    private var configVersion: Int = 0
    private var currentVersion: Int = 0
    
    public init(name: String? = nil) { self.name = name; self.context = StateMachineContext(stateMachine: self) }
    public func addRegion(_ region: Region) { region.stateMachine = self; regions.append(region) }
    
    public func start(in externalContext: StateMachineContext? = nil) {
        guard !isRunning, !isTerminated else { return }
        do { try validate() } catch { StateMachineLogger.log("❌ 状态机启动校验失败：\(error.localizedDescription)"); return }
        isRunning = true
        if let external = externalContext { context = external; external.stateMachine = self } else { context = StateMachineContext(stateMachine: self) }
        propagateStateMachineToRegions()
        StateMachineLogger.log("🚀 状态机启动: \(name ?? "匿名")")
        delegate?.stateMachineDidStart(self)
        regions.forEach { $0.enterDefault(context: context!) }
    }
    
    private func propagateStateMachineToRegions() {
        func configureRegion(_ region: Region) {
            region.stateMachine = self
            for vertex in region.vertices {
                if let composite = vertex as? CompositeState { for subRegion in composite.regions {
                    configureRegion(subRegion)
                } }
            }
        }
        for region in regions {
            configureRegion(region)
        }
    }
    
    public func stop() {
        guard isRunning else { return }
        StateMachineLogger.log("🛑 状态机停止: \(name ?? "匿名")")
        regions.forEach { $0.exitAll(context: context) }
        isRunning = false; invalidateConfigurationCache(); delegate?.stateMachineDidStop(self)
    }
    
    public func terminate() {
        guard isRunning else { return }
        StateMachineLogger.log("☠️ 状态机终止: \(name ?? "匿名")")
        isTerminated = true; isRunning = false; invalidateConfigurationCache(); delegate?.stateMachineDidStop(self)
    }
    
    func complete() {
        guard isRunning else { return }
        StateMachineLogger.log("✅ 状态机自然完成: \(name ?? "匿名")")
        isRunning = false; invalidateConfigurationCache()
    }
    
    public func post(event: EventProtocol) {
        queueLock.lock(); eventQueue.append(event); queueLock.unlock()
        processEventQueue()
    }
    
    private func processEventQueue() {
        executionLock.lock()
        guard !isProcessing, isRunning, !isTerminated else { executionLock.unlock(); return }
        isProcessing = true
        executionLock.unlock()
        
        while true {
            queueLock.lock()
            guard !eventQueue.isEmpty else { queueLock.unlock(); break }
            let batch = eventQueue; eventQueue.removeAll(); queueLock.unlock()
            
            for event in batch {
                executionLock.lock()
                guard isRunning else { executionLock.unlock(); break }
                executionLock.unlock()
                
                context.currentEvent = event
                delegate?.stateMachine(self, willProcessEvent: event)
                let oldConfig = getActiveStateConfiguration()
                var handled = false
                for region in regions {
                    if region.processEventInRTC(event, context: context) { handled = true }
                }
                delegate?.stateMachine(self, didProcessEvent: event, handled: handled)
                if handled {
                    let newConfig = getActiveStateConfiguration()
                    if let fromState = oldConfig.leafStates.first, let toState = newConfig.leafStates.first, fromState !== toState {
                        delegate?.stateMachine(self, didTransitionFrom: fromState, to: toState, by: event)
                    }
                } else if !(event is StateCompletionEvent) {
                    StateMachineLogger.log("⚠️ 事件未处理: \(event.eventType.identifier)")
                    handleError(.unhandledEvent(event, getActiveStateConfiguration()))
                }
            }
        }
        
        executionLock.lock()
        isProcessing = false
        executionLock.unlock()
    }
    
    func handleError(_ error: StateMachineError) {
        delegate?.stateMachine(self, didFailWithError: error)
        switch errorStrategy {
        case .assertionFailure: assertionFailure(error.localizedDescription)
        case .logWarning: StateMachineLogger.log("[警告] \(error.localizedDescription)")
        case .customHandler(let handler): handler(error)
        }
    }
    
    func deferEvent(_ event: EventProtocol, for state: State) {
        queueLock.lock()
        let key = ObjectIdentifier(state)
        deferredPool[key, default: []].append(event)
        queueLock.unlock()
    }
    
    func releaseDeferredEvents(for state: State) {
        queueLock.lock()
        let key = ObjectIdentifier(state)
        let toRelease = deferredPool.removeValue(forKey: key)
        queueLock.unlock()
        if let events = toRelease, !events.isEmpty {
            StateMachineLogger.log("   ⏳ 释放延迟事件池 (状态: \(state.name ?? "匿名"))，事件数: \(events.count)")
            events.forEach { post(event: $0) }
        }
    }
    
    func invalidateConfigurationCache() { currentVersion += 1 }
    
    public func getActiveStateConfiguration() -> StateConfiguration {
        if let cached = cachedConfiguration, configVersion == currentVersion { return cached }
        var states: [State] = []
        for region in regions {
            if let current = region.currentState { states.append(current); states.append(contentsOf: getSubstates(from: current)) }
        }
        let config = StateConfiguration(states: states)
        cachedConfiguration = config; configVersion = currentVersion; return config
    }
    
    private func getSubstates(from state: State) -> [State] {
        guard let composite = state as? CompositeState else { return [] }
        var substates: [State] = []
        for region in composite.regions {
            if let current = region.currentState { substates.append(current); substates.append(contentsOf: getSubstates(from: current)) }
        }
        return substates
    }
    
    public var active: Bool { isRunning && !isTerminated }
    
    public func validate() throws {
        var errors: [String] = []
        func validateRegion(_ region: Region) {
            let initials = region.vertices.filter { $0 is InitialPseudostate }
            if initials.count > 1 { errors.append("区域 '\(region.name ?? "未命名")' 有多个初始伪状态") }
            for vertex in region.vertices {
                if let final = vertex as? FinalState, !final.outgoingTransitions.isEmpty { errors.append("终止状态 '\(final.name ?? "未命名")' 不能有出转换") }
                if let join = vertex as? Join, join.incomingTransitions.isEmpty { errors.append("Join '\(join.name ?? "未命名")' 必须有入转换") }
                if let fork = vertex as? Fork { for t in fork.outgoingTransitions {
                    if !t.triggers.isEmpty || t.guardCondition != nil { errors.append("Fork '\(fork.name ?? "未命名")' 的出转换不能有触发器或守卫") }
                } }
                if let initial = vertex as? InitialPseudostate, let t = initial.outgoingTransitions.first { if !t.triggers.isEmpty || t.guardCondition != nil { errors.append("初始伪状态 '\(initial.name ?? "未命名")' 的出转换不能有触发器或守卫") } }
                if let history = vertex as? HistoryPseudostate, history.outgoingTransitions.count > 1 { errors.append("历史伪状态 '\(history.name ?? "未命名")' 最多一条出转换") }
                if let composite = vertex as? CompositeState { composite.regions.forEach { validateRegion($0) } }
            }
        }
        regions.forEach { validateRegion($0) }
        if !errors.isEmpty { throw StateMachineError.validationError(errors.map { "\($0)" }.joined(separator: "\n")) }
    }
}

// ============================================================================

// MARK: - 构建器与扩展

// ============================================================================
public final class StateMachineBuilder {
    private let stateMachine: StateMachine
    public init(name: String? = nil) { self.stateMachine = StateMachine(name: name) }
    @discardableResult
    public func region(_ name: String? = nil, @RegionBuilder _ builder: () -> [Vertex]) -> StateMachineBuilder {
        let region = Region(name: name); builder().forEach { region.addVertex($0) }; stateMachine.addRegion(region); return self
    }

    public func build() throws -> StateMachine { try stateMachine.validate(); return stateMachine }
}

@resultBuilder
public struct RegionBuilder { public static func buildBlock(_ components: Vertex...) -> [Vertex] { return components } }

public extension State {
    @discardableResult func onEntry(_ action: @escaping (StateMachineContext) -> Void) -> Self { entryAction = AnyAction(action); return self }
    @discardableResult func onExit(_ action: @escaping (StateMachineContext) -> Void) -> Self { exitAction = AnyAction(action); return self }
    @discardableResult func onDo(_ activity: @escaping (StateMachineContext) -> Void) -> Self { doActivity = AnyAction(activity); return self }
    @discardableResult func `defer`(_ eventType: EventType) -> Self { deferredEvents.insert(eventType); return self }
}

public extension Vertex {
    @discardableResult func transition(to target: Vertex, on trigger: Trigger, guard guardCondition: AnyGuard<StateMachineContext>? = nil, isElse: Bool = false, action: AnyAction<StateMachineContext>? = nil) -> Transition {
        return addTransition(to: target, trigger: trigger, guardCondition: guardCondition, isElse: isElse, action: action)
    }

    @discardableResult func completionTransition(to target: Vertex, guard guardCondition: AnyGuard<StateMachineContext>? = nil, action: AnyAction<StateMachineContext>? = nil) -> Transition {
        return addTransition(to: target, triggers: [], guardCondition: guardCondition, action: action)
    }
}
