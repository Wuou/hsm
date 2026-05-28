//
//  StateMachine.swift
//  hsm
//
//  Created by wuou on 2026/5/28.
//

import Foundation
 
/// 简单的断言辅助方法
func assertThat(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if !condition {
        print("❌ 断言失败 [\(file):\(line)]: \(message)")
    } else {
        print("✅ 断言通过: \(message)")
    }
}

/// 监听状态机生命周期的委托
class TestDelegate: StateMachineDelegate {
    var transitionLog: [(from: String?, to: String?)] = []
    var errorLog: [StateMachineError] = []
    var didStop = false
    
    func stateMachine(_ stateMachine: StateMachine, didTransitionFrom fromState: State?, to toState: State?, by event: EventProtocol?) {
        transitionLog.append((from: fromState?.name, to: toState?.name))
        print("   🔄 转换: \(fromState?.name ?? "nil") -> \(toState?.name ?? "nil") (事件: \(event?.eventType.identifier ?? "completion"))")
    }

    func stateMachineDidStart(_ stateMachine: StateMachine) { print("   🟢 状态机启动") }
    func stateMachineDidStop(_ stateMachine: StateMachine) { didStop = true; print("   🔴 状态机停止") }
    func stateMachine(_ stateMachine: StateMachine, didFailWithError error: StateMachineError) {
        errorLog.append(error)
        print("   ⚠️ 错误: \(error.localizedDescription)")
    }

    func stateMachine(_ stateMachine: StateMachine, willProcessEvent event: EventProtocol) {}
    func stateMachine(_ stateMachine: StateMachine, didProcessEvent event: EventProtocol, handled: Bool) {}
}

// ============================================================================

// MARK: - 核心功能测试函数

// ============================================================================

func testSimpleTransition() {
    print("\n=== 测试: 基础状态与转换 ===")
    let sm = StateMachine(name: "SimpleSM")
    let region = Region(name: "R1")
    sm.addRegion(region)
    
    let initial = InitialPseudostate(name: "Init")
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    
    region.addVertex(initial)
    region.addVertex(s1)
    region.addVertex(s2)
    
    initial.addTransition(to: s1)
    s1.addTransition(to: s2, trigger: Trigger(eventType: EventType("E1")))
    
    let delegate = TestDelegate()
    sm.delegate = delegate
    sm.start()
    
    assertThat(sm.getActiveStateConfiguration().leafStates.first?.name == "S1", "初始转换应到达 S1")
    
    sm.post(event: TestEvent("E1"))
    assertThat(sm.getActiveStateConfiguration().leafStates.first?.name == "S2", "触发 E1 后应到达 S2")
}

func testGuardCondition() {
    print("\n=== 测试: 守卫条件 ===")
    let sm = StateMachine(name: "GuardSM")
    let region = Region(name: "R1")
    sm.addRegion(region)
    
    let initial = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    let s3 = SimpleState(name: "S3")
    
    region.addVertex(initial); region.addVertex(s1); region.addVertex(s2); region.addVertex(s3)
    initial.addTransition(to: s1)
    
    let e1 = Trigger(eventType: EventType("E1"))
    let guardFalse = AnyGuard<StateMachineContext> { _ in false }
    let guardTrue = AnyGuard<StateMachineContext> { _ in true }
    
    s1.addTransition(to: s2, trigger: e1, guardCondition: guardFalse)
    s1.addTransition(to: s3, trigger: e1, guardCondition: guardTrue)
    
    sm.start()
    sm.post(event: TestEvent("E1"))
    
    assertThat(sm.getActiveStateConfiguration().leafStates.first?.name == "S3", "应为守卫为 true 的分支 S3")
}

func testEntryExitActionsAndTransitionAction() {
    print("\n=== 测试: 动作执行顺序 ===")
    let sm = StateMachine(name: "ActionsSM")
    let region = Region(name: "R1")
    sm.addRegion(region)
    
    let initial = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    
    region.addVertex(initial); region.addVertex(s1); region.addVertex(s2)
    initial.addTransition(to: s1)
    
    var actionLog: [String] = []
    s1.onExit { _ in actionLog.append("ExitS1") }
    s2.onEntry { _ in actionLog.append("EntryS2") }
    
    let e1 = Trigger(eventType: EventType("E1"))
    s1.addTransition(to: s2, trigger: e1, action: AnyAction { _ in actionLog.append("TransAction") })
    
    sm.start()
    actionLog.removeAll() // 忽略启动时的动作
    
    sm.post(event: TestEvent("E1"))
    assertThat(actionLog == ["ExitS1", "TransAction", "EntryS2"], "动作顺序应为: ExitS1 -> TransAction -> EntryS2")
}

func testCompletionTransitionWithDoActivity() {
    print("\n=== 测试: 完成转换与 DoActivity ===")
    let sm = StateMachine(name: "CompletionSM")
    let region = Region(name: "R1")
    sm.addRegion(region)
    
    let initial = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    
    region.addVertex(initial); region.addVertex(s1); region.addVertex(s2)
    initial.addTransition(to: s1)
    
    // S1 执行 doActivity，完成后自动触发完成转换
    s1.onDo { _ in print("   ⏳ S1 doActivity 执行中...") }
    s1.completionTransition(to: s2)
    
    sm.start()
    assertThat(sm.getActiveStateConfiguration().leafStates.first?.name == "S1", "初始应处于 S1")
    
    // 等待异步 doActivity 完成
    Thread.sleep(forTimeInterval: 0.2)
    assertThat(sm.getActiveStateConfiguration().leafStates.first?.name == "S2", "DoActivity 完成后应自动转换到 S2")
}

func testFinalStateTerminatesRegion() {
    print("\n=== 测试: 终止状态 ===")
    let sm = StateMachine(name: "FinalSM")
    let region = Region(name: "R1")
    sm.addRegion(region)
    
    let initial = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let fin = FinalState(name: "Fin")
    
    region.addVertex(initial); region.addVertex(s1); region.addVertex(fin)
    initial.addTransition(to: s1)
    s1.addTransition(to: fin, trigger: Trigger(eventType: EventType("E1")))
    
    sm.start()
    sm.post(event: TestEvent("E1"))
    
    assertThat(region.isCompleted, "进入 FinalState 后，区域应标记为完成")
    assertThat(sm.getActiveStateConfiguration().leafStates.first?.name == "Fin", "应停留在 FinalState")
}

func testCompositeStateAndForkJoin() {
    print("\n=== 测试: 复合状态、正交区域与 Fork/Join ===")
    let sm = StateMachine(name: "OrthogonalSM")
    let region = Region(name: "R1")
    sm.addRegion(region)
    
    let initial = InitialPseudostate()
    let composite = CompositeState(name: "Composite")
    let s_end = SimpleState(name: "End")
    
    let r1 = Region(name: "R1_1"); let r2 = Region(name: "R1_2")
    composite.addRegion(r1); composite.addRegion(r2)
    
    let init_r1 = InitialPseudostate(); let a1 = SimpleState(name: "A1")
    r1.addVertex(init_r1); r1.addVertex(a1); init_r1.addTransition(to: a1)
    
    let init_r2 = InitialPseudostate(); let b1 = SimpleState(name: "B1")
    r2.addVertex(init_r2); r2.addVertex(b1); init_r2.addTransition(to: b1)
    
    region.addVertex(initial); region.addVertex(composite); region.addVertex(s_end)
    
    let fork = Fork(name: "Fork")
    region.addVertex(fork)
    initial.addTransition(to: fork)
    fork.addTransition(to: a1)
    fork.addTransition(to: b1)
    
    // 严格遵守 UML：Join 的入转换不能有 Trigger，必须用 Completion Transition
    let join = Join(name: "Join")
    region.addVertex(join)
    a1.completionTransition(to: join)
    b1.completionTransition(to: join)
    join.addTransition(to: s_end)
    
    // 通过日志验证并发过程，而不是通过断言
    a1.onEntry { _ in print("   🟢 进入 A1") }
    a1.onExit { _ in print("   🔴 退出 A1 (到达 Join 边界，等待 B1)") }
    a1.onDo { _ in
        print("   ⏳ A1 doActivity 执行中...")
        Thread.sleep(forTimeInterval: 0.1) // 模拟较短耗时
    }
    
    b1.onEntry { _ in print("   🟢 进入 B1") }
    b1.onExit { _ in print("   🔴 退出 B1 (到达 Join 边界，Join 汇合)") }
    b1.onDo { _ in
        print("   ⏳ B1 doActivity 执行中...")
        Thread.sleep(forTimeInterval: 0.3) // 模拟较长耗时，验证 Join 等待
    }
    
    sm.start()
    
    // 放弃中间状态的时序断言，等待足够时间后只验证最终汇合状态
    Thread.sleep(forTimeInterval: 0.5)
    
    // 只有当 A1 和 B1 都完成，Join 汇合成功，才会到达 End
    assertThat(sm.getActiveStateConfiguration().leafStates.first?.name == "End", "A1 和 B1 均完成，Join 汇合，应到达 End")
}

func testChoiceWithElse() {
    print("\n=== 测试: Choice 伪状态与 Else 守卫 ===")
    let sm = StateMachine(name: "ChoiceSM")
    let region = Region(name: "R1")
    sm.addRegion(region)
    
    let initial = InitialPseudostate(); let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2"); let s3 = SimpleState(name: "S3")
    let choice = Choice(name: "Choice")
    
    region.addVertex(initial); region.addVertex(s1); region.addVertex(s2); region.addVertex(s3); region.addVertex(choice)
    initial.addTransition(to: s1)
    
    let e1 = Trigger(eventType: EventType("E1"))
    s1.addTransition(to: choice, trigger: e1)
    
    let guardFalse = AnyGuard<StateMachineContext> { _ in false }
    choice.addTransition(to: s2, guardCondition: guardFalse)
    choice.addTransition(to: s3, isElse: true) // Else 分支
    
    sm.start()
    sm.post(event: TestEvent("E1"))
    
    assertThat(sm.getActiveStateConfiguration().leafStates.first?.name == "S3", "守卫均为 false，应走 Else 分支到达 S3")
}
 
func testDeepHistoryPseudostate() {
    print("\n=== 测试: 深历史伪状态 ===")
    let sm = StateMachine(name: "DeepHistorySM")
    let region = Region(name: "R1")
    sm.addRegion(region)
    
    let initial = InitialPseudostate(); let s_idle = SimpleState(name: "Idle"); let composite = CompositeState(name: "Comp")
    let s_error = SimpleState(name: "Error")
    
    let r1 = Region(name: "Comp_R1")
    let c_init = InitialPseudostate(); let c_s1 = SimpleState(name: "C_S1"); let c_s2 = SimpleState(name: "C_S2")
    r1.addVertex(c_init); r1.addVertex(c_s1); r1.addVertex(c_s2)
    c_init.addTransition(to: c_s1)
    composite.addRegion(r1)
    
    let deepHist = DeepHistory(name: "D_Hist")
    r1.addVertex(deepHist)
    deepHist.setDefaultTransition(c_init.addTransition(to: c_s1))
    
    region.addVertex(initial); region.addVertex(s_idle); region.addVertex(composite); region.addVertex(s_error)
    initial.addTransition(to: s_idle)
    
    let e_start = Trigger(eventType: EventType("START"))
    let e_next = Trigger(eventType: EventType("NEXT"))
    let e_fault = Trigger(eventType: EventType("FAULT"))
    let e_resume = Trigger(eventType: EventType("RESUME"))
    
    s_idle.addTransition(to: composite, trigger: e_start)
    c_s1.addTransition(to: c_s2, trigger: e_next)
    composite.addTransition(to: s_error, trigger: e_fault) // 中断
    s_error.addTransition(to: deepHist, trigger: e_resume) // 恢复到深历史
    
    sm.start()
    sm.post(event: TestEvent("START")) // Idle -> Comp(C_S1)
    sm.post(event: TestEvent("NEXT")) // Comp(C_S1 -> C_S2)
    sm.post(event: TestEvent("FAULT")) // Comp(C_S2) -> Error
    
    sm.post(event: TestEvent("RESUME")) // Error -> DeepHistory -> C_S2
    assertThat(sm.getActiveStateConfiguration().leafStates.first?.name == "C_S2", "深历史恢复应直接进入中断前的深层状态 C_S2")
}
 
func testDeferredEvent() {
    print("\n=== 测试: 延迟事件 ===")
    let sm = StateMachine(name: "DeferredSM")
    let region = Region(name: "R1")
    sm.addRegion(region)
    
    let e_def = EventType("E_DEF")
    
    let initial = InitialPseudostate(); let s1 = SimpleState(name: "S1"); let s2 = SimpleState(name: "S2")
    region.addVertex(initial); region.addVertex(s1); region.addVertex(s2)
    initial.addTransition(to: s1)
    
    s1.defer(e_def) // 在 S1 延迟 E_DEF
    
    let e_trigger = Trigger(eventType: EventType("E_TRIG"))
    s1.addTransition(to: s2, trigger: e_trigger)
    s2.addTransition(to: s1, trigger: Trigger(eventType: e_def)) // 离开S1后，E_DEF在S2被释放并导致转回S1
    
    var s2EntryCount = 0
    s2.onEntry { _ in s2EntryCount += 1 }
    
    sm.start()
    
    sm.post(event: TestEvent("E_DEF")) // 发送被延迟的事件
    assertThat(s2EntryCount == 0, "事件被延迟，不应触发 S2")
    
    sm.post(event: TestEvent("E_TRIG")) // 离开 S1，释放延迟事件
    assertThat(s2EntryCount == 1, "正常触发应到达 S2")
    
    // 等待延迟事件重新入队并被处理
    Thread.sleep(forTimeInterval: 0.1)
    assertThat(sm.getActiveStateConfiguration().leafStates.first?.name == "S1", "延迟事件在 S2 释放后应触发转换回 S1")
}
 
func testUnhandledEventError() {
    print("\n=== 测试: 运行时未处理事件错误 ===")
    let sm = StateMachine(name: "ErrorSM")
    let region = Region(name: "R1")
    sm.addRegion(region)
    
    let initial = InitialPseudostate(); let s1 = SimpleState(name: "S1")
    region.addVertex(initial); region.addVertex(s1)
    initial.addTransition(to: s1)
    
    let delegate = TestDelegate()
    sm.delegate = delegate
    sm.start()
    
    sm.post(event: TestEvent("UNHANDLED"))
    
    assertThat(delegate.errorLog.count == 1, "应触发一次错误回调")
    if case .unhandledEvent(let evt, _) = delegate.errorLog.first {
        assertThat(evt.eventType.identifier == "UNHANDLED", "错误事件类型应为 UNHANDLED")
    } else {
        assertThat(false, "错误类型应为 unhandledEvent")
    }
}

// ============================================================================

// MARK: - 执行所有测试

// ============================================================================

func runAllStateMachineTests1() {
    print("🚀 开始执行状态机功能测试...")
    testSimpleTransition()
    testGuardCondition()
    testEntryExitActionsAndTransitionAction()
    testCompletionTransitionWithDoActivity()
    testFinalStateTerminatesRegion()
    testCompositeStateAndForkJoin()
    testChoiceWithElse()
    testTerminatePseudostate()
    testDeepHistoryPseudostate()
    testInternalTransition()
    testDeferredEvent()
    testValidationConstraints()
    testUnhandledEventError()
    print("🎉 所有状态机功能测试执行完毕！")
}

// 直接调用即可运行
// runAllStateMachineTests()
