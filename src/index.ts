import { NativeModules, NativeEventEmitter } from "react-native";

const { ProcessModule } = NativeModules;

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

export type ProcessEventPayload =
  | { pid: number; data: string } // stdout / stderr
  | { pid: number; code: number } // exit
  | { pid: number } // start
  | { pid?: number; message: string }; // error

const emitter = new NativeEventEmitter(ProcessModule);

export const Process = {
  executeCommand(
    command: string,
    args: string[] = [],
    cwd?: string
  ): Promise<ExecResult> {
    return ProcessModule.executeCommand(command, args, cwd);
  },

  executeWithOptions(
    command: string,
    args: string[] = [],
    options?: Record<string, unknown>
  ): Promise<ExecResult> {
    return ProcessModule.executeWithOptions(command, args, options);
  },

  killProcess(pid: number, signal = 15): Promise<{ success: boolean }> {
    return ProcessModule.killProcess(pid, signal);
  },

  listRunning(): Promise<number[]> {
    return ProcessModule.listRunning();
  },

  changeDirectory(path: string): Promise<{ success: boolean }> {
    return ProcessModule.changeDirectory(path);
  },

  getCurrentDirectory(): Promise<string> {
    return ProcessModule.getCurrentDirectory();
  },

  getEnvironment(): Promise<Record<string, string>> {
    return ProcessModule.getEnvironment();
  },

  getSystemInfo(): Promise<Record<string, string | number | boolean>> {
    return ProcessModule.getSystemInfo();
  },

  addListener(event: ProcessEvent, cb: (payload: ProcessEventPayload) => void) {
    return emitter.addListener(event, cb);
  },

  removeAllListeners(event: ProcessEvent) {
    emitter.removeAllListeners(event);
  },
};

export default Process;
