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

declare const Process: {
  executeCommand(
    command: string,
    args?: string[],
    cwd?: string
  ): Promise<ExecResult>;
  executeWithOptions(
    command: string,
    args?: string[],
    options?: any
  ): Promise<ExecResult>;
  killProcess(pid: number, signal?: number): Promise<any>;
  listRunning(): Promise<number[]>;
  changeDirectory(path: string): Promise<any>;
  getCurrentDirectory(): Promise<string>;
  getEnvironment(): Promise<Record<string, string>>;
  getSystemInfo(): Promise<Record<string, any>>;
  addListener(
    event: ProcessEvent,
    cb: (payload: any) => void
  ): import("react-native").EmitterSubscription;
  removeAllListeners(event: ProcessEvent): void;
};

export default Process;
