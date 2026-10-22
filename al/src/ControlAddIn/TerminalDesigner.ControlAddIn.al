controladdin "DOPSWHS Terminal Designer"
{
    // Terminal Ekran Tasarımcısı — React (web/src/terminalDesigner) derlemesi.
    // Yönetici terminal ana menüsünü ve ekran düğmelerini sürükle-bırak ile düzenler.
    RequestedHeight = 820;
    MinimumHeight = 560;
    RequestedWidth = 1180;
    MinimumWidth = 720;
    VerticalStretch = true;
    HorizontalStretch = true;
    Scripts = 'Resources/terminalDesigner.js';
    StyleSheets = 'Resources/terminalDesigner.css';
    StartupScript = 'Resources/terminalDesigner.js';

    /// Katalog, yerleşim listesi, roller, terminaller ve seçili yerleşim.
    procedure SetData(Json: Text);
    /// "Önizleme rolü" sonucu: hangi yerleşimin uygulanacağı ve öğeleri.
    procedure SetPreview(Json: Text);
    /// {"ok":true|false,"message":"..."}
    procedure NotifyResult(Json: Text);

    event ControlReady();
    event LoadLayout(LayoutCode: Text);
    event SaveLayout(Json: Text);
    event CreateLayout(Json: Text);
    event DeleteLayout(LayoutCode: Text);
    event RequestPreview(RoleCode: Text; TerminalCode: Text);
}
