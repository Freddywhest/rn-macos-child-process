Below is a **complete professional README.md** for your package, including:

✔ Installation
✔ Linking
✔ API docs (using the exact types you provided)
✔ Event system
✔ Usage examples (simple + full streaming demo)
✔ Error handling
✔ Package structure

You can paste this directly as your library’s `README.md`.

---

# 📦 react-native-macos-process

A **native macOS terminal/command execution module** for React Native macOS.

Features:

* 🟢 **Run shell commands** (e.g., `npm -v`, `ls`, `php artisan`, `composer`)
* 🟢 **Real-time stdout + stderr streaming**
* 🟢 **Reject automatically when stderr appears**
* 🟢 **Kill running processes**
* 🟢 **List active processes**
* 🟢 **Change directory / read environment / system info**
* 🟢 Fully typed (TypeScript declarations included)
* 🟢 Uses Swift + FileHandle streaming (non-blocking)

---

# 🚀 Installation

```
npm install rn-macos-child-process
```

Or:

```
yarn add rn-macos-child-process
```

---

# 🔗 Autolinking (React Native macOS ≥ 0.71)

Nothing else required.

If for some reason the macOS project did not update:

```
cd macos
pod install
```

---

# 🧩 Importing

```ts
import Process from "rn-macos-child-process";
```

---

# 📘 TypeScript Types

These are included automatically through your `index.d.ts`.

```ts
export type ExecResult = {
  pid: number;
  code: number;
  stdout: string;
  stderr: string;
  cwd?: string | null;
};

export type ProcessEvent =
  | "process-stdout"
  | "process-stderr"
  | "process-exit"
  | "process-start"
  | "process-error";
```

---

# 📚 API Reference

## **Process.executeCommand(command, args?, cwd?)**

Runs a command and returns a final result (no options object).

```ts
const result = await Process.executeCommand("npm", ["-v"]);
```

---

## **Process.executeWithOptions(command, args?, options?)**

Same as above but provides more configuration:

```ts
const result = await Process.executeWithOptions("ls", ["-la"], {
  cwd: "/Users/me",
  env: { CUSTOM_VAR: "1" }
});
```

Returns `ExecResult`:

```ts
{
  pid: 12345,
  code: 0,
  stdout: "...",
  stderr: "",
  cwd: "/Users/me"
}
```

---

## **Process.killProcess(pid, signal?)**

```ts
await Process.killProcess(12345, 15);
```

---

## **Process.listRunning()**

Returns all active PIDs:

```ts
const running = await Process.listRunning();
```

---

## **Process.changeDirectory(path)**

Changes internal working directory:

```ts
await Process.changeDirectory("/Users/me/project");
```

---

## **Process.getCurrentDirectory()**

```ts
const cwd = await Process.getCurrentDirectory();
```

---

## **Process.getEnvironment()**

```ts
const env = await Process.getEnvironment();
```

---

## **Process.getSystemInfo()**

Returns CPU, RAM, OS, and more:

```ts
const info = await Process.getSystemInfo();
```

---

# 🔔 Events

Use:

```ts
const sub = Process.addListener("process-stdout", event => {
  console.log(event.data);
});
```

Supported events:

| Event            | Description           |
| ---------------- | --------------------- |
| `process-start`  | When command begins   |
| `process-stdout` | When stdout emits     |
| `process-stderr` | When stderr emits     |
| `process-exit`   | When the process ends |
| `process-error`  | Internal native error |

Remove listeners:

```ts
Process.removeAllListeners("process-stdout");
```

---

# 📝 Full Streaming Example (Recommended)

```tsx
import React, {useEffect, useState} from "react";
import {View, Button, Text, ScrollView} from "react-native";
import Process from "rn-macos-child-process";

export default function TerminalScreen() {
  const [logs, setLogs] = useState<string[]>([]);
  const [runningPid, setRunningPid] = useState<number | null>(null);

  useEffect(() => {
    const subs = [
      Process.addListener("process-start", e =>
        push(`[START] pid=${e.pid} cwd=${e.cwd}`)
      ),
      Process.addListener("process-stdout", e =>
        push(`[OUT] ${e.data}`)
      ),
      Process.addListener("process-stderr", e =>
        push(`[ERR] ${e.data}`)
      ),
      Process.addListener("process-exit", e =>
        push(`[EXIT] code=${e.code}`)
      ),
      Process.addListener("process-error", e =>
        push(`[NATIVE ERROR] ${e.message}`)
      ),
    ];

    return () => subs.forEach(s => s.remove());
  }, []);

  const push = (msg: string) =>
    setLogs(prev => [...prev, msg]);

  const run = async () => {
    setLogs([]);
    const result = await Process.executeWithOptions(
      "ls",
      ["-la"],
      {cwd: "/Users/alfrednti"}
    );
    setRunningPid(result.pid);
  };

  return (
    <View style={{flex: 1, padding: 20}}>
      <Button title="Run Command" onPress={run} />

      <ScrollView style={{marginTop: 20}}>
        {logs.map((l, i) => (
          <Text key={i} style={{color: "white"}}>
            {l}
          </Text>
        ))}
      </ScrollView>
    </View>
  );
}
```

---

# ⚠️ Error Handling

The native module **rejects on stderr** automatically:

* If stderr emits *first*, the process stops
* `process-stderr` event still fires (so UI can show it)
* Promise rejects with:

```ts
{
  code: "STDERR_ERROR",
  message: "...",
  nativeStackIOS: [...]
}
```

This ensures:

✔ safe behavior
✔ correct JS error stack
✔ consistent error mapping

---

# 📦 Project Structure

```
react-native-macos-process/
│
├── index.js
├── index.d.ts
├── package.json
├── README.md
│
├── macos/
│   ├── ProcessModule.swift
│   └── ProcessModule.m
│
└── react-native.config.js
```

---

# 🛠 Example Commands That Work

```ts
Process.executeCommand("npm", ["-v"]);
Process.executeCommand("composer", ["install"]);
Process.executeCommand("php", ["artisan", "migrate"]);
Process.executeCommand("git", ["status"]);
Process.executeWithOptions("bash", ["script.sh"], {cwd: "/scripts"});
```

---

# 💬 Support

If you need:

* full rewrite in Objective-C instead of Swift
* additional events
* persistent background processes
* streaming chunk size changes
* command queue system
* sandbox bypass (within macOS rules)

Just open an issue or request an enhancement.
