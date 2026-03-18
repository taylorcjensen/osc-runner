import Foundation
import OSCFoundation

// Disable stdout buffering so logs appear immediately when running under launchd
setbuf(stdout, nil)

// MARK: - Config

struct Rule: Decodable, Sendable {
    let address: String
    let command: String
}

struct Config: Decodable, Sendable {
    let host: String
    let port: UInt16?
    let rules: [Rule]
}

func loadConfig(_ path: String) throws -> Config {
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Config.self, from: data)
}

// MARK: - Substitution
//
// Since Eos can't send OSC arguments, all substitutions come from the address path:
//   {address}  full address string, e.g. /eos/out/event/cue/1/5/fire
//   {0},{1}... path components (split on /), e.g. {4}=1 (cue list), {5}=5 (cue number)

func applySubstitutions(_ template: String, address: String) -> String {
    var result = template
    result = result.replacingOccurrences(of: "{address}", with: address)

    let parts = address.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    for (i, part) in parts.enumerated() {
        result = result.replacingOccurrences(of: "{\(i)}", with: part)
    }

    return result
}

// MARK: - Shell execution

func run(command: String) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/bash")
    proc.arguments = ["-c", command]
    do {
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            print("  ✗ exited with status \(proc.terminationStatus)")
        }
    } catch {
        print("  ✗ failed to run: \(error)")
    }
}

// MARK: - Main loop

func connectAndListen(config: Config) async {
    let port = config.port ?? 3032
    let client = OSCTCPClient(host: config.host, port: port)
    let space = OSCAddressSpace()

    for rule in config.rules {
        let cmd = rule.command
        space.register(rule.address) { msg in
            let expanded = applySubstitutions(cmd, address: msg.addressPattern)
            print("[\(msg.addressPattern)] → \(expanded)")
            Task.detached { run(command: expanded) }
        }
    }

    print("Connecting to \(config.host):\(port)...")
    await client.connect()

    let stateUpdates = await client.stateUpdates
    let packets = await client.packets

    // Wait until connected (or fail out)
    var didConnect = false
    for await state in stateUpdates {
        switch state {
        case .connected:
            print("Connected. Listening for \(config.rules.count) rule(s).")
            didConnect = true
        case .failed(let err):
            print("Connection failed: \(err)")
            return
        case .disconnected:
            return
        case .connecting:
            break
        }
        if didConnect { break }
    }
    guard didConnect else { return }

    // Process packets until the connection closes
    for await packet in packets {
        space.dispatch(packet)
    }

    print("Connection closed.")
}

func main() async {
    let args = CommandLine.arguments

    if args.count < 2 {
        fputs("""
            Usage: osc-runner <config.json>

            Config format:
              {
                "host": "192.168.1.100",
                "port": 3032,
                "rules": [
                  { "address": "/eos/out/event/cue/1/*/fire", "command": "echo 'cue fired: {address}'" },
                  { "address": "/eos/out/active/cue",         "command": "echo 'active cue: {0}'" }
                ]
              }

            Substitutions in command strings:
              {address}  full OSC address, e.g. /eos/out/event/cue/1/5/fire
              {0},{1}... address path components split on /
                         e.g. for /eos/out/event/cue/1/5/fire:
                              {0}=eos {1}=out {4}=1 (cue list) {5}=5 (cue number)

            """, stderr)
        exit(1)
    }

    let configPath = args[1]

    let config: Config
    do {
        config = try loadConfig(configPath)
    } catch {
        fputs("Failed to load config: \(error)\n", stderr)
        exit(1)
    }

    print("Loaded \(config.rules.count) rule(s).")

    // Reconnect loop
    while true {
        await connectAndListen(config: config)
        print("Reconnecting in 5 seconds...")
        try? await Task.sleep(nanoseconds: 5_000_000_000)
    }
}

await main()
