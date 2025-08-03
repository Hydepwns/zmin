import * as vscode from 'vscode';
import * as cp from 'child_process';
import * as path from 'path';
import * as fs from 'fs';

let outputChannel: vscode.OutputChannel;
let statusBarItem: vscode.StatusBarItem;

export function activate(context: vscode.ExtensionContext) {
    // Create output channel
    outputChannel = vscode.window.createOutputChannel('zmin');
    
    // Create status bar item
    statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    statusBarItem.command = 'zmin.configure';
    context.subscriptions.push(statusBarItem);
    
    // Register commands
    context.subscriptions.push(
        vscode.commands.registerCommand('zmin.minify', () => minifyFile()),
        vscode.commands.registerCommand('zmin.minifySelection', () => minifySelection()),
        vscode.commands.registerCommand('zmin.validate', () => validateJson()),
        vscode.commands.registerCommand('zmin.benchmark', () => benchmarkFile()),
        vscode.commands.registerCommand('zmin.configure', () => configureZmin())
    );
    
    // Auto-minify on save if enabled
    context.subscriptions.push(
        vscode.workspace.onDidSaveTextDocument((document) => {
            if (document.languageId === 'json' && getConfig().get('autoMinifyOnSave')) {
                minifyFile(document.uri);
            }
        })
    );
    
    // Update status bar
    updateStatusBar();
}

export function deactivate() {
    if (outputChannel) {
        outputChannel.dispose();
    }
    if (statusBarItem) {
        statusBarItem.dispose();
    }
}

function getConfig() {
    return vscode.workspace.getConfiguration('zmin');
}

function updateStatusBar() {
    const mode = getConfig().get('mode');
    statusBarItem.text = `zmin: ${mode}`;
    statusBarItem.tooltip = 'Click to configure zmin';
    statusBarItem.show();
}

async function minifyFile(uri?: vscode.Uri) {
    try {
        const editor = vscode.window.activeTextEditor;
        if (!uri && !editor) {
            vscode.window.showErrorMessage('No file open');
            return;
        }
        
        const filePath = uri ? uri.fsPath : editor!.document.fileName;
        if (!filePath.endsWith('.json')) {
            vscode.window.showErrorMessage('Not a JSON file');
            return;
        }
        
        // Show progress
        vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: 'Minifying JSON...',
            cancellable: false
        }, async (progress) => {
            const startTime = Date.now();
            
            // Get configuration
            const config = getConfig();
            const executable = config.get<string>('executable', 'zmin');
            const mode = config.get<string>('mode', 'sport');
            const enableGpu = config.get<boolean>('enableGpu', false);
            const streaming = config.get<boolean>('streaming', false);
            
            // Build command
            const args = ['-m', mode];
            if (enableGpu) args.push('--gpu');
            if (streaming) args.push('--streaming');
            args.push(filePath);
            
            // Create output file path
            const parsed = path.parse(filePath);
            const outputPath = path.join(parsed.dir, `${parsed.name}.min${parsed.ext}`);
            args.push('-o', outputPath);
            
            // Execute zmin
            const result = await executeZmin(executable, args);
            
            if (result.success) {
                const elapsed = Date.now() - startTime;
                const inputSize = fs.statSync(filePath).size;
                const outputSize = fs.statSync(outputPath).size;
                const reduction = ((1 - outputSize / inputSize) * 100).toFixed(1);
                
                // Show success message
                const message = `Minified in ${elapsed}ms (${reduction}% reduction)`;
                vscode.window.showInformationMessage(message);
                
                // Show benchmarks if enabled
                if (config.get('showBenchmarks')) {
                    outputChannel.appendLine(`\nMinification Results:`);
                    outputChannel.appendLine(`Input: ${formatBytes(inputSize)}`);
                    outputChannel.appendLine(`Output: ${formatBytes(outputSize)}`);
                    outputChannel.appendLine(`Reduction: ${reduction}%`);
                    outputChannel.appendLine(`Time: ${elapsed}ms`);
                    outputChannel.appendLine(`Throughput: ${formatThroughput(inputSize, elapsed)}`);
                }
                
                // Open minified file
                const doc = await vscode.workspace.openTextDocument(outputPath);
                await vscode.window.showTextDocument(doc, { preview: false });
            } else {
                vscode.window.showErrorMessage(`Minification failed: ${result.error}`);
                outputChannel.appendLine(`Error: ${result.error}`);
                outputChannel.show();
            }
        });
    } catch (error) {
        vscode.window.showErrorMessage(`Error: ${error}`);
    }
}

async function minifySelection() {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
        vscode.window.showErrorMessage('No editor open');
        return;
    }
    
    const selection = editor.selection;
    if (selection.isEmpty) {
        vscode.window.showErrorMessage('No selection');
        return;
    }
    
    const selectedText = editor.document.getText(selection);
    
    try {
        // Create temporary file
        const tempFile = path.join(vscode.workspace.workspaceFolders![0].uri.fsPath, '.zmin-temp.json');
        fs.writeFileSync(tempFile, selectedText);
        
        // Get configuration
        const config = getConfig();
        const executable = config.get<string>('executable', 'zmin');
        const mode = config.get<string>('mode', 'sport');
        
        // Execute zmin
        const args = ['-m', mode, tempFile];
        const result = await executeZmin(executable, args);
        
        if (result.success && result.stdout) {
            // Replace selection with minified content
            await editor.edit(editBuilder => {
                editBuilder.replace(selection, result.stdout.trim());
            });
            
            vscode.window.showInformationMessage('Selection minified');
        } else {
            vscode.window.showErrorMessage(`Minification failed: ${result.error}`);
        }
        
        // Clean up temp file
        if (fs.existsSync(tempFile)) {
            fs.unlinkSync(tempFile);
        }
    } catch (error) {
        vscode.window.showErrorMessage(`Error: ${error}`);
    }
}

async function validateJson() {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== 'json') {
        vscode.window.showErrorMessage('No JSON file open');
        return;
    }
    
    const filePath = editor.document.fileName;
    const config = getConfig();
    const executable = config.get<string>('executable', 'zmin');
    
    // Execute zmin with validate flag
    const result = await executeZmin(executable, ['--validate', filePath]);
    
    if (result.success) {
        vscode.window.showInformationMessage('Valid JSON');
    } else {
        vscode.window.showErrorMessage(`Invalid JSON: ${result.error}`);
        outputChannel.appendLine(`Validation error: ${result.error}`);
        outputChannel.show();
    }
}

async function benchmarkFile() {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== 'json') {
        vscode.window.showErrorMessage('No JSON file open');
        return;
    }
    
    const filePath = editor.document.fileName;
    const config = getConfig();
    const executable = config.get<string>('executable', 'zmin');
    
    outputChannel.clear();
    outputChannel.show();
    outputChannel.appendLine('Running benchmarks...\n');
    
    // Test all modes
    for (const mode of ['eco', 'sport', 'turbo']) {
        outputChannel.appendLine(`Testing ${mode} mode:`);
        
        const startTime = Date.now();
        const result = await executeZmin(executable, ['-m', mode, '--benchmark', filePath]);
        const elapsed = Date.now() - startTime;
        
        if (result.success) {
            const fileSize = fs.statSync(filePath).size;
            outputChannel.appendLine(`  Time: ${elapsed}ms`);
            outputChannel.appendLine(`  Throughput: ${formatThroughput(fileSize, elapsed)}`);
            if (result.stdout) {
                outputChannel.appendLine(`  ${result.stdout}`);
            }
        } else {
            outputChannel.appendLine(`  Error: ${result.error}`);
        }
        outputChannel.appendLine('');
    }
}

async function configureZmin() {
    const config = getConfig();
    
    // Mode selection
    const mode = await vscode.window.showQuickPick(['eco', 'sport', 'turbo'], {
        placeHolder: 'Select performance mode',
        activeItem: config.get('mode')
    });
    
    if (mode) {
        await config.update('mode', mode, vscode.ConfigurationTarget.Global);
        updateStatusBar();
    }
}

function executeZmin(executable: string, args: string[]): Promise<{success: boolean, stdout?: string, error?: string}> {
    return new Promise((resolve) => {
        cp.execFile(executable, args, (error, stdout, stderr) => {
            if (error) {
                resolve({ success: false, error: error.message });
            } else if (stderr) {
                resolve({ success: false, error: stderr });
            } else {
                resolve({ success: true, stdout });
            }
        });
    });
}

function formatBytes(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

function formatThroughput(bytes: number, milliseconds: number): string {
    const mbPerSecond = (bytes / (1024 * 1024)) / (milliseconds / 1000);
    if (mbPerSecond < 1024) {
        return `${mbPerSecond.toFixed(1)} MB/s`;
    } else {
        return `${(mbPerSecond / 1024).toFixed(2)} GB/s`;
    }
}