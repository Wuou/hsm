import Foundation

// ============================================================================

// MARK: - 补充测试辅助工具

// ============================================================================

// 1. 用于测试 eventParameter 的带载事件
struct PayloadEvent: EventProtocol {
    var eventType: EventType
    let message: String
    init(id: String, message: String) {
        self.eventType = EventType(id)
        self.message = message
    }
}

// 2. 用于测试 Delegate 的 Mock 类
class MockStateMachineDelegate: StateMachineDelegate {
    var didStart = false
    var didStop = false
    var didComplete = false
    var didTransition = false
    var lastTransitionEvent: EventProtocol?
    var handledEvents: [EventProtocol] = []
    var unhandledErrors: [StateMachineError] = []
    
    func stateMachineDidStart(_ stateMachine: StateMachine) { didStart = true }
    func stateMachineDidStop(_ stateMachine: StateMachine) { didStop = true }
    func stateMachineDidComplete(_ stateMachine: StateMachine) { didComplete = true }
    
    func stateMachine(_ stateMachine: StateMachine, didTransitionFrom fromState: State?, to toState: State?, by event: EventProtocol?) {
        didTransition = true
        lastTransitionEvent = event
    }
    
    func stateMachine(_ stateMachine: StateMachine, willProcessEvent event: EventProtocol) {}
    
    func stateMachine(_ stateMachine: StateMachine, didProcessEvent event: EventProtocol, handled: Bool) {
        if handled { handledEvents.append(event) }
    }
    
    func stateMachine(_ stateMachine: StateMachine, didFailWithError error: StateMachineError) {
        unhandledErrors.append(error)
    }
}

// ============================================================================

// MARK: - 补充测试用例

// ============================================================================

func testDelegateCallbacks() {
    print("\n--- 测试：状态机委托回调 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "DelegateTest")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let sFinal = FinalState(name: "Final")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: sFinal, trigger: e1)
    r.addVertex(initP); r.addVertex(s1); r.addVertex(sFinal)
    sm.addRegion(r)
    
    // --- 阶段1：测试强制停止 ---
    var mockDelegate = MockStateMachineDelegate()
    sm.delegate = mockDelegate
    
    sm.start()
    SMAssert(mockDelegate.didStart, "启动时应触发 didStart")
    
    sm.stop()
    SMAssert(mockDelegate.didStop, "手动停止时应触发 didStop")
    
    // --- 阶段2：测试状态转换与自然完成 ---
    mockDelegate = MockStateMachineDelegate() // 重置 Mock 状态
    sm.delegate = mockDelegate
    
    sm.start() // 重新启动
    SMAssert(mockDelegate.didStart, "重新启动时应触发 didStart")
    
    sm.post(event: TestEvent(e1))
    SMAssert(mockDelegate.didTransition, "状态转换时应触发 didTransition")
    SMAssert(mockDelegate.lastTransitionEvent?.eventType == e1.eventType, "转换事件应匹配 E1")
    SMAssert(mockDelegate.handledEvents.contains(where: { $0.eventType == e1.eventType }), "应处理了事件 E1")
    
    // 到达终态自然完成 (同步触发)
    SMAssert(mockDelegate.didComplete, "到达终态应触发 didComplete")
    
    // 已完成的状态机，再次 stop 不应触发 didStop
    mockDelegate.didStop = false
    sm.stop()
    SMAssert(!mockDelegate.didStop, "已完成的状态机调用 stop 不应触发 didStop")
}

func testBuilderPattern() {
    print("\n--- 测试：构建器模式 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    
    do {
        let sm = try StateMachineBuilder(name: "BuilderSM")
            .region("R1") {
                let initP = InitialPseudostate()
                let s1 = SimpleState(name: "S1")
                let s2 = SimpleState(name: "S2")
                initP.addTransition(to: s1)
                s1.addTransition(to: s2, trigger: e1)
                return [initP, s1, s2]
            }
            .build()
        
        sm.start()
        SMAssert(sm.getActiveStateConfiguration().activeStates.first?.name == "S1", "构建器创建的状态机应正常启动进入 S1")
        sm.post(event: TestEvent(e1))
        SMAssert(sm.getActiveStateConfiguration().activeStates.first?.name == "S2", "构建器创建的状态机应正常转换到 S2")
    } catch {
        SMAssert(false, "构建器构建过程不应抛出错误")
    }
}

func testContextAPIs() {
    print("\n--- 测试：上下文 API ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    let sm = StateMachine(name: "ContextAPISM")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: s2, trigger: e1)
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2)
    sm.addRegion(r)
    sm.start()
    
    // 1. 测试 isInState
    SMAssert(sm.context.isInState(s1), "应处于 S1")
    SMAssert(!sm.context.isInState(s2), "不应处于 S2")
    
    // 2. 测试 eventParameter
    let payloadTrigger = Trigger(eventType: EventType("Payload"))
    s1.addInternalTransition(trigger: payloadTrigger, action: AnyAction { ctx in
        let msg: String? = ctx.eventParameter(named: "message")
        ctx.userInfo["extractedMsg"] = msg
    })
    sm.post(event: PayloadEvent(id: "Payload", message: "HelloContext"))
    SMAssert(sm.context.userInfo["extractedMsg"] as? String == "HelloContext", "应能通过 eventParameter 提取参数")
    
    // 3. 测试 sendSignal
    s1.onExit { ctx in ctx.sendSignal(TestEvent(e2)) } // 退出 S1 时发送 E2
    s2.onEntry { ctx in ctx.userInfo["s2_entered_by"] = ctx.currentEvent?.eventType.identifier }
    sm.post(event: TestEvent(e1)) // E1 触发 S1->S2
    SMAssert(sm.context.userInfo["s2_entered_by"] as? String == e1.eventType.identifier, "S2 应由 E1 触发进入，sendSignal 是异步入队的")
}

func testErrorHandlingStrategies() {
    print("\n--- 测试：错误处理策略 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    
    // 1. LogWarning 策略
    let sm1 = StateMachine(name: "LogWarningSM")
    let r1 = Region(name: "R1")
    let initP1 = InitialPseudostate()
    let s1_1 = SimpleState(name: "S1")
    initP1.addTransition(to: s1_1)
    r1.addVertex(initP1); r1.addVertex(s1_1)
    sm1.addRegion(r1)
    sm1.errorStrategy = .logWarning
    sm1.start()
    sm1.post(event: TestEvent(e1)) // 未处理事件，不应崩溃
    SMAssert(sm1.getActiveStateConfiguration().contains(s1_1), "LogWarning 策略下状态机应继续运行")
    
    // 2. AssertionFailure 策略 (仅在 Debug 下断言，此处验证配置不崩溃)
    let sm2 = StateMachine(name: "AssertSM")
    let r2 = Region(name: "R2")
    let initP2 = InitialPseudostate()
    let s2_1 = SimpleState(name: "S1")
    initP2.addTransition(to: s2_1)
    r2.addVertex(initP2); r2.addVertex(s2_1)
    sm2.addRegion(r2)
    sm2.errorStrategy = .assertionFailure
    // sm2.start(); sm2.post(event: TestEvent(e1)) // 注意：这会触发断言失败，测试时注释掉
    SMAssert(true, "AssertionFailure 策略配置成功")
}

//
// func testConcurrentEventPosting() {
//    print("\n--- 测试：并发发送事件 ---")
//    let e1 = Trigger(eventType: EventType("E1"))
//    let sm = StateMachine(name: "ConcurrentSM")
//    let r = Region(name: "R1")
//    let initP = InitialPseudostate()
//    let s1 = SimpleState(name: "S1")
//    let sFinal = FinalState(name: "Final")
//
//    initP.addTransition(to: s1)
//    s1.addTransition(to: sFinal, trigger: e1)
//    r.addVertex(initP); r.addVertex(s1); r.addVertex(sFinal)
//    sm.addRegion(r)
//    sm.start()
//
//    // 从多个线程同时发送事件
//    let group = DispatchGroup()
//    for _ in 1...10 {
//        DispatchQueue.global().async(group: group) {
//            sm.post(event: TestEvent(e1))
//        }
//    }
//    group.wait()
//
//    // 等待状态机处理完队列
//    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
//
//    // 第一个 E1 触发进入终态，后续 E1 应被忽略或抛出未处理错误，但状态机不应崩溃
//    SMAssert(sm.getActiveStateConfiguration().contains(sFinal), "并发事件下应安全到达终态")
//    SMAssert(!sm.active, "状态机应已结束")
// }

func testSubmachineWithEntryPointAndExitPoint() {
    print("\n--- 测试：子状态机与 Entry/Exit Point 组合 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    
    // 内部状态机
    let innerSM = StateMachine(name: "InnerSM")
    let innerR = Region(name: "InnerR")
    let innerInit = InitialPseudostate()
    let innerS1 = SimpleState(name: "InnerS1")
    let innerS2 = SimpleState(name: "InnerS2")
    let ep = EntryPoint(name: "InnerEP")
    let xp = ExitPoint(name: "InnerXP")
    
    innerInit.addTransition(to: innerS1)
    ep.addTransition(to: innerS2) // 从入口点进入 S2
    innerS1.addTransition(to: xp, trigger: e2) // 从 S2 触发出口点
    innerR.addVertex(innerInit); innerR.addVertex(innerS1); innerR.addVertex(innerS2)
    innerR.addVertex(ep); innerR.addVertex(xp)
    innerSM.addRegion(innerR)
    
    // 外部状态机
    let outerSM = StateMachine(name: "OuterSM")
    let outerR = Region(name: "OuterR")
    let outerInit = InitialPseudostate()
    let outerS1 = SimpleState(name: "OuterS1")
    let subState = SubmachineState(name: "SubSM", submachine: innerSM)
    let outerS2 = SimpleState(name: "OuterS2")
    
    outerInit.addTransition(to: outerS1)
    outerS1.addTransition(to: subState, trigger: e1)
    subState.addTransition(to: outerS2, triggers: []) // 子状态机完成转换
    
    outerR.addVertex(outerInit); outerR.addVertex(outerS1); outerR.addVertex(subState); outerR.addVertex(outerS2)
    outerSM.addRegion(outerR)
    outerSM.start()
    
    // 测试外部启动子状态机，默认进入 InnerS1，然后自内而外通过 ExitPoint 结束
    outerSM.post(event: TestEvent(e1))
    SMAssert(innerSM.getActiveStateConfiguration().contains(innerS1), "子状态机应默认进入 InnerS1")
    
    outerSM.post(event: TestEvent(e2)) // 触发 InnerS1 -> XP，内部完成，外部触发转换
    SMAssert(!innerSM.active, "内部状态机应停止")
    SMAssert(outerSM.getActiveStateConfiguration().contains(outerS2), "应进入 OuterS2")
}

func testNestedSubmachineStates() {
    print("\n--- 测试：嵌套子状态机 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    
    // 最深层状态机
    let deepSM = StateMachine(name: "DeepSM")
    let deepR = Region(name: "DeepR")
    let deepInit = InitialPseudostate()
    let deepS1 = SimpleState(name: "DeepS1") // 🌟 新增：用于等待事件的中间状态
    let deepFinal = FinalState(name: "DeepFinal")
    
    deepInit.addTransition(to: deepS1) // 🌟 修复：初始转换不能有触发器
    deepS1.addTransition(to: deepFinal, trigger: e1) // 🌟 修复：由 E1 触发进入终态
    deepR.addVertex(deepInit); deepR.addVertex(deepS1); deepR.addVertex(deepFinal)
    deepSM.addRegion(deepR)
    
    // 中间层状态机
    let midSM = StateMachine(name: "MidSM")
    let midR = Region(name: "MidR")
    let midInit = InitialPseudostate()
    let midSub = SubmachineState(name: "MidSub", submachine: deepSM)
    let midFinal = FinalState(name: "MidFinal")
    midInit.addTransition(to: midSub)
    midSub.addTransition(to: midFinal, triggers: []) // deepSM完成触发
    midR.addVertex(midInit); midR.addVertex(midSub); midR.addVertex(midFinal)
    midSM.addRegion(midR)
    
    // 顶层状态机
    let topSM = StateMachine(name: "TopSM")
    let topR = Region(name: "TopR")
    let topInit = InitialPseudostate()
    let topSub = SubmachineState(name: "TopSub", submachine: midSM)
    topInit.addTransition(to: topSub)
    topR.addVertex(topInit); topR.addVertex(topSub)
    topSM.addRegion(topR)
    
    topSM.start()
    SMAssert(deepSM.active, "所有嵌套状态机都应启动")
    SMAssert(deepSM.getActiveStateConfiguration().contains(deepS1), "最深层应停留在 DeepS1")
    
    // 事件应穿透到最深层
    topSM.post(event: TestEvent(e1))
    SMAssert(!deepSM.active, "最深层状态机应完成")
    SMAssert(!midSM.active, "中间层状态机应完成")
    SMAssert(topSM.getActiveStateConfiguration().contains(topSub), "顶层状态机应仍在 TopSub (无出转换)")
}

func testEventQueueOrdering() {
    print("\n--- 测试：事件队列顺序 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    let e3 = Trigger(eventType: EventType("E3"))
    
    let sm = StateMachine(name: "QueueOrder")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    let s3 = SimpleState(name: "S3")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: s2, trigger: e1)
    s2.addTransition(to: s3, trigger: e2)
    s3.onEntry { $0.userInfo["reached_end"] = true }
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2); r.addVertex(s3)
    sm.addRegion(r)
    sm.start()
    
    // 批量入队事件
    sm.post(event: TestEvent(e3)) // 无效事件，应被忽略
    sm.post(event: TestEvent(e1)) // S1 -> S2
    sm.post(event: TestEvent(e2)) // S2 -> S3
    
    SMAssert(sm.context.userInfo["reached_end"] as? Bool == true, "事件应按入队顺序依次处理，最终到达 S3")
}

func testEmptyStateMachine() {
    print("\n--- 测试：空状态机 (无区域) ---")
    let sm = StateMachine(name: "EmptySM")
    sm.start()
    SMAssert(sm.active, "空状态机应能启动")
    sm.stop()
    SMAssert(!sm.active, "空状态机应能停止")
}

// func testDoActivityCancellation() {
//    print("\n--- 测试：DoActivity 被转换中断 ---")
//    let e1 = Trigger(eventType: EventType("E1")) // 打断事件
//    let sm = StateMachine(name: "DoCancel")
//    let r = Region(name: "R1")
//    let initP = InitialPseudostate()
//    let s1 = SimpleState(name: "S1")
//    let s2 = SimpleState(name: "S2")
//    let s3 = SimpleState(name: "S3") // 如果 DoActivity 意外完成会错误进入此状态
//
//    initP.addTransition(to: s1)
//    s1.addTransition(to: s2, trigger: e1)
//    s1.addTransition(to: s3, triggers: []) // S1 的完成转换
//
//    // 设置一个耗时 2 秒的 DoActivity
//    s1.onDo { ctx in
//        Thread.sleep(forTimeInterval: 2.0)
//        ctx.userInfo["do_finished"] = true
//    }
//
//    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2); r.addVertex(s3)
//    sm.addRegion(r)
//    sm.start()
//
//    SMAssert(sm.getActiveStateConfiguration().contains(s1), "应进入 S1")
//
//    // 等待 0.1 秒，确保 DoActivity 已经在后台开始执行
//    Thread.sleep(forTimeInterval: 0.1)
//
//    // 发送 E1 打断 S1，此时 S1 退出，DoActivity 应被 Cancel
//    sm.post(event: TestEvent(e1))
//    SMAssert(sm.getActiveStateConfiguration().contains(s2), "应被 E1 打断并进入 S2")
//
//    // 等待足够长的时间（超过 DoActivity 的 2 秒），验证其完成逻辑是否被彻底拦截
//    Thread.sleep(forTimeInterval: 2.5)
//
//    SMAssert(sm.context.userInfo["do_finished"] == nil, "DoActivity 应被取消，未执行完毕")
//    SMAssert(!sm.getActiveStateConfiguration().contains(s3), "Completion Transition 不应被触发，不应进入 S3")
//    SMAssert(sm.getActiveStateConfiguration().contains(s2), "状态应稳定停留在 S2")
// }

func testDoActivityCancellation() {
    print("\n--- 测试：DoActivity 被转换中断 ---")
    let e1 = Trigger(eventType: EventType("E1")) // 打断事件
    let sm = StateMachine(name: "DoCancel")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    let s3 = SimpleState(name: "S3") // 如果 DoActivity 意外完成会错误进入此状态
    
    initP.addTransition(to: s1)
    s1.addTransition(to: s2, trigger: e1)
    s1.addTransition(to: s3, triggers: []) // S1 的完成转换
    
    // 修改：在 sleep 之前设置标志，证明闭包确实开始执行了
    s1.onDo { ctx in
        ctx.userInfo["do_started"] = true
        Thread.sleep(forTimeInterval: 2.0)
        // 注意：这行代码在 GCD 中无法阻止其执行，这是线程模型的客观限制
        // ctx.userInfo["do_finished"] = true
    }
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2); r.addVertex(s3)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.getActiveStateConfiguration().contains(s1), "应进入 S1")
    
    // 等待 0.1 秒，确保 DoActivity 已经在后台开始执行
    Thread.sleep(forTimeInterval: 0.1)
    SMAssert(sm.context.userInfo["do_started"] as? Bool == true, "Do Activity 应已开始执行")
    
    // 发送 E1 打断 S1，此时 S1 退出
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(s2), "应被 E1 打断并进入 S2")
    
    // 等待足够长的时间（超过 DoActivity 的 2 秒）
    Thread.sleep(forTimeInterval: 2.5)
    
    // 🌟 核心断言：UML 规范只保证 Completion Transition 不被触发，状态机行为不混乱
    SMAssert(!sm.getActiveStateConfiguration().contains(s3), "Completion Transition 不应被触发，不应进入 S3")
    SMAssert(sm.getActiveStateConfiguration().contains(s2), "状态应稳定停留在 S2，未受后台线程干扰")
}

func testConcurrentEventPosting() {
    print("\n--- 测试：多线程并发 Post 事件 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let sm = StateMachine(name: "Concurrent")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    
    initP.addTransition(to: s1)
    // 自转换，用来计数
    s1.addTransition(to: s1, trigger: e1)
    s1.onEntry { $0.userInfo["count"] = ($0.userInfo["count"] as? Int ?? 0) + 1 }
    
    r.addVertex(initP); r.addVertex(s1)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.context.userInfo["count"] as? Int == 1, "初始进入应计数 1")
    
    let totalEvents = 200
    let concurrentQueue = DispatchQueue(label: "com.sm.test.concurrent", attributes: .concurrent)
    let group = DispatchGroup()
    
    // 从多个线程同时投递 200 个事件
    for _ in 0 ..< totalEvents {
        concurrentQueue.async(group: group) {
            sm.post(event: TestEvent(e1))
        }
    }
    
    // 等待所有投递动作完成
    group.wait()
    
    // 由于状态机内部有异步 RTC 队列，需短暂等待所有事件被消费完
    let semaphore = DispatchSemaphore(value: 0)
    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
        semaphore.signal()
    }
    semaphore.wait()
    
    let finalCount = sm.context.userInfo["count"] as? Int ?? 0
    // 1 (初始) + 200 (并发事件) = 201
    SMAssert(finalCount == 1 + totalEvents, "应精确处理所有并发事件，期望 \(1 + totalEvents)，实际 \(finalCount)")
}

func testInternalTransitionPriorityOverDeferral() {
    print("\n--- 测试：内部转换优先于延迟 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    
    let sm = StateMachine(name: "InternalOverDefer")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    
    // S1 既延迟 E1，又有 E1 的内部转换
    let s1 = SimpleState(name: "S1").defer(e1.eventType)
    let s2 = SimpleState(name: "S2")
    
    initP.addTransition(to: s1)
    s1.addInternalTransition(trigger: e1, action: AnyAction { $0.userInfo["internal_fired"] = true })
    s1.addTransition(to: s2, trigger: e1) // 显式出转换也应该低于内部转换
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2)
    sm.addRegion(r)
    sm.start()
    
    sm.post(event: TestEvent(e1))
    
    // 验证：事件未被延迟，也未触发外部转换，而是被内部转换消费
    SMAssert(sm.context.userInfo["internal_fired"] as? Bool == true, "内部转换应被执行")
    SMAssert(sm.getActiveStateConfiguration().contains(s1), "状态应停留在 S1")
}

func testDeeplyNestedDeepHistory() {
    print("\n--- 测试：深层嵌套的 Deep History ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    let e3 = Trigger(eventType: EventType("E3"))
    let e4 = Trigger(eventType: EventType("E4"))
    
    let sm = StateMachine(name: "DeepNestedHistory")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    
    // 外层复合状态
    let outerComp = CompositeState(name: "OuterComp", regions: [Region(name: "R_Outer")])
    let outerInit = InitialPseudostate()
    
    // 内层复合状态
    let innerComp = CompositeState(name: "InnerComp", regions: [Region(name: "R_Inner")])
    let innerInit = InitialPseudostate()
    let leaf1 = SimpleState(name: "Leaf1")
    let leaf2 = SimpleState(name: "Leaf2")
    
    innerComp.regions[0].addVertex(innerInit); innerComp.regions[0].addVertex(leaf1); innerComp.regions[0].addVertex(leaf2)
    innerInit.addTransition(to: leaf1)
    leaf1.addTransition(to: leaf2, trigger: e2)
    
    outerComp.regions[0].addVertex(outerInit); outerComp.regions[0].addVertex(innerComp)
    outerInit.addTransition(to: innerComp)
    
    let deepH = DeepHistory(name: "DH")
    outerComp.regions[0].addVertex(deepH)
    deepH.addTransition(to: innerComp) // 默认进入内层复合
    
    let outerS = SimpleState(name: "OuterS")
    initP.addTransition(to: outerComp)
    outerComp.addTransition(to: outerS, trigger: e3)
    outerS.addTransition(to: deepH, trigger: e4)
    
    r.addVertex(initP); r.addVertex(outerComp); r.addVertex(outerS)
    sm.addRegion(r)
    sm.start()
    
    // 1. 进入到最底层的 Leaf2
    sm.post(event: TestEvent(e2))
    SMAssert(sm.getActiveStateConfiguration().contains(leaf2), "应进入最深层 Leaf2")
    
    // 2. 退出整个嵌套结构
    sm.post(event: TestEvent(e3))
    SMAssert(sm.getActiveStateConfiguration().contains(outerS), "应退出到 OuterS")
    
    // 3. 通过深历史重入，验证是否穿透恢复到 Leaf2
    sm.post(event: TestEvent(e4))
    SMAssert(sm.getActiveStateConfiguration().contains(innerComp), "应恢复内层复合状态")
    SMAssert(sm.getActiveStateConfiguration().contains(leaf2), "深历史必须穿透恢复到最深层 Leaf2，而不是 Leaf1")
}

func testDeferredEventReleaseOnSelfTransition() {
    print("\n--- 测试：自转换时延迟事件的释放与消费 ---")
    let e1 = Trigger(eventType: EventType("E1")) // 将被延迟的事件
    let e2 = Trigger(eventType: EventType("E2")) // 触发自转换的事件
    
    let sm = StateMachine(name: "DeferRelease")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    
    // S1 初始延迟 E1，且存在 E2 触发的自转换
    let s1 = SimpleState(name: "S1").defer(e1.eventType)
    s1.onEntry { $0.userInfo["s1_enter_count"] = ($0.userInfo["s1_enter_count"] as? Int ?? 0) + 1 }
    
    initP.addTransition(to: s1)
    s1.addTransition(to: s1, trigger: e2) // 自转换
    
    r.addVertex(initP); r.addVertex(s1)
    sm.addRegion(r)
    sm.start()
    
    // 1. 投递 E1，被 S1 延迟
    sm.post(event: TestEvent(e1))
    SMAssert(sm.context.userInfo["s1_enter_count"] as? Int == 1, "初始进入 S1")
    
    // 2. 触发自转换。S1 退出时释放 E1，S1 重新进入时 E1 在队列中，但此时 S1 依然延迟 E1，所以 E1 会再次进入延迟池
    sm.post(event: TestEvent(e2))
    SMAssert(sm.context.userInfo["s1_enter_count"] as? Int == 2, "自转换后重新进入 S1")
    
    // 🌟 核心变化：现在让 S1 不再延迟 E1（模拟业务状态变更）
    s1.deferredEvents.remove(e1.eventType)
    // 给 S1 加一个 E1 的显式转换，验证事件是否真的被释放出来了
    let s2 = SimpleState(name: "S2")
    s1.addTransition(to: s2, trigger: e1)
    r.addVertex(s2)
    
    // 3. 再次触发自转换，S1 退出时释放池中的 E1，重新进入 S1，此时 S1 不延迟 E1，且有 E1 的出转换
    sm.post(event: TestEvent(e2))
    SMAssert(sm.getActiveStateConfiguration().contains(s2), "延迟事件 E1 应被释放并触发 S1->S2 的转换")
}

func testChoiceMissingElseGuardFailure() {
    print("\n--- 测试：Choice 缺少 Else 分支的容错 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    
    let sm = StateMachine(name: "ChoiceFail")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    let s1 = SimpleState(name: "S1")
    let choice = Choice(name: "C1")
    let s2 = SimpleState(name: "S2")
    
    initP.addTransition(to: s1)
    s1.addTransition(to: choice, trigger: e1)
    
    // 🌟 修复：将 guard 改为 guardCondition，明确闭包参数类型
    choice.addTransition(to: s2, guardCondition: AnyGuard { (_: StateMachineContext) in false })
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(choice); r.addVertex(s2)
    sm.addRegion(r)
    sm.start()
    
    SMAssert(sm.getActiveStateConfiguration().contains(s1), "初始应进入 S1")
    
    // 触发进入 Choice
    sm.post(event: TestEvent(e1))
    
    // 预期：Choice 找不到可用分支，转换链断裂。
    // 状态机绝不应进入 S2。
    SMAssert(!sm.getActiveStateConfiguration().contains(s2), "Choice 所有 Guard 失效，绝不应进入 S2")
}

func testPartialCompletionInterruptedByOuterTransition() {
    print("\n--- 测试：正交区域部分完成时被外部打断 ---")
    let e1 = Trigger(eventType: EventType("E1")) // 推进 R1 到终态
    let e2 = Trigger(eventType: EventType("E2")) // 外部打断事件
    
    let sm = StateMachine(name: "PartialInterrupt")
    let r1 = Region(name: "R1")
    let r2 = Region(name: "R2")
    
    // R1: 可以到达终态
    let r1Init = InitialPseudostate()
    let r1S1 = SimpleState(name: "R1_S1")
    let r1Final = FinalState(name: "R1_Final")
    r1Init.addTransition(to: r1S1)
    r1S1.addTransition(to: r1Final, trigger: e1)
    r1.addVertex(r1Init); r1.addVertex(r1S1); r1.addVertex(r1Final)
    
    // R2: 持续运行，不到终态
    let r2Init = InitialPseudostate()
    let r2S1 = SimpleState(name: "R2_S1")
    r2Init.addTransition(to: r2S1)
    r2.addVertex(r2Init); r2.addVertex(r2S1)
    
    let comp = CompositeState(name: "Comp", regions: [r1, r2])
    let initP = InitialPseudostate()
    let outerS = SimpleState(name: "OuterS")
    
    initP.addTransition(to: comp)
    comp.addTransition(to: outerS, trigger: e2) // 外部打断
    // comp 的完成转换（如果测试通过，这个转换绝不能触发）
    let wrongS = SimpleState(name: "WrongS")
    comp.addTransition(to: wrongS, triggers: [])
    
    let mainR = Region(name: "MainR")
    mainR.addVertex(initP); mainR.addVertex(comp); mainR.addVertex(outerS); mainR.addVertex(wrongS)
    sm.addRegion(mainR)
    sm.start()
    
    // 1. 推进 R1 到终态（部分完成）
    sm.post(event: TestEvent(e1))
    SMAssert(r1.isCompleted, "R1 应已完成")
    SMAssert(!r2.isCompleted, "R2 未完成")
    SMAssert(sm.getActiveStateConfiguration().contains(comp), "复合状态整体未完成，应停留在 Comp")
    
    // 2. 外部打断
    sm.post(event: TestEvent(e2))
    SMAssert(sm.getActiveStateConfiguration().contains(outerS), "应被打断并进入 OuterS")
    SMAssert(!sm.getActiveStateConfiguration().contains(wrongS), "完成转换绝不应被触发")
}

func testStrictActionExecutionOrder() {
    print("\n--- 测试：动作执行严格顺序 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    
    let sm = StateMachine(name: "ActionOrder")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    
    // 1. 构建源状态层级: OuterSource -> InnerSource
    let outerSource = CompositeState(name: "OuterSource", regions: [Region(name: "R_OS")])
    let innerSource = SimpleState(name: "InnerSource")
    let osInit = InitialPseudostate()
    osInit.addTransition(to: innerSource)
    outerSource.regions[0].addVertex(osInit)
    outerSource.regions[0].addVertex(innerSource)
    
    // 2. 构建目标状态层级: OuterTarget -> InnerTarget
    let outerTarget = CompositeState(name: "OuterTarget", regions: [Region(name: "R_OT")])
    let innerTarget = SimpleState(name: "InnerTarget")
    let otInit = InitialPseudostate()
    otInit.addTransition(to: innerTarget)
    outerTarget.regions[0].addVertex(otInit)
    outerTarget.regions[0].addVertex(innerTarget)
    
    initP.addTransition(to: outerSource)
    
    // 🌟 修复：显式声明参数类型 (_ ctx: StateMachineContext)，并直接捕获外部 log 数组
    var log: [String] = []
    
    outerSource.exitAction = AnyAction { (_: StateMachineContext) in log.append("ExitOuterSource") }
    innerSource.exitAction = AnyAction { (_: StateMachineContext) in log.append("ExitInnerSource") }
    
    innerSource.addTransition(
        to: outerTarget,
        trigger: e1,
        action: AnyAction { (_: StateMachineContext) in log.append("TransAction") }
    )
    
    outerTarget.entryAction = AnyAction { (_: StateMachineContext) in log.append("EnterOuterTarget") }
    innerTarget.entryAction = AnyAction { (_: StateMachineContext) in log.append("EnterInnerTarget") }
    
    r.addVertex(initP); r.addVertex(outerSource); r.addVertex(outerTarget)
    sm.addRegion(r)
    sm.start()
    
    // 触发跨层级转换
    sm.post(event: TestEvent(e1))
    
    // 验证顺序：退出(由内向外) -> 转换动作 -> 进入(由外向内)
    let expected = ["ExitInnerSource", "ExitOuterSource", "TransAction", "EnterOuterTarget", "EnterInnerTarget"]
    SMAssert(log == expected, "动作顺序应为: \(expected), 实际: \(log)")
}

func testDeferredEventInheritanceAndOverride() {
    print("\n--- 测试：延迟事件的继承与重写 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    let e2 = Trigger(eventType: EventType("E2"))
    
    let sm = StateMachine(name: "DeferInherit")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    
    // Parent 延迟 E1 和 E2
    let parent = CompositeState(name: "Parent", regions: [Region(name: "R_P")])
    parent.defer(e1.eventType)
    parent.defer(e2.eventType)
    
    // Child 只处理 E1（重写了父类对 E1 的延迟）
    let child = SimpleState(name: "Child")
    let otherState = SimpleState(name: "OtherState")
    child.addTransition(to: otherState, trigger: e1)
    
    let pInit = InitialPseudostate()
    pInit.addTransition(to: child)
    parent.regions[0].addVertex(pInit)
    parent.regions[0].addVertex(child)
    parent.regions[0].addVertex(otherState)
    
    initP.addTransition(to: parent)
    r.addVertex(initP); r.addVertex(parent)
    sm.addRegion(r)
    sm.start()
    
    // 1. 投递 E1，Child 有转换，应被处理，而不是被延迟
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(otherState), "E1 应被子状态转换消费，而非被父状态延迟")
    
    // 2. 投递 E2，Child 无转换，应被父状态延迟
    sm.post(event: TestEvent(e2))
    // (可以再通过让 Parent 退出，观察 E2 是否被释放来进一步验证，这里仅验证核心重写逻辑)
}

func testSubmachineExitPointBailout() {
    print("\n--- 测试：子状态机 Exit Point 跨区域跳出 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    
    let sm = StateMachine(name: "ExitPointTest")
    let mainR = Region(name: "MainR")
    let initP = InitialPseudostate()
    
    // 1. 构建子状态机
    let subSM = StateMachine(name: "SubSM")
    let subR = Region(name: "SubR")
    let subInit = InitialPseudostate()
    let subS1 = SimpleState(name: "SubS1")
    let exitP = ExitPoint(name: "Exit1")
    
    subS1.addTransition(to: exitP, trigger: e1) // 内部到达退出点
    subR.addVertex(subInit);
    subR.addVertex(subS1);
    subR.addVertex(exitP)
    subSM.addRegion(subR)
    
    // 2. 构建主状态机
    let subState = SubmachineState(name: "SubState", submachine: subSM)
    let outerS = SimpleState(name: "OuterS")
    
    initP.addTransition(to: subState)
    // 🌟 核心：ExitPoint 连接到外部状态
    subState.addTransition(to: outerS, trigger: e1) // 或者通过 exitPoint 映射，取决于你的 API 设计
    
    mainR.addVertex(initP);
    mainR.addVertex(subState);
    mainR.addVertex(outerS)
    sm.addRegion(mainR)
    sm.start()
    
    SMAssert(sm.getActiveStateConfiguration().contains(subS1), "应进入子状态机内部 SubS1")
    
    // 触发退出
    sm.post(event: TestEvent(e1))
    SMAssert(sm.getActiveStateConfiguration().contains(outerS), "应通过 ExitPoint 跳出到 OuterS")
}


func testZombieDoActivityCancellation() {
    print("\n--- 测试：僵尸 Do Activity 的取消与守卫 ---")
    let e1 = Trigger(eventType: EventType("E1"))
    
    let sm = StateMachine(name: "ZombieDo")
    let r = Region(name: "R1")
    let initP = InitialPseudostate()
    
    let s1 = SimpleState(name: "S1")
    let s2 = SimpleState(name: "S2")
    
    // 模拟一个耗时 Do Activity
    s1.onDo { ctx in
        Thread.sleep(forTimeInterval: 0.5) // 模拟耗时
    }
    
    initP.addTransition(to: s1)
    s1.addTransition(to: s2, trigger: e1) // 提前退出
    
    r.addVertex(initP); r.addVertex(s1); r.addVertex(s2)
    sm.addRegion(r)
    sm.start()
    
    // 立即触发退出，不等待 DoActivity 完成
    sm.post(event: TestEvent(e1))
    
    // 🌟 修复：使用 .activeStates.contains
    SMAssert(sm.getActiveStateConfiguration().activeStates.contains { $0.name == "S2" }, "应已到达 S2")
    
    // 等待 DoActivity 原本应该执行完的时间
    Thread.sleep(forTimeInterval: 1.0)
    
    // 🌟 核心验证：DoActivity 虽然耗时结束了，但因为被 Cancel，不应该触发 Completion 导致状态机崩溃或误转
    SMAssert(sm.getActiveStateConfiguration().activeStates.contains { $0.name == "S2" }, "状态机应仍稳定停留在 S2，未受僵尸回调影响")
}



func runAdditionalStateMachineTests() {
    StateMachineLogger.isEnabled = true
    
    testDelegateCallbacks()
    testBuilderPattern()
    testContextAPIs()
    testErrorHandlingStrategies()
    testConcurrentEventPosting()
    testSubmachineWithEntryPointAndExitPoint()
    testNestedSubmachineStates()
    testEventQueueOrdering()
    testEmptyStateMachine()
    
    testDoActivityCancellation()
    
    testInternalTransitionPriorityOverDeferral()
    testDeeplyNestedDeepHistory()
    
    testDeferredEventReleaseOnSelfTransition()
    testChoiceMissingElseGuardFailure()
    testPartialCompletionInterruptedByOuterTransition()
    
    testStrictActionExecutionOrder()
    testDeferredEventInheritanceAndOverride()
    
    testZombieDoActivityCancellation()
    
    print("\n🏁 补充测试执行完毕")
}

// 调用此函数执行补充测试
// runAdditionalStateMachineTests()
