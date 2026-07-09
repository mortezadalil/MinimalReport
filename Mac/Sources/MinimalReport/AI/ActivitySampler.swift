import Foundation

enum ActivitySampler {
    struct Sample {
        var number: Int
        var top: String
        var vmStat: String
        var disk: String
        var ioStat: String
        var ps: String
    }

    struct Extras {
        var launchAgentList: String
        var userLaunchAgents: String
        var systemLaunchAgents: String
        var loginItems: String
    }

    static func collectSample(_ number: Int) -> Sample {
        Sample(
            number: number,
            top: shell("top -l 1 -n 20 -o cpu -stats pid,command,cpu,rsize"),
            vmStat: shell("vm_stat"),
            disk: shell("df -h /"),
            ioStat: shell("iostat -d 1 1"),
            ps: shell("ps aux | sort -k3 -rn | head -15")
        )
    }

    static func collectExtras() -> Extras {
        Extras(
            launchAgentList: shell("launchctl list | head -80"),
            userLaunchAgents: shell("ls ~/Library/LaunchAgents/ 2>/dev/null"),
            systemLaunchAgents: shell("ls /Library/LaunchAgents/ 2>/dev/null"),
            loginItems: shell("osascript -e 'tell application \"System Events\" to get the name of every login item'")
        )
    }

    private static func shell(_ cmd: String) -> String {
        (try? Shell.runShell(cmd)) ?? "(unavailable)"
    }
}
