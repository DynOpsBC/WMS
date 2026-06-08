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
        table "WMS Worker" = X,
        table "WMS Worker Menu" = X,
        table "WMS Menu Item" = X,
        table "WMS License Plate" = X,
        table "WMS License Plate Line" = X,
        page "WMS Workers" = X,
        page "WMS Worker Card" = X,
        page "WMS License Plates" = X,
        page "WMS Worker API" = X,
        page "WMS License Plate API" = X,
        codeunit "WMS Api Setup" = X;
}
