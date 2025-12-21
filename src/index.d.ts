export type ExecResult = {
    pid: number;
    code: number;
    stdout: string;
    stderr: string;
    cwd?: string | null;
};
export type FileItem = {
    name: string;
    path: string;
    isFile: boolean;
    isDirectory: boolean;
    size: number;
    mtime: number;
    ctime: number;
};
export type ProcessEvent = 'process-stdout' | 'process-stderr' | 'process-exit' | 'process-start' | 'process-error';
export type ProcessEventPayload = {
    pid: number;
    data: string;
} | {
    pid: number;
    code: number;
} | {
    pid: number;
} | {
    pid?: number;
    message: string;
};
export declare const Process: {
    executeCommand(command: string, args?: string[], cwd?: string): Promise<ExecResult>;
    executeWithOptions(command: string, args?: string[], options?: Record<string, unknown>): Promise<ExecResult>;
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
    readFile(path: string): Promise<string>;
    writeFile(path: string, content: string): Promise<{
        success: boolean;
        path: string;
    }>;
    appendToFile(path: string, content: string): Promise<{
        success: boolean;
        path: string;
    }>;
    deleteFile(path: string): Promise<{
        success: boolean;
        path: string;
    }>;
    exists(path: string): Promise<{
        exists: boolean;
        path: string;
    }>;
    createDirectory(path: string): Promise<{
        success: boolean;
        path: string;
    }>;
    listDirectory(path: string): Promise<{
        items: string[];
        path: string;
    }>;
    moveFile(fromPath: string, toPath: string): Promise<{
        success: boolean;
        from: string;
        to: string;
    }>;
    copyFile(fromPath: string, toPath: string): Promise<{
        success: boolean;
        from: string;
        to: string;
    }>;
    list(path: string): Promise<{
        path: string;
        items: FileItem[];
    }>;
};
export default Process;
