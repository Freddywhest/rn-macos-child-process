export type ExecResult = {
    pid: number;
    code: number;
    stdout: string;
    stderr: string;
    cwd?: string | null;
};
export type ProcessEvent = "process-stdout" | "process-stderr" | "process-exit" | "process-start" | "process-error";
export type ProcessEventPayload = {
    pid: number;
    code?: number;
    stdout?: string;
    stderr?: string;
    cwd?: string;
    type: ProcessEvent;
    command: string;
    identifier: string;
};

export type ExecuteOptions = {
    env?: Record<string, string>;
    timeout?: number;
    allowUnsafe?: boolean;
    envPaths?: string[];
    cwd?: string;
    identifier?: string;
};

export declare const Process: {
    executeCommand(command: string, args?: string[], cwd?: string): Promise<ExecResult>;
    executeWithOptions(command: string, args?: string[], options?: ExecuteOptions): Promise<ExecResult>;
    killProcess(pid: number, signal?: number): Promise<{
        success: boolean;
    }>;
    listRunning(): Promise<number[]>;
    changeDirectory(path: string): Promise<{
        success: boolean;
    }>;
    getCurrentDirectory(): Promise<string>;
    getEnvironment(): Promise<Record<string, string>>;
    getSystemInfo(): Promise<Record<string, string | number | boolean>>;
    addListener(event: ProcessEvent, cb: (payload: ProcessEventPayload) => void): import("react-native").EmitterSubscription;
    removeAllListeners(event: ProcessEvent): void;
};
export default Process;
