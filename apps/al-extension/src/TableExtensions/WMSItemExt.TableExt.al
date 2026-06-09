tableextension 50102 "WMS Item Ext" extends Item
{
    fields
    {
        field(50100; "WMS Catch Weight"; Boolean) { Caption = 'WMS Catch Weight'; DataClassification = CustomerContent; }
        field(50101; "WMS Hazmat Class"; Code[10]) { Caption = 'WMS Hazmat Class'; DataClassification = CustomerContent; }
        field(50102; "WMS FEFO Required"; Boolean) { Caption = 'WMS FEFO Required'; DataClassification = CustomerContent; }
    }
}
