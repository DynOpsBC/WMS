using System.Text.Json;
using BCWMS.PrintAgent.Core.Configuration;
using Xunit;

namespace BCWMS.PrintAgent.Core.Tests;

public sealed class PrinterNamePersistenceTests
{
    [Fact]
    public void AssigningStableIdsPreservesNamesAcrossConfigurationRoundTrip()
    {
        var settings = new AgentSettings
        {
            LabelPrinters =
            [
                new() { PrinterId = "", PrinterName = "Zebra A", DisplayName = "Yazıcı 1" },
                new() { PrinterId = "", PrinterName = "Zebra B", DisplayName = "Sevkiyat" }
            ],
            DocumentPrinterDisplayName = "Belge yazıcısı"
        };
        var ids = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Zebra A"] = "P0000000000000001",
            ["Zebra B"] = "P0000000000000002"
        };

        settings = settings with { LabelPrinters = settings.BindLabelPrinterIds(ids) };
        var reloaded = JsonSerializer.Deserialize<AgentSettings>(JsonSerializer.Serialize(settings))!;

        Assert.Equal("Yazıcı 1", reloaded.LabelPrinters[0].DisplayName);
        Assert.Equal("Sevkiyat", reloaded.LabelPrinters[1].DisplayName);
        Assert.Equal("P0000000000000001", reloaded.LabelPrinters[0].PrinterId);
        Assert.Equal("Zebra A", reloaded.LabelPrinters[0].PrinterName);
        Assert.Equal("Belge yazıcısı", reloaded.DocumentPrinterDisplayName);
        Assert.Equal(reloaded.LabelPrinters, reloaded.BindLabelPrinterIds(ids));
    }

    [Fact]
    public void DuplicateWindowsNamesKeepFirstSelectionAndItsAlias()
    {
        var settings = new AgentSettings
        {
            LabelPrinters =
            [
                new() { PrinterId = "", PrinterName = "Zebra", DisplayName = "Mal Kabul" },
                new() { PrinterId = "", PrinterName = "ZEBRA", DisplayName = "Duplicate" }
            ]
        };
        var result = settings.BindLabelPrinterIds(
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) { ["Zebra"] = "P0000000000000001" });
        Assert.Equal("Mal Kabul", Assert.Single(result).DisplayName);
    }

    [Fact]
    public void ClearingAliasRemainsEmptyAfterSave()
    {
        var settings = new AgentSettings
        {
            LabelPrinters = [new() { PrinterId = "", PrinterName = "Zebra", DisplayName = "" }]
        };
        var result = settings.BindLabelPrinterIds(
            new Dictionary<string, string> { ["Zebra"] = "P0000000000000001" });
        Assert.Equal("", Assert.Single(result).DisplayName);
    }

    [Fact]
    public void LegacySinglePrinterKeepsItsWindowsNameAndStableId()
    {
        var settings = new AgentSettings { LabelPrinterName = "Legacy Zebra" };
        var result = settings.BindLabelPrinterIds(
            new Dictionary<string, string> { ["Legacy Zebra"] = "P0000000000000001" });
        var printer = Assert.Single(result);
        Assert.Equal("Legacy Zebra", printer.PrinterName);
        Assert.Equal("P0000000000000001", printer.PrinterId);
        Assert.Equal("", printer.DisplayName);
    }
}
