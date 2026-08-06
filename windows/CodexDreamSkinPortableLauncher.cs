using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Codex Dream Skin 主题管理器")]
[assembly: AssemblyProduct("Codex Dream Skin Portable")]
[assembly: AssemblyDescription("内置运行环境的 Codex 便携主题管理器")]
[assembly: AssemblyVersion("1.4.8.0")]
[assembly: AssemblyFileVersion("1.4.8.0")]

internal static class CodexDreamSkinPortableLauncher
{
    private const string AppVersion = "1.4.8";
    private const string PayloadHash = "d5c547dcdde4ae24b25129951fbc2903df12b82ccb86c2d7ce78094ed179c88e";
    private const string ResourceName = "CodexDreamSkin.Payload.zip";

    [STAThread]
    private static int Main(string[] args)
    {
        if (IsStartupSkinMode(args)) return StartInstalledSkin(true);
        if (IsStartSkinMode(args)) return StartInstalledSkin(false);
        if (IsUpdateWatcherMode(args)) return StartUpdateWatcher();
        if (IsUninstallMode(args)) return StartUninstall();

        bool created;
        using (var mutex = new Mutex(true, "Local\\CodexDreamSkinPortableLauncher", out created))
        {
            if (!created)
            {
                MessageBox.Show("Codex Dream Skin 主题管理器已经在启动或运行。", "Codex Dream Skin",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return 2;
            }

            try
            {
                string payloadRoot = EnsurePayload();
                string script = Path.Combine(payloadRoot, "CodexSkinManagerPortable.ps1");
                if (!File.Exists(script)) throw new FileNotFoundException("便携管理器脚本不存在。", script);

                string forwarded = BuildForwardedArguments(args);
                var start = new ProcessStartInfo
                {
                    FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                        "WindowsPowerShell", "v1.0", "powershell.exe"),
                    Arguments = "-NoProfile -STA -ExecutionPolicy RemoteSigned -File " + Quote(script) + forwarded,
                    WorkingDirectory = payloadRoot,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Normal
                };
                start.EnvironmentVariables["CODEX_DREAM_SKIN_LAUNCHER"] = Assembly.GetExecutingAssembly().Location;
                using (Process process = Process.Start(start))
                {
                    if (process == null) throw new InvalidOperationException("无法启动主题管理器。 ");
                    if (IsSynchronousMode(args))
                    {
                        process.WaitForExit();
                        return process.ExitCode;
                    }
                }
                return 0;
            }
            catch (Exception ex)
            {
                MessageBox.Show("启动失败：" + ex.Message, "Codex Dream Skin",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }
    }

    private static bool IsStartSkinMode(string[] args)
    {
        return args.Length == 1 &&
            string.Equals(args[0], "--start-skin", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsStartupSkinMode(string[] args)
    {
        return args.Length == 1 &&
            string.Equals(args[0], "--startup-skin", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsUpdateWatcherMode(string[] args)
    {
        return args.Length == 1 &&
            string.Equals(args[0], "--watch-updates", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsUninstallMode(string[] args)
    {
        return args.Length == 1 &&
            string.Equals(args[0], "--uninstall", StringComparison.OrdinalIgnoreCase);
    }

    private static int StartUninstall()
    {
        DialogResult answer = MessageBox.Show(
            "卸载会关闭 Codex，恢复软件修改过的外观配置，并删除 Dream Skin 的主题、运行数据、快捷方式、登录守护和当前便携程序文件夹。\r\n\r\n" +
            "不会修改其他系统设置、Codex 任务、登录信息、插件或工作区文件。请先保存未发送内容。确定继续吗？",
            "卸载 Codex Dream Skin",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning);
        if (answer != DialogResult.Yes) return 0;

        try
        {
            string payloadRoot = EnsurePayload();
            string script = Path.Combine(payloadRoot, "dream-skin", "scripts",
                "uninstall-dream-skin-manager.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("卸载脚本不存在。", script);

            string portableRoot = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            var start = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                    "WindowsPowerShell", "v1.0", "powershell.exe"),
                Arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File " +
                    Quote(script) + " -PortableRoot " + Quote(portableRoot),
                WorkingDirectory = Path.GetDirectoryName(script),
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            start.EnvironmentVariables["CODEX_DREAM_SKIN_LAUNCHER"] = Assembly.GetExecutingAssembly().Location;
            using (Process process = Process.Start(start))
            {
                if (process == null) throw new InvalidOperationException("无法启动卸载脚本。");
            }
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show("卸载启动失败：" + ex.Message, "Codex Dream Skin",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static int StartUpdateWatcher()
    {
        try
        {
            string payloadRoot = EnsurePayload();
            string engineRoot = Path.Combine(payloadRoot, "dream-skin");
            string script = Path.Combine(engineRoot, "scripts", "watch-dream-skin-updates.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("更新守护脚本不存在。", script);

            var start = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                    "WindowsPowerShell", "v1.0", "powershell.exe"),
                Arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File " +
                    Quote(script),
                WorkingDirectory = engineRoot,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            start.EnvironmentVariables["CODEX_DREAM_SKIN_LAUNCHER"] = Assembly.GetExecutingAssembly().Location;
            using (Process process = Process.Start(start))
            {
                if (process == null) throw new InvalidOperationException("无法启动更新守护进程。");
            }
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show("更新守护启动失败：" + ex.Message, "Codex Dream Skin",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static int StartInstalledSkin(bool startupMode)
    {
        try
        {
            // Use the runtime embedded in the current launcher. The installed copy can
            // be stale after the official Codex package updates.
            string payloadRoot = EnsurePayload();
            string engineRoot = Path.Combine(payloadRoot, "dream-skin");
            string script = Path.Combine(engineRoot, "scripts", "start-dream-skin.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("皮肤运行环境尚未安装，请先打开主题管理器并应用主题。", script);

            var start = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                    "WindowsPowerShell", "v1.0", "powershell.exe"),
                Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File " +
                    Quote(script) + (startupMode ? " -RestartExisting" : " -PromptRestart"),
                WorkingDirectory = engineRoot,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            start.EnvironmentVariables["CODEX_DREAM_SKIN_LAUNCHER"] = Assembly.GetExecutingAssembly().Location;
            using (Process process = Process.Start(start))
            {
                if (process == null) throw new InvalidOperationException("无法在后台启动皮肤引擎。");
                if (startupMode)
                {
                    process.WaitForExit();
                    if (process.ExitCode != 0) return process.ExitCode;
                }
            }
            if (startupMode) return StartUpdateWatcher();
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show("带皮肤启动失败：" + ex.Message, "Codex Dream Skin",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static bool IsSynchronousMode(string[] args)
    {
        return args.Length > 0 && (string.Equals(args[0], "--self-test", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(args[0], "--render-preview", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(args[0], "--round-trip-test", StringComparison.OrdinalIgnoreCase));
    }

    private static string BuildForwardedArguments(string[] args)
    {
        if (args.Length == 0) return string.Empty;
        if (string.Equals(args[0], "--self-test", StringComparison.OrdinalIgnoreCase))
        {
            string output = args.Length > 1 ? Path.GetFullPath(args[1]) :
                Path.Combine(Path.GetTempPath(), "codex-dream-skin-selftest.json");
            return " -SelfTest -SelfTestOutput " + Quote(output);
        }
        if (string.Equals(args[0], "--render-preview", StringComparison.OrdinalIgnoreCase))
        {
            if (args.Length < 2) throw new ArgumentException("--render-preview 需要输出图片路径。");
            return " -RenderPreview " + Quote(Path.GetFullPath(args[1]));
        }
        if (string.Equals(args[0], "--round-trip-test", StringComparison.OrdinalIgnoreCase))
        {
            if (args.Length < 3) throw new ArgumentException("--round-trip-test 需要结果文件和截图目录。");
            return " -RoundTripTestOutput " + Quote(Path.GetFullPath(args[1])) +
                " -RoundTripScreenshotDirectory " + Quote(Path.GetFullPath(args[2]));
        }
        throw new ArgumentException("不支持的启动参数。");
    }

    private static string EnsurePayload()
    {
        string cacheOverride = Environment.GetEnvironmentVariable("CODEX_DREAM_SKIN_PORTABLE_CACHE");
        string cacheRoot = string.IsNullOrWhiteSpace(cacheOverride)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodexDreamSkinManager")
            : Path.GetFullPath(cacheOverride);
        string target = Path.Combine(cacheRoot, "payload-" + AppVersion + "-" + PayloadHash.Substring(0, 12));
        string marker = Path.Combine(target, ".payload-sha256");
        string manager = Path.Combine(target, "CodexSkinManagerPortable.ps1");
        if (File.Exists(manager) && File.Exists(marker) &&
            string.Equals(File.ReadAllText(marker).Trim(), PayloadHash, StringComparison.OrdinalIgnoreCase)) return target;

        Directory.CreateDirectory(cacheRoot);
        if (Directory.Exists(target)) Directory.Delete(target, true);
        string staging = Path.Combine(cacheRoot, ".staging-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            VerifyEmbeddedPayload();
            ExtractEmbeddedPayload(staging);
            File.WriteAllText(Path.Combine(staging, ".payload-sha256"), PayloadHash + Environment.NewLine,
                new UTF8Encoding(false));
            if (!File.Exists(Path.Combine(staging, "CodexSkinManagerPortable.ps1")))
                throw new InvalidDataException("释放后的便携包不完整。");
            Directory.Move(staging, target);
            return target;
        }
        catch
        {
            if (Directory.Exists(staging)) Directory.Delete(staging, true);
            throw;
        }
    }

    private static Stream OpenPayload()
    {
        Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName);
        if (stream == null) throw new InvalidDataException("程序内置资源不存在。");
        return stream;
    }

    private static void VerifyEmbeddedPayload()
    {
        using (Stream stream = OpenPayload())
        using (SHA256 sha = SHA256.Create())
        {
            string actual = BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
            if (!string.Equals(actual, PayloadHash, StringComparison.Ordinal))
                throw new InvalidDataException("程序内置资源校验失败。");
        }
    }

    private static void ExtractEmbeddedPayload(string staging)
    {
        string root = Path.GetFullPath(staging).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        using (Stream stream = OpenPayload())
        using (var archive = new ZipArchive(stream, ZipArchiveMode.Read, false))
        {
            foreach (ZipArchiveEntry entry in archive.Entries)
            {
                string relative = entry.FullName.Replace('/', Path.DirectorySeparatorChar)
                    .Replace('\\', Path.DirectorySeparatorChar);
                string destination = Path.GetFullPath(Path.Combine(staging, relative));
                if (!destination.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("便携包包含不安全路径。");
                if (string.IsNullOrEmpty(entry.Name))
                {
                    Directory.CreateDirectory(destination);
                    continue;
                }
                string parent = Path.GetDirectoryName(destination);
                if (!string.IsNullOrEmpty(parent)) Directory.CreateDirectory(parent);
                using (Stream input = entry.Open())
                using (var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                    input.CopyTo(output);
            }
        }
    }

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }
}
