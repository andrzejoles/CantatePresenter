using System;
using System.Text;
using System.Windows;
using CantatePresenter.Services;

namespace CantatePresenter
{
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            // Register CodePages for Windows-1250 / ISO-8859-2 encoding support
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);

            // Initialize DataStore
            _ = DataStore.Shared;
        }

        protected override void OnExit(ExitEventArgs e)
        {
            var store = DataStore.Shared;
            if (store.Settings.GoogleDrive.IsEnabled && store.Settings.GoogleDrive.AutoBackupOnExit)
            {
                try
                {
                    _ = BackupService.CreateBackupArchive(comment: "Automatyczny backup przy zamykaniu CantatePresenter");
                }
                catch { }
            }

            base.OnExit(e);
        }
    }
}
