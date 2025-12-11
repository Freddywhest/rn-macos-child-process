import AppKit
import Foundation
import React

@objc(ProcessModule)
class ProcessModule: RCTEventEmitter {

    // MARK: - Process tracking
    private var processes: [Int32: Process] = [:]
    private let processesQueue = DispatchQueue(label: "com.example.ProcessModule.queue")

    // MARK: - Whitelist commands
    private let defaultWhitelist: Set<String> = [
        "ls", "pwd", "cat", "echo", "git", "node", "npm", "yarn", "python3", "swift",
        "which", "brew", "rm", "cp", "mv", "mkdir", "rmdir", "chmod", "chown", "php", "node", "npm",
        "composer",
        "npx",
    ]

    // MARK: - Supported events
    override func supportedEvents() -> [String]? {
        return [
            "process-stdout",
            "process-stderr",
            "process-exit",
            "process-error",
            "process-start",
        ]
    }

    @objc
    static override func requiresMainQueueSetup() -> Bool { false }

    // MARK: - Helpers
    private func defaultEnvironment(merging extra: [String: String]?) -> [String: String] {
      var env = ProcessInfo.processInfo.environment
      env["PATH"] =  "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/Users/\(NSUserName())/Library/Application Support/Herd/config/nvm/versions/node/v22.18.0/bin:/Users/\(NSUserName())/Library/Application Support/Herd/bin/"
        extra?.forEach { env[$0.key] = $0.value }
        return env
    }

    private func escapeSingleQuotes(_ s: String) -> String {
        return s.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    private func makeBashCommand(command: String, arguments: [String]) -> String {
        if arguments.isEmpty { return command }
        let quotedArgs = arguments.map { arg -> String in
            if arg.rangeOfCharacter(
                from: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "\"'`$\\")
                )
            ) != nil {
                return "'\(escapeSingleQuotes(arg))'"
            } else {
                return arg
            }
        }
        return ([command] + quotedArgs).joined(separator: " ")
    }

    // MARK: - Execute command with options
    @objc
    func executeWithOptions(
        _ command: String,
        arguments: [String],
        options: [String: Any]?,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let opts = options ?? [:]
            let cwd = opts["cwd"] as? String
            let envExtra = opts["env"] as? [String: String]
            let timeoutSec = opts["timeout"] as? Double
            let allowUnsafe = opts["allowUnsafe"] as? Bool ?? false

            // Whitelist check
            if !allowUnsafe {
                let base = (command as NSString).lastPathComponent
                if !self.defaultWhitelist.contains(base) {
                    DispatchQueue.main.async {
                        reject("FORBIDDEN", "Command not allowed: \(base)", nil)
                    }
                    return
                }
            }

            // Prepare process
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.environment = self.defaultEnvironment(merging: envExtra)

            let commandString = self.makeBashCommand(command: command, arguments: arguments)

            // Validate cwd
            if let cwd = cwd, !cwd.isEmpty {
                var isDir: ObjCBool = false
                let fm = FileManager.default
                if !fm.fileExists(atPath: cwd, isDirectory: &isDir) || !isDir.boolValue {
                    DispatchQueue.main.async {
                        reject("CD_ERROR", "Directory not found or not directory: \(cwd)", nil)
                    }
                    return
                }
            }

            process.executableURL = URL(fileURLWithPath: "/bin/bash")
//            let bashCommand: String
//            if let cwd = cwd, !cwd.isEmpty {
//                let escCwd = self.escapeSingleQuotes(cwd)
//                bashCommand = """
//                cd '\(escCwd)' && \
//                [ -f ~/.bash_profile ] && source ~/.bash_profile; \
//                [ -f ~/.zshrc ] && source ~/.zshrc; \
//                [ -f ~/.bashrc ] && source ~/.bashrc; \
//                \(commandString)
//                """
//            } else {
//                bashCommand = """
//                [ -f ~/.bash_profile ] && source ~/.bash_profile; \
//                [ -f ~/.zshrc ] && source ~/.zshrc; \
//                [ -f ~/.bashrc ] && source ~/.bashrc; \
//                \(commandString)
//                """
//            }
          
            let bashCommand: String
            if let cwd = cwd, !cwd.isEmpty {
                let escCwd = self.escapeSingleQuotes(cwd)
                bashCommand = "cd '\(escCwd)' && \(commandString)"
            } else {
                bashCommand = commandString
            }
            process.arguments = ["-lc", bashCommand]

            // Track process
            do { try process.run() } catch {
                DispatchQueue.main.async {
                    reject(
                        "EXEC_ERROR", "Failed to run process: \(error.localizedDescription)", error)
                }
                return
            }

            let pid = process.processIdentifier
            self.processesQueue.sync { self.processes[pid] = process }

            // Notify start
            self.sendEvent(
                withName: "process-start",
                body: [
                    "pid": pid, "cwd": cwd ?? "", "command": commandString, "type": "process-start",
                ])

            // Collect stdout/stderr
            var fullStdout = ""
            var collectedStderr = ""
            var didReject = false
            let stdoutHandle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading

            stdoutHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.count > 0, let s = String(data: data, encoding: .utf8) {
                    fullStdout += s
                    self.sendEvent(
                        withName: "process-stdout",
                        body: [
                            "pid": pid, "data": s, "cwd": cwd ?? "", "type": "process-stdout",
                            "command": commandString,
                        ])
                }
            }

          stderrHandle.readabilityHandler = { handle in
             let data = handle.availableData
             if let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty {

                 collectedStderr += chunk

                 self.sendEvent(
                     withName: "process-stderr",
                     body: [
                         "type": "stderr",
                         "data": chunk,
                         "pid": process.processIdentifier,
                         "command": commandString,
                         "cwd": cwd ?? ""
                     ]
                 )
             }
         }

            // Timeout support
            var timeoutWorkItem: DispatchWorkItem?
            if let t = timeoutSec, t > 0 {
                let item = DispatchWorkItem {
                    self.processesQueue.sync {
                        if let p = self.processes[pid] { p.terminate() }
                    }
                    self.sendEvent(
                        withName: "process-error",
                        body: [
                            "pid": pid, "error": "timeout", "type": "process-error-timeout",
                            "command": commandString, "cwd": cwd ?? "",
                        ])
                }
                timeoutWorkItem = item
                DispatchQueue.global().asyncAfter(deadline: .now() + t, execute: item)
            }

            // Termination handler
          // Termination handler
            process.terminationHandler = { p in
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil
                timeoutWorkItem?.cancel()
                if didReject { return }

                let remainingData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                if let s = String(data: remainingData, encoding: .utf8) { fullStdout += s }

                self.processesQueue.sync { self.processes.removeValue(forKey: pid) }

                self.sendEvent(
                    withName: "process-exit",
                    body: [
                        "pid": pid, "code": p.terminationStatus, "stdout": fullStdout,
                        "cwd": cwd ?? "", "type": "process-exit", "command": commandString,
                    ])

                DispatchQueue.main.async {
                  if p.terminationStatus == 0 {
                       resolve([
                           "pid": pid,
                           "code": p.terminationStatus,
                           "stdout": fullStdout,
                           "stderr": collectedStderr,
                           "cwd": cwd ?? ""
                       ])
                   } else {
                       reject(
                           "PROCESS_ERROR",
                           collectedStderr.trimmingCharacters(in: .whitespacesAndNewlines),
                           nil
                       )
                   }
//                    resolve([
//                        "pid": pid,
//                        "code": p.terminationStatus,
//                        "stdout": fullStdout,
//                        "cwd": cwd ?? "",
//                    ])
                }
            }
        }
    }

    // Simple wrapper
    @objc
    func executeCommand(
        _ command: String,
        arguments: [String],
        cwd: String?,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        self.executeWithOptions(
            command,
            arguments: arguments,
            options: ["cwd": cwd as Any],
            resolver: resolve,
            rejecter: reject
        )
    }

    // MARK: - Kill process
    @objc
    func killProcess(
        _ pid: Int32,
        signal: Int32,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.processesQueue.sync {
                if let p = self.processes[pid] {
                    let killProc = Process()
                    killProc.executableURL = URL(fileURLWithPath: "/bin/kill")
                    killProc.arguments = ["-\(signal)", "\(pid)"]
                    do {
                        try killProc.run()
                        killProc.waitUntilExit()
                        p.terminate()
                        self.processes.removeValue(forKey: pid)
                        DispatchQueue.main.async { resolve(["success": true]) }
                    } catch {
                        DispatchQueue.main.async {
                            reject(
                                "KILL_ERROR",
                                "Failed to kill \(pid): \(error.localizedDescription)",
                                error
                            )
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        reject("NO_PROCESS", "No running process with pid \(pid)", nil)
                    }
                }
            }
        }
    }

    // MARK: - List running
    @objc
    func listRunning(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let pids = processesQueue.sync { Array(self.processes.keys) }
        resolve(pids)
    }

    // MARK: - Directory & Environment
    @objc
    func changeDirectory(
        _ path: String,
        resolver resolve: RCTPromiseResolveBlock,
        rejecter reject: RCTPromiseRejectBlock
    ) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            fm.changeCurrentDirectoryPath(path)
            resolve(["success": true, "path": path])
        } else {
            reject("CD_ERROR", "Directory not found: \(path)", nil)
        }
    }

    @objc
    func getCurrentDirectory(
        _ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock
    ) {
        resolve(FileManager.default.currentDirectoryPath)
    }

    @objc
    func getEnvironment(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(ProcessInfo.processInfo.environment)
    }

    @objc
    func getSystemInfo(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let info: [String: Any] = [
            "platform": "darwin",
            "cpus": ProcessInfo.processInfo.processorCount,
            "memory": ProcessInfo.processInfo.physicalMemory,
            "hostname": ProcessInfo.processInfo.hostName,
            "homedir": FileManager.default.homeDirectoryForCurrentUser.path,
            "tmpdir": NSTemporaryDirectory(),
            "username": NSUserName(),
            "platformVersion": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        resolve(info)
    }
}
