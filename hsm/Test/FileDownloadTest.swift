import Foundation

// 下载相关事件
struct StartDownloadEvent: EventProtocol {
    let eventType = EventType("StartDownload")
    let url: String
}

struct PauseDownloadEvent: EventProtocol {
    let eventType = EventType("PauseDownload")
}

struct ResumeDownloadEvent: EventProtocol {
    let eventType = EventType("ResumeDownload")
}

struct CancelDownloadEvent: EventProtocol {
    let eventType = EventType("CancelDownload")
}

struct DownloadProgressEvent: EventProtocol {
    let eventType = EventType("DownloadProgress")
    let progress: Double // 0.0 ~ 1.0
}

struct DownloadCompleteEvent: EventProtocol {
    let eventType = EventType("DownloadComplete")
    let filePath: String
}

struct DownloadFailedEvent: EventProtocol {
    let eventType = EventType("DownloadFailed")
    let error: String
}

struct ConnectedEvent: EventProtocol {
    let eventType = EventType("Connected")
}

struct ResetEvent: EventProtocol {
    let eventType = EventType("Reset")
}

struct KillEvent: EventProtocol {
    let eventType = EventType("Kill")
}

// MARK: - 增强版状态机（带日志功能）

public class DebuggableStateMachine: StateMachine {
//    deinit {
//        print("StateMachine Dealloc")
//    }
    
    override public func post(event: EventProtocol) {
        if event as? StateCompletionEvent == nil {
            StateMachineLogger.log(event: "EVENT_POST", details: [
                "type": event.eventType.identifier,
                "queueCount": eventQueue.count + 1
            ])
        }
        super.post(event: event)
    }

    override public func start(in externalContext: StateMachineContext? = nil) {
        StateMachineLogger.log(event: "MACHINE_START", details: [
            "name": name ?? "Unnamed",
            "regions": regions.count
        ])
        super.start(in: externalContext)
    }

//    override public func handleUnhandledEvent(_ event: EventProtocol) {
//        logger?.log(event: "EVENT_UNHANDLED", details: [
//            "type": event.eventType.identifier,
//            "currentConfig": getActiveStateConfiguration().activeStates.map { $0.name ?? "?" }
//        ])
//        super.handleUnhandledEvent(event)
//    }
}

func buildFileDownloadStateMachine() -> DebuggableStateMachine {
    let sm = DebuggableStateMachine(name: "FileDownloader")
 
    // 创建主区域
    let mainRegion = Region(name: "MainRegion")

    // ---------- 状态定义 ----------
    let idle = SimpleState(name: "Idle")
    let connecting = SimpleState(name: "Connecting")
    let downloading = CompositeState(name: "Downloading") // 复合状态，可包含子状态
    let paused = SimpleState(name: "Paused")
    let completed = SimpleState(name: "Completed")
    let failed = SimpleState(name: "Failed")

    // ---------- 下载中复合状态的内部区域 ----------
    let downloadingRegion = Region(name: "DownloadingRegion")
    let active = SimpleState(name: "Active")
    let error = SimpleState(name: "Error") // 演示内部临时错误处理

    downloadingRegion.addVertex(active)
    downloadingRegion.addVertex(error)

    // 在下载区域内部，从 active 开始
    let initialInDownloading = InitialPseudostate(name: "InitDownloading")
    initialInDownloading.addTransition(to: active)
    downloadingRegion.addVertex(initialInDownloading)

    let choice = Choice(name: "ConnectResultChoice")

    choice.addTransition(
        to: downloading,
        guardCondition: AnyGuard { _ in
            // 例如：根据文件大小或校验结果决定
            true
        },
        action: AnyAction { _ in
            print(" 进入 Completed")
        }
    )

    choice.addTransition(
        to: error,
        guardCondition: AnyGuard { _ in
            false
        },
        action: AnyAction { _ in
            print(" 进入 Failed")
        }
    )

    // active 状态行为
    active
        .onEntry { context in
            if let progressEvent = context.currentEvent as? DownloadProgressEvent {
                print("  ⬇️ 下载进度: \(Int(progressEvent.progress * 100))%")
            } else {
                print("  ⬇️ 开始下载数据...")
            }
        }
        .onExit { _ in
            print("  ⏸️ 下载暂停或结束")
        }

    // 内部转换：下载进度事件（不离开 active）
    active.addInternalTransition(trigger: Trigger(eventType: EventType("DownloadProgress")), action: AnyAction { context in
        if let event = context.currentEvent as? DownloadProgressEvent {
            print("  📊 进度更新: \(Int(event.progress * 100))% ")
        }
    })

    // 内部错误处理：模拟临时错误后回到 active（实际可设计为重试）
    active.addInternalTransition(
        trigger: Trigger(eventType: EventType("TemporaryError")),
        action: AnyAction { _ in
            print("  ⚠️ 临时错误，自动重试...")
        }
    )

    // 将区域添加到 downloading 复合状态
    downloading.addRegion(downloadingRegion)

    // ---------- 状态行为 ----------
    idle.onEntry { _ in
        print("  💤 空闲，等待下载任务")
    }

    downloading
        .onEntry { _ in
            print("进入下载状态")
        }
        .onExit { _ in
            print("退出下载状态")
        }
        .onDo { _ in
            print("  downloading do ")
        }

    connecting
        .onEntry { context in
            if let event = context.currentEvent as? StartDownloadEvent {
                print("  🔗 正在连接服务器: \(event.url)")
                context.stateMachine?.post(event: ConnectedEvent())
            }
        }
        .onDo { _ in
            print("  connecting do ")
        }
        .onExit { _ in
            print("  ✅ 连接完成")
        }

    paused
        .onEntry { _ in
            print("  ⏸️ 下载已暂停")
        }
        .onExit { _ in
            print("  ▶️ 恢复下载")
        }

    completed.onEntry { _ in
        print("  ✅ 下载完成！")
    }

    failed.onEntry { context in
        if let event = context.currentEvent as? DownloadFailedEvent {
            print("  ❌ 下载失败: \(event.error)")
        } else {
            print("  ❌ 下载失败")
        }
    }

    // ---------- 转换配置 ----------
    // Idle -> Connecting (StartDownload)
    idle.addTransition(
        to: connecting,
        trigger: Trigger(eventType: EventType("StartDownload")),
        action: AnyAction { _ in
            print("  🚀 启动下载任务")
        }
    )

    // Connecting -> Downloading (完成转换)
    connecting.addTransition(
        to: choice,
        trigger: Trigger(eventType: EventType("Connected")), // 完成转换
        guardCondition: AnyGuard { _ in
            // 模拟连接成功
            print("  ✅ 连接成功")
            return true
        },
        action: AnyAction { _ in
            print("  ⬇️ 进入下载状态")
        }
    )

    // Downloading -> Paused (Pause)
    downloading.addTransition(
        to: paused,
        trigger: Trigger(eventType: EventType("PauseDownload")),
        action: AnyAction { _ in
            print("  ⏸️ 暂停下载")
        }
    )

    // Paused -> Downloading (Resume)
    paused.addTransition(
        to: downloading,
        trigger: Trigger(eventType: EventType("ResumeDownload")),
        action: AnyAction { _ in
            print("  ▶️ 恢复下载")
        }
    )

    // Downloading -> Completed (DownloadComplete)
    downloading.addTransition(
        to: completed,
        trigger: Trigger(eventType: EventType("DownloadComplete")),
        action: AnyAction { context in
            if let event = context.currentEvent as? DownloadCompleteEvent {
                print("  ✅ 文件已保存至: \(event.filePath)")
            }
        }
    )

    // Downloading -> Failed (DownloadFailed) 或取消
    downloading.addTransition(
        to: failed,
        trigger: Trigger(eventType: EventType("DownloadFailed")),
        action: AnyAction { context in
            if let event = context.currentEvent as? DownloadFailedEvent {
                print("  ❌ 错误: \(event.error)")
            }
        }
    )

    // 从任何中间状态取消 (Cancel) 直接进入 Idle（简单处理）
    connecting.addTransition(
        to: idle,
        trigger: Trigger(eventType: EventType("CancelDownload")),
        action: AnyAction { _ in print("  🛑 取消连接") }
    )
    downloading.addTransition(
        to: idle,
        trigger: Trigger(eventType: EventType("CancelDownload")),
        action: AnyAction { _ in print("  🛑 取消下载") }
    )
    paused.addTransition(
        to: idle,
        trigger: Trigger(eventType: EventType("CancelDownload")),
        action: AnyAction { _ in print("  🛑 取消下载") }
    )

    // 完成或失败后，可手动重置回 idle（但 FinalState 通常不外出）
    // 为演示简单，我们添加一个 Reset 事件
    completed.addTransition(
        to: idle,
        trigger: Trigger(eventType: EventType("Reset")),
        action: AnyAction { _ in print("  🔄 重置到空闲") }
    )
    failed.addTransition(
        to: idle,
        trigger: Trigger(eventType: EventType("Reset")),
        action: AnyAction { _ in print("  🔄 重置到空闲") }
    )

    // ---------- 初始伪状态 ----------
    let initial = InitialPseudostate(name: "Initial")
    initial.addTransition(to: idle)

    // 将所有顶点添加到主区域
    mainRegion.addVertex(initial)
    mainRegion.addVertex(idle)
    mainRegion.addVertex(choice)
    mainRegion.addVertex(connecting)
    mainRegion.addVertex(downloading)
    mainRegion.addVertex(paused)
    mainRegion.addVertex(completed)
    mainRegion.addVertex(failed)

    sm.addRegion(mainRegion)
    return sm
}

func runFileDownloadExample() {
    print("╔════════════════════════════════════════════════════════╗")
    print("║             文件下载状态机演示                         ║")
    print("╚════════════════════════════════════════════════════════╝")
    print()

    let downloader = buildFileDownloadStateMachine()
    downloader.start()

    // 模拟用户操作
    print("\n>>> 1. 启动下载任务")
    downloader.post(event: StartDownloadEvent(url: "https://example.com/file.zip"))

    // 模拟连接完成后自动进入下载中（通过完成转换）
    // 这里我们手动发送进度事件（实际应由下载任务触发）
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        print("\n>>> 2. 下载进度更新")
        downloader.post(event: DownloadProgressEvent(progress: 0.3))
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        print("\n>>> 2. 下载进度更新")
        downloader.post(event: DownloadProgressEvent(progress: 0.4))
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        print("\n>>> 3. 暂停下载")
        downloader.post(event: PauseDownloadEvent())
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        print("\n>>> 4. 恢复下载")
        downloader.post(event: ResumeDownloadEvent())
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        print("\n>>> 2. 下载进度更新")
        downloader.post(event: DownloadProgressEvent(progress: 0.8))
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
        print("\n>>> 5. 下载完成")
        downloader.post(event: DownloadCompleteEvent(filePath: "/Downloads/file.zip"))
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
        print("\n>>> 6. 重置状态机")
        downloader.post(event: ResetEvent()) // 使用简单事件
    }

    // 让主线程等待足够长时间以观察输出
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 10))
}

/// 匿名事件 - 用于不需要携带额外数据的简单事件触发
public struct AnonymousEvent: EventProtocol {
    public let eventType: EventType

    public init(_ eventType: EventType) {
        self.eventType = eventType
    }

    public init(_ identifier: String) {
        self.eventType = EventType(identifier)
    }
}

extension EventType {
    static let Kill = EventType("Kill")
}

/// 目标：验证 FinalState 不能有出转换，以及 Terminate 伪状态不执行退出动作。
func testUMLSemantics() {
    let sm = StateMachine(name: "UMLTest")
    let region = Region(name: "R1")

    let idle = SimpleState(name: "Idle")
    var didExitIdle = false
    idle.onExit { _ in
        didExitIdle = true
    }

    // 场景 A: FinalState 尝试添加出转换
    let final = FinalState(name: "Final")
    final.addTransition(to: idle, trigger: Trigger(eventType: EventType("Reset")))

    // 场景 B: Terminate 伪状态
    let terminate = TerminatePseudostate(name: "Terminate")
    idle.addTransition(to: terminate, trigger: Trigger(eventType: .Kill))

    let initial = InitialPseudostate()
    initial.addTransition(to: idle)

    region.addVertex(initial)
    region.addVertex(idle)
    region.addVertex(final)
    region.addVertex(terminate)
    sm.addRegion(region)

    // 启动并测试
    do {
        try sm.validate() // 原代码此处不报错，重构代码会抛出错误
        print("❌ 场景A失败：FinalState 允许了出转换")
    } catch {
        print("✅ 场景A通过：拦截 FinalState 的出转换 - \(error.localizedDescription)")
    }

    // 强行启动测试 Terminate
    sm.errorStrategy = .logWarning // 防止校验报错阻断
    sm.start()
    sm.post(event: KillEvent()) // 触发进入 Terminate

    // 检查 Idle 的 exit 是否执行
    if didExitIdle {
        print("❌ 场景B失败：Terminate 伪状态执行了 Exit 动作")
    } else {
        print("✅ 场景B通过：Terminate 伪状态直接终止，未执行 Exit 动作")
    }
}

func testRTCTiming() {
    let sm = StateMachine(name: "RTCTest")
    let region = Region(name: "R1")

    let stateA = SimpleState(name: "StateA")
    let stateB = SimpleState(name: "StateB")

    // A 的 doActivity 瞬间完成，触发完成转换到 B
    stateA.onDo { _ in /* 瞬间完成 */ }
    stateA.completionTransition(to: stateB)

    // B 监听普通事件
    stateB.onEntry { _ in print("进入了 StateB") }
    stateB.addTransition(to: stateA, trigger: Trigger(eventType: EventType("Back")))

    let initial = InitialPseudostate()
    initial.addTransition(to: stateA)

    region.addVertex(initial)
    region.addVertex(stateA)
    region.addVertex(stateB)
    sm.addRegion(region)

    sm.start()

    // 关键测试：向外部队列塞入大量耗时事件，再发完成事件
    print(">>> 开始向外部队列塞入 1000 个无用事件")
    for i in 0 ..< 1000 {
        sm.post(event: AnonymousEvent("JunkEvent_\(i)"))
    }

    // 检查当前状态
    let currentState = sm.getActiveStateConfiguration().leafStates.first
    if currentState === stateB {
        print("✅ 时序测试通过：完成事件立即生效，未被 1000 个外部事件阻塞")
    } else {
        print("❌ 时序测试失败：状态还停留在 StateA，完成事件被排在了外部队列末尾")
    }
}

func testExitPointLogic() {
    let sm = StateMachine(name: "ExitPointTest")
    let region = Region(name: "R1")

    let outside = SimpleState(name: "Outside")
    let composite = CompositeState(name: "Composite")
    let compRegion = Region(name: "CompRegion")

    var didExitComposite = false
    composite.onExit { _ in didExitComposite = true }

    let innerState = SimpleState(name: "InnerState")
    let exitPt = ExitPoint(name: "Exit")

    // 内部状态 -> ExitPoint -> 外部状态
    innerState.addTransition(to: exitPt, trigger: Trigger(eventType: EventType("Escape")))
    exitPt.addTransition(to: outside)

    let compInitial = InitialPseudostate()
    compInitial.addTransition(to: innerState)

    compRegion.addVertex(compInitial)
    compRegion.addVertex(innerState)
    compRegion.addVertex(exitPt)
    composite.addRegion(compRegion)

    let initial = InitialPseudostate()
    initial.addTransition(to: composite)

    region.addVertex(initial)
    region.addVertex(composite)
    region.addVertex(outside)
    sm.addRegion(region)

    sm.start()
    sm.post(event: AnonymousEvent("Escape")) // 触发退出

    if didExitComposite {
        print("✅ ExitPoint 测试通过：正确退出了复合状态并执行了 exitAction")
    } else {
        print("❌ ExitPoint 测试失败：只执行了出转换，未执行复合状态的 exitAction")
    }
}

func testArchitectureRobustness() {
    let sm = StateMachine(name: "RobustTest")
    let region = Region(name: "R1")

    let composite = CompositeState(name: "Composite")
    let subRegion = Region(name: "SubRegion")

    // 关键：子状态没有 doActivity，进入后立刻触发完成事件
    let subState = SimpleState(name: "SubState")
    let finalInSub = FinalState(name: "FinalInSub")
    subState.completionTransition(to: finalInSub)

    let subInitial = InitialPseudostate()
    subInitial.addTransition(to: subState)

    subRegion.addVertex(subInitial)
    subRegion.addVertex(subState)
    subRegion.addVertex(finalInSub)
    composite.addRegion(subRegion)

    let initial = InitialPseudostate()
    initial.addTransition(to: composite)

    region.addVertex(initial)
    region.addVertex(composite)
    sm.addRegion(region)

    // 启动状态机，这将进入复合状态及其子状态，子状态瞬间完成
    sm.start()

    // 如果代码不够健壮，上面这行就会因为 subRegion.stateMachine 为 nil 而 Crash
    print("✅ 架构健壮性测试通过：嵌套区域触发完成事件未引起崩溃")
}
