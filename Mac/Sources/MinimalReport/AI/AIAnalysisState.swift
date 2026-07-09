import Foundation

@MainActor
final class AIAnalysisState: ObservableObject {
    enum Phase {
        case idle
        case sampling(progress: Double, label: String)
        case analyzing
        case done
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var report: String = ""

    /// Delay between the three activity snapshots.
    private static let sampleGap: UInt64 = 5_000_000_000 // 5s in nanoseconds

    func startAnalysis() {
        Task {
            do {
                phase = .sampling(progress: 0.05, label: "Collecting sample 1/3…")
                let s1 = await Task.detached { ActivitySampler.collectSample(1) }.value
                phase = .sampling(progress: 0.25, label: "Sample 1/3 done. Waiting 5s…")

                try await Task.sleep(nanoseconds: Self.sampleGap)

                phase = .sampling(progress: 0.40, label: "Collecting sample 2/3…")
                let s2 = await Task.detached { ActivitySampler.collectSample(2) }.value
                phase = .sampling(progress: 0.60, label: "Sample 2/3 done. Waiting 5s…")

                try await Task.sleep(nanoseconds: Self.sampleGap)

                phase = .sampling(progress: 0.75, label: "Collecting sample 3/3…")
                let s3 = await Task.detached { ActivitySampler.collectSample(3) }.value
                phase = .sampling(progress: 0.88, label: "Collecting system info…")

                let extras = await Task.detached { ActivitySampler.collectExtras() }.value
                phase = .sampling(progress: 1.0, label: "Sending to AI…")
                phase = .analyzing

                let messages = buildMessages(samples: [s1, s2, s3], extras: extras)
                let result = try await GLMService.complete(messages: messages)
                report = result
                phase = .done
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func reset() {
        phase = .idle
        report = ""
    }

    // MARK: - Prompt builder

    private func buildMessages(
        samples: [ActivitySampler.Sample],
        extras: ActivitySampler.Extras
    ) -> [[String: Any]] {
        var body = "I've collected 3 system activity snapshots from a real Mac, 5 seconds apart.\n\n"

        for sample in samples {
            body += """
            ═══ SNAPSHOT \(sample.number)/3 ═══

            [TOP — CPU]
            \(sample.top)

            [VM_STAT — Memory pages]
            \(sample.vmStat)

            [DISK — df -h]
            \(sample.disk)

            [IOSTAT — Disk I/O]
            \(sample.ioStat)

            [PS — Top 15 by CPU]
            \(sample.ps)

            """
        }

        body += """
        ═══ SYSTEM SERVICES ═══

        [launchctl list — active services]
        \(extras.launchAgentList)

        [~/Library/LaunchAgents — user agents]
        \(extras.userLaunchAgents)

        [/Library/LaunchAgents — system agents]
        \(extras.systemLaunchAgents)

        [Login Items]
        \(extras.loginItems)
        """

        let system = """
        You are an expert macOS system performance analyst. Analyze the system snapshots and produce a detailed, actionable report using Markdown.

        Your report MUST include ALL of these sections with these EXACT headings:

        ## 🔴 High CPU Processes
        For each process consuming notable CPU: what it is (system daemon / user app / background service), whether it is safe to quit or uninstall, the exact Terminal command to kill it (`killall Name`), and how to prevent it from auto-launching (launchctl unload path, System Settings > Login Items, or uninstall command).

        ## 🟡 Memory Hogs
        Processes using the most RAM: what each does, whether quitting it actually frees RAM, and how to disable or remove it.

        ## 💾 Disk I/O
        Processes with heavy disk activity: what they do, whether they can be paused or configured to reduce writes (indexing, iCloud sync, Time Machine, etc.).

        ## 🚀 Startup Items & Launch Agents
        Based on the launch agent / login item lists: identify items that are unnecessary third-party agents (provide exact `launchctl unload` command), and mark safe Apple system services as ✅ KEEP.

        ## ✅ Top Recommended Actions
        A numbered, prioritized list of the most impactful cleanup actions to take right now, with the exact Terminal command or System Settings path for each step.

        ## 📊 System Health Summary
        2–3 sentences of overall assessment: is this system healthy, under stress, or bloated?

        Style rules:
        - Use exact process/binary names; put all Terminal commands in `backticks`
        - Mark Apple system processes as ⚠️ DO NOT REMOVE; user-installed processes as ✅ SAFE TO REMOVE
        - If a process is ambiguous, say so and explain how to identify it
        - Be concise and actionable; skip obvious or irrelevant information
        """

        return [
            ["role": "system", "content": system],
            ["role": "user", "content": body]
        ]
    }
}
