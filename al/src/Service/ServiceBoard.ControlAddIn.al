controladdin "DOPSWHS Service Board"
{
    RequestedHeight = 720;
    MinimumHeight = 420;
    RequestedWidth = 1000;
    MinimumWidth = 320;
    VerticalStretch = true;
    VerticalShrink = true;
    HorizontalStretch = true;
    HorizontalShrink = true;
    Scripts = 'Resources/serviceBoard.js';
    StartupScript = 'Resources/serviceBoardStart.js';
    StyleSheets = 'Resources/serviceBoard.css';

    procedure SetLocale(LocaleCode: Text);
    procedure SetData(Json: Text);
    procedure ShowMessage(MessageText: Text; IsError: Boolean);

    event ControlReady();
    event RequestRefresh();
    event OpenOrder(OrderNo: Text);
    event OpenSummary(OrderNo: Text);
}
