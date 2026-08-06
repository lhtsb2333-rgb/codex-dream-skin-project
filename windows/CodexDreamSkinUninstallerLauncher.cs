using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("卸载 Codex Dream Skin")]
[assembly: System.Reflection.AssemblyProduct("Codex Dream Skin Uninstaller")]
[assembly: System.Reflection.AssemblyVersion("1.4.8.0")]
[assembly: System.Reflection.AssemblyFileVersion("1.4.8.0")]

internal static class CodexDreamSkinUninstallerLauncher
{
    [STAThread]
    private static int Main()
    {
        try
        {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string manager = Path.Combine(root, "Codex Dream Skin 主题管理器.exe");
            if (!File.Exists(manager))
                throw new FileNotFoundException("主题管理器主程序不存在，无法执行受控卸载。", manager);

            var start = new ProcessStartInfo
            {
                FileName = manager,
                Arguments = "--uninstall",
                WorkingDirectory = root,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            using (Process process = Process.Start(start))
            {
                if (process == null) throw new InvalidOperationException("无法启动卸载程序。");
            }
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show("无法开始卸载：" + ex.Message, "Codex Dream Skin",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
