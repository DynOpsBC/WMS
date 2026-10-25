// Kitoko (21 Eki 2026): sürükle-bırak etiket tasarımcısı (docs/label-designer-contract.md).
// Tasarımcı yalnız çizer ve DesignJson verir; ZPL'i BC'deki Label Layout Engine üretir.
controladdin "DOPSWHS Label Designer"
{
    RequestedHeight = 760;
    MinimumHeight = 480;
    RequestedWidth = 1100;
    MinimumWidth = 640;
    VerticalStretch = true;
    HorizontalStretch = true;
    Scripts = 'Resources/labelDesigner.js';
    StyleSheets = 'Resources/labelDesigner.css';
    StartupScript = 'Resources/labelDesigner.js';

    /// <summary>Tasarım + alan listesi + resimler (DesignJson).</summary>
    procedure LoadDesign(DesignJson: Text);
    /// <summary>Labelary önizleme PNG'si (base64).</summary>
    procedure ShowPreview(PngBase64: Text);
    /// <summary>Kind: info | error | success.</summary>
    procedure ShowMessage(Kind: Text; Message: Text);

    event ControlReady();
    event SaveRequested(DesignJson: Text);
    event TestPrintRequested(DesignJson: Text);
    event PreviewRequested(DesignJson: Text);
    event CompanyLogoRequested();
}
