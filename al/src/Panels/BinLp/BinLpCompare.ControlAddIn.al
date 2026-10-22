controladdin "DOPSWHS Bin LP Compare"
{
    // Göz ve LP Karşılaştırma — BC sayfasına gömülü React ekranı
    // (web/src/binLpCompare, tek IIFE paket: Resources/binLpCompare.js/.css).
    RequestedHeight = 760;
    MinimumHeight = 420;
    MaximumHeight = 2000;
    RequestedWidth = 1100;
    MinimumWidth = 520;
    VerticalStretch = true;
    HorizontalStretch = true;
    Scripts = '../../ControlAddIn/Resources/binLpCompare.js';
    StyleSheets = '../../ControlAddIn/Resources/binLpCompare.css';
    StartupScript = '../../ControlAddIn/Resources/binLpCompare.js';

    procedure SetData(Json: Text);
    procedure SetLocale(LocaleCode: Text);
    procedure NotifyResult(Json: Text);

    event ControlReady();
    event Compare(FilterJson: Text);
    event RepairUndoneReceipt(UndoEntryNosCsv: Text; FilterJson: Text);
    event ReleaseOrphans(LpNosCsv: Text; FilterJson: Text);
    event OpenLp(LpNo: Text);
    event OpenBinContent(LocationCode: Text; BinCode: Text; ItemNo: Text; VariantCode: Text);
    event OpenTraceability(LpNo: Text; ItemNo: Text; LotNo: Text);
    event ExportExcel(FilterJson: Text);
}
