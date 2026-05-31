import AppKit

if CommandLine.arguments.contains("--smoke-test-tasks") {
    TaskPersistenceSmokeTest.run()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.contains("--smoke-test-pet-state") {
    MainActor.assumeIsolated {
        PetStateSmokeTest.run()
    }
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.contains("--smoke-test-schedule") {
    MainActor.assumeIsolated {
        ScheduleSmokeTest.run()
    }
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.contains("--smoke-test-reminder-seconds") {
    MainActor.assumeIsolated {
        ReminderSecondsSmokeTest.run()
    }
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.contains("--smoke-test-ai") {
    let semaphore = DispatchSemaphore(value: 0)
    Task { @MainActor in
        await AITaskSmokeTest.run()
        semaphore.signal()
    }
    while semaphore.wait(timeout: .now()) == .timedOut {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    exit(EXIT_SUCCESS)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated {
    AppDelegate()
}

MainActor.assumeIsolated {
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
}
app.run()
