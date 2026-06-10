permissionset 50100 "WMS"
{
    Assignable = true;
    Caption = 'BCWMSApp - All', MaxLength = 30;

    Permissions =
        tabledata "WMS Worker" = RIMD,
        tabledata "WMS Worker Menu" = RIMD,
        tabledata "WMS Menu Item" = RIMD,
        tabledata "WMS License Plate" = RIMD,
        tabledata "WMS License Plate Line" = RIMD,
        tabledata "WMS Mobile Device" = RIMD,
        tabledata "WMS Detour" = RIMD,
        tabledata "WMS Data Inquiry" = RIMD,
        tabledata "WMS Packing Policy" = RIMD,
        tabledata "WMS Item Barcode" = RIMD,
        tabledata "WMS Container" = RIMD,
        tabledata "WMS Container Line" = RIMD,
        tabledata "WMS Wave" = RIMD,
        tabledata "WMS Cycle Count Plan" = RIMD,
        tabledata "WMS Count Variance" = RIMD,
        tabledata "WMS Carrier" = RIMD,
        tabledata "WMS Shipping Rate" = RIMD,
        tabledata "WMS Packing Log" = RIMD,
        tabledata "WMS Action Request" = RIMD,
        codeunit "WMS Api Setup" = X,
        codeunit "WMS Menu Renderer" = X,
        codeunit "WMS Action Dispatcher" = X,
        codeunit "WMS Receive Svc" = X,
        codeunit "WMS Putaway Svc" = X,
        codeunit "WMS Pick Svc" = X,
        codeunit "WMS Pack Svc" = X,
        codeunit "WMS Movement Svc" = X,
        codeunit "WMS Cycle Count Svc" = X,
        codeunit "WMS Production Svc" = X,
        codeunit "WMS Ship Svc" = X,
        codeunit "WMS Webhook Publisher" = X;
}
