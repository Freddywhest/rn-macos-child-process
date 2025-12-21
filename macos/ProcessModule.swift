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
        "composer", "npx",
    ]

    private  func eventName(_ base: String, _ id: String) -> String {
        // Removed identifier suffixing for simplicity
        return !id.isEmpty ? base : base
    }

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
    private func defaultEnvironment(merging extra: [String: String]?, extraPaths: [String] = []) -> [String: String] {
      var env = ProcessInfo.processInfo.environment
      env["PATH"] =  "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/Users/\(NSUserName())/Library/Application Support/Herd/bin/"
        if !extraPaths.isEmpty {
            let currentPath = env["PATH"] ?? ""
            let additionalPath = extraPaths.joined(separator: ":")
            env["PATH"] = additionalPath + ":" + currentPath
        }
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
            let opts: [String: Any] = options ?? [:]
            let cwd = opts["cwd"] as? String
            let envExtra = opts["env"] as? [String: String]
            let timeoutSec = opts["timeout"] as? Double
            let allowUnsafe = opts["allowUnsafe"] as? Bool ?? false
            let extraEnvPaths = opts["envPaths"] as? [String] ?? []
            let identifier = opts["identifier"] as? String ?? ""

            let eventNameProcessStart  = self.eventName("process-start", identifier)
            let eventNameProcessStdOut = self.eventName("process-stdout", identifier)
            let eventNameProcessStdErr = self.eventName("process-stderr", identifier)
            let eventNameProcessExit   = self.eventName("process-exit", identifier)
            let eventNameProcessError = self.eventName("process-error", identifier)

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
            process.environment = self.defaultEnvironment(merging: envExtra, extraPaths: extraEnvPaths)

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
                withName: eventNameProcessStart,
                body: [
                    "pid": pid, 
                    "cwd": cwd ?? "", 
                    "command": commandString, 
                    "type": "start", 
                    "identifier": identifier,
                    "timestamp": Date().timeIntervalSince1970
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
                        withName: eventNameProcessStdOut,
                        body: [
                            "pid": pid, 
                            "data": s, 
                            "cwd": cwd ?? "", 
                            "type": "stdout",
                            "command": commandString,
                            "identifier": identifier,
                            "timestamp": Date().timeIntervalSince1970
                        ])
                }
            }

          stderrHandle.readabilityHandler = { handle in
             let data = handle.availableData
             if let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty {

                 collectedStderr += chunk

                 self.sendEvent(
                     withName: eventNameProcessStdErr,
                     body: [
                         "type": "stderr",
                         "data": chunk,
                         "pid": process.processIdentifier,
                         "command": commandString,
                         "cwd": cwd ?? "",
                         "identifier": identifier,
                         "timestamp": Date().timeIntervalSince1970
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
                        withName: eventNameProcessError,
                        body: [
                            "pid": pid, 
                            "data": "Timeout after \(t) seconds", 
                            "type": "error-timeout",
                            "command": commandString, 
                            "cwd": cwd ?? "", 
                            "identifier": identifier,
                            "timestamp": Date().timeIntervalSince1970
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
                    withName: eventNameProcessExit,
                    body: [
                        "pid": pid, 
                        "code": p.terminationStatus, 
                        "stdout": fullStdout, 
                        "cwd": cwd ?? "", 
                        "type": "exit", 
                        "command": commandString, 
                        "identifier": identifier,
                        "timestamp": Date().timeIntervalSince1970
                    ])

                DispatchQueue.main.async {
                    let result: [String: Any] = [
                        "pid": pid,
                        "code": p.terminationStatus,
                        "stdout": fullStdout,
                        "stderr": collectedStderr,
                        "cwd": cwd ?? "",
                        "command": commandString,
                        "identifier": identifier,
                        "timestamp": Date().timeIntervalSince1970
                    ]
                    
                    if p.terminationStatus == 0 {
                        resolve(result)
                    } else {
                        // Convert the dictionary → JSON string for reject()
                        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: []),
                        let jsonString = String(data: jsonData, encoding: .utf8) {
                            
                            reject(
                                "PROCESS_ERROR",
                                jsonString,
                                nil
                            )
                        } else {
                            reject("PROCESS_ERROR", "Command execution failed with exit code: \(p.terminationStatus)", nil)
                        }
                    }
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

    @objc
    func readFile(_ path: String,
                  resolver resolve: @escaping RCTPromiseResolveBlock,
                  rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try String(contentsOfFile: path, encoding: .utf8)
                DispatchQueue.main.async { resolve(data) }
            } catch {
                DispatchQueue.main.async {
                    reject("READ_ERROR", "Failed to read file at \(path): \(error.localizedDescription)", error)
                }
            }
        }
    }

    @objc
    func writeFile(_ path: String, content: String,
                   resolver resolve: @escaping RCTPromiseResolveBlock,
                   rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                DispatchQueue.main.async { resolve(["success": true, "path": path]) }
            } catch {
                DispatchQueue.main.async {
                    reject("WRITE_ERROR", "Failed to write file at \(path): \(error.localizedDescription)", error)
                }
            }
        }
    }

    @objc
    func deleteFile(_ path: String,
                    resolver resolve: @escaping RCTPromiseResolveBlock,
                    rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.removeItem(atPath: path)
                DispatchQueue.main.async { resolve(["success": true, "path": path]) }
            } catch {
                DispatchQueue.main.async {
                    reject("DELETE_ERROR", "Failed to delete file at \(path): \(error.localizedDescription)", error)
                }
            }
        }
    }

    @objc
    func exists(_ path: String,
                resolver resolve: @escaping RCTPromiseResolveBlock,
                rejecter reject: @escaping RCTPromiseRejectBlock) {
        let exists = FileManager.default.fileExists(atPath: path)
        resolve(["exists": exists, "path": path])
    }

    @objc
    func createDirectory(_ path: String,
                         resolver resolve: @escaping RCTPromiseResolveBlock,
                         rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
                DispatchQueue.main.async { resolve(["success": true, "path": path]) }
            } catch {
                DispatchQueue.main.async {
                    reject("MKDIR_ERROR", "Failed to create directory at \(path): \(error.localizedDescription)", error)
                }
            }
        }
    }

    @objc
    func listDirectory(_ path: String,
                       resolver resolve: @escaping RCTPromiseResolveBlock,
                       rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let items = try FileManager.default.contentsOfDirectory(atPath: path)
                DispatchQueue.main.async { resolve(["items": items, "path": path]) }
            } catch {
                DispatchQueue.main.async {
                    reject("LS_ERROR", "Failed to list directory at \(path): \(error.localizedDescription)", error)
                }
            }
        }
    }

     @objc
    func listDirectoryItems(_ path: String,
                       resolver resolve: @escaping RCTPromiseResolveBlock,
                       rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                DispatchQueue.main.async {
                    reject("NOT_FOUND", "Directory not found: \(path)", nil)
                }
                return
            }

            do {
                let contents = try fm.contentsOfDirectory(atPath: path)
                var result: [[String: Any]] = []

                for item in contents {
                    let fullPath = (path as NSString).appendingPathComponent(item)
                    var isDirItem: ObjCBool = false
                    fm.fileExists(atPath: fullPath, isDirectory: &isDirItem)

                    let attrs = try fm.attributesOfItem(atPath: fullPath)
                    let fileInfo: [String: Any] = [
                        "name": item,
                        "path": fullPath,
                        "isFile": !isDirItem.boolValue,
                        "isDirectory": isDirItem.boolValue,
                        "size": attrs[FileAttributeKey.size] ?? 0,
                        "mtime": (attrs[FileAttributeKey.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                        "ctime": (attrs[FileAttributeKey.creationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                    ]
                    result.append(fileInfo)
                }

                DispatchQueue.main.async {
                    resolve(["path": path, "items": result])
                }

            } catch {
                DispatchQueue.main.async {
                    reject("LIST_ERROR", "Failed to list directory \(path): \(error.localizedDescription)", error)
                }
            }
        }
    }

    @objc
    func appendToFile(_ path: String, content: String,
                      resolver resolve: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let handle = FileHandle(forWritingAtPath: path) {
                do {
                    handle.seekToEndOfFile()
                    if let data = content.data(using: .utf8) {
                        handle.write(data)
                    }
                    handle.closeFile()
                    DispatchQueue.main.async { resolve(["success": true, "path": path]) }
                } catch {
                    DispatchQueue.main.async {
                        reject("APPEND_ERROR", "Failed to append to file at \(path): \(error.localizedDescription)", error)
                    }
                }
            } else {
                // File doesn’t exist, create it
                do {
                    try content.write(toFile: path, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async { resolve(["success": true, "path": path]) }
                } catch {
                    DispatchQueue.main.async {
                        reject("APPEND_ERROR", "Failed to create file for appending at \(path): \(error.localizedDescription)", error)
                    }
                }
            }
        }
    }

    @objc
    func moveFile(_ fromPath: String, toPath: String,
                  resolver resolve: @escaping RCTPromiseResolveBlock,
                  rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.moveItem(atPath: fromPath, toPath: toPath)
                DispatchQueue.main.async { resolve(["success": true, "from": fromPath, "to": toPath]) }
            } catch {
                DispatchQueue.main.async {
                    reject("MOVE_ERROR", "Failed to move file from \(fromPath) to \(toPath): \(error.localizedDescription)", error)
                }
            }
        }
    }

    @objc
    func copyFile(_ fromPath: String, toPath: String,
                  resolver resolve: @escaping RCTPromiseResolveBlock,
                  rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.copyItem(atPath: fromPath, toPath: toPath)
                DispatchQueue.main.async { resolve(["success": true, "from": fromPath, "to": toPath]) }
            } catch {
                DispatchQueue.main.async {
                    reject("COPY_ERROR", "Failed to copy file from \(fromPath) to \(toPath): \(error.localizedDescription)", error)
                }
            }
        }
    }

}
