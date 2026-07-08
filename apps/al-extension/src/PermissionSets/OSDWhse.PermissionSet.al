permissionset 50029000 "OSD Whse"
{
    Assignable = true;
    Caption = 'BCWMSApp - All', MaxLength = 30;

    Permissions =
        tabledata "OSD Worker" = RIMD,
        tabledata "OSD Worker Menu" = RIMD,
        tabledata "OSD Menu Item" = RIMD,
        tabledata "OSD License Plate" = RIMD,
        tabledata "OSD License Plate Line" = RIMD,
        tabledata "OSD Mobile Device" = RIMD,
        tabledata "OSD Detour" = RIMD,
        tabledata "OSD Data Inquiry" = RIMD,
        tabledata "OSD Packing Policy" = RIMD,
        tabledata "OSD Item Barcode" = RIMD,
        tabledata "OSD Container" = RIMD,
        tabledata "OSD Container Line" = RIMD,
        tabledata "OSD Wave" = RIMD,
        tabledata "OSD Cycle Count Plan" = RIMD,
        tabledata "OSD Count Variance" = RIMD,
        tabledata "OSD Carrier" = RIMD,
        tabledata "OSD Shipping Rate" = RIMD,
        tabledata "OSD Packing Log" = RIMD,
        tabledata "OSD Action Request" = RIMD,
        codeunit "OSD Api Setup" = X,
        codeunit "OSD Menu Renderer" = X,
        codeunit "OSD Action Dispatcher" = X,
        codeunit "OSD Pairing Svc" = X,
        codeunit "OSD Receive Svc" = X,
        codeunit "OSD Putaway Svc" = X,
        codeunit "OSD Pick Svc" = X,
        codeunit "OSD Pack Svc" = X,
        codeunit "OSD Movement Svc" = X,
        codeunit "OSD Cycle Count Svc" = X,
        codeunit "OSD Production Svc" = X,
        codeunit "OSD Ship Svc" = X,
        codeunit "OSD Webhook Pub" = X;
}
