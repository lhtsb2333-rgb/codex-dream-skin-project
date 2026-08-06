using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Codex Dream Skin 安装程序")]
[assembly: AssemblyProduct("Codex Dream Skin Setup")]
[assembly: AssemblyVersion("1.4.8.0")]
[assembly: AssemblyFileVersion("1.4.8.0")]

internal sealed class SetupForm : Form
{
    private const string ProductId = "CodexDreamSkinPortable";
    private const string PackageVersion = "1.4.8";
    private const string ResourceName = "CodexDreamSkin.Portable.zip";
    private const string PortableZipHash = "d63f5a726ebc024700ade82eeaa7723301520fd11baed9d16d73cadd164ca0f1";
    private const string ManagerFileName = "Codex Dream Skin 主题管理器.exe";
    private const string UninstallerFileName = "卸载 Codex Dream Skin.exe";
    private const string MarkerFileName = ".codex-dream-skin-product.json";

    private readonly TextBox installPath = new TextBox();
    private readonly Button browseButton = new Button();
    private readonly CheckBox desktopShortcuts = new CheckBox();
    private readonly CheckBox startMenuShortcuts = new CheckBox();
    private readonly CheckBox updateWatcher = new CheckBox();
    private readonly CheckBox launchAfterInstall = new CheckBox();
    private readonly ProgressBar progress = new ProgressBar();
    private readonly Label status = new Label();
    private readonly Button installButton = new Button();
    private readonly Button cancelButton = new Button();

    internal SetupForm()
    {
        Text = "ChatGPT Dream Skin v1.4.8 安装程序";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = true;
        ClientSize = new Size(690, 455);
        BackColor = Color.FromArgb(255, 247, 250);
        Font = new Font("Microsoft YaHei UI", 9F);
        Icon = Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location);

        var title = new Label();
        title.Text = "安装 Codex Dream Skin";
        title.Font = new Font("Microsoft YaHei UI", 20F, FontStyle.Bold);
        title.ForeColor = Color.FromArgb(103, 57, 126);
        title.AutoSize = true;
        title.Location = new Point(34, 28);
        Controls.Add(title);

        var subtitle = new Label();
        subtitle.Text = "选择安装位置，安装程序会自动解压并创建所需入口。";
        subtitle.ForeColor = Color.FromArgb(102, 82, 111);
        subtitle.AutoSize = true;
        subtitle.Location = new Point(38, 78);
        Controls.Add(subtitle);

        var pathLabel = new Label();
        pathLabel.Text = "安装位置";
        pathLabel.AutoSize = true;
        pathLabel.Location = new Point(38, 125);
        Controls.Add(pathLabel);

        installPath.Location = new Point(40, 151);
        installPath.Size = new Size(518, 25);
        installPath.Text = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs", "Codex Dream Skin 主题管理器");
        Controls.Add(installPath);

        browseButton.Text = "浏览…";
        browseButton.Location = new Point(570, 149);
        browseButton.Size = new Size(82, 30);
        browseButton.Click += BrowseButtonClick;
        Controls.Add(browseButton);

        desktopShortcuts.Text = "创建桌面快捷方式";
        desktopShortcuts.Checked = true;
        desktopShortcuts.AutoSize = true;
        desktopShortcuts.Location = new Point(40, 208);
        Controls.Add(desktopShortcuts);

        startMenuShortcuts.Text = "创建开始菜单入口";
        startMenuShortcuts.Checked = true;
        startMenuShortcuts.AutoSize = true;
        startMenuShortcuts.Location = new Point(245, 208);
        Controls.Add(startMenuShortcuts);

        updateWatcher.Text = "开机自动启动带皮肤 ChatGPT，并启用官方更新守护";
        updateWatcher.Checked = true;
        updateWatcher.AutoSize = true;
        updateWatcher.Location = new Point(442, 208);
        Controls.Add(updateWatcher);

        launchAfterInstall.Text = "安装完成后打开主题管理器";
        launchAfterInstall.Checked = true;
        launchAfterInstall.AutoSize = true;
        launchAfterInstall.Location = new Point(40, 246);
        Controls.Add(launchAfterInstall);

        var safety = new Label();
        safety.Text = "安装程序不会修改 WindowsApps、Codex 登录信息、任务、插件或工作区文件。";
        safety.ForeColor = Color.FromArgb(127, 93, 62);
        safety.AutoSize = true;
        safety.Location = new Point(40, 285);
        Controls.Add(safety);

        progress.Location = new Point(40, 328);
        progress.Size = new Size(612, 20);
        progress.Minimum = 0;
        progress.Maximum = 100;
        Controls.Add(progress);

        status.Text = "准备安装";
        status.ForeColor = Color.FromArgb(102, 82, 111);
        status.AutoEllipsis = true;
        status.Location = new Point(40, 357);
        status.Size = new Size(612, 23);
        Controls.Add(status);

        installButton.Text = "安装";
        installButton.BackColor = Color.FromArgb(126, 78, 159);
        installButton.ForeColor = Color.White;
        installButton.FlatStyle = FlatStyle.Flat;
        installButton.Location = new Point(458, 400);
        installButton.Size = new Size(92, 36);
        installButton.Click += InstallButtonClick;
        Controls.Add(installButton);

        cancelButton.Text = "取消";
        cancelButton.Location = new Point(560, 400);
        cancelButton.Size = new Size(92, 36);
        cancelButton.Click += delegate { Close(); };
        Controls.Add(cancelButton);
    }

    private void BrowseButtonClick(object sender, EventArgs e)
    {
        using (var dialog = new FolderBrowserDialog())
        {
            dialog.Description = "选择 Codex Dream Skin 的安装目录";
            dialog.SelectedPath = Directory.Exists(installPath.Text)
                ? installPath.Text
                : Path.GetDirectoryName(installPath.Text);
            if (dialog.ShowDialog(this) == DialogResult.OK)
                installPath.Text = dialog.SelectedPath;
        }
    }

    private void InstallButtonClick(object sender, EventArgs e)
    {
        string target = string.Empty;
        try
        {
            SetBusy(true);
            target = ValidateInstallPath(installPath.Text);
            InstallPackage(target);
            string shortcutWarning = null;
            try
            {
                CreateSelectedShortcuts(target);
            }
            catch (Exception shortcutError)
            {
                shortcutWarning = "\r\n\r\n程序文件已安装，但部分快捷方式创建失败：" +
                    shortcutError.Message;
            }
            progress.Value = 100;
            status.Text = "安装完成";
            MessageBox.Show(this, "ChatGPT Dream Skin v1.4.8 安装完成。" + shortcutWarning,
                "安装成功", MessageBoxButtons.OK, MessageBoxIcon.Information);
            if (launchAfterInstall.Checked)
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = Path.Combine(target, ManagerFileName),
                    WorkingDirectory = target,
                    UseShellExecute = true
                });
            }
            Close();
        }
        catch (Exception ex)
        {
            status.Text = "安装未完成";
            MessageBox.Show(this, "安装未能安全完成：\r\n" + ex.Message,
                "安装失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
            SetBusy(false);
        }
    }

    private void SetBusy(bool busy)
    {
        installPath.Enabled = !busy;
        browseButton.Enabled = !busy;
        desktopShortcuts.Enabled = !busy;
        startMenuShortcuts.Enabled = !busy;
        updateWatcher.Enabled = !busy;
        launchAfterInstall.Enabled = !busy;
        installButton.Enabled = !busy;
        cancelButton.Enabled = !busy;
        UseWaitCursor = busy;
        Application.DoEvents();
    }

    private static string ValidateInstallPath(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) throw new InvalidOperationException("请选择安装位置。");
        string target = Path.GetFullPath(value.Trim()).TrimEnd(Path.DirectorySeparatorChar);
        string root = Path.GetPathRoot(target).TrimEnd(Path.DirectorySeparatorChar);
        if (string.Equals(target, root, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("不能安装到磁盘根目录。");

        string[] forbidden = {
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            Environment.GetFolderPath(Environment.SpecialFolder.Desktop),
            Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86)
        };
        foreach (string item in forbidden)
        {
            if (!string.IsNullOrEmpty(item) &&
                string.Equals(target, Path.GetFullPath(item).TrimEnd(Path.DirectorySeparatorChar),
                    StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("请选择上述系统或用户目录中的专用子文件夹。");
        }
        AssertNoReparseComponents(target);
        return target;
    }

    private void InstallPackage(string target)
    {
        string parent = Path.GetDirectoryName(target);
        if (string.IsNullOrEmpty(parent)) throw new InvalidOperationException("安装目录无效。");
        Directory.CreateDirectory(parent);
        string staging = target + ".installing-" + Guid.NewGuid().ToString("N");
        string backup = target + ".previous-" + Guid.NewGuid().ToString("N");
        bool oldMoved = false;
        bool newCommitted = false;

        try
        {
            if (Directory.Exists(target) && Directory.GetFileSystemEntries(target).Length > 0)
            {
                AssertExistingProductDirectory(target);
                DialogResult replace = MessageBox.Show(this,
                    "所选目录中已存在 Dream Skin。安装程序将把它升级到 v1.4.8，主题收藏与 ChatGPT 数据不会删除。是否继续？",
                    "升级现有安装", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                if (replace != DialogResult.Yes) throw new OperationCanceledException("用户取消了升级。");
            }

            Directory.CreateDirectory(staging);
            ExtractEmbeddedPortable(staging);
            VerifyExtractedProduct(staging);
            File.WriteAllText(Path.Combine(staging, MarkerFileName),
                "{\r\n  \"productId\": \"" + ProductId + "\",\r\n  \"version\": \"" +
                PackageVersion + "\"\r\n}\r\n", new UTF8Encoding(false));

            if (Directory.Exists(target))
            {
                Directory.Move(target, backup);
                oldMoved = true;
            }
            Directory.Move(staging, target);
            newCommitted = true;

            if (oldMoved && Directory.Exists(backup))
                Directory.Delete(backup, true);
        }
        catch
        {
            if (newCommitted && Directory.Exists(target))
            {
                AssertExistingProductDirectory(target);
                Directory.Delete(target, true);
            }
            if (oldMoved && Directory.Exists(backup) && !Directory.Exists(target))
                Directory.Move(backup, target);
            if (Directory.Exists(staging)) Directory.Delete(staging, true);
            throw;
        }
    }

    private void ExtractEmbeddedPortable(string staging)
    {
        using (Stream source = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName))
        {
            if (source == null) throw new InvalidDataException("安装包内置文件不存在。");
            VerifyResourceHash(source);
            source.Position = 0;
            using (var archive = new ZipArchive(source, ZipArchiveMode.Read, false))
            {
                int total = Math.Max(1, archive.Entries.Count);
                int completed = 0;
                string root = Path.GetFullPath(staging).TrimEnd(Path.DirectorySeparatorChar) +
                    Path.DirectorySeparatorChar;
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string relative = entry.FullName.Replace('/', Path.DirectorySeparatorChar)
                        .Replace('\\', Path.DirectorySeparatorChar);
                    string destination = Path.GetFullPath(Path.Combine(staging, relative));
                    if (!destination.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidDataException("安装包包含不安全路径。");
                    if (string.IsNullOrEmpty(entry.Name))
                    {
                        Directory.CreateDirectory(destination);
                    }
                    else
                    {
                        string directory = Path.GetDirectoryName(destination);
                        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
                        using (Stream input = entry.Open())
                        using (var output = new FileStream(destination, FileMode.CreateNew,
                            FileAccess.Write, FileShare.None))
                            input.CopyTo(output);
                    }
                    completed++;
                    progress.Value = Math.Min(95, completed * 95 / total);
                    status.Text = "正在安装：" + entry.FullName;
                    Application.DoEvents();
                }
            }
        }
    }

    private static void VerifyResourceHash(Stream stream)
    {
        using (SHA256 sha = SHA256.Create())
        {
            string actual = BitConverter.ToString(sha.ComputeHash(stream))
                .Replace("-", "").ToLowerInvariant();
            if (!string.Equals(actual, PortableZipHash, StringComparison.Ordinal))
                throw new InvalidDataException("安装包完整性校验失败。");
        }
    }

    private static void VerifyExtractedProduct(string root)
    {
        if (!File.Exists(Path.Combine(root, ManagerFileName)) ||
            !File.Exists(Path.Combine(root, UninstallerFileName)))
            throw new InvalidDataException("安装包缺少主程序或卸载程序。");
    }

    private static void AssertExistingProductDirectory(string target)
    {
        AssertNoReparseComponents(target);
        AssertNoReparseTree(target);
        string marker = Path.Combine(target, MarkerFileName);
        bool marked = false;
        if (File.Exists(marker))
        {
            string content = File.ReadAllText(marker, Encoding.UTF8);
            marked = content.IndexOf("\"productId\": \"" + ProductId + "\"",
                StringComparison.Ordinal) >= 0;
        }
        bool legacy = File.Exists(Path.Combine(target, ManagerFileName)) &&
            File.Exists(Path.Combine(target, UninstallerFileName));
        if (!marked && !legacy)
            throw new InvalidOperationException("所选目录不是可安全升级的 Codex Dream Skin 目录，请选择空文件夹。");
        if (!marked)
        {
            string[] allowed = {
                ManagerFileName, UninstallerFileName, "使用说明.md", "SHA256.txt",
                "licenses", "预览"
            };
            foreach (string entry in Directory.GetFileSystemEntries(target))
            {
                string name = Path.GetFileName(entry);
                bool known = Array.Exists(allowed, delegate(string candidate)
                {
                    return string.Equals(candidate, name, StringComparison.OrdinalIgnoreCase);
                });
                if (!known)
                    throw new InvalidOperationException(
                        "旧版目录包含无法确认归属的文件，安装程序不会覆盖它：" + name);
            }
        }
    }

    private static void AssertNoReparseComponents(string target)
    {
        string current = Path.GetFullPath(target);
        while (!string.IsNullOrEmpty(current))
        {
            if (Directory.Exists(current))
            {
                var info = new DirectoryInfo(current);
                if ((info.Attributes & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidOperationException("安装路径不能包含符号链接或联接点：" + current);
            }
            string parent = Path.GetDirectoryName(current);
            if (string.Equals(parent, current, StringComparison.OrdinalIgnoreCase)) break;
            current = parent;
        }
    }

    private static void AssertNoReparseTree(string target)
    {
        if (!Directory.Exists(target)) return;
        foreach (string path in Directory.GetFileSystemEntries(target, "*",
            SearchOption.AllDirectories))
        {
            FileAttributes attributes = File.GetAttributes(path);
            if ((attributes & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("安装目录包含符号链接或联接点：" + path);
        }
    }

    private void CreateSelectedShortcuts(string target)
    {
        string manager = Path.Combine(target, ManagerFileName);
        string uninstaller = Path.Combine(target, UninstallerFileName);
        if (desktopShortcuts.Checked)
        {
            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            CreateShortcut(Path.Combine(desktop, "ChatGPT 皮肤管理器.lnk"),
                manager, string.Empty, target, "打开 ChatGPT Dream Skin 主题管理器");
            CreateShortcut(Path.Combine(desktop, "ChatGPT（带皮肤启动）.lnk"),
                manager, "--start-skin", target, "启动带皮肤的 ChatGPT");
        }
        if (startMenuShortcuts.Checked)
        {
            string productMenu = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Programs),
                "ChatGPT Dream Skin");
            Directory.CreateDirectory(productMenu);
            CreateShortcut(Path.Combine(productMenu, "ChatGPT 皮肤管理器.lnk"),
                manager, string.Empty, target, "打开 ChatGPT Dream Skin 主题管理器");
            CreateShortcut(Path.Combine(productMenu, "ChatGPT（带皮肤启动）.lnk"),
                manager, "--start-skin", target, "启动带皮肤的 ChatGPT");
            CreateShortcut(Path.Combine(productMenu, "卸载 Codex Dream Skin.lnk"),
                uninstaller, string.Empty, target, "完整卸载 Codex Dream Skin");
        }
        if (updateWatcher.Checked && !File.Exists(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CodexDreamSkin", "update-watcher.disabled")))
        {
            string startup = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
            string state = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodexDreamSkin");
            Directory.CreateDirectory(state);
            File.Delete(Path.Combine(state, "update-watcher.disabled"));
            CreateShortcut(Path.Combine(startup, "ChatGPT（带皮肤自动启动）.lnk"),
                manager, "--startup-skin", target, "登录后启动带皮肤的 ChatGPT，并检测官方更新");
        }
    }

    private static void CreateShortcut(string path, string target, string arguments,
        string workingDirectory, string description)
    {
        Type shellType = Type.GetTypeFromProgID("WScript.Shell");
        if (shellType == null) throw new InvalidOperationException("Windows 快捷方式组件不可用。");
        object shellObject = Activator.CreateInstance(shellType);
        try
        {
            dynamic shell = shellObject;
            dynamic link = shell.CreateShortcut(path);
            link.TargetPath = target;
            link.Arguments = arguments;
            link.WorkingDirectory = workingDirectory;
            link.IconLocation = target + ",0";
            link.Description = description;
            link.Save();
            Marshal.FinalReleaseComObject(link);
        }
        finally
        {
            if (Marshal.IsComObject(shellObject)) Marshal.FinalReleaseComObject(shellObject);
        }
    }
}

internal static class CodexDreamSkinSetup
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new SetupForm());
    }
}
