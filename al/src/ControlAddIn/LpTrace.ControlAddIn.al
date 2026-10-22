controladdin "DOPSWHS LP Trace"
{
    // LP İzlenebilirlik: React eklentisi (web/src/lpTrace, vite.lpTrace.config.ts
    // tek IIFE paketi üretir). Veri DOPSWHS LP Trace Data codeunit'inden JSON gelir.
    RequestedHeight = 760;
    MinimumHeight = 420;
    RequestedWidth = 1100;
    MinimumWidth = 520;
    VerticalStretch = true;
    HorizontalStretch = true;
    Scripts = 'Resources/lpTrace.js';
    StyleSheets = 'Resources/lpTrace.css';
    StartupScript = 'Resources/lpTrace.js';

    procedure SetData(Json: Text);
    procedure SetBusy(Busy: Boolean);

    event ControlReady();
    event Search(SearchText: Text);
    event OpenNode(Kind: Text; NodeKey: Text);
}
