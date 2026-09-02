using System.Diagnostics;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Win32;

namespace DynOps.DKCProduction.PrintAgent.Setup;

internal static class Program
{
    private const string ProductId = "DynOps.DKCProduction.PrintAgent";
    private const string DisplayName = "DKC Production Print Agent";
    private const string AgentExeName = "DKCProduction.PrintAgent.exe";
    private const string AgentProcessName = "DKCProduction.PrintAgent";
    private const string MarkerName = ".dkc-production-print-agent.install.json";
    private const string PayloadResourceName = "DKC.PrintAgent.Payload.zip";
    private const string RunValueName = "DKCProductionPrintAgent";
    private const string UninstallKeyName = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\DynOps.DKCProduction.PrintAgent";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true
    };

    [STAThread]
    private static void Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        if (!OperatingSystem.IsWindows())
        {
            MessageBox.Show("Bu kurulum yalnız Windows x64 üzerinde çalışır.", DisplayName, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        try
        {
            if (args.Any(static value => value.Equals("/uninstall", StringComparison.OrdinalIgnoreCase)))
            {
                Uninstall(args.Any(static value => value.Equals("/detached", StringComparison.OrdinalIgnoreCase)));
                return;
            }

            Install();
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Kurulum tamamlanamadı.\r\n\r\n" + ex.Message,
                DisplayName,
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            Environment.ExitCode = 1;
        }
    }

    private static void Install()
    {
        if (MessageBox.Show(
                "DKC Production Print Agent bu Windows kullanıcısı için kurulacak.\r\n\r\nMevcut WMS Print Agent etkilenmeyecektir. Devam edilsin mi?",
                DisplayName,
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question) != DialogResult.Yes)
        {
            return;
        }

        EnsureAgentStopped();

        var localPrograms = Path.GetFullPath(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs"));
        var installDirectory = SafeDirectChild(localPrograms, Path.Combine(localPrograms, DisplayName), "Kurulum klasörü");
        var operationId = Guid.NewGuid().ToString("N");
        var stagingDirectory = SafeDirectChild(localPrograms, installDirectory + ".staging-" + operationId, "Geçici kurulum klasörü");
        var backupDirectory = SafeDirectChild(localPrograms, installDirectory + ".backup-" + operationId, "Yedek klasörü");
        var extractionDirectory = Path.Combine(Path.GetTempPath(), "dkc-print-agent-setup-" + operationId);
        var movedExistingInstall = false;
        var committedNewInstall = false;
        var postInstallWarnings = new List<string>();

        Directory.CreateDirectory(extractionDirectory);
        try
        {
            ExtractEmbeddedPayload(extractionDirectory);
            var manifest = ValidatePayload(extractionDirectory);

            if (Directory.Exists(installDirectory))
            {
                ValidateInstalledProduct(installDirectory);
            }

            Directory.CreateDirectory(stagingDirectory);
            foreach (var file in manifest.Files)
            {
                var source = SafePayloadPath(extractionDirectory, file.Path);
                var destination = SafePayloadPath(stagingDirectory, file.Path);
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                File.Copy(source, destination, overwrite: false);
                VerifyHash(destination, file.Sha256);
            }

            var setupSource = Environment.ProcessPath
                ?? throw new InvalidOperationException("Çalışan Setup.exe yolu alınamadı.");
            var installedSetup = Path.Combine(stagingDirectory, "DKC-Production-Print-Agent-Setup.exe");
            File.Copy(setupSource, installedSetup, overwrite: true);

            var marker = new InstallMarker(
                SchemaVersion: 1,
                ProductId: ProductId,
                ProductVersion: manifest.ProductVersion,
                InstalledAtUtc: DateTimeOffset.UtcNow);
            File.WriteAllText(
                Path.Combine(stagingDirectory, MarkerName),
                JsonSerializer.Serialize(marker, JsonOptions));

            if (Directory.Exists(installDirectory))
            {
                Directory.Move(installDirectory, backupDirectory);
                movedExistingInstall = true;
            }

            Directory.Move(stagingDirectory, installDirectory);
            committedNewInstall = true;

            try
            {
                ConfigureCurrentUserIntegration(installDirectory, manifest.ProductVersion);
            }
            catch (Exception ex)
            {
                postInstallWarnings.Add("Başlat menüsü/otomatik başlangıç ayarlanamadı: " + ex.Message);
            }

            try
            {
                StartAgent(installDirectory);
            }
            catch (Exception ex)
            {
                postInstallWarnings.Add("Agent otomatik açılamadı; Başlat menüsünden elle açın: " + ex.Message);
            }

            if (Directory.Exists(backupDirectory))
            {
                try
                {
                    Directory.Delete(backupDirectory, recursive: true);
                }
                catch (Exception ex)
                {
                    postInstallWarnings.Add("Eski sürüm yedeği kaldırılamadı: " + ex.Message);
                }
            }

            var warningText = postInstallWarnings.Count == 0
                ? string.Empty
                : "\r\n\r\nUyarılar:\r\n- " + string.Join("\r\n- ", postInstallWarnings);
            MessageBox.Show(
                "Kurulum tamamlandı.\r\n\r\nAçılan agent ekranında DKC print-agent.runtime.secrets.json dosyasını içe aktarın, etiket yazıcısını seçin ve 'Ayarları Kaydet ve Bağlan' düğmesine basın." + warningText,
                DisplayName,
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
        catch
        {
            if (!committedNewInstall && Directory.Exists(stagingDirectory))
            {
                Directory.Delete(stagingDirectory, recursive: true);
            }

            if (committedNewInstall && Directory.Exists(installDirectory))
            {
                Directory.Delete(installDirectory, recursive: true);
            }

            if (movedExistingInstall && Directory.Exists(backupDirectory))
            {
                Directory.Move(backupDirectory, installDirectory);
            }

            throw;
        }
        finally
        {
            if (Directory.Exists(extractionDirectory))
            {
                Directory.Delete(extractionDirectory, recursive: true);
            }
        }
    }

    private static void Uninstall(bool detached)
    {
        var installDirectory = Path.GetFullPath(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs",
            DisplayName));

        if (!detached)
        {
            if (MessageBox.Show(
                    "DKC Production Print Agent kaldırılacak. Şifreli ayarlar ve iş geçmişi korunacaktır. Devam edilsin mi?",
                    DisplayName,
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Warning) != DialogResult.Yes)
            {
                return;
            }

            ValidateInstalledProduct(installDirectory);
            var currentSetup = Environment.ProcessPath
                ?? throw new InvalidOperationException("Çalışan Setup.exe yolu alınamadı.");
            var detachedSetup = Path.Combine(Path.GetTempPath(), "dkc-print-agent-uninstall-" + Guid.NewGuid().ToString("N") + ".exe");
            File.Copy(currentSetup, detachedSetup, overwrite: false);
            Process.Start(new ProcessStartInfo
            {
                FileName = detachedSetup,
                Arguments = "/uninstall /detached",
                UseShellExecute = true
            });
            return;
        }

        Thread.Sleep(800);
        ValidateInstalledProduct(installDirectory);
        StopAgentProcesses();
        RemoveCurrentUserIntegration();
        Directory.Delete(installDirectory, recursive: true);
        MessageBox.Show(
            "DKC Production Print Agent kaldırıldı. Şifreli kullanıcı ayarları ve iş geçmişi korundu.",
            DisplayName,
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);
        ScheduleDetachedSetupDeletion();
    }

    private static void ExtractEmbeddedPayload(string destination)
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(PayloadResourceName)
            ?? throw new InvalidDataException("Kurulum payload'u Setup.exe içinde bulunamadı.");
        using var archive = new ZipArchive(stream, ZipArchiveMode.Read, leaveOpen: false);
        var root = Path.GetFullPath(destination).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var entry in archive.Entries)
        {
            if (string.IsNullOrEmpty(entry.Name))
            {
                continue;
            }

            if (entry.FullName.Contains('\\') || Path.IsPathRooted(entry.FullName))
            {
                throw new InvalidDataException("Payload güvensiz dosya yolu içeriyor.");
            }

            var segments = entry.FullName.Split('/', StringSplitOptions.RemoveEmptyEntries);
            if (segments.Length == 0 || segments.Any(static segment => segment is "." or ".." || segment.Contains(':')))
            {
                throw new InvalidDataException("Payload güvensiz dosya yolu içeriyor.");
            }

            var normalized = string.Join('/', segments);
            if (!seen.Add(normalized))
            {
                throw new InvalidDataException("Payload yinelenen dosya yolu içeriyor: " + normalized);
            }

            var outputPath = Path.GetFullPath(Path.Combine(destination, Path.Combine(segments)));
            if (!outputPath.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("Payload kurulum alanının dışına çıkmaya çalışıyor.");
            }

            Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
            entry.ExtractToFile(outputPath, overwrite: false);
        }
    }

    private static PackageManifest ValidatePayload(string root)
    {
        var manifestPath = Path.Combine(root, "manifest.sha256.json");
        if (!File.Exists(manifestPath))
        {
            throw new InvalidDataException("Paket bütünlük manifesti bulunamadı.");
        }

        var manifest = JsonSerializer.Deserialize<PackageManifest>(File.ReadAllText(manifestPath), JsonOptions)
            ?? throw new InvalidDataException("Paket manifesti boş.");
        if (manifest.SchemaVersion != 1 || manifest.ProductId != ProductId ||
            manifest.Runtime != "win-x64" || !manifest.SelfContained || manifest.Files.Length == 0)
        {
            throw new InvalidDataException("Paket manifesti DKC win-x64 ürünüyle uyuşmuyor.");
        }

        var expected = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var file in manifest.Files)
        {
            if (!expected.Add(file.Path))
            {
                throw new InvalidDataException("Manifest yinelenen dosya içeriyor: " + file.Path);
            }

            VerifyHash(SafePayloadPath(root, file.Path), file.Sha256);
        }

        var actual = Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)
            .Select(path => Path.GetRelativePath(root, path).Replace('\\', '/'))
            .Where(path => !path.Equals("manifest.sha256.json", StringComparison.OrdinalIgnoreCase))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (!actual.SetEquals(expected))
        {
            throw new InvalidDataException("Paket dosya listesi manifest ile uyuşmuyor.");
        }

        if (!expected.Contains(AgentExeName))
        {
            throw new InvalidDataException("DKC agent executable paket içinde bulunamadı.");
        }

        return manifest;
    }

    private static void VerifyHash(string path, string expectedHash)
    {
        if (!File.Exists(path) || expectedHash.Length != 64)
        {
            throw new InvalidDataException("Paket dosyası eksik veya hash alanı geçersiz: " + path);
        }

        using var stream = File.OpenRead(path);
        var actual = Convert.ToHexString(SHA256.HashData(stream));
        if (!actual.Equals(expectedHash, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("Paket dosyası hash doğrulamasından geçemedi: " + Path.GetFileName(path));
        }
    }

    private static string SafePayloadPath(string root, string relativePath)
    {
        if (string.IsNullOrWhiteSpace(relativePath) || relativePath.Contains('\\') || Path.IsPathRooted(relativePath))
        {
            throw new InvalidDataException("Manifest güvensiz dosya yolu içeriyor.");
        }

        var segments = relativePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length == 0 || segments.Any(static segment => segment is "." or ".." || segment.Contains(':')))
        {
            throw new InvalidDataException("Manifest güvensiz dosya yolu içeriyor.");
        }

        var rootPrefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var fullPath = Path.GetFullPath(Path.Combine(root, Path.Combine(segments)));
        if (!fullPath.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("Manifest kurulum alanının dışına çıkmaya çalışıyor.");
        }

        return fullPath;
    }

    private static string SafeDirectChild(string parent, string candidate, string label)
    {
        var parentPrefix = Path.GetFullPath(parent).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var fullPath = Path.GetFullPath(candidate);
        if (!fullPath.StartsWith(parentPrefix, StringComparison.OrdinalIgnoreCase) ||
            !Path.GetDirectoryName(fullPath)!.Equals(Path.GetFullPath(parent), StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(label + " güvenli LOCALAPPDATA\\Programs alanının dışında.");
        }

        return fullPath;
    }

    private static void ValidateInstalledProduct(string installDirectory)
    {
        var markerPath = Path.Combine(installDirectory, MarkerName);
        var agentPath = Path.Combine(installDirectory, AgentExeName);
        if (!File.Exists(markerPath) || !File.Exists(agentPath))
        {
            throw new InvalidOperationException("Hedef klasör doğrulanmış DKC Production Print Agent kurulumu değil; üzerine yazma veya silme reddedildi.");
        }

        var marker = JsonSerializer.Deserialize<InstallMarker>(File.ReadAllText(markerPath), JsonOptions);
        if (marker is null || marker.SchemaVersion != 1 || marker.ProductId != ProductId)
        {
            throw new InvalidOperationException("Kurulum product marker değeri uyuşmuyor.");
        }
    }

    private static void EnsureAgentStopped()
    {
        var processes = Process.GetProcessesByName(AgentProcessName);
        if (processes.Length == 0)
        {
            return;
        }

        foreach (var process in processes)
        {
            process.Dispose();
        }

        throw new InvalidOperationException("DKC Production Print Agent çalışıyor. Sistem tepsisinden Çıkış deyip kurulumu yeniden başlatın.");
    }

    private static void StopAgentProcesses()
    {
        foreach (var process in Process.GetProcessesByName(AgentProcessName))
        {
            using (process)
            {
                process.Kill(entireProcessTree: true);
                process.WaitForExit(10_000);
            }
        }
    }

    private static void ConfigureCurrentUserIntegration(string installDirectory, string version)
    {
        var agentPath = Path.Combine(installDirectory, AgentExeName);
        var setupPath = Path.Combine(installDirectory, "DKC-Production-Print-Agent-Setup.exe");
        using (var runKey = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", writable: true))
        {
            runKey.SetValue(RunValueName, $"\"{agentPath}\"", RegistryValueKind.String);
        }

        var startMenu = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Microsoft",
            "Windows",
            "Start Menu",
            "Programs");
        Directory.CreateDirectory(startMenu);
        CreateShortcut(Path.Combine(startMenu, DisplayName + ".lnk"), agentPath, installDirectory);

        using var uninstallKey = Registry.CurrentUser.CreateSubKey(UninstallKeyName, writable: true);
        uninstallKey.SetValue("DisplayName", DisplayName, RegistryValueKind.String);
        uninstallKey.SetValue("DisplayVersion", version, RegistryValueKind.String);
        uninstallKey.SetValue("Publisher", "DynamicsOps", RegistryValueKind.String);
        uninstallKey.SetValue("InstallLocation", installDirectory, RegistryValueKind.String);
        uninstallKey.SetValue("DisplayIcon", agentPath, RegistryValueKind.String);
        uninstallKey.SetValue("UninstallString", $"\"{setupPath}\" /uninstall", RegistryValueKind.String);
        uninstallKey.SetValue("NoModify", 1, RegistryValueKind.DWord);
        uninstallKey.SetValue("NoRepair", 1, RegistryValueKind.DWord);
        uninstallKey.SetValue("InstallDate", DateTime.UtcNow.ToString("yyyyMMdd"), RegistryValueKind.String);
        var estimatedKilobytes = Directory.EnumerateFiles(installDirectory, "*", SearchOption.AllDirectories)
            .Sum(path => new FileInfo(path).Length) / 1024;
        uninstallKey.SetValue("EstimatedSize", (int)Math.Min(estimatedKilobytes, int.MaxValue), RegistryValueKind.DWord);
    }

    private static void RemoveCurrentUserIntegration()
    {
        using (var runKey = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", writable: true))
        {
            runKey?.DeleteValue(RunValueName, throwOnMissingValue: false);
        }

        var shortcutPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Microsoft",
            "Windows",
            "Start Menu",
            "Programs",
            DisplayName + ".lnk");
        if (File.Exists(shortcutPath))
        {
            File.Delete(shortcutPath);
        }

        Registry.CurrentUser.DeleteSubKeyTree(UninstallKeyName, throwOnMissingSubKey: false);
    }

    private static void CreateShortcut(string shortcutPath, string targetPath, string workingDirectory)
    {
        var shellType = Type.GetTypeFromProgID("WScript.Shell")
            ?? throw new InvalidOperationException("Windows shortcut servisi bulunamadı.");
        dynamic shell = Activator.CreateInstance(shellType)
            ?? throw new InvalidOperationException("Windows shortcut servisi başlatılamadı.");
        dynamic shortcut = shell.CreateShortcut(shortcutPath);
        shortcut.TargetPath = targetPath;
        shortcut.WorkingDirectory = workingDirectory;
        shortcut.Description = DisplayName;
        shortcut.Save();
    }

    private static void StartAgent(string installDirectory)
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = Path.Combine(installDirectory, AgentExeName),
            WorkingDirectory = installDirectory,
            UseShellExecute = true
        });
    }

    private static void ScheduleDetachedSetupDeletion()
    {
        var currentSetup = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(currentSetup) ||
            !Path.GetFileName(currentSetup).StartsWith("dkc-print-agent-uninstall-", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = $"/d /c ping 127.0.0.1 -n 3 > nul & del /f /q \"{currentSetup}\"",
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        });
    }

    private sealed record PackageFile(string Path, string Sha256);

    private sealed record PackageManifest(
        int SchemaVersion,
        string ProductId,
        string ProductVersion,
        string Runtime,
        bool SelfContained,
        bool AuthenticodeSigned,
        PackageFile[] Files);

    private sealed record InstallMarker(
        int SchemaVersion,
        string ProductId,
        string ProductVersion,
        DateTimeOffset InstalledAtUtc);
}
