import Foundation

// ============================================================================

// MARK: - 测试辅助工具

// ============================================================================

struct TestEvent: EventProtocol {
    let eventType: EventType
    init(_ id: String) { self.eventType = EventType(id) }
    init(_ trigger: Trigger) { self.eventType = trigger.eventType }
}

func SMAssert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition { print("✅ 通过: \(message)") }
    else { print("❌ 失败: \(message) (文件: \(file.split(separator: "/").last ?? ""), 行: \(line))") }
}

// ============================================================================

// MARK: - 测试用例

// ============================================================================

func testBasicTransition() {
    print("\n--- 测试：基础状态与转换 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "Basic")
    let r = Region(name: "R1")
    let initP = InitialPseudostate(name: "Init")
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: s2, trigger: e1)
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.getActiveStateConfiguration().contains(s1), "初始应进入S1")
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(s2), "E1触发后应进入S2")
}

func testGuardAndChoice() {
    print("\n--- 测试：守卫条件与 Choice ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "Choice")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let choice = Choice(name: "C1")
    let s2 = SimpleState(name: "S2")
    let s3 = SimpleState(name: "S3")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: choice, trigger: e1)
    choice.addTransition(to: s2, guardCondition: AnyGuard { $0.userInfo["flag"] as? Bool == true })
    choice.addTransition(to: s3, isElse: true)
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(choice); r.addVertex(s2); r.addVertex(s3)
    sm.addRegion(r)
    
    // 测试 Else 分支
    sm.start()
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(s3), "守卫失败应走Else进入S3")
    
    // 测试 Guard True 分支
    sm.stop()
    sm.start()
    sm.context.userInfo["flag"] = true // 修复：在 start 之后设置，防止 context 被重置清空
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(s2), "守卫成功应进入S2")
}

func testJunction() {
    print("\n--- 测试：Junction 伪状态 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "Junction")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let j1 = Junction(name: "J1")
    let s2 = SimpleState(name: "S2")
    let s3 = SimpleState(name: "S3")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: j1, trigger: e1)
    j1.addTransition(to: s2, guardCondition: AnyGuard { $0.userInfo["jflag"] as? Bool == true })
    j1.addTransition(to: s3, isElse: true)
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(j1); r.addVertex(s2); r.addVertex(s3)
    sm.addRegion(r)
    sm.start()
    
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(s3), "Junction 应走 Else 分支进入 S3")
}

func testActionsOrder() {
    print("\n--- 测试：动作执行顺序 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "Actions")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: s2, trigger: e1, action: AnyAction { $0.userInfo["log"] = ($0.userInfo["log"] as? String ?? "") + "T|" })
    
    s1.onEntry { $0.userInfo["log"] = ($0.userInfo["log"] as? String ?? "") + "E1|" }
    s1.onExit { $0.userInfo["log"] = ($0.userInfo["log"] as? String ?? "") + "X1|" }
    s2.onEntry { $0.userInfo["log"] = ($0.userInfo["log"] as? String ?? "") + "E2|" }
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.context.userInfo["log"] as? String == "E1|", "初始进入S1应执行Entry")
    sm.post(event: TestEvent(e1))
    SMAssert(sm.context.userInfo["log"] as? String == "E1|X1|T|E2|", "动作执行顺序应为：Exit1 -> TransitionAction -> Entry2")
}

func testInternalTransition() {
    print("\n--- 测试：内部转换 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    let sm = StateMachine(name: "Internal")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: s2, trigger: e1)
    s1.addInternalTransition(trigger: e2, action: AnyAction { $0.userInfo["internal"] = true })
    s1.onExit { $0.userInfo["exit_called"] = true }
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2)
    sm.addRegion(r)
    sm.start()
    
    sm.post(event: TestEvent(e2))
    SMAssert(sm.getActiveStateConfiguration().contains(s1), "内部转换不应改变状态")
    SMAssert(sm.context.userInfo["internal"] as? Bool == true, "内部转换动作应执行")
    SMAssert(sm.context.userInfo["exit_called"] == nil, "内部转换不应触发Exit动作")
    
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(s2), "外部转换应正常触发")
}

func testDeferredEvents() {
    print("\n--- 测试：延迟事件 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    let sm = StateMachine(name: "Deferred")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1").defer(e2.eventType)
    let s2 = SimpleState(name: "S2")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: s2, trigger: e1)
    s2.addInternalTransition(trigger: e2, action: AnyAction { $0.userInfo["e2_handled"] = true })
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2)
    sm.addRegion(r)
    sm.start()
    
    sm.post(event: TestEvent(e2))
    SMAssert(sm.context.userInfo["e2_handled"] == nil, "E2 应在 S1 被延迟，不执行")
    
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(s2), "应进入S2")
    SMAssert(sm.context.userInfo["e2_handled"] as? Bool == true, "E2 应在离开 S1 后被释放并在 S2 处理")
}

func testForkAndJoin() {
    print("\n--- 测试：正交状态与 Fork/Join ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    
    let sm = StateMachine(name: "ForkJoin")
    let rMain = Region(name: "RMain")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let fork = Fork(name: "F1")
    
    let comp = CompositeState(name: "Comp", regions: [Region(name: "R_A"), Region(name: "R_B")])
    let sA1 = SimpleState(name: "SA1")
    comp.regions[0].addVertex(sA1)
    let sB1 = SimpleState(name: "SB1")
    comp.regions[1].addVertex(sB1)
    
    let join = Join(name: "J1")
    let sEnd = SimpleState(name: "End")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: fork, trigger: e1)
    fork.addTransition(to: sA1)
    fork.addTransition(to: sB1)
    
    // 修复：去除不规范的触发器校验报错，由于 SA1 没有 DoActivity，它进入后瞬间自动完成(Completion)到达 Join
    sA1.addTransition(to: join)
    // SB1 通过 E2 触发到达 Join
    sB1.addTransition(to: join, trigger: e2)
    join.addTransition(to: sEnd)
    
    rMain.addVertex(initP); rMain.addVertex(s1); rMain.addVertex(fork)
    rMain.addVertex(comp); rMain.addVertex(join); rMain.addVertex(sEnd)
    sm.addRegion(rMain)
    sm.start()
    
    // 触发 Fork
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(comp), "Fork 后应处于复合状态 Comp 中")
    
    // SA1 会自动完成到达 Join 等待，此时不应退出 Comp
    SMAssert(sm.getActiveStateConfiguration().contains(comp), "Join 未同步完成，应停留在 Comp")
    
    // 触发 SB1 到达 Join
    sm.post(event: TestEvent(e2))
    SMAssert(sm.getActiveStateConfiguration().contains(sEnd), "Join 同步完成，应进入 End")
}

func testShallowHistory() {
    print("\n--- 测试：浅历史伪状态 ---")
    let e2 = Trigger(eventType: EventType("E2"))
    let e3 = Trigger(eventType: EventType("E3"))
    let e4 = Trigger(eventType: EventType("E4"))
    
    let sm = StateMachine(name: "ShallowHistory")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let comp = CompositeState(name: "Comp", regions: [Region(name: "R_Sub")])
    let initSub = InitialPseudostate()
    let subS1 = SimpleState(name: "SubS1")
    let subS2 = SimpleState(name: "SubS2")
    
    // 修复：SH 必须属于复合状态的内部区域 R_Sub
    let shallowH = ShallowHistory(name: "SH")
    comp.regions[0].addVertex(initSub); comp.regions[0].addVertex(subS1); comp.regions[0].addVertex(subS2)
    comp.regions[0].addVertex(shallowH)
    
    initSub.addTransition(to: subS1)
    subS1.addTransition(to: subS2, trigger: e2)
    shallowH.addTransition(to: subS1) // 历史伪状态的默认出转换
    
    let outerS = SimpleState(name: "OuterS")
    
    initP.addTransition(to: comp)
    comp.addTransition(to: outerS, trigger: e3)
    // 修复：从外部跨区域直接指向复合状态内部的历史伪状态
    outerS.addTransition(to: shallowH, trigger: e4)
    
    r.addVertex(initP); r.addVertex(comp); r.addVertex(outerS)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.getActiveStateConfiguration().contains(subS1), "应默认进入 SubS1")
    sm.post(event: TestEvent(e3))
    SMAssert(sm.getActiveStateConfiguration().contains(outerS), "应退出到 OuterS")
    
    // 触发跨区域进入 SH，此时 R_Sub 的浅历史是 SubS1，将正确恢复
    sm.post(event: TestEvent(e4))
    SMAssert(sm.getActiveStateConfiguration().contains(subS1), "浅历史应恢复到第一层子状态 SubS1")
}

func testDeepHistory() {
    print("\n--- 测试：深历史伪状态 ---")
    let e2 = Trigger(eventType: EventType("E2"))
    let e3 = Trigger(eventType: EventType("E3"))
    let e4 = Trigger(eventType: EventType("E4"))
    
    let sm = StateMachine(name: "DeepHistory")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let comp = CompositeState(name: "Comp", regions: [Region(name: "R_Sub")])
    let initSub = InitialPseudostate()
    let subS1 = SimpleState(name: "SubS1")
    let subS2 = SimpleState(name: "SubS2")
    
    // 修复：DH 必须属于复合状态的内部区域 R_Sub
    let deepH = DeepHistory(name: "DH")
    comp.regions[0].addVertex(initSub); comp.regions[0].addVertex(subS1); comp.regions[0].addVertex(subS2)
    comp.regions[0].addVertex(deepH)
    
    initSub.addTransition(to: subS1)
    subS1.addTransition(to: subS2, trigger: e2)
    deepH.addTransition(to: subS1)
    
    let outerS = SimpleState(name: "OuterS")
    
    initP.addTransition(to: comp)
    comp.addTransition(to: outerS, trigger: e3)
    // 修复：从外部跨区域直接指向复合状态内部的深历史伪状态
    outerS.addTransition(to: deepH, trigger: e4)
    
    r.addVertex(initP); r.addVertex(comp); r.addVertex(outerS)
    sm.addRegion(r)
    sm.start()
    
    sm.post(event: TestEvent(e2))
    SMAssert(sm.getActiveStateConfiguration().contains(subS2), "应进入 SubS2")
    sm.post(event: TestEvent(e3))
    SMAssert(sm.getActiveStateConfiguration().contains(outerS), "应退出到 OuterS")
    
    // 触发跨区域进入 DH，此时 R_Sub 的浅历史是 SubS2，深历史递归将正确恢复 SubS2
    sm.post(event: TestEvent(e4))
    SMAssert(sm.getActiveStateConfiguration().contains(subS2), "深历史应恢复到最深层的 SubS2")
}

func testTerminatePseudostate() {
    print("\n--- 测试：终止伪状态 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "Terminate")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let term = TerminatePseudostate(name: "Term")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: term, trigger: e1)
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(term)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.active, "状态机应正在运行")
    sm.post(event: TestEvent(e1))
    SMAssert(!sm.active, "状态机应被终止")
}

func testEntryPointAndExitPoint() {
    print("\n--- 测试：EntryPoint 与 ExitPoint ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    let e3 = Trigger(eventType: EventType("E3"))
    
    let sm = StateMachine(name: "EntryExitPoint")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    
    let comp = CompositeState(name: "Comp", regions: [Region(name: "R_Sub")])
    let initSub = InitialPseudostate()
    let subS1 = SimpleState(name: "SubS1")
    let subS2 = SimpleState(name: "SubS2")
    comp.regions[0].addVertex(initSub); comp.regions[0].addVertex(subS1); comp.regions[0].addVertex(subS2)
    initSub.addTransition(to: subS1)
    
    let entryP = EntryPoint(name: "EP")
    let exitP = ExitPoint(name: "XP")
    
    comp.addEntryPoint(entryP)
    comp.addExitPoint(exitP)
    
    let sEnd = SimpleState(name: "End")
    
    s1.addTransition(to: entryP, trigger: e1)
    entryP.addTransition(to: subS2)
    
    subS1.addTransition(to: exitP, trigger: e2)
    exitP.addTransition(to: sEnd)
    
    // 修复：增加一条普通进入 Comp 的路径
    s1.addTransition(to: comp, trigger: e3)
    
    initP.addTransition(to: s1)
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(comp); r.addVertex(sEnd)
    r.addVertex(entryP); r.addVertex(exitP)
    
    sm.addRegion(r)
    sm.start()
    
    // 测试 EntryPoint
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(subS2), "应通过 EntryPoint 进入 SubS2")
    
    // 测试 ExitPoint (重启走默认 SubS1)
    sm.stop(); sm.start()
    // 先通过 E3 普通 entering，走默认 InitialPseudostate 进入 SubS1
    sm.post(event: TestEvent(e3))
    SMAssert(sm.getActiveStateConfiguration().contains(subS1), "应默认进入 SubS1")
    // 再通过 E2 触发 ExitPoint
    sm.post(event: TestEvent(e2))
    SMAssert(sm.getActiveStateConfiguration().contains(sEnd), "应通过 ExitPoint 退出到 End")
}

func testSubmachineState() {
    print("\n--- 测试：子状态机 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    let e3 = Trigger(eventType: EventType("E3")) // 新增：专门用于触发外部退出的独立事件
    
    let innerSM = StateMachine(name: "InnerSM")
    let innerR = Region(name: "InnerR")
    let innerInit = InitialPseudostate()
    let innerS1 = SimpleState(name: "InnerS1")
    let innerS2 = SimpleState(name: "InnerS2")
    innerInit.addTransition(to: innerS1)
    innerS1.addTransition(to: innerS2, trigger: e2) // 内部只响应 E2
    innerR.addVertex(innerInit); innerR.addVertex(innerS1); innerR.addVertex(innerS2)
    innerSM.addRegion(innerR)
    
    let outerSM = StateMachine(name: "OuterSM")
    let outerR = Region(name: "OuterR")
    let outerInit = InitialPseudostate()
    let outerS1 = SimpleState(name: "OuterS1")
    let submachineState = SubmachineState(name: "SubSM", submachine: innerSM)
    let outerS2 = SimpleState(name: "OuterS2")
    outerInit.addTransition(to: outerS1)
    outerS1.addTransition(to: submachineState, trigger: e1)
    
    // 修改：外部只响应 E3，避免与内部的 E2 冲突
    submachineState.addTransition(to: outerS2, trigger: e3)
    
    outerR.addVertex(outerInit); outerR.addVertex(outerS1); outerR.addVertex(submachineState); outerR.addVertex(outerS2)
    outerSM.addRegion(outerR)
    outerSM.start()
    
    SMAssert(outerSM.getActiveStateConfiguration().contains(outerS1), "外部应进入 OuterS1")
    outerSM.post(event: TestEvent(e1))
    SMAssert(innerSM.active, "内部子状态机应启动")
    SMAssert(innerSM.getActiveStateConfiguration().contains(innerS1), "内部子状态机应进入 InnerS1")
    
    // 1. 测试内部拦截：E2 被内部消费，外部不应退出
    outerSM.post(event: TestEvent(e2))
    SMAssert(innerSM.active, "E2 被内部消费，子状态机应仍在运行")
    SMAssert(innerSM.getActiveStateConfiguration().contains(innerS2), "内部应进入 InnerS2")
    SMAssert(outerSM.getActiveStateConfiguration().contains(submachineState), "外部应停留在 SubSM")
    
    // 2. 测试外部透传：E3 未被内部处理，由外部 SubSM 消费并退出
    outerSM.post(event: TestEvent(e3))
    SMAssert(!innerSM.active, "E3 触发了外部转换，子状态机应停止")
    SMAssert(outerSM.getActiveStateConfiguration().contains(outerS2), "外部应进入 OuterS2")
}


func testCompletionTransition() {
    print("\n--- 测试：Completion Transition (自动转换) ---")
    let sm = StateMachine(name: "Completion")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: s2, triggers: [])
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.getActiveStateConfiguration().contains(s2), "S1 无 DoActivity，应自动 Completion 转换到 S2")
}

func testFinalStateTriggerParentCompletion() {
    print("\n--- 测试：FinalState 触发父级复合状态完成 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    
    let sm = StateMachine(name: "FinalTriggerComp")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let comp = CompositeState(name: "Comp", regions: [Region(name: "R_Sub")])
    
    let initSub = InitialPseudostate()
    let subS1 = SimpleState(name: "SubS1")
    let subFinal = FinalState(name: "SubFinal")
    
    comp.regions[0].addVertex(initSub); comp.regions[0].addVertex(subS1); comp.regions[0].addVertex(subFinal)
    initSub.addTransition(to: subS1)
    subS1.addTransition(to: subFinal, trigger: e1)
    
    let outerS = SimpleState(name: "OuterS")
    
    initP.addTransition(to: comp)
    comp.addTransition(to: outerS, triggers: []) // 父级 Comp 的完成转换
    
    r.addVertex(initP); r.addVertex(comp); r.addVertex(outerS)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.getActiveStateConfiguration().contains(subS1), "应进入 SubS1")
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(outerS), "子区域终态应触发父复合状态完成，进入 OuterS")
}

func testHistoryDefaultTransition() {
    print("\n--- 测试：历史伪状态的默认转换 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    
    let sm = StateMachine(name: "HistoryDefault")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    
    let comp = CompositeState(name: "Comp", regions: [Region(name: "R_Sub")])
    let initSub = InitialPseudostate()
    let subS1 = SimpleState(name: "SubS1")
    let subS2 = SimpleState(name: "SubS2")
    let deepH = DeepHistory(name: "DH")
    
    comp.regions[0].addVertex(initSub); comp.regions[0].addVertex(subS1); comp.regions[0].addVertex(subS2); comp.regions[0].addVertex(deepH)
    initSub.addTransition(to: subS1)
    deepH.addTransition(to: subS1)
    
    initP.addTransition(to: s1)
    s1.addTransition(to: deepH, trigger: e1)
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(comp)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.getActiveStateConfiguration().contains(s1), "应进入 S1")
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(subS1), "无历史记录时，应走默认转换进入 SubS1")
}

func testSelfTransition() {
    print("\n--- 测试：自转换 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "SelfTransition")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: s1, trigger: e1)
    
    s1.onEntry { $0.userInfo["count"] = ($0.userInfo["count"] as? Int ?? 0) + 1 }
    s1.onExit { $0.userInfo["exited"] = true }
    
    r.addVertex(initP); r.addVertex(s1)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.context.userInfo["count"] as? Int == 1, "初始进入应执行一次 Entry")
    SMAssert(sm.context.userInfo["exited"] == nil, "初始进入不应执行 Exit")
    
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(s1), "自转换后状态仍应为 S1")
    SMAssert(sm.context.userInfo["exited"] as? Bool == true, "自转换应执行 Exit")
    SMAssert(sm.context.userInfo["count"] as? Int == 2, "自转换应再次执行 Entry")
}

func testOrthogonalEventDispatch() {
    print("\n--- 测试：正交状态事件独立分发 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    
    let sm = StateMachine(name: "OrthogonalDispatch")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let comp = CompositeState(name: "Comp", regions: [Region(name: "R_A"), Region(name: "R_B")])
    
    let initA = InitialPseudostate()
    let sA1 = SimpleState(name: "SA1"); let sA2 = SimpleState(name: "SA2")
    comp.regions[0].addVertex(initA); comp.regions[0].addVertex(sA1); comp.regions[0].addVertex(sA2)
    initA.addTransition(to: sA1)
    sA1.addTransition(to: sA2, trigger: e1)
    
    let initB = InitialPseudostate()
    let sB1 = SimpleState(name: "SB1"); let sB2 = SimpleState(name: "SB2")
    comp.regions[1].addVertex(initB); comp.regions[1].addVertex(sB1); comp.regions[1].addVertex(sB2)
    initB.addTransition(to: sB1)
    sB1.addTransition(to: sB2, trigger: e2)
    
    initP.addTransition(to: comp)
    r.addVertex(initP); r.addVertex(comp)
    sm.addRegion(r)
    sm.start()
    
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(sA2), "区域 A 应响应 E1 进入 SA2")
    SMAssert(sm.getActiveStateConfiguration().contains(sB1), "区域 B 不应响应 E1，停留在 SB1")
    
    sm.post(event: TestEvent(e2))
    SMAssert(sm.getActiveStateConfiguration().contains(sA2), "区域 A 不应响应 E2，停留在 SA2")
    SMAssert(sm.getActiveStateConfiguration().contains(sB2), "区域 B 应响应 E2 进入 SB2")
}


func testChoiceDeadlockError() {
    print("\n--- 测试：Choice 伪状态死锁 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "ChoiceDeadlock")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let choice = Choice(name: "C1")
    let s2 = SimpleState(name: "S2")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: choice, trigger: e1)
    // 只有守卫为 true 才能通过，没有 Else
    choice.addTransition(to: s2, guardCondition: AnyGuard { $0.userInfo["always_false"] as? Bool == true })
    
    r.addVertex(initP);
    r.addVertex(s1);
    r.addVertex(choice);
    r.addVertex(s2)
    sm.addRegion(r)
    
    // 拦截状态机内部错误
    var caughtError: StateMachineError?
    sm.errorStrategy = .customHandler { error in
        caughtError = error
    }
    
    sm.start()
    sm.post(event: TestEvent(e1))
    
    // 修正：UML 规范中 Choice 是动态分支，一旦离开 S1 就无法回滚。
    // 死锁发生时，S1 已经 Exit，但新状态未 Enter，状态机处于不一致的悬浮状态（无活跃状态）。
    SMAssert(sm.getActiveStateConfiguration().activeStates.isEmpty, "死锁时由于 S1 已退出且无新状态进入，活跃状态应为空")
    
    // 验证抛出了正确的死锁错误
    if case .noEnabledChoice(let msg) = caughtError {
        SMAssert(msg.contains("C1"), "应抛出包含 C1 的死锁错误")
    } else {
        SMAssert(false, "应抛出 noEnabledChoice 错误")
    }
}

func testDoActivityCompletionTransition() {
    print("\n--- 测试：DoActivity 完成触发转换 ---")
    let semaphore = DispatchSemaphore(value: 0)
    
    let sm = StateMachine(name: "DoActivityCompletion")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    
    initP.addTransition(to: s1)
    // S1 的 Completion Transition
    s1.addTransition(to: s2, triggers: [])
    
    // 设置一个异步的 doActivity
    s1.onDo { ctx in
        // 模拟耗时任务
        Thread.sleep(forTimeInterval: 0.1)
        ctx.userInfo["do_finished"] = true
        semaphore.signal()
    }
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2)
    sm.addRegion(r)
    sm.start()
    
    // 刚启动时，DoActivity 尚未完成，不应进入 S2
    SMAssert(!sm.getActiveStateConfiguration().contains(s2), "DoActivity 未完成，不应进入 S2")
    
    // 等待异步 DoActivity 执行完毕
    _ = semaphore.wait(timeout: .now() + 2)
    // 稍微等一下让状态机的 RTC 队列处理完成事件
    Thread.sleep(forTimeInterval: 0.1)
    
    // DoActivity 完成后，应自动触发 Completion Transition 进入 S2
    SMAssert(sm.context.userInfo["do_finished"] as? Bool == true, "DoActivity 应已执行完毕")
    SMAssert(sm.getActiveStateConfiguration().contains(s2), "DoActivity 完成后应自动转换到 S2")
}

func testValidationConstraints() {
    print("\n--- 测试：构建时约束校验 ---")
    
    // 场景 A：终态不能有出转换
    let sm1 = StateMachine(name: "InvalidFinal")
    let r1 = Region(name: "R1")
    let initP1 = InitialPseudostate()
    let finalState = FinalState(name: "F1")
    let s1 = SimpleState(name: "S1")
    
    initP1.addTransition(to: finalState)
    finalState.addTransition(to: s1, trigger: Trigger(eventType: EventType("E1"))) // 非法！
    r1.addVertex(initP1); r1.addVertex(finalState); r1.addVertex(s1)
    sm1.addRegion(r1)
    
    do {
        try sm1.validate()
        SMAssert(false, "终态有出转换应校验失败")
    } catch StateMachineError.validationError(let msg) {
        SMAssert(msg.contains("不能有出转换"), "应拦截终态出转换错误")
    } catch {
        SMAssert(false, "抛出了未知错误")
    }
    
    // 场景 B：初始伪状态出转换不能有触发器
    let sm2 = StateMachine(name: "InvalidInitial")
    let r2 = Region(name: "R2")
    let initP2 = InitialPseudostate()
    let s2 = SimpleState(name: "S2")
    
    initP2.addTransition(to: s2, trigger: Trigger(eventType: EventType("E1"))) // 非法！
    r2.addVertex(initP2); r2.addVertex(s2)
    sm2.addRegion(r2)
    
    do {
        try sm2.validate()
        SMAssert(false, "初始伪状态有触发器应校验失败")
    } catch StateMachineError.validationError(let msg) {
        SMAssert(msg.contains("不能有触发器或守卫"), "应拦截初始状态触发器错误")
    } catch {
        SMAssert(false, "抛出了未知错误")
    }
}

func testTransitionPriorityOverDeferral() {
    print("\n--- 测试：转换优先于延迟 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "PriorityOverDefer")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    // S1 既延迟 E1，又有 E1 的出转换
    let s1 = SimpleState(name: "S1").defer(e1.eventType)
    let s2 = SimpleState(name: "S2")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: s2, trigger: e1)
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.getActiveStateConfiguration().contains(s1), "应进入 S1")
    // 发送 E1，虽然 S1 延迟了 E1，但因为有显式出转换，必须走转换而不是延迟
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(s2), "出转换必须优先于延迟，应进入 S2")
}

func testDeepHistoryWithOrthogonalRegions() {
    print("\n--- 测试：深历史与正交区域组合 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    let e3 = Trigger(eventType: EventType("E3"))
    let e4 = Trigger(eventType: EventType("E4"))
    
    let sm = StateMachine(name: "DeepOrthoHistory")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let comp = CompositeState(name: "Comp", regions: [Region(name: "R_A"), Region(name: "R_B")])
    
    let initA = InitialPseudostate(); let sA1 = SimpleState(name: "SA1"); let sA2 = SimpleState(name: "SA2")
    comp.regions[0].addVertex(initA); comp.regions[0].addVertex(sA1); comp.regions[0].addVertex(sA2)
    initA.addTransition(to: sA1)
    sA1.addTransition(to: sA2, trigger: e1)
    
    let initB = InitialPseudostate(); let sB1 = SimpleState(name: "SB1"); let sB2 = SimpleState(name: "SB2")
    comp.regions[1].addVertex(initB); comp.regions[1].addVertex(sB1); comp.regions[1].addVertex(sB2)
    initB.addTransition(to: sB1)
    sB1.addTransition(to: sB2, trigger: e2)
    
    let deepH = DeepHistory(name: "DH")
    comp.regions[0].addVertex(deepH) // 深历史放在第一个区域
    deepH.addTransition(to: sA1)
    
    let outerS = SimpleState(name: "OuterS")
    
    initP.addTransition(to: comp)
    comp.addTransition(to: outerS, trigger: e3)
    outerS.addTransition(to: deepH, trigger: e4)
    
    r.addVertex(initP); r.addVertex(comp); r.addVertex(outerS)
    sm.addRegion(r)
    sm.start()
    
    // 分别进入两个区域的深层状态
    sm.post(event: TestEvent(e1)) // -> SA2
    sm.post(event: TestEvent(e2)) // -> SB2
    SMAssert(sm.getActiveStateConfiguration().contains(sA2), "应进入 SA2")
    SMAssert(sm.getActiveStateConfiguration().contains(sB2), "应进入 SB2")
    
    // 退出复合状态
    sm.post(event: TestEvent(e3))
    SMAssert(sm.getActiveStateConfiguration().contains(outerS), "应退出到 OuterS")
    
    // 通过深历史恢复，两个正交区域都应恢复到深层状态
    sm.post(event: TestEvent(e4))
    SMAssert(sm.getActiveStateConfiguration().contains(sA2), "深历史应恢复区域 A 到 SA2")
    SMAssert(sm.getActiveStateConfiguration().contains(sB2), "深历史应恢复区域 B 到 SB2")
}

func testNestedCompositeExitOrder() {
    print("\n--- 测试：嵌套复合状态退出顺序 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "NestedExitOrder")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    
    let outerComp = CompositeState(name: "OuterComp", regions: [Region(name: "R_Outer")])
    let initOuter = InitialPseudostate()
    let innerComp = CompositeState(name: "InnerComp", regions: [Region(name: "R_Inner")])
    
    let initInner = InitialPseudostate()
    let leaf = SimpleState(name: "Leaf")
    
    innerComp.regions[0].addVertex(initInner); innerComp.regions[0].addVertex(leaf)
    initInner.addTransition(to: leaf)
    
    outerComp.regions[0].addVertex(initOuter); outerComp.regions[0].addVertex(innerComp)
    initOuter.addTransition(to: innerComp)
    
    let endS = SimpleState(name: "End")
    
    initP.addTransition(to: outerComp)
    leaf.addTransition(to: endS, trigger: e1)
    
    // 记录退出顺序
    leaf.onExit { $0.userInfo["log"] = ($0.userInfo["log"] as? String ?? "") + "Leaf|" }
    innerComp.onExit { $0.userInfo["log"] = ($0.userInfo["log"] as? String ?? "") + "Inner|" }
    outerComp.onExit { $0.userInfo["log"] = ($0.userInfo["log"] as? String ?? "") + "Outer|" }
    
    r.addVertex(initP); r.addVertex(outerComp); r.addVertex(endS)
    sm.addRegion(r)
    sm.start()
    
    sm.post(event: TestEvent(e1))
    // UML 规范：退出顺序必须是从内向外
    SMAssert(sm.context.userInfo["log"] as? String == "Leaf|Inner|Outer|", "嵌套退出顺序应为：Leaf -> Inner -> Outer")
}


func testInnerStatePriorityOverParent() {
    print("\n--- 测试：子状态事件响应优先级 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "InnerPriority")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    
    let comp = CompositeState(name: "Comp", regions: [Region(name: "R_Sub")])
    let initSub = InitialPseudostate()
    let subS1 = SimpleState(name: "SubS1")
    let subS2 = SimpleState(name: "SubS2")
    
    comp.regions[0].addVertex(initSub); comp.regions[0].addVertex(subS1); comp.regions[0].addVertex(subS2)
    initSub.addTransition(to: subS1)
    subS1.addTransition(to: subS2, trigger: e1) // 子状态响应 E1
    
    let outerS = SimpleState(name: "OuterS")
    comp.addTransition(to: outerS, trigger: e1) // 父状态也响应 E1
    
    initP.addTransition(to: comp)
    r.addVertex(initP); r.addVertex(comp); r.addVertex(outerS)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.getActiveStateConfiguration().contains(subS1), "应进入 SubS1")
    // 触发 E1，由于 SubS1 在最内层，它必须优先消费事件进入 SubS2
    // 父状态的 Comp->OuterS 转换不应被触发
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(subS2), "子状态应优先响应，进入 SubS2")
    SMAssert(!sm.getActiveStateConfiguration().contains(outerS), "父状态不应响应，不应进入 OuterS")
}

func testGuardedCompletionTransition() {
    print("\n--- 测试：守卫失败的完成转换 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "GuardedCompletion")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    
    initP.addTransition(to: s1)
    // 完成转换带守卫
    s1.addTransition(to: s2, triggers: [], guardCondition: AnyGuard { $0.userInfo["flag"] as? Bool == true })
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2)
    sm.addRegion(r)
    sm.start()
    
    // 进入 S1 后触发完成事件，但守卫为 false
    SMAssert(sm.getActiveStateConfiguration().contains(s1), "守卫失败，应停留在 S1")
    
    // 发送无关事件，状态仍然保持
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(s1), "收到无关事件，仍停留在 S1")
}

func testMultipleTriggersTransition() {
    print("\n--- 测试：多触发器转换 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    let e3 = Trigger(eventType: EventType("E3"))
    
    let sm = StateMachine(name: "MultiTrigger")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    
    initP.addTransition(to: s1)
    // E1 或 E2 都可以触发 S1 到 S2 的转换
    s1.addTransition(to: s2, triggers: [e1, e2])
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2)
    sm.addRegion(r)
    sm.start()
    
    // 测试 E2 触发
    sm.post(event: TestEvent(e2))
    SMAssert(sm.getActiveStateConfiguration().contains(s2), "E2 应触发转换进入 S2")
    
    // 重置并测试 E1 触发
    sm.stop(); sm.start()
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(s2), "E1 应触发转换进入 S2")
    
    // 重置并测试 E3 无效
    sm.stop(); sm.start()
    sm.post(event: TestEvent(e3))
    SMAssert(sm.getActiveStateConfiguration().contains(s1), "E3 不应触发转换，停留在 S1")
}


func testDeferredEventInheritance() {
    print("\n--- 测试：延迟事件继承 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    
    let sm = StateMachine(name: "DeferredInheritance")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    
    // 父复合状态延迟 E2
    let comp = CompositeState(name: "Comp", regions: [Region(name: "R_Sub")]).defer(e2.eventType)
    let initSub = InitialPseudostate()
    let subS1 = SimpleState(name: "SubS1") // 子状态未声明延迟 E2
    let subS2 = SimpleState(name: "SubS2")
    
    comp.regions[0].addVertex(initSub);
    comp.regions[0].addVertex(subS1);
    comp.regions[0].addVertex(subS2)
    initSub.addTransition(to: subS1)
    subS1.addTransition(to: subS2, trigger: e1)
    
    let outerS = SimpleState(name: "OuterS")
    comp.addTransition(to: outerS, trigger: e2) // 父状态对 E2 有出转换
    
    initP.addTransition(to: comp)
    r.addVertex(initP);
    r.addVertex(comp);
    r.addVertex(outerS)
    sm.addRegion(r)
    sm.start()
    
    // 在 SubS1 时发送 E2，由于父状态 Comp 延迟了 E2，事件应被延迟而不是报错
    sm.post(event: TestEvent(e2))
    SMAssert(sm.getActiveStateConfiguration().contains(subS1), "E2 应在父级 Comp 被延迟，SubS1 不变")
    
    // 触发 E1 进入 SubS2
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(subS2), "E1 应触发进入 SubS2")
}

func testCompositeStateReentry() {
    print("\n--- 测试：复合状态重入 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    let e3 = Trigger(eventType: EventType("E3"))
    
    let sm = StateMachine(name: "CompReentry")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    
    let comp = CompositeState(name: "Comp", regions: [Region(name: "R_Sub")])
    let initSub = InitialPseudostate()
    let subS1 = SimpleState(name: "SubS1")
    let subS2 = SimpleState(name: "SubS2")
    
    comp.regions[0].addVertex(initSub); comp.regions[0].addVertex(subS1); comp.regions[0].addVertex(subS2)
    initSub.addTransition(to: subS1)
    subS1.addTransition(to: subS2, trigger: e2)
    
    let outerS = SimpleState(name: "OuterS")
    
    initP.addTransition(to: comp)
    comp.addTransition(to: outerS, trigger: e3)
    // 关键：不是转到历史伪状态，而是直接转回复合状态本身
    outerS.addTransition(to: comp, trigger: e1)
    
    r.addVertex(initP); r.addVertex(comp); r.addVertex(outerS)
    sm.addRegion(r)
    sm.start()
    
    // 进入 SubS2，积累历史
    sm.post(event: TestEvent(e2))
    SMAssert(sm.getActiveStateConfiguration().contains(subS2), "应进入 SubS2")
    
    // 退出到 OuterS
    sm.post(event: TestEvent(e3))
    SMAssert(sm.getActiveStateConfiguration().contains(outerS), "应退出到 OuterS")
    
    // 重新进入 Comp（非历史），应重新初始化到 SubS1，而不是恢复到 SubS2
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(subS1), "重入复合状态应重新初始化子区域，进入 SubS1")
    SMAssert(!sm.getActiveStateConfiguration().contains(subS2), "不应恢复历史到 SubS2")
}

func testTransitionGuardPriority() {
    print("\n--- 测试：多出转换守卫优先级 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "GuardPriority")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    let s3 = SimpleState(name: "S3")
    
    initP.addTransition(to: s1)
    // 两个转换都由 E1 触发，且守卫都为 true
    s1.addTransition(to: s2, trigger: e1, guardCondition: AnyGuard { _ in true })
    s1.addTransition(to: s3, trigger: e1, guardCondition: AnyGuard { _ in true })
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2); r.addVertex(s3)
    sm.addRegion(r)
    sm.start()
    
    sm.post(event: TestEvent(e1))
    // 先定义的转换 S1->S2 应该优先触发
    SMAssert(sm.getActiveStateConfiguration().contains(s2), "先定义的守卫转换应优先匹配")
    SMAssert(!sm.getActiveStateConfiguration().contains(s3), "后定义的转换不应执行")
}

func testInternalVsSelfTransition() {
    print("\n--- 测试：内部转换与自转换的区别 ---")
    let e1 = Trigger(eventType: EventType("E1")) // 内部转换触发器
    let e2 = Trigger(eventType: EventType("E2")) // 自转换触发器
    
    let sm = StateMachine(name: "InternalVsSelf")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    
    initP.addTransition(to: s1)
    
    // 内部转换：只改数据，不换状态
    s1.addInternalTransition(trigger: e1, action: AnyAction({ ctx in
        ctx.userInfo["internal_count"] = (ctx.userInfo["internal_count"] as? Int ?? 0) + 1
    }))
     
    
    // 自转换：退出并重新进入
    s1.addTransition(to: s1, trigger: e2)
    
    s1.onEntry { $0.userInfo["entry_count"] = ($0.userInfo["entry_count"] as? Int ?? 0) + 1 }
    s1.onExit { $0.userInfo["exit_count"] = ($0.userInfo["exit_count"] as? Int ?? 0) + 1 }
    
    r.addVertex(initP); r.addVertex(s1)
    sm.addRegion(r)
    sm.start()
    
    // 初始进入触发一次 Entry
    SMAssert(sm.context.userInfo["entry_count"] as? Int == 1, "初始进入应执行 Entry")
    
    // 触发内部转换
    sm.post(event: TestEvent(e1))
    SMAssert(sm.context.userInfo["internal_count"] as? Int == 1, "内部转换动作应执行")
    SMAssert(sm.context.userInfo["entry_count"] as? Int == 1, "内部转换不应触发 Entry")
    SMAssert(sm.context.userInfo["exit_count"] == nil, "内部转换不应触发 Exit")
    
    // 触发自转换
    sm.post(event: TestEvent(e2))
    SMAssert(sm.context.userInfo["exit_count"] as? Int == 1, "自转换应触发 Exit")
    SMAssert(sm.context.userInfo["entry_count"] as? Int == 2, "自转换应触发 Entry")
}

func testExitPointCrossRegion() {
    print("\n--- 测试：Exit Point 跨区域跳出 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "ExitPointTest")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    
    let comp = CompositeState(name: "Comp", regions: [Region(name: "R_Sub")])
    let initSub = InitialPseudostate()
    let subS1 = SimpleState(name: "SubS1")
    let exitP = ExitPoint(name: "EP1")
    
    comp.regions[0].addVertex(initSub); comp.regions[0].addVertex(subS1); comp.regions[0].addVertex(exitP)
    initSub.addTransition(to: subS1)
    subS1.addTransition(to: exitP, trigger: e1) // 内部状态指向出口点
    
    let outerS = SimpleState(name: "OuterS")
    exitP.addTransition(to: outerS) // 出口点指向外部状态
    
    initP.addTransition(to: comp)
    r.addVertex(initP); r.addVertex(comp); r.addVertex(outerS)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.getActiveStateConfiguration().contains(subS1), "应进入 SubS1")
    // 通过 Exit Point 跳出
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(outerS), "应通过 Exit Point 跳出到 OuterS")
}

func testOrthogonalFinalStateSynchronization() {
    print("\n--- 测试：正交区域终态同步完成 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    
    let sm = StateMachine(name: "OrthoSync")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    
    let comp = CompositeState(name: "Comp", regions: [Region(name: "R_A"), Region(name: "R_B")])
    
    let initA = InitialPseudostate(); let sA1 = SimpleState(name: "SA1"); let finalA = FinalState(name: "FinalA")
    comp.regions[0].addVertex(initA); comp.regions[0].addVertex(sA1); comp.regions[0].addVertex(finalA)
    initA.addTransition(to: sA1)
    sA1.addTransition(to: finalA, trigger: e1)
    
    let initB = InitialPseudostate(); let sB1 = SimpleState(name: "SB1"); let finalB = FinalState(name: "FinalB")
    comp.regions[1].addVertex(initB); comp.regions[1].addVertex(sB1); comp.regions[1].addVertex(finalB)
    initB.addTransition(to: sB1)
    sB1.addTransition(to: finalB, trigger: e2)
    
    // 使用 Entry 动作留下“到此一游”的标记，因为终态会在父级退出时立刻被退出
    finalA.onEntry { $0.userInfo["finalA_entered"] = true }
    finalB.onEntry { $0.userInfo["finalB_entered"] = true }
    
    let outerS = SimpleState(name: "OuterS")
    initP.addTransition(to: comp)
    comp.addTransition(to: outerS, triggers: []) // Comp 的完成转换
    
    r.addVertex(initP); r.addVertex(comp); r.addVertex(outerS)
    sm.addRegion(r)
    sm.start()
    
    // 仅区域 A 完成
    sm.post(event: TestEvent(e1))
    SMAssert(sm.context.userInfo["finalA_entered"] as? Bool == true, "区域 A 应到达过终态")
    SMAssert(sm.getActiveStateConfiguration().contains(sB1), "区域 B 仍在运行")
    SMAssert(!sm.getActiveStateConfiguration().contains(outerS), "部分区域完成，父级不应触发完成转换")
    
    // 区域 B 也完成
    sm.post(event: TestEvent(e2))
    SMAssert(sm.context.userInfo["finalB_entered"] as? Bool == true, "区域 B 应到达过终态")
    
    // 所有区域完成，父复合状态完成，触发 Completion Transition，此时终态已随父级退出
    SMAssert(sm.getActiveStateConfiguration().contains(outerS), "所有区域完成，应进入 OuterS")
    SMAssert(!sm.getActiveStateConfiguration().contains(finalA), "FinalA 应已随 Comp 退出")
    SMAssert(!sm.getActiveStateConfiguration().contains(finalB), "FinalB 应已随 Comp 退出")
}

func testDirectCrossRegionEntry() {
    print("\n--- 测试：直接跨区域进入子状态 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "DirectEntry")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let outerS = SimpleState(name: "OuterS")
    
    let comp = CompositeState(name: "Comp", regions: [Region(name: "R_Sub")])
    let initSub = InitialPseudostate()
    let subS1 = SimpleState(name: "SubS1") // 默认进入
    let subS2 = SimpleState(name: "SubS2") // 直接跨区域进入的目标
    
    comp.regions[0].addVertex(initSub); comp.regions[0].addVertex(subS1); comp.regions[0].addVertex(subS2)
    initSub.addTransition(to: subS1)
    
    initP.addTransition(to: outerS)
    // 关键：外部状态直接指向复合状态内部的 SubS2
    outerS.addTransition(to: subS2, trigger: e1)
    
    r.addVertex(initP); r.addVertex(outerS); r.addVertex(comp)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.getActiveStateConfiguration().contains(outerS), "应进入 OuterS")
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(comp), "应进入复合状态 Comp")
    SMAssert(sm.getActiveStateConfiguration().contains(subS2), "应直接跨区域进入 SubS2，而非默认的 SubS1")
}

func testSubmachineStateCompletion() {
    print("\n--- 测试：子状态机完成触发外部转换 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    
    let innerSM = StateMachine(name: "InnerSM")
    let innerR = Region(name: "InnerR")
    let innerInit = InitialPseudostate()
    let innerS1 = SimpleState(name: "InnerS1")
    let innerFinal = FinalState(name: "InnerFinal")
    
    innerInit.addTransition(to: innerS1)
    innerS1.addTransition(to: innerFinal, trigger: e1)
    innerR.addVertex(innerInit); innerR.addVertex(innerS1); innerR.addVertex(innerFinal)
    innerSM.addRegion(innerR)
    
    let outerSM = StateMachine(name: "OuterSM")
    let outerR = Region(name: "OuterR")
    let outerInit = InitialPseudostate()
    let subState = SubmachineState(name: "SubSM", submachine: innerSM)
    let outerS2 = SimpleState(name: "OuterS2")
    
    outerInit.addTransition(to: subState)
    // 关键：子状态机的完成转换
    subState.addTransition(to: outerS2, triggers: [])
    
    outerR.addVertex(outerInit); outerR.addVertex(subState); outerR.addVertex(outerS2)
    outerSM.addRegion(outerR)
    outerSM.start()
    
    SMAssert(outerSM.getActiveStateConfiguration().contains(subState), "应进入子状态机")
    // 触发内部状态机到达终态
    outerSM.post(event: TestEvent(e1))
    
    SMAssert(!innerSM.active, "内部子状态机应停止")
    SMAssert(outerSM.getActiveStateConfiguration().contains(outerS2), "子状态机完成应触发外部 Completion 进入 OuterS2")
}

func testDeferredEventReleaseUnhandled() {
    print("\n--- 测试：延迟事件释放后仍未被处理的边界情况 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    
    let sm = StateMachine(name: "DeferredReleaseUnhandled")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    
    // S1 延迟 E2
    let s1 = SimpleState(name: "S1").defer(e2.eventType)
    // S2 对 E2 没有任何转换，也没有延迟
    let s2 = SimpleState(name: "S2")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: s2, trigger: e1)
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2)
    sm.addRegion(r)
    
    // 拦截状态机内部错误，用于后续断言
    var caughtError: StateMachineError?
    sm.errorStrategy = .customHandler { error in
        caughtError = error
    }
    
    sm.start()
    SMAssert(sm.getActiveStateConfiguration().contains(s1), "初始应进入 S1")
    
    // 1. 在 S1 发送 E2，事件应被延迟
    sm.post(event: TestEvent(e2))
    SMAssert(sm.getActiveStateConfiguration().contains(s1), "E2 在 S1 应被延迟，状态保持 S1")
    
    // 2. 发送 E1，触发 S1 退出进入 S2
    // 核心：S1 退出时会释放 E2，E2 重新进入事件队列
    // 但当前状态 S2 无法处理 E2，E2 应被丢弃，状态机不能死锁
    sm.post(event: TestEvent(e1))
    
    // 3. 验证状态机正常运行，没有死锁在某个中间态
    SMAssert(sm.getActiveStateConfiguration().contains(s2), "应正常进入 S2 且不发生死锁")
    
    // 4. 验证状态机正确地抛出了未处理事件错误
    if case .unhandledEvent(let event, _) = caughtError {
        SMAssert(event.eventType == e2.eventType, "应正确抛出 E2 未处理错误")
    } else {
        SMAssert(false, "应抛出 unhandledEvent 错误，实际: \(String(describing: caughtError))")
    }
}


func runAllStateMachineTests() {
    StateMachineLogger.isEnabled = true
    testBasicTransition()
    testGuardAndChoice()
    testJunction()
    testActionsOrder()
    testInternalTransition()
    testDeferredEvents()
    testForkAndJoin()
    testShallowHistory()
    testDeepHistory()
    testTerminatePseudostate()
    testEntryPointAndExitPoint()
    testSubmachineState()
    
    testCompletionTransition()
    testFinalStateTriggerParentCompletion()
    testHistoryDefaultTransition()
    testSelfTransition()
    testOrthogonalEventDispatch()
    
    testChoiceDeadlockError()
    testValidationConstraints()
    testDoActivityCompletionTransition()
    
    testTransitionPriorityOverDeferral()
    testDeepHistoryWithOrthogonalRegions()
    testNestedCompositeExitOrder()
    
    testInnerStatePriorityOverParent()
    testGuardedCompletionTransition()
    testMultipleTriggersTransition()
    
    testDeferredEventInheritance()
    testCompositeStateReentry()
    testTransitionGuardPriority()
    
    testInternalVsSelfTransition()
    testExitPointCrossRegion()
    testOrthogonalFinalStateSynchronization()
    
    testDirectCrossRegionEntry()
    testSubmachineStateCompletion()
    testDeferredEventReleaseUnhandled()
    
    print("\n🏁 所有测试执行完毕")
}

// 调用此函数执行测试
// runAllStateMachineTests()
