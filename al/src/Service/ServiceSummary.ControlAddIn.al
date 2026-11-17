controladdin "DOPSWHS Service Summary"
{
    RequestedHeight = 720;
    MinimumHeight = 420;
    RequestedWidth = 1000;
    MinimumWidth = 320;
    VerticalStretch = true;
    VerticalShrink = true;
    HorizontalStretch = true;
    HorizontalShrink = true;
    Scripts = 'Resources/serviceSummary.js';
    StartupScript = 'Resources/serviceSummaryStart.js';
    StyleSheets = 'Resources/serviceSummary.css';

    procedure SetLocale(LocaleCode: Text);
    procedure SetData(Json: Text);

    event ControlReady();
    event OpenOrder(OrderNo: Text);
}
