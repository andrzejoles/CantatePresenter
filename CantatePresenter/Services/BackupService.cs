using System;
using System.IO;
using System.IO.Compression;
using System.Text.Encodings.Web;
using System.Text.Json;
using CantatePresenter.Models;

namespace CantatePresenter.Services
{
    public class BackupService
    {
        public static string GetDataDirectory()
        {
            var baseDir = AppDomain.CurrentDomain.BaseDirectory;
            var dataDir = Path.Combine(baseDir, "data");
            if (!Directory.Exists(dataDir))
                Directory.CreateDirectory(dataDir);
            return dataDir;
        }

        public static (string ArchivePath, BackupManifest Manifest) CreateBackupArchive(string? destinationFolder = null, string? comment = null)
        {
            var dataDir = GetDataDirectory();
            var timestamp = DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss");
            var archiveName = $"CantatePresenter_Backup_{timestamp}.cantatebackup";
            var outDir = destinationFolder ?? Path.GetTempPath();
            var archivePath = Path.Combine(outDir, archiveName);

            var tempStaging = Path.Combine(Path.GetTempPath(), "CantateStaging_" + Guid.NewGuid());
            Directory.CreateDirectory(tempStaging);

            try
            {
                var filesToCopy = new[] { "songs.json", "plans.json", "settings.json", "standby.html", "custom_languages.json" };
                var includedFiles = new System.Collections.Generic.List<string>();

                foreach (var f in filesToCopy)
                {
                    var src = Path.Combine(dataDir, f);
                    if (File.Exists(src))
                    {
                        File.Copy(src, Path.Combine(tempStaging, f), true);
                        includedFiles.Add(f);
                    }
                }

                var dirsToCopy = new[] { "logos", "templates" };
                foreach (var d in dirsToCopy)
                {
                    var srcDir = Path.Combine(dataDir, d);
                    if (Directory.Exists(srcDir))
                    {
                        var dstDir = Path.Combine(tempStaging, d);
                        CopyDirectory(srcDir, dstDir);
                        includedFiles.Add(d + "/");
                    }
                }

                int songCount = 0;
                int planCount = 0;
                try
                {
                    var songsJson = Path.Combine(dataDir, "songs.json");
                    if (File.Exists(songsJson))
                    {
                        var songs = JsonSerializer.Deserialize<System.Collections.Generic.List<Song>>(File.ReadAllText(songsJson));
                        songCount = songs?.Count ?? 0;
                    }
                    var plansJson = Path.Combine(dataDir, "plans.json");
                    if (File.Exists(plansJson))
                    {
                        var plans = JsonSerializer.Deserialize<System.Collections.Generic.List<ServicePlan>>(File.ReadAllText(plansJson));
                        planCount = plans?.Count ?? 0;
                    }
                }
                catch { }

                var manifest = new BackupManifest
                {
                    SongsCount = songCount,
                    PlansCount = planCount,
                    ActiveLogoId = "equipes_notre_dame",
                    AppLanguage = "pl",
                    IncludedFiles = includedFiles,
                    Comment = comment
                };

                var options = new JsonSerializerOptions
                {
                    WriteIndented = true,
                    Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
                };
                var manifestJson = JsonSerializer.Serialize(manifest, options);
                File.WriteAllText(Path.Combine(tempStaging, "manifest.json"), manifestJson);

                if (File.Exists(archivePath))
                    File.Delete(archivePath);

                ZipFile.CreateFromDirectory(tempStaging, archivePath, CompressionLevel.Optimal, false);
                return (archivePath, manifest);
            }
            finally
            {
                if (Directory.Exists(tempStaging))
                    Directory.Delete(tempStaging, true);
            }
        }

        public static bool RestoreBackupArchive(string archivePath)
        {
            if (!File.Exists(archivePath)) return false;

            var dataDir = GetDataDirectory();
            var tempUnpack = Path.Combine(Path.GetTempPath(), "CantateRestore_" + Guid.NewGuid());
            Directory.CreateDirectory(tempUnpack);

            try
            {
                ZipFile.ExtractToDirectory(archivePath, tempUnpack, true);

                // Copy unpacked files back to dataDir
                foreach (var file in Directory.GetFiles(tempUnpack, "*.*", SearchOption.AllDirectories))
                {
                    var relPath = Path.GetRelativePath(tempUnpack, file);
                    if (relPath.Equals("manifest.json", StringComparison.OrdinalIgnoreCase)) continue;

                    var targetFile = Path.Combine(dataDir, relPath);
                    var targetParent = Path.GetDirectoryName(targetFile);
                    if (!string.IsNullOrEmpty(targetParent) && !Directory.Exists(targetParent))
                        Directory.CreateDirectory(targetParent);

                    File.Copy(file, targetFile, true);
                }

                return true;
            }
            catch
            {
                return false;
            }
            finally
            {
                if (Directory.Exists(tempUnpack))
                    Directory.Delete(tempUnpack, true);
            }
        }

        private static void CopyDirectory(string sourceDir, string destinationDir)
        {
            Directory.CreateDirectory(destinationDir);
            foreach (var file in Directory.GetFiles(sourceDir))
            {
                var dest = Path.Combine(destinationDir, Path.GetFileName(file));
                File.Copy(file, dest, true);
            }
            foreach (var sub in Directory.GetDirectories(sourceDir))
            {
                var dest = Path.Combine(destinationDir, Path.GetFileName(sub));
                CopyDirectory(sub, dest);
            }
        }
    }
}
