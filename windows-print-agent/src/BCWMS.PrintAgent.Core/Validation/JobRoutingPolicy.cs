using BCWMS.PrintAgent.Core.Configuration;
using BCWMS.PrintAgent.Core.Contracts;

namespace BCWMS.PrintAgent.Core.Validation;

public static class JobRoutingPolicy
{
    public static void Validate(PrintJobV1 job, AgentSettings settings)
    {
        if (!string.Equals(job.TenantId, settings.TenantId, StringComparison.Ordinal) ||
            !string.Equals(job.CompanyId, settings.CompanyId, StringComparison.Ordinal) ||
            !string.Equals(job.StationId, settings.StationId, StringComparison.Ordinal))
        {
            throw new PermanentJobException("Job tenant/company/station does not match the local allowlist.");
        }

        var pdf = job.Format == PrintFormat.PDF;
        if (!pdf && job.Format != settings.LabelFormat)
        {
            throw new PermanentJobException($"Job label format {job.Format} does not match configured format {settings.LabelFormat}.");
        }

        if (pdf)
        {
            if (string.IsNullOrWhiteSpace(settings.DocumentPrinterId) || string.IsNullOrWhiteSpace(settings.DocumentPrinterName))
            {
                throw new PermanentJobException("Document printer is not configured.");
            }

            if (!Matches(job, settings.DocumentPrinterId, settings.DocumentPrinterName))
            {
                throw new PermanentJobException("Job printerId/printerName does not match the local printer allowlist.");
            }

            return;
        }

        // Any enabled label printer may be addressed; the job names the exact
        // Windows queue, so several Zebras can hang off one station.
        var labelPrinters = settings.EffectiveLabelPrinters();
        if (labelPrinters.Count == 0)
        {
            throw new PermanentJobException("Label printer is not configured.");
        }

        if (!labelPrinters.Any(printer => Matches(job, printer.PrinterId, printer.PrinterName)))
        {
            throw new PermanentJobException("Job printerId/printerName does not match the local printer allowlist.");
        }
    }

    private static bool Matches(PrintJobV1 job, string printerId, string printerName) =>
        string.Equals(job.PrinterId, printerId, StringComparison.Ordinal) &&
        string.Equals(job.PrinterName, printerName, StringComparison.OrdinalIgnoreCase);
}
